# Conectar y habilitar el panel de HoraClara

## Si tu conexión ya funciona

No cambies tus variables de conexión ni vuelvas a instalar la base inicial.

1. Abrí `supabase/migrations/003_admin_dashboard.sql`.
2. Copiá todo el archivo en SQL Editor de tu proyecto y ejecutalo una sola vez.
3. Abrí `supabase/promote_admin.sql` y reemplazá `REEMPLAZAR_CON_TU_CORREO`
   por el correo de tu propia cuenta. Ejecutá todo ese archivo en SQL Editor.
4. Recargá la app e ingresá con esa cuenta. El dashboard y los módulos
   administrativos se muestran automáticamente según el rol del perfil.

La migración añade cálculo, revisión, configuración, cierres y auditoría.
No elimina los fichajes existentes. Los procesa en orden con la jornada
inicial 08:00–17:00 y los feriados presentes en la base al migrar.
Las entradas sin salida y los movimientos ambiguos quedan pendientes.
Revisá los resultados históricos antes del primer cierre.

Si aparece “Falta instalar la migración 003_admin_dashboard.sql”, verificá
que la ejecutaste en el mismo proyecto de la URL configurada en la app.

## Instalar un proyecto nuevo

1. Creá el proyecto en https://supabase.com/dashboard.
2. Ejecutá todo `supabase/setup.sql` una sola vez. Incluye las migraciones 001, 002 y 003.
3. Creá una cuenta con correo y contraseña desde Authentication → Users.
   Confirmá su correo si corresponde. El trigger crea su perfil y legajo.
4. Copiá `.env.example` a `.env.local` y completá:

```dotenv
VITE_DATA_MODE=supabase
VITE_SUPABASE_URL=https://TU-PROYECTO.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=TU_CLAVE_PUBLICA
```

Se admite `VITE_SUPABASE_ANON_KEY` para claves anon legacy.
No usar secret ni service_role en variables VITE_*.
Reiniciá el servidor de desarrollo después de cambiar variables.

5. Para la primera cuenta administradora, ejecutá `supabase/promote_admin.sql`
   reemplazando el correo de ejemplo.
6. Ingresá a la app.

Si solo instalaste la migración 001, ejecutá 002 y luego 003.
No ejecutar `setup.sql` sobre una instalación existente.

## Roles y empleados

Cada cuenta nueva nace como empleado. El rol administrativo se asigna
inicialmente desde el SQL anterior; luego un administrador puede editar
el rol de otras cuentas desde Empleados.

Un empleado ve solo sus propios períodos y eventos, incluso al llamar
directamente a la API. Un administrador activo ve el equipo completo.
Nadie puede concederse permisos desde el frontend. Los cambios de roles
se validan en el servidor y quedan auditados. La app no permite que un
administrador quite su propio acceso.

## Registro directo y administradores

Los usuarios pueden elegir **Crear cuenta** en la pantalla de acceso y completar
nombre, correo y contraseña (mínimo 6 caracteres). Se crea su perfil y legajo
automáticamente con rol de empleado.

Para este uso interno sin confirmación de correo, configurar una sola vez en
el panel de Supabase, dentro de **Authentication**:
- Habilitar **Allow new users to sign up**.
- Abrir la configuración del proveedor **Email**, desactivar **Confirm email**
  y guardar.

Con esa opción desactivada, el registro devuelve una sesión y la app abre el
panel automáticamente. Si la confirmación sigue activada, la app informa que
hay que revisar el correo; no presenta el registro como un ingreso completado.
La configuración del proveedor se administra en Supabase, no desde la app.

Para designar otro administrador, ingresar con tu cuenta administradora,
abrir **Empleados** y cambiar su selector **Rol** de **Empleado** a
**Administrador**. Se guarda directamente, sin confirmaciones ni SQL.
Para quitar ese rol, seleccionar **Empleado**. La cuenta debe estar activa
para administrar. La app mantiene tu propio acceso administrativo.

Después del cambio, el usuario puede presionar **Actualizar** o recargar;
el panel también se actualiza automáticamente cada 30 segundos.
Desde **Editar** se pueden ajustar nombre, legajo y estado.

No se necesitan nuevas migraciones si ya aplicaste la 003.
Referencia de configuración: https://supabase.com/docs/guides/auth/general-configuration.

## Comprobar los flujos

- Crear una cuenta desde la app, comprobar que entra automáticamente y aparece en Empleados.
- Asignarle rol Administrador desde el selector y comprobar que se habilita su panel.
- Ingresar como administrador: aparecen todos los módulos y los usuarios reales.
- Ingresar con otro usuario empleado: aparecen solo su dashboard, fichaje,
  historial y reportes; una URL administrativa redirige a su dashboard.
- Registrar un movimiento, recargar y revisar “Movimientos originales”.
  La fecha y hora son del servidor.
- Asociar entrada y salida del mismo día e institución. Las horas extras
  se calculan antes y después de la jornada configurada.
- Revisar una entrada incompleta: corregir ambos horarios y guardar un motivo,
  o rechazarla. Los eventos originales no cambian.
- Cerrar un mes sin pendientes: queda bloqueado. Reabrirlo con motivo
  permite cambios; el siguiente cierre crea una nueva versión.
- Cambiar jornada, feriados o instituciones: se aplican a períodos nuevos.
  Deshabilitar una institución conserva su historial.
- Desactivar un legajo: ese usuario puede consultar sus datos, pero no fichar.
- Cerrar sesión: el panel y su caché desaparecen.
- Consultar Auditoría: muestra las últimas 100 acciones.

Los turnos de distintos días no se emparejan automáticamente. Las correcciones
permiten resolver períodos del mismo día. La demo no se importa automáticamente.

## Pruebas

`npm run build`, `npm run typecheck` y `npm test` verifican el frontend local.
Las pruebas de integración usan respuestas simuladas y no conectan a tu cuenta.

Ejecutar `supabase/tests/security.sql` y `supabase/tests/admin.sql` después
de instalar la migración, preferentemente en un proyecto de pruebas.
El segundo archivo crea fixtures dentro de una transacción y hace `ROLLBACK`
al finalizar. Si falla, ejecutar `ROLLBACK` antes de continuar.
La suite SQL no debe confundirse con una verificación ya ejecutada en tu proyecto.

Documentación de referencia:
- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://www.postgresql.org/docs/current/functions-formatting.html
