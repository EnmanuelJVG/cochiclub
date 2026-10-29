-- =====================================================================
-- COCHI CLUB · Migración 0001 · esquema, seguridad y operaciones atómicas
-- Ejecutar completa en Supabase → SQL Editor (una sola vez).
-- La contraseña vive solo en auth.users (la gestiona Supabase Auth).
-- =====================================================================

create type public.app_role    as enum ('customer','staff','admin');
create type public.card_status as enum ('active','reward_available','redeemed');
create type public.stamp_kind  as enum ('earn','reversal');

-- ---------- Perfiles -------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       public.app_role not null default 'customer',
  full_name  text not null check (char_length(full_name) between 2 and 120),
  phone      text,
  email      text,
  address    text,
  extra_id   text,  -- campo adicional configurable (cédula, nº de cliente...)
  -- Token opaco para el QR: no contiene datos personales.
  qr_token   text not null unique
             default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  suspended  boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index profiles_phone_uq on public.profiles (phone) where phone is not null;
create index profiles_search_idx on public.profiles (lower(full_name), lower(email));

-- Crea el perfil al registrarse. El rol SIEMPRE es 'customer': nunca se lee del navegador.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, phone, email, address, extra_id)
  values (new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'Cliente'),
    nullif(trim(new.raw_user_meta_data->>'phone'), ''),
    new.email,
    nullif(trim(new.raw_user_meta_data->>'address'), ''),
    nullif(trim(new.raw_user_meta_data->>'extra_id'), ''));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Configuración visual y textos (una sola fila) ------------
create table public.program_settings (
  id boolean primary key default true check (id),
  program_name      text not null default 'Cochi Club',
  welcome_title     text not null default 'Gana sellos con cada pedido',
  instructions      text not null default 'Muestra tu tarjeta cuando hagas un pedido y te agregamos un sello.',
  terms             text not null default '',
  extra_id_label    text not null default 'Cédula',
  extra_id_visible  boolean not null default false,
  extra_id_required boolean not null default false,
  theme jsonb not null default
    '{"primary":"#EB140C","background":"#E6E0BF","text":"#1F1A17","stampActive":"#EB140C","stampPending":"#B9B08A"}'
);
insert into public.program_settings default values;

-- ---------- Versiones del programa (reglas + recompensa) -------------
-- Cada tarjeta guarda una copia de las reglas con las que nació, así
-- cambiar de 8 a 10 sellos NO altera las tarjetas ya iniciadas.
create table public.loyalty_program_versions (
  id uuid primary key default gen_random_uuid(),
  version int not null unique,
  enabled boolean not null default true,
  stamps_required int not null check (stamps_required between 2 and 24),
  reward_name text,            -- NULL = recompensa pendiente de configurar
  reward_description text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
insert into public.loyalty_program_versions (version, stamps_required) values (1, 8);

-- ---------- Tarjetas (un ciclo = una tarjeta) ------------------------
-- El canje queda registrado en la propia tarjeta (redeemed_at / redeemed_by).
create table public.loyalty_cards (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  version_id  uuid not null references public.loyalty_program_versions(id),
  stamps_required int not null check (stamps_required > 0),
  reward_name text,
  stamps_count int not null default 0,
  status public.card_status not null default 'active',
  created_at   timestamptz not null default now(),
  completed_at timestamptz,
  redeemed_at  timestamptz,
  redeemed_by  uuid references public.profiles(id),
  check (stamps_count between 0 and stamps_required),
  check ((status = 'redeemed') = (redeemed_at is not null))
);
-- Un cliente solo puede tener una tarjeta abierta a la vez.
create unique index one_open_card_per_customer
  on public.loyalty_cards (customer_id) where status <> 'redeemed';

-- ---------- Movimientos de sellos (solo se agregan, nunca se editan) -
create table public.stamp_transactions (
  id uuid primary key default gen_random_uuid(),
  card_id     uuid not null references public.loyalty_cards(id),
  customer_id uuid not null references public.profiles(id),
  kind        public.stamp_kind not null,
  quantity    int  not null,
  request_id  uuid not null unique,   -- evita duplicados si se repite la petición
  order_ref   text,
  note        text,
  reverses_id uuid unique references public.stamp_transactions(id),  -- un sello se revierte una sola vez
  created_by  uuid not null references public.profiles(id),
  created_at  timestamptz not null default now(),
  check ((kind = 'reversal') = (reverses_id is not null)),
  check ((kind = 'earn' and quantity = 1) or (kind = 'reversal' and quantity = -1)),
  check (kind <> 'reversal' or char_length(trim(coalesce(note, ''))) >= 3)
);
create unique index stamp_order_ref_uq
  on public.stamp_transactions (lower(order_ref)) where kind = 'earn' and order_ref is not null;
create index stamp_tx_customer_idx on public.stamp_transactions (customer_id, created_at desc);

-- ---------- Auditoría administrativa ---------------------------------
create table public.admin_audit_logs (
  id bigint generated always as identity primary key,
  actor_id  uuid not null references public.profiles(id),
  action    text not null,
  target_id uuid,
  details   jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- Historial inmutable: ni siquiera el personal puede editarlo o borrarlo.
create function public.forbid_mutation() returns trigger language plpgsql as $$
begin
  raise exception 'Este registro es histórico y no se puede modificar ni borrar.';
end $$;
create trigger stamp_tx_immutable before update or delete on public.stamp_transactions
  for each row execute function public.forbid_mutation();
create trigger audit_immutable before update or delete on public.admin_audit_logs
  for each row execute function public.forbid_mutation();

-- ---------- Roles ----------------------------------------------------
create function public.is_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('staff','admin') and not suspended);
$$;
create function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role = 'admin' and not suspended);
$$;

