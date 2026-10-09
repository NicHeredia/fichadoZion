-- Ejecutar después de 005. Todo se revierte con ROLLBACK.
begin;
create function pg_temp.comp_today() returns date language sql stable as $$
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date;
$$;
grant execute on function pg_temp.comp_today() to authenticated;
create function pg_temp.check_comp(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
create function pg_temp.comp_error(statement text,fragment text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if position(lower(fragment) in lower(sqlerrm))=0 then raise; end if;
    return;
  end;
  raise exception 'La operación no fue rechazada: %',statement;
end $$;
grant execute on function pg_temp.check_comp(boolean,text),pg_temp.comp_error(text,text) to authenticated;
select set_config('test.comp_admin',gen_random_uuid()::text,true),
  set_config('test.comp_user',gen_random_uuid()::text,true),
  set_config('test.comp_other',gen_random_uuid()::text,true),
  set_config('test.comp_place',gen_random_uuid()::text,true),
  set_config('test.comp_first',gen_random_uuid()::text,true),
  set_config('test.comp_second',gen_random_uuid()::text,true),
  set_config('test.comp_future',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,id||'@example.invalid','{"display_name":"Prueba compensaciones"}'::jsonb
from unnest(array[current_setting('test.comp_admin'),current_setting('test.comp_user'),current_setting('test.comp_other')]) id;
update public.profiles set role='admin' where id=current_setting('test.comp_admin')::uuid;
select set_config('test.comp_employee',(select id::text from public.employees where profile_id=current_setting('test.comp_user')::uuid),true);
insert into public.institutions(id,name) values(current_setting('test.comp_place')::uuid,'Prueba compensaciones');
update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
delete from public.holidays where holiday_date between '2194-01-05' and '2194-01-08';
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select current_setting('test.comp_employee')::uuid,current_setting('test.comp_place')::uuid,
  kind::public.event_type,at::timestamptz,'Prueba',current_setting('test.comp_user')::uuid
from (values ('entry','2194-01-05 06:00:00-03'),('exit','2194-01-05 20:00:00-03'),
  ('entry','2194-01-06 06:00:00-03'),('exit','2194-01-06 20:00:00-03'),
  ('entry','2194-01-07 18:00:00-03'),('exit','2194-01-07 20:00:00-03'),
  ('entry','2194-01-08 06:00:00-03')) x(kind,at) order by at;
update public.work_sessions set status='rejected' where employee_id=current_setting('test.comp_employee')::uuid and work_date='2194-01-07';
select pg_temp.check_comp((public.app_compensation_balance(current_setting('test.comp_employee')::uuid)->>'earned')::int=600,
  'Diez horas disponibles; pendientes y rechazadas excluidos');
update public.work_sessions set status='approved' where employee_id=current_setting('test.comp_employee')::uuid and work_date='2194-01-05';
update public.work_sessions set status='corrected' where employee_id=current_setting('test.comp_employee')::uuid and work_date='2194-01-06';
select pg_temp.check_comp((public.app_compensation_balance(current_setting('test.comp_employee')::uuid)->>'earned')::int=600,
  'Las horas aprobadas y corregidas conservan el crédito');

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.comp_admin'),true);
select public.admin_create_compensation(current_setting('test.comp_first')::uuid,current_setting('test.comp_employee')::uuid,180,
  (now() at time zone 'America/Argentina/Buenos_Aires')::date,'Descanso realizado','completed');
select public.admin_create_compensation(current_setting('test.comp_second')::uuid,current_setting('test.comp_employee')::uuid,120,
  (now() at time zone 'America/Argentina/Buenos_Aires')::date,'Descanso programado','scheduled');
-- Repetir la solicitud no duplica el descuento ni la auditoría.
select public.admin_create_compensation(current_setting('test.comp_second')::uuid,current_setting('test.comp_employee')::uuid,120,
  (now() at time zone 'America/Argentina/Buenos_Aires')::date,'Descanso programado','scheduled');
select pg_temp.check_comp((select count(*)=2 from public.overtime_compensations where employee_id=current_setting('test.comp_employee')::uuid),'Reintentos sin duplicados');
select pg_temp.check_comp((select (b->>'reserved')::int=120 and (b->>'used')::int=180 and (b->>'available')::int=300
  from jsonb_array_elements(public.get_compensation_data()->'balances') b where b->>'employeeId'=current_setting('test.comp_employee')),'Reserva y uso separados del saldo');
select pg_temp.comp_error('select public.admin_create_compensation(gen_random_uuid(),'''||current_setting('test.comp_employee')||''',301,pg_temp.comp_today(),''Exceso'',''completed'')','saldo disponible');
select pg_temp.comp_error('select public.admin_create_compensation(gen_random_uuid(),'''||current_setting('test.comp_employee')||''',0,pg_temp.comp_today(),''Cero'',''completed'')','Completá');
select pg_temp.comp_error('select public.admin_create_compensation(gen_random_uuid(),'''||current_setting('test.comp_employee')||''',1,pg_temp.comp_today(),'' '',''completed'')','Completá');
select pg_temp.comp_error('select public.admin_create_compensation(gen_random_uuid(),'''||current_setting('test.comp_employee')||''',1,pg_temp.comp_today()+1,''Futuro'',''completed'')','futuro');
select pg_temp.comp_error('select public.admin_create_compensation(gen_random_uuid(),'''||current_setting('test.comp_employee')||''',1,pg_temp.comp_today()-1,''Pasado'',''scheduled'')','futura');
select public.admin_change_compensation(current_setting('test.comp_second')::uuid,'completed');
select public.admin_change_compensation(current_setting('test.comp_second')::uuid,'completed');
select pg_temp.check_comp((select (b->>'reserved')::int=0 and (b->>'used')::int=300 and (b->>'available')::int=300
  from jsonb_array_elements(public.get_compensation_data()->'balances') b where b->>'employeeId'=current_setting('test.comp_employee')),'Confirmar no descuenta dos veces');
select pg_temp.comp_error('select public.admin_change_compensation('''||current_setting('test.comp_first')||''',''cancelled'','''')','motivo');
select public.admin_change_compensation(current_setting('test.comp_first')::uuid,'cancelled','Descanso anulado');
select public.admin_change_compensation(current_setting('test.comp_first')::uuid,'cancelled','Descanso anulado');
select public.admin_create_compensation(current_setting('test.comp_future')::uuid,current_setting('test.comp_employee')::uuid,60,
  (now() at time zone 'America/Argentina/Buenos_Aires')::date+1,'Descanso futuro','scheduled');
select pg_temp.comp_error('select public.admin_change_compensation('''||current_setting('test.comp_future')||''',''completed'')','futuro');
select public.admin_change_compensation(current_setting('test.comp_future')::uuid,'cancelled','Cambio de fecha');
select pg_temp.comp_error('select public.admin_change_compensation('''||current_setting('test.comp_future')||''',''completed'')','cancelada');
select pg_temp.check_comp((select (b->>'used')::int=120 and (b->>'available')::int=480
  from jsonb_array_elements(public.get_compensation_data()->'balances') b where b->>'employeeId'=current_setting('test.comp_employee')),'Cancelar devuelve las horas');

-- Lectura propia y rechazo de mutaciones para empleados.
select set_config('request.jwt.claim.sub',current_setting('test.comp_user'),true);
select pg_temp.check_comp(jsonb_array_length(public.get_compensation_data()->'balances')=1
  and jsonb_array_length(public.get_compensation_data()->'compensations')=3,'El empleado consulta solo su saldo y descansos');
select pg_temp.comp_error('select public.admin_change_compensation('''||current_setting('test.comp_second')||''',''cancelled'',''Fraude'')','administrador');
select pg_temp.comp_error('select public.admin_create_compensation(gen_random_uuid(),'''||current_setting('test.comp_employee')||''',1,pg_temp.comp_today(),''Fraude'',''completed'')','administrador');
select pg_temp.comp_error('update public.overtime_compensations set minutes=1','permission denied');
select pg_temp.comp_error('select public.app_compensation_balance('''||current_setting('test.comp_employee')||''')','permission denied');
select set_config('request.jwt.claim.sub',current_setting('test.comp_other'),true);
select pg_temp.check_comp(jsonb_array_length(public.get_compensation_data()->'compensations')=0
  and not exists(select 1 from public.overtime_compensations),'Otro empleado no ve descansos ajenos');
reset role;
select pg_temp.check_comp((select count(*)=7 from public.time_events where employee_id=current_setting('test.comp_employee')::uuid),'Los fichajes originales se conservan');
select pg_temp.check_comp((select count(*)=6 from public.audit_logs where entity_type='compensation'
  and actor_id=current_setting('test.comp_admin')::uuid),'Cada cambio se audita; reintentos no duplican auditoría');
select pg_temp.check_comp(not has_function_privilege('anon','public.get_compensation_data()','execute'),'Sin lectura anónima');
insert into public.monthly_closures(year,month,version,closed_by,closed_at)
values(2193,1,1,current_setting('test.comp_admin')::uuid,now());
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.comp_admin'),true);
select pg_temp.comp_error('select public.admin_create_compensation(gen_random_uuid(),'''||current_setting('test.comp_employee')||''',1,''2193-01-05'',''Cerrado'',''scheduled'')','cerrado');
reset role;
rollback;
select 'OK: compensaciones, saldo, permisos, fechas, auditoría y reintentos. Cambios revertidos.' as resultado;
