-- Ejecutar en SQL Editor, preferentemente en un proyecto de pruebas con 001–003.
-- Usa usuario y lugar temporales. ROLLBACK revierte todos los cambios.
-- Si falla, ejecutar ROLLBACK antes de continuar.
begin;
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
rollback;
select 'OK: dos movimientos, una jornada y cinco horas extras. Datos de prueba revertidos.' as resultado;
