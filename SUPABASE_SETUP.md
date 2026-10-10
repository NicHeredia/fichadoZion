# Conectar y habilitar el panel de Fichado Zion ortopedia

## Corregir el guardado de instituciones y feriados

Si aparece `DELETE requires a WHERE clause`, ejecutar una sola vez
`supabase/migrations/007_fix_settings_save.sql` después de 006.
La función anterior borraba todos los feriados sin WHERE al guardar cualquier
cambio de configuración. La nueva quita solo las fechas retiradas y conserva
las restantes. No volver a ejecutar setup.sql. Prueba reversible:
`supabase/tests/settings.sql` en SQL Editor tras la migración.

## Habilitar fichajes manuales de administradores

Después de 005, ejecutar una sola vez todo
`supabase/migrations/006_admin_manual_punch.sql` en SQL Editor y recargar.
No repetir setup.sql. La migración añade origen manual, asociación a una jornada
y RPC exclusiva para administradores; no cambia los eventos existentes.
Verificar con `supabase/tests/manual_punch.sql`, que revierte los datos ficticios.
Si falla una prueba, ejecutar `ROLLBACK` antes de continuar.

## Habilitar compensaciones en una base existente

Con las migraciones 001–004 instaladas, ejecutar una sola vez todo
`supabase/migrations/005_overtime_compensations.sql` en SQL Editor y recargar
la aplicación. No volver a ejecutar `setup.sql`. La migración crea el registro
de descansos, protege sus permisos y habilita el saldo; no modifica fichajes.

Hasta instalar 005, el resto del panel sigue funcionando y Compensaciones
indica que el módulo no está habilitado. Después, los administradores pueden
reservar descansos, confirmar su realización y cancelarlos con motivo.
Los empleados consultan sus descansos y saldo. Reportes muestra el uso mensual
y el saldo global por separado de las horas trabajadas.

Prueba de la base instalada: `supabase/tests/compensations.sql` (datos de prueba
revertidos con ROLLBACK). El mes actual debe estar abierto para los descansos
de prueba. Si aparece un error, ejecutar `ROLLBACK` antes de continuar.

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

## Salida automática al finalizar el día

Para un proyecto que ya tiene 001, 002 y 003, ejecutar únicamente
`supabase/migrations/004_automatic_checkout.sql` en SQL Editor. No repetir setup.
La migración habilita pg_cron, instala el cierre y programa su ejecución cada minuto.
Si la extensión requiere habilitación previa, activarla en Integrations → Cron
y volver a ejecutar 004.

Después de las 00:00 de Argentina, las entradas abiertas de días laborales
se completan con la salida guardada en esa jornada (17:00 por defecto).
No cambia fichajes originales: marca el período como Automático, salida inferida,
recalcula extras y registra la acción del sistema en Auditoría. Funciona con la app cerrada.
También procesa pendientes anteriores elegibles al instalarse.
Días no laborales/feriados, entradas a partir de la salida habitual, superposiciones
y registros ambiguos siguen pendientes. No modifica meses cerrados.

Comprobar en Integrations → Cron que zion-close-missing-exits esté activo
y tenga ejecuciones exitosas. Pruebas SQL: supabase/tests/automatic_checkout.sql
(en un proyecto de pruebas; terminan con ROLLBACK).
Referencia: https://supabase.com/docs/guides/cron/quickstart
## Activar las mejoras de fichaje, solicitudes y reportes

Para una base existente con las migraciones 001 a 007 aplicadas:

1. Abrir `supabase/migrations/008_daily_workflow.sql`.
2. Ejecutar el archivo completo una sola vez en SQL Editor del proyecto Supabase.
3. Recargar la aplicación. Aparecen “Jornada completa” en Fichaje manual y
   las solicitudes se habilitan en “Mis solicitudes” y “Revisiones”.

La migración incorpora el horario histórico y el desglose a los reportes, registra
solicitudes auditadas y añade la carga atómica de entrada y salida. Conserva fichajes,
totales y reglas históricas. No ejecutar `setup.sql` sobre una base existente.
Las instalaciones nuevas ya incluyen 008 dentro de `setup.sql`.

Validación opcional en una base de pruebas: `supabase/tests/daily_workflow.sql`.
Usa fechas ficticias de enero de 2003 y revierte sus datos al terminar; si falla,
ejecutar `ROLLBACK`. Las pruebas locales no confirman la instalación remota.

## Activar salidas asociadas y correcciones de institución

Con 001 a 008 instaladas, ejecutar completo una sola vez
`supabase/migrations/009_specific_checkout.sql` en SQL Editor y recargar la app.
No ejecutar `setup.sql` sobre una base existente; las instalaciones nuevas ya incluyen 009.

Cada salida cierra la entrada seleccionada y conserva su institución. Si no hay entrada
abierta, se exige confirmación para registrar solo la salida. En un día laboral se calcula
con la entrada habitual marcada como inferida; una urgencia es un motivo válido.
Los casos que no permiten inferencia permanecen pendientes de revisión.

El empleado puede solicitar corregir solo la institución, incluso con una entrada abierta.
La aprobación conserva horarios, estado y fichajes originales, y registra la corrección
en auditoría. El servidor bloquea solicitudes desactualizadas y meses cerrados.

`npm test` valida `supabase/tests/specific_checkout.sql` en una base local aislada.
Estas pruebas no aplican la migración al proyecto remoto.
