# Cochi Club — cómo configurar y actualizar la página

La app sigue siendo una página ligera (`index.html`) más la carpeta `brand`. Usa Supabase para las cuentas, clientes y tarjetas.

## Qué cambia con esta versión

Ahora los registros nuevos quedan **pendientes de aprobación**. El cliente abre el QR, crea su cuenta y ve un aviso de que su solicitud está pendiente. Desde el panel, el usuario con rol `admin` tiene una pestaña **Pendientes** y puede aprobar el acceso con un botón. Los usuarios `staff` pueden gestionar clientes y sellos, pero no aprobar cuentas.

Además, el administrador puede **eliminar clientes directamente desde el panel**: desde la ficha de un cliente aprobado o desde la lista de solicitudes pendientes. La acción pide dos confirmaciones. El acceso de Auth y el perfil se eliminan; las tarjetas, movimientos y auditorías se conservan como registros históricos sin un perfil de cliente activo. Las cuentas `admin` y `staff` no se pueden eliminar desde esta opción.

No hay una integración con WhatsApp ni se envían códigos por WhatsApp.

## Paso 1 · Actualizar la base de datos

Si ya tienes Cochi Club funcionando, **no vuelvas a ejecutar** `1-base-de-datos.sql`: ese archivo crea las tablas iniciales.

1. Entra a Supabase → **SQL Editor** → **New query**.
2. Abre `2-aprobacion-desde-panel.sql`, copia todo su contenido y ejecútalo una sola vez.
3. La migración añade el campo de aprobación y una función segura que solo permite aprobar a una cuenta administradora autorizada. No borra clientes, tarjetas ni sellos.

Si vas a crear el proyecto desde cero, ejecuta primero `1-base-de-datos.sql` y después `2-aprobacion-desde-panel.sql`.

## Paso 2 · Activar la eliminación desde el panel

Si Cochi Club ya está funcionando con las migraciones 0001 y 0002, ejecuta **una sola vez** el archivo `3-eliminar-cliente-desde-panel.sql` en Supabase → SQL Editor → New query. Esta migración elimina las referencias obligatorias al perfil desde `customer_id` en tarjetas y movimientos, para que la cuenta de Auth pueda borrarse sin destruir el historial. No vuelvas a ejecutar los archivos 1 o 2.

Después, publica el `index.html` actualizado y conserva la carpeta `brand`. El botón aparece en la ficha de clientes aprobados y en cada solicitud pendiente. Solo lo ve el administrador.

**Importante:** antes de ejecutar una migración de base de datos, es recomendable tener una copia de seguridad. El botón borra la cuenta de acceso y el perfil, pero deja los registros históricos vinculados al UUID anterior; no es un mecanismo para borrar auditorías.

## Paso 3 · Configurar el registro por correo

En Supabase abre **Authentication → Sign In / Providers → Email** (el nombre puede variar ligeramente en el panel) y desactiva **Confirm Email**.

Esto permite que el cliente cree su cuenta e inicie sesión sin esperar un enlace de confirmación. La aprobación del negocio queda separada y la controla el panel de Cochi Club.

**Importante:** al desactivar la confirmación, Supabase deja de comprobar que el usuario sea dueño de ese correo. Por eso, revisa los datos de cada solicitud antes de pulsar **Aprobar**. Si necesitas verificar que cada correo pertenece realmente al cliente, mantén la confirmación por email y no uses el acceso sin verificar.

## Paso 4 · Comprobar el administrador

En Supabase → **SQL Editor**, comprueba que tu correo tenga el rol `admin` y aprobación habilitada. Cambia el correo de ejemplo:

```sql
update public.profiles
set role = 'admin', approved = true
where email = 'correo-del-negocio@ejemplo.com';
```

Para una cuenta interna que solo pone sellos, usa:

```sql
update public.profiles
set role = 'staff', approved = true
where email = 'personal@ejemplo.com';
```

No asignes el rol `admin` a clientes. La aprobación de clientes desde la web solo aparece para administradores.

## Paso 5 · Publicar la página

Sustituye en tu hosting el `index.html` y la carpeta `brand` por los de esta versión. Conserva los mismos valores de `SUPABASE_URL` y `SUPABASE_KEY` que ya tiene tu proyecto.

No publiques una clave `secret` ni `service_role` en el navegador. La clave `sb_publishable_` es la que debe quedar en `index.html`.

## Cómo será el proceso a partir de ahora

1. El cliente escanea el QR y crea su cuenta.
2. Puede iniciar sesión, pero solo verá **Solicitud recibida** mientras esté pendiente.
3. Tú entras con tu correo administrador y abres **Pendientes**.
4. Revisas nombre, correo y teléfono y pulsas **Aprobar**.
5. El cliente vuelve a entrar y ya puede ver su tarjeta.

Cada aprobación queda registrada en el historial administrativo de Supabase. Si se suspende una cuenta, la suspensión sigue bloqueando el acceso.

## Notas importantes

- Las cuentas existentes cuyo correo o teléfono ya estaba confirmado conservan el acceso. Los registros anteriores que no estaban confirmados quedan en la lista de pendientes para revisión.
- La pestaña **Pendientes** solo aparece para `admin`; `staff` no puede aprobar cuentas.
- El panel no necesita una clave secreta de Supabase en el navegador.
- Las demás funciones de Cochi Club (sellos, premios, temas, invitaciones y recuperación de contraseña) se mantienen.

## Funciones que todavía no incluye

Estadísticas, gráficos, exportación CSV y escáner de QR de la tarjeta del cliente.
