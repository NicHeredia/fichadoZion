# Fichado Zion ortopedia

Sistema de horas extras con React, TypeScript, Vite y Supabase.

## Modos de funcionamiento

- `VITE_DATA_MODE=demo`: interfaz completa con datos de ejemplo y persistencia local.
- `VITE_DATA_MODE=supabase`: la misma interfaz con usuarios, fichajes y reglas del servidor.

En Supabase, los administradores acceden a dashboard, empleados, historial, revisiones,
reportes, cierres, configuración, instituciones y auditoría. Los empleados acceden
a su dashboard, fichaje, historial y reportes propios. Los legajos inactivos pueden
consultar sus datos, pero no fichar ni administrar.

## Actualizar un proyecto que ya está conectado

1. Ejecutar `supabase/migrations/003_admin_dashboard.sql` una sola vez en SQL Editor.
2. Abrir `supabase/promote_admin.sql`, reemplazar el correo de ejemplo por el de
   la cuenta que será administradora y ejecutar ese archivo.
3. Recargar la app e ingresar con esa cuenta.

No volver a ejecutar `setup.sql` en una instalación existente.
La migración conserva los eventos y procesa los anteriores en orden.
Consultar `SUPABASE_SETUP.md` para instalación nueva y comprobaciones.

## Flujos implementados

- Carga manual de movimientos por administradores: fecha y hora declaradas,
  motivo, responsable y hora de carga; completa jornadas pendientes o inferidas.

- Compensaciones de horas extras por descanso: saldo acumulado, reservas,
  confirmación, cancelación con motivo y auditoría. Requiere migración 005.

- Hora oficial del servidor y reintentos de fichaje con identificador de solicitud.
- Emparejamiento del mismo empleado, día e institución cuando existe una sola entrada pendiente.
- Cálculo de minutos antes y después de la jornada; período completo en días no laborales.
- Salida sin entrada: inferencia de entrada en día laboral cuando el horario es válido.
- Las entradas abiertas quedan pendientes hasta la medianoche argentina. En días laborales, el servidor completa la salida habitual (17:00 por defecto) como inferida y recalcula las horas extras. Movimientos ambiguos, entradas posteriores a la salida habitual y días no laborales requieren revisión.
- Corrección de horarios de un período del mismo día, aprobación o rechazo.
- Los eventos originales se conservan; las decisiones y cambios se auditan.
- Configuración de jornada, días laborales, feriados e instituciones.
- Edición de nombres, legajos, roles y estado de cuentas ya creadas.
- Cierre versionado con copia de registros y totales; reapertura con motivo.
- CSV e impresión de reportes; los rechazados quedan fuera de los totales.

La configuración se aplica a períodos nuevos. Una salida emparejada conserva
las reglas de su entrada. Los movimientos de distintos días no se emparejan
automáticamente. Para un turno que cruza medianoche, la revisión administra
sus períodos por día; no hay cálculo automático de turnos nocturnos.

Las cuentas nuevas se crean desde **Crear cuenta** en la pantalla de acceso,
con nombre, correo y contraseña. El perfil y legajo se crean automáticamente
como empleado. Para ingresar sin confirmar el correo, habilitar **Allow new
users to sign up** y desactivar **Confirm email** en el proveedor Email de
Authentication en Supabase. El frontend utiliza solo una clave pública y no
usa `service_role`.
Los registros locales de la demo no se migran a Supabase.

## Desarrollo y verificación

El servidor de Figma Make ya está iniciado. En un entorno local:

```sh
npm install
npm run dev
```

```sh
npm run build
npm run typecheck
npm test
```

Las pruebas locales cubren cálculo/persistencia demo y flujos conectados
con respuestas simuladas: separación de roles, selección de empleados por ID,
mutaciones remotas, registro de usuarios, cambios de rol y reintentos sin duplicar solicitudes.

`supabase/tests/security.sql` comprueba los permisos del esquema.
`supabase/tests/admin.sql` comprueba en PostgreSQL la lectura por usuario,
roles, cálculo, correcciones, cierres, reaperturas e idempotencia.
Ejecutar estas pruebas después de la migración, preferentemente en un proyecto
de pruebas. `admin.sql` revierte sus datos al finalizar con `ROLLBACK`.

