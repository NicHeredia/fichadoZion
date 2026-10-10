-- Solo para una base donde TODOS los movimientos sean de prueba.
-- Ejecutar desde SQL Editor con las migraciones 001 a 009 instaladas.
-- Conserva usuarios, perfiles, empleados, instituciones, jornadas y configuración.
-- Borra fichajes, horas, solicitudes, descansos, cierres, avisos y auditoría.
-- Primero probar con ROLLBACK. Cambiar la última línea a COMMIT para borrar realmente.
-- No usar mientras los empleados estén registrando movimientos.

begin;

-- El bloqueo coordina la limpieza con las operaciones de fichaje y revisión.
select pg_advisory_xact_lock(73482001);

select 'time_events' as tabla, count(*) as registros from public.time_events
union all select 'work_sessions', count(*) from public.work_sessions
union all select 'overtime_calculations', count(*) from public.overtime_calculations
union all select 'review_cases', count(*) from public.review_cases
union all select 'correction_requests', count(*) from public.correction_requests
union all select 'manual_session_requests', count(*) from public.manual_session_requests
union all select 'overtime_compensations', count(*) from public.overtime_compensations
union all select 'monthly_closures', count(*) from public.monthly_closures
union all select 'monthly_closure_items', count(*) from public.monthly_closure_items
union all select 'notifications', count(*) from public.notifications
union all select 'audit_logs', count(*) from public.audit_logs
order by tabla;

-- Lista explícita sin CASCADE: si hay nuevas dependencias, se detiene sin borrar.
truncate table
  public.correction_requests,
  public.manual_session_requests,
  public.review_cases,
  public.overtime_calculations,
  public.work_sessions,
  public.time_events,
  public.overtime_compensations,
  public.monthly_closure_items,
  public.monthly_closures,
  public.notifications,
  public.audit_logs;

-- Por defecto simula la limpieza y luego recupera los datos.
rollback;
