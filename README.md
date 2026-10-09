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
