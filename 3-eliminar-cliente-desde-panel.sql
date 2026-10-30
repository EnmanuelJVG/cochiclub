-- =====================================================================
-- COCHI CLUB · Migración 0003 · eliminar clientes desde el panel
-- Ejecutar UNA SOLA VEZ en Supabase → SQL Editor, después de 0001 y 0002.
-- Conserva el historial de tarjetas y movimientos; elimina el perfil y la
-- identidad de autenticación del cliente. No borra sellos ni auditorías.
-- =====================================================================

-- Los registros históricos conservan el UUID del cliente como referencia
-- interna, pero ya no dependen de la existencia de su perfil. Esto evita que
-- una tarjeta o sus movimientos impidan eliminar la cuenta de Auth.
DO $$
DECLARE
  v_fk record;
BEGIN
  FOR v_fk IN
    SELECT c.conrelid::regclass AS table_name, c.conname
    FROM pg_constraint c
    JOIN LATERAL unnest(c.conkey) AS fk_col(attnum) ON true
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid
     AND a.attnum = fk_col.attnum
    WHERE c.contype = 'f'
      AND c.confrelid = 'public.profiles'::regclass
      AND c.conrelid IN (
        'public.loyalty_cards'::regclass,
        'public.stamp_transactions'::regclass
      )
      AND a.attname = 'customer_id'
      AND cardinality(c.conkey) = 1
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', v_fk.table_name, v_fk.conname);
  END LOOP;
END;
$$;

-- Solo un administrador activo y aprobado puede llamar esta función.
-- No se permite borrar cuentas admin/staff ni la propia cuenta.
CREATE OR REPLACE FUNCTION public.delete_customer(p_customer uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role public.app_role;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador activo puede eliminar clientes.'
      USING ERRCODE = '42501';
  END IF;

  IF p_customer IS NULL THEN
    RAISE EXCEPTION 'No se indicó el cliente que deseas eliminar.';
  END IF;

  IF p_customer = auth.uid() THEN
    RAISE EXCEPTION 'No puedes eliminar tu propia cuenta desde esta opción.';
  END IF;

  SELECT p.role
    INTO v_role
    FROM public.profiles p
   WHERE p.id = p_customer
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró el cliente. Puede que ya haya sido eliminado.';
  END IF;

  IF v_role <> 'customer' THEN
    RAISE EXCEPTION 'Por seguridad, desde aquí solo se pueden eliminar cuentas de clientes. No se pueden eliminar cuentas de administración o personal.';
  END IF;

  -- Protege las referencias de autoría/auditoría: si esta cuenta alguna vez
  -- actuó como personal, se conserva y debe suspenderse en lugar de borrarse.
  IF EXISTS (SELECT 1 FROM public.admin_audit_logs l WHERE l.actor_id = p_customer)
     OR EXISTS (SELECT 1 FROM public.stamp_transactions t WHERE t.created_by = p_customer)
     OR EXISTS (SELECT 1 FROM public.loyalty_cards c WHERE c.redeemed_by = p_customer)
     OR EXISTS (SELECT 1 FROM public.loyalty_program_versions v WHERE v.created_by = p_customer)
  THEN
    RAISE EXCEPTION 'Esta cuenta figura como responsable de acciones históricas. Por seguridad, no se puede eliminar; suspéndela desde la gestión de clientes.';
  END IF;

  -- El borrado de auth.users elimina en cascada profiles e identidades/sesiones.
  -- Las tarjetas y movimientos históricos permanecen asociados al UUID anterior,
  -- sin datos personales ni una cuenta que permita iniciar sesión.
  DELETE FROM auth.users u WHERE u.id = p_customer;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supabase no encontró la cuenta de autenticación del cliente.';
  END IF;

  -- El target_id no tiene FK a profiles: la auditoría sobrevive al borrado.
  INSERT INTO public.admin_audit_logs (actor_id, action, target_id, details)
  VALUES (
    auth.uid(),
    'customer.delete',
    p_customer,
    jsonb_build_object('deleted', true, 'method', 'admin_panel')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_customer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_customer(uuid) TO authenticated;

-- Fin de la migración 0003.
