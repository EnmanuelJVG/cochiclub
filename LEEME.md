# Cochi Club — cómo ponerlo en línea (unos 20 minutos)

La app es **un solo archivo (`index.html`)** más la carpeta `brand` con los logos. No hay que instalar nada.
Necesitas dos servicios gratuitos: **Supabase** (guarda clientes y sellos) y un sitio donde subir la carpeta (**Netlify**, Vercel o GitHub Pages).

## Paso 1 · Crear la base de datos
1. Entra a **supabase.com**, crea una cuenta y pulsa **New project**. Guarda la contraseña que te pida.
2. Cuando termine de crearse, abre **SQL Editor → New query**.
3. Abre el archivo `1-base-de-datos.sql`, copia **todo** su contenido, pégalo y pulsa **Run**. Debe decir que terminó sin errores.
4. Entra a **Authentication**, busca la configuración de **Email** y **apaga «Confirm email»**. Así los clientes entran apenas se registran.

## Paso 2 · Conectar la app (2 datos)
1. En Supabase abre **Project Settings → API Keys** (también sirve el botón **Connect** de arriba).
2. Copia la **Project URL** y la **Publishable key** (empieza por `sb_publishable_`).
3. Abre `index.html` con el Bloc de notas y reemplaza en las dos líneas marcadas:
   - `PEGA_AQUI_TU_URL` por tu URL
   - `PEGA_AQUI_TU_CLAVE` por tu clave

La clave *publishable* está hecha para ser pública: la seguridad la dan las reglas del paso 1, no ocultar la clave. **Nunca pegues la clave «secret» ni «service_role».**

## Paso 3 · Subir la carpeta
Sube la carpeta completa `cochi-club` (con `index.html` y `brand`) a **Netlify** (busca la opción de arrastrar una carpeta para publicarla) o a Vercel / GitHub Pages. Te darán un link tipo `https://tu-sitio.netlify.app`. Ese es el link de Cochi Club.

Luego, en Supabase: **Authentication → URL Configuration → Site URL**, pega ese link. Sirve para que funcione «Olvidé mi contraseña».

## Paso 4 · Crear tu usuario administrador
1. Abre tu link y **crea una cuenta con el correo del negocio** (como si fueras cliente).
2. En Supabase, **SQL Editor**, ejecuta esto cambiando el correo:

```sql
update public.profiles set role = 'admin' where email = 'correo-del-negocio@ejemplo.com';
```

3. Cierra sesión y vuelve a entrar con ese correo y contraseña: ahora verás el **panel**.

Para personal que solo pone sellos (sin poder cambiar ajustes), igual: que se registren y ejecuta lo mismo con `role = 'staff'`.
Usa un correo distinto al tuyo personal de cliente: las cuentas de administración no tienen tarjeta.

## Uso diario
- **Clientes:** busca por nombre, teléfono o correo → abre al cliente → **Agregar sello**. Si pone el número de pedido, no se puede dar dos sellos por el mismo pedido. Si te equivocas: **Quitar el último sello** (pide motivo y queda registrado).
- **Premio:** cuando la tarjeta se completa aparece **Entregar premio**. Un premio solo se entrega una vez; después el cliente empieza una tarjeta nueva.
- **Ajustes:** cantidad de sellos, premio, tema (Cochi, Halloween, Navidad, San Valentín, Cochi Dulce), colores, icono y textos. La vista previa cambia mientras editas; no se aplica hasta **Guardar cambios**.
- **Invitar:** link de registro y QR para imprimir o enviar.

## Importante saber
- **Cambiar sellos o premio vale para tarjetas nuevas.** Las que ya están empezadas conservan la regla con la que nacieron, para no cambiarle las reglas a un cliente a medias. Si aún no habías definido premio, esas tarjetas sí toman el que pongas.
- Los movimientos de sellos no se pueden borrar ni editar (así hay historial confiable).
- Para agregar otro tema (por ejemplo «Carnaval»), en `index.html` busca `PRESETS` y copia una de las líneas cambiando nombre, colores e icono.

## Qué NO está todavía
- Estadísticas, gráficos y exportación a CSV.
- Escáner de QR de la tarjeta del cliente (por ahora se busca por nombre o teléfono).
- Editar los datos personales desde la cuenta del cliente.
- Suspender cuentas y borrar datos desde el panel (hoy se hace desde Supabase).

## Estado de las pruebas
Se verificó que el código JavaScript no tiene errores de sintaxis. **No se pudo probar contra una base de datos real ni en un teléfono** porque mi entorno no tiene internet. Después del paso 4, haz esta prueba rápida con dos teléfonos o dos navegadores: registra un cliente, agrégale un sello desde el panel, y mira que aparezca en su tarjeta al pulsar «Actualizar mi tarjeta».