-- ---------- Permisos y RLS -------------------------------------------
alter table public.profiles                 enable row level security;
alter table public.program_settings         enable row level security;
alter table public.loyalty_program_versions enable row level security;
alter table public.loyalty_cards            enable row level security;
alter table public.stamp_transactions       enable row level security;
alter table public.admin_audit_logs         enable row level security;

revoke all on public.profiles, public.program_settings, public.loyalty_program_versions,
              public.loyalty_cards, public.stamp_transactions, public.admin_audit_logs
  from anon, authenticated;

grant select on public.program_settings, public.loyalty_program_versions to anon, authenticated;
grant select on public.profiles, public.loyalty_cards, public.stamp_transactions,
                public.admin_audit_logs to authenticated;
-- El cliente solo puede editar estas columnas; rol, suspensión y QR quedan fuera.
grant update (full_name, phone, address, extra_id) on public.profiles to authenticated;
grant update on public.program_settings to authenticated;

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_staff());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid() and not suspended) with check (id = auth.uid());
create policy settings_read  on public.program_settings for select using (true);
create policy settings_admin on public.program_settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy versions_read  on public.loyalty_program_versions for select using (true);
create policy cards_select   on public.loyalty_cards for select to authenticated
  using (customer_id = auth.uid() or public.is_staff());
create policy tx_select      on public.stamp_transactions for select to authenticated
  using (customer_id = auth.uid() or public.is_staff());
create policy audit_select   on public.admin_audit_logs for select to authenticated
  using (public.is_admin());
-- No hay políticas de INSERT/UPDATE/DELETE sobre tarjetas ni movimientos:
-- los sellos y canjes solo se escriben con las funciones de abajo.

-- ---------- Agregar un sello -----------------------------------------
create function public.add_stamp(
  p_customer uuid, p_request_id uuid, p_order_ref text default null, p_note text default null)
returns public.loyalty_cards language plpgsql security definer set search_path = '' as $$
declare
  v_card public.loyalty_cards;
  v_ver  public.loyalty_program_versions;
  v_ref  text := nullif(trim(p_order_ref), '');
begin
  if not public.is_staff() then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;

  -- Petición repetida: devolvemos el resultado anterior sin sumar otro sello.
  select c.* into v_card from public.loyalty_cards c
    join public.stamp_transactions t on t.card_id = c.id where t.request_id = p_request_id;
  if found then return v_card; end if;

  perform 1 from public.profiles where id = p_customer and role = 'customer' and not suspended;
  if not found then raise exception 'Cliente no encontrado o cuenta suspendida.'; end if;

  if v_ref is not null and exists (select 1 from public.stamp_transactions
       where kind = 'earn' and lower(order_ref) = lower(v_ref)) then
    raise exception 'Ese pedido ya generó un sello.';
  end if;

  select * into v_ver from public.loyalty_program_versions order by version desc limit 1;
  if not v_ver.enabled then raise exception 'El programa de fidelización está desactivado.'; end if;

  insert into public.loyalty_cards (customer_id, version_id, stamps_required, reward_name)
  values (p_customer, v_ver.id, v_ver.stamps_required, v_ver.reward_name)
  on conflict (customer_id) where status <> 'redeemed' do nothing;

  -- Bloquea la tarjeta: dos sellos simultáneos se procesan uno detrás de otro.
  select * into v_card from public.loyalty_cards
    where customer_id = p_customer and status <> 'redeemed' for update;

  if v_card.status = 'reward_available' then
    raise exception 'La tarjeta está completa. Registra el canje del premio antes de agregar más sellos.';
  end if;

  insert into public.stamp_transactions (card_id, customer_id, kind, quantity, request_id, order_ref, note, created_by)
  values (v_card.id, p_customer, 'earn', 1, p_request_id, v_ref, nullif(trim(p_note), ''), auth.uid());

  update public.loyalty_cards set
    stamps_count = stamps_count + 1,
    status = case when stamps_count + 1 >= stamps_required
                  then 'reward_available'::public.card_status else status end,
    completed_at = case when stamps_count + 1 >= stamps_required then now() else completed_at end
  where id = v_card.id returning * into v_card;

  insert into public.admin_audit_logs (actor_id, action, target_id, details)
  values (auth.uid(), 'stamp.add', p_customer,
          jsonb_build_object('card', v_card.id, 'order_ref', v_ref, 'count', v_card.stamps_count));
  return v_card;
