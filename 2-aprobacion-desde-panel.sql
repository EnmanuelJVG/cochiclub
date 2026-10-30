-- =====================================================================
-- COCHI CLUB · Migración 0002 · aprobación manual desde el panel
-- Ejecutar UNA SOLA VEZ en Supabase → SQL Editor, después de 1-base-de-datos.sql.
-- No modifica contraseñas, tarjetas ni movimientos.
-- =====================================================================

-- Los nuevos registros quedan pendientes por defecto.
alter table public.profiles
  add column if not exists approved boolean not null default false;

create index if not exists profiles_pending_approval_idx
  on public.profiles (created_at)
  where role = 'customer' and approved = false and suspended = false;

-- Conserva el acceso de las cuentas existentes cuyo correo/teléfono ya estaba
-- confirmado y de las cuentas internas que ya tenían rol staff/admin.
-- Las cuentas de clientes no confirmadas quedan pendientes para revisión.
update public.profiles p
set approved = true
where p.role in ('admin', 'staff')
   or exists (
     select 1
     from auth.users u
     where u.id = p.id
       and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)
   );

-- Los permisos internos también requieren que la cuenta esté aprobada.
create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('staff', 'admin')
      and not suspended
      and approved
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and not suspended
      and approved
  );
$$;

-- Única vía para aprobar desde el navegador: valida el rol en el servidor.
-- La columna approved NO se concede para actualización directa al cliente.
create or replace function public.approve_customer(p_customer uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador aprobado puede autorizar clientes.';
  end if;

  update public.profiles
     set approved = true
   where id = p_customer
     and role = 'customer'
     and approved = false
     and not suspended;

  if not found then
    raise exception 'No se encontró una solicitud pendiente para aprobar.';
  end if;

  insert into public.admin_audit_logs (actor_id, action, target_id, details)
  values (
    auth.uid(),
    'customer.approve',
    p_customer,
    jsonb_build_object('approved', true)
  );
end;
$$;

revoke all on function public.approve_customer(uuid) from public, anon;
grant execute on function public.approve_customer(uuid) to authenticated;

-- Fin de la migración 0002.
