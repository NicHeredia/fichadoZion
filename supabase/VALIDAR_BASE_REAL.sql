/* Validación real: ejecutar TODO. No instala migraciones. Si falla, ejecutar ROLLBACK. */
begin;
set local lock_timeout='10s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(73482001);

-- Ejecutar en SQL Editor, preferentemente en un proyecto de pruebas con 001–003.
-- Usa usuario y lugar temporales. ROLLBACK revierte todos los cambios.
-- Si falla, ejecutar ROLLBACK antes de continuar.

create function pg_temp.assert_pairing(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'Prueba fallida: %', message; end if;
end $$;
select set_config('test.pair_user',gen_random_uuid()::text,true);
select set_config('test.pair_place',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
values(current_setting('test.pair_user')::uuid,
  current_setting('test.pair_user')||'@example.invalid',
  '{"display_name":"Prueba entrada y salida"}'::jsonb);
insert into public.institutions(id,name)
values(current_setting('test.pair_place')::uuid,'Prueba unión '||current_setting('test.pair_place'));
update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
delete from public.holidays where holiday_date='2196-01-05';
select pg_temp.assert_pairing(not public.app_month_closed('2196-01-05'),'Mes de prueba abierto');

-- Insertar por separado para comprobar también el estado después de la entrada.
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select id,current_setting('test.pair_place')::uuid,'entry','2196-01-05 06:00:00-03',
  'Inicio de jornada',profile_id from public.employees
where profile_id=current_setting('test.pair_user')::uuid;
select set_config('test.pair_session',(select s.id::text from public.work_sessions s
  join public.employees e on e.id=s.employee_id
  where e.profile_id=current_setting('test.pair_user')::uuid),true);
select pg_temp.assert_pairing(exists(select 1 from public.work_sessions
  where id=current_setting('test.pair_session')::uuid and status='pending'
  and entry_event_id is not null and exit_event_id is null and ends_at is null),
  'La entrada crea una jornada pendiente sin salida');

insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select id,current_setting('test.pair_place')::uuid,'exit','2196-01-05 20:00:00-03',
  'Fin de jornada',profile_id from public.employees
where profile_id=current_setting('test.pair_user')::uuid;
select pg_temp.assert_pairing((select count(*)=2 from public.time_events t
  join public.employees e on e.id=t.employee_id
  where e.profile_id=current_setting('test.pair_user')::uuid),'Se conservan dos movimientos originales');
select pg_temp.assert_pairing((select count(*)=1 from public.work_sessions s
  join public.employees e on e.id=s.employee_id
  where e.profile_id=current_setting('test.pair_user')::uuid),'Los dos movimientos forman una sola jornada');
select pg_temp.assert_pairing(exists(select 1 from public.work_sessions s
  join public.time_events a on a.id=s.entry_event_id
  join public.time_events b on b.id=s.exit_event_id
  join public.overtime_calculations c on c.session_id=s.id
  where s.id=current_setting('test.pair_session')::uuid
    and a.event_type='entry' and b.event_type='exit'
    and s.starts_at='2196-01-05 06:00:00-03'::timestamptz
    and s.ends_at='2196-01-05 20:00:00-03'::timestamptz
    and s.status='automatic' and not s.entry_inferred and not s.exit_inferred
    and c.before_minutes=120 and c.after_minutes=180 and c.total_minutes=300),
  'Se actualiza la misma jornada con horas reales y cinco horas extras');

-- Comprobar la respuesta que consume la interfaz con permisos del empleado.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.pair_user'),true);
select pg_temp.assert_pairing(jsonb_array_length(public.get_app_data()->'records')=1
  and jsonb_array_length(public.get_app_data()->'events')=2
  and public.get_app_data()->'records'->0->>'entry'='06:00'
  and public.get_app_data()->'records'->0->>'exit'='20:00'
  and (public.get_app_data()->'records'->0->>'minutes')::integer=300,
  'La app recibe una jornada, dos movimientos y 300 minutos extra');
reset role;



-- Ejecutar tras 004, preferentemente en un proyecto de pruebas.
-- Prueba real del motor SQL. Todos los cambios se revierten al terminar.

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

-- Comprobaciones básicas de permisos. Ejecutar después de la migración 003 o el setup.sql actualizado.
-- No sustituye las pruebas de dos usuarios reales sobre la API.

do $$
declare name text;
begin
  foreach name in array array['profiles','employees','work_schedules','institutions','time_events','work_sessions','overtime_calculations','review_cases','monthly_closures','monthly_closure_items','holidays','notifications','audit_logs','app_settings'] loop
    if not exists(select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = name and c.relrowsecurity) then raise exception 'RLS ausente en %', name; end if;
    if has_table_privilege('anon', 'public.' || name, 'SELECT') then raise exception 'Lectura anónima en %', name; end if;
    if has_table_privilege('authenticated', 'public.' || name, 'INSERT,UPDATE,DELETE') then raise exception 'Escritura directa habilitada en %', name; end if;
  end loop;
  if has_function_privilege('anon', 'public.register_time_event(public.event_type,uuid,text,text,uuid)', 'EXECUTE') then raise exception 'RPC expuesto a anon'; end if;
  if not has_function_privilege('authenticated', 'public.register_time_event(public.event_type,uuid,text,text,uuid)', 'EXECUTE') then raise exception 'RPC inaccesible para usuarios'; end if;
  if has_function_privilege('anon','public.get_app_data()','EXECUTE') then raise exception 'Panel expuesto a anon'; end if;
  if has_function_privilege('authenticated','public.app_record(uuid)','EXECUTE') then raise exception 'Función interna expuesta'; end if;
  if has_function_privilege('authenticated','public.app_process_event(uuid)','EXECUTE') then raise exception 'Procesamiento interno expuesto'; end if;
end $$;

rollback;
select 'OK: emparejamiento, cálculo, cierre automático y permisos comprobados. Cambios revertidos.' as resultado;
select j.jobname,j.active,j.schedule,r.status as ultima_ejecucion,r.start_time,r.end_time,r.return_message from cron.job j left join lateral (select status,start_time,end_time,return_message from cron.job_run_details where jobid=j.jobid order by start_time desc limit 1) r on true where j.jobname='zion-close-missing-exits';