La aplicación consulta un resumen completo de los datos autorizados y lo actualiza
cada 30 segundos o al volver a la ventana. Para un historial de gran volumen,
conviene agregar consultas por período y paginación en el servidor.

Las migraciones y pruebas SQL deben verificarse en el proyecto de Supabase;
una compilación local no confirma su ejecución remota.

## Compensaciones por descanso

En una base existente, ejecutar únicamente `supabase/migrations/005_overtime_compensations.sql`
después de 004 y recargar la app. No repetir `setup.sql`.

En **Compensaciones**, un administrador selecciona empleado, cantidad `H:MM`,
fecha y motivo. **Programado** reserva el saldo; **Realizado** confirma el uso
del descanso; **Cancelado** libera las horas. Se pueden registrar descansos ya
realizados con fecha pasada o actual; un descanso futuro no puede confirmarse.
Cancelar o anular un descuento requiere motivo. Para cambiar fecha o cantidad,
cancelar la compensación original y crear otra, conservando la auditoría.

El saldo abarca todo el historial, sin vencimiento: horas automáticas, aprobadas
y corregidas menos descansos realizados y reservas. Pendientes y rechazadas
no generan crédito. No se permiten reservas o descuentos mayores al saldo.
Los fichajes originales y los totales de horas trabajadas se conservan.
Los reportes muestran descansos según su fecha y el saldo disponible acumulado;
los CSV de fichajes y descansos se exportan por separado.
Los empleados solo consultan sus propios datos, incluso estando inactivos.
Un legajo inactivo no recibe nuevos descansos. Los meses cerrados bloquean
altas y cambios de descansos fechados en ese mes hasta su reapertura.
El saldo global no queda congelado por un cierre; se calcula del historial completo.

`npm test` ejecuta las pruebas de interfaz y las funciones SQL en PostgreSQL
local con PGlite. Auth y la programación Cron se simulan en ese motor;
`npm run test:sql` ejecuta solo la suite SQL. Para validar las funciones instaladas
en Supabase, ejecutar `supabase/tests/compensations.sql` en SQL Editor después
de 005, preferentemente en una base de pruebas con el mes actual abierto.
El archivo revierte sus datos con `ROLLBACK`; si falla, ejecutar `ROLLBACK`.

## Fichajes manuales por administradores

Aplicar `supabase/migrations/006_admin_manual_punch.sql` una sola vez después
de 005 y recargar. La opción **Fichaje manual** aparece en el menú administrativo
y desde **Registrar fichaje**. El empleado mantiene su fichaje con hora del servidor.

Seleccionar empleado, entrada/salida, institución, fecha, hora argentina y motivo
del olvido. Si ya existe una jornada pendiente o con hora inferida del mismo día
y lugar, seleccionarla para completarla, conservando sus reglas originales.
La hora inferida se reemplaza por la real; los eventos anteriores no se editan.
Las jornadas completadas manualmente quedan como Corregido.
Los períodos nuevos usan la configuración vigente en el momento de la carga;
una entrada sola queda pendiente y una salida sola sigue las reglas de inferencia
habituales. Cron puede completar una entrada histórica antes de cargar su salida;
en ese caso, seleccionar la jornada con salida inferida.

No se permiten fechas futuras, movimientos iguales en el mismo minuto,
superposiciones ni cargas en meses cerrados. Jornadas ya revisadas (aprobadas,
corregidas o rechazadas) no admiten agregar movimientos. Si la corrección reduce
el saldo por debajo de reservas/descansos ya utilizados, se rechaza hasta resolver
esas compensaciones. Se admiten cargas históricas para legajos inactivos.
Historial distingue la fecha del movimiento, la hora de carga y su origen manual;
Auditoría registra al administrador responsable.

Pruebas reales del módulo: `supabase/tests/manual_punch.sql` en SQL Editor tras
006, preferentemente en un proyecto de pruebas. Usa datos ficticios y ROLLBACK;
requiere abierto el mes actual y enero de 2002 para sus escenarios.
