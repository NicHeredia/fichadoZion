-- Ejecutar tras 004, preferentemente en un proyecto de pruebas.
-- Prueba real del motor SQL. Todos los cambios se revierten al terminar.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
select set_config('test.checkout_user',gen_random_uuid()::text,true);
select set_config('test.checkout_place',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
values(current_setting('test.checkout_user')::uuid,
  current_setting('test.checkout_user')||'@example.invalid','{"display_name":"Prueba cierre automático"}');
insert into public.institutions(id,name)
values(current_setting('test.checkout_place')::uuid,'Prueba cierre '||current_setting('test.checkout_place'));
update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
select pg_temp.assert_true(not public.app_month_closed('2198-01-05'),'Mes de prueba abierto');
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select e.id,current_setting('test.checkout_place')::uuid,x.kind::public.event_type,
  x.at::timestamptz,'Prueba',e.profile_id
from public.employees e cross join (values
  ('entry','2198-01-05 06:00:00-03'),
  ('entry','2198-01-06 18:00:00-03'),
  ('entry','2198-01-07 06:00:00-03'),
  ('entry','2198-01-07 07:00:00-03'),
  ('entry','2198-01-08 06:00:00-03'),
  ('exit','2198-01-08 19:00:00-03')
) x(kind,at) where e.profile_id=current_setting('test.checkout_user')::uuid order by x.at;
update public.app_settings set weekdays=array[]::integer[];
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select id,current_setting('test.checkout_place')::uuid,'entry',
  '2198-01-09 06:00:00-03','Día no laboral',profile_id
from public.employees where profile_id=current_setting('test.checkout_user')::uuid;
-- Cambiar configuración después de fichar no cambia la salida de aquel día.
update public.app_settings set ends_at='18:00';
select public.app_finalize_open_sessions('2198-01-06 02:59:59+00');
select pg_temp.assert_true(exists(select 1 from public.work_sessions s join public.employees e on e.id=s.employee_id
  where e.profile_id=current_setting('test.checkout_user')::uuid and s.work_date='2198-01-05'
    and s.status='pending' and s.ends_at is null),'Antes de medianoche sigue abierto');
select public.app_finalize_open_sessions('2198-01-06 03:00:00+00');
select pg_temp.assert_true(exists(select 1 from public.work_sessions s
  join public.employees e on e.id=s.employee_id join public.overtime_calculations c on c.session_id=s.id
  where e.profile_id=current_setting('test.checkout_user')::uuid and s.work_date='2198-01-05'
    and s.status='automatic' and s.exit_inferred and s.exit_event_id is null
    and s.ends_at='2198-01-05 17:00:00-03'::timestamptz and c.total_minutes=120),
  'A medianoche: salida inferida 17:00 y 120 minutos extra');
select public.app_finalize_open_sessions('2198-01-10 03:00:00+00');
select public.app_finalize_open_sessions('2198-01-10 03:00:00+00');
select pg_temp.assert_true((select count(*)=4 from public.work_sessions s join public.employees e on e.id=s.employee_id
  where e.profile_id=current_setting('test.checkout_user')::uuid and s.status='pending'),
  'Entrada tardía, dos ambiguas y día no laboral siguen pendientes');
select pg_temp.assert_true(exists(select 1 from public.work_sessions s join public.employees e on e.id=s.employee_id
  where e.profile_id=current_setting('test.checkout_user')::uuid and s.work_date='2198-01-08'
    and s.ends_at='2198-01-08 19:00:00-03'::timestamptz and not s.exit_inferred),
  'La salida real no cambia');
select pg_temp.assert_true((select count(*)=7 from public.time_events t join public.employees e on e.id=t.employee_id
  where e.profile_id=current_setting('test.checkout_user')::uuid),'No fabrica fichajes');
select pg_temp.assert_true((select count(*)=1 from public.audit_logs a
  join public.work_sessions s on s.id=a.entity_id join public.employees e on e.id=s.employee_id
  where e.profile_id=current_setting('test.checkout_user')::uuid and a.action='Salida automática al finalizar el día'
    and a.actor_id is null),'Auditoría del sistema una sola vez');
select pg_temp.assert_true(not has_function_privilege('authenticated',
  'public.app_finalize_open_sessions(timestamptz)','EXECUTE'),'No ejecutable desde cliente');
select pg_temp.assert_true(not has_function_privilege('anon',
  'public.app_finalize_open_sessions(timestamptz)','EXECUTE'),'No ejecutable sin sesión');
select pg_temp.assert_true(exists(select 1 from cron.job where jobname='zion-close-missing-exits' and active),
  'Cron activo');
rollback;