end $$;

-- ---------- Revertir un sello (con motivo; el original se conserva) --
create function public.reverse_stamp(p_tx_id uuid, p_request_id uuid, p_reason text)
returns public.loyalty_cards language plpgsql security definer set search_path = '' as $$
declare
  v_tx   public.stamp_transactions;
  v_card public.loyalty_cards;
begin
  if not public.is_staff() then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Indica el motivo de la reversión.';
  end if;

  select * into v_tx from public.stamp_transactions where id = p_tx_id and kind = 'earn';
  if not found then raise exception 'Movimiento no encontrado.'; end if;

  select * into v_card from public.loyalty_cards where id = v_tx.card_id for update;
  if v_card.status = 'redeemed' then
    raise exception 'Esa tarjeta ya fue canjeada; no se puede revertir.';
  end if;
  if exists (select 1 from public.stamp_transactions where reverses_id = p_tx_id) then
    raise exception 'Ese sello ya fue revertido.';
  end if;

  insert into public.stamp_transactions (card_id, customer_id, kind, quantity, request_id, note, reverses_id, created_by)
  values (v_tx.card_id, v_tx.customer_id, 'reversal', -1, p_request_id, trim(p_reason), p_tx_id, auth.uid());

  update public.loyalty_cards set stamps_count = stamps_count - 1, status = 'active', completed_at = null
  where id = v_card.id returning * into v_card;

  insert into public.admin_audit_logs (actor_id, action, target_id, details)
  values (auth.uid(), 'stamp.reverse', v_tx.customer_id,
          jsonb_build_object('tx', p_tx_id, 'reason', trim(p_reason)));
  return v_card;
end $$;

-- ---------- Canjear la recompensa (una sola vez) ---------------------
create function public.redeem_reward(p_card_id uuid)
returns public.loyalty_cards language plpgsql security definer set search_path = '' as $$
declare
  v_card   public.loyalty_cards;
  v_reward text;
begin
  if not public.is_staff() then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;

  select * into v_card from public.loyalty_cards where id = p_card_id for update;
  if not found then raise exception 'Tarjeta no encontrada.'; end if;
  if v_card.status <> 'reward_available' then
    raise exception 'Esta tarjeta no tiene un premio disponible o ya fue canjeado.';
  end if;

  v_reward := coalesce(v_card.reward_name,
    (select reward_name from public.loyalty_program_versions order by version desc limit 1));
  if v_reward is null then
    raise exception 'Primero configura la recompensa del programa.';
  end if;

  update public.loyalty_cards set status = 'redeemed', redeemed_at = now(),
         redeemed_by = auth.uid(), reward_name = v_reward
  where id = p_card_id returning * into v_card;

  insert into public.admin_audit_logs (actor_id, action, target_id, details)
  values (auth.uid(), 'reward.redeem', v_card.customer_id,
          jsonb_build_object('card', p_card_id, 'reward', v_reward));
  return v_card;
end $$;

-- ---------- Publicar nuevas reglas (solo administrador) --------------
-- Afecta únicamente a las tarjetas que se creen DESPUÉS.
create function public.publish_program_version(
  p_stamps int, p_reward_name text, p_reward_description text, p_enabled boolean)
returns public.loyalty_program_versions language plpgsql security definer set search_path = '' as $$
declare v public.loyalty_program_versions;
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede cambiar las reglas.' using errcode = '42501';
  end if;
  insert into public.loyalty_program_versions
    (version, enabled, stamps_required, reward_name, reward_description, created_by)
  values ((select coalesce(max(version), 0) + 1 from public.loyalty_program_versions),
          p_enabled, p_stamps, nullif(trim(p_reward_name), ''), nullif(trim(p_reward_description), ''), auth.uid())
  returning * into v;
  insert into public.admin_audit_logs (actor_id, action, details)
  values (auth.uid(), 'program.publish', jsonb_build_object('version', v.version, 'stamps', v.stamps_required));
  return v;
end $$;

-- Solo usuarios con sesión pueden llamar a estas funciones (y ellas verifican el rol).
revoke execute on function public.add_stamp(uuid, uuid, text, text)        from public, anon;
revoke execute on function public.reverse_stamp(uuid, uuid, text)          from public, anon;
revoke execute on function public.redeem_reward(uuid)                      from public, anon;
revoke execute on function public.publish_program_version(int, text, text, boolean) from public, anon;
grant  execute on function public.add_stamp(uuid, uuid, text, text)        to authenticated;
grant  execute on function public.reverse_stamp(uuid, uuid, text)          to authenticated;
grant  execute on function public.redeem_reward(uuid)                      to authenticated;
grant  execute on function public.publish_program_version(int, text, text, boolean) to authenticated;
