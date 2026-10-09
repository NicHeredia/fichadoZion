-- Ejecutar después de 003_admin_dashboard.sql, preferentemente en un proyecto de pruebas.
-- Crea usuarios/fichajes temporales dentro de una transacción; ROLLBACK revierte todo.
-- Si falla una aserción, ejecutar ROLLBACK antes de continuar.
begin;
create temporary table admin_test_ids(admin_id uuid, user_a uuid, user_b uuid, place_id uuid);
insert into admin_test_ids values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
grant select on admin_test_ids to authenticated,anon;
create function pg_temp.assert_true(p_ok boolean,p_message text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'Prueba fallida: %',p_message; end if; end $$;
create function pg_temp.expect_error(p_sql text,p_fragment text) returns void language plpgsql as $$
declare failed boolean := false;
begin
  begin execute p_sql;
  exception when others then
    if position(lower(p_fragment) in lower(sqlerrm))=0 then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'La operación no fue rechazada: %',p_sql; end if;
end $$;
grant execute on function pg_temp.assert_true(boolean,text),pg_temp.expect_error(text,text) to authenticated,anon;
select set_config('test.admin',admin_id::text,true),set_config('test.user_a',user_a::text,true),set_config('test.user_b',user_b::text,true),set_config('test.place',place_id::text,true) from admin_test_ids;
insert into auth.users(id,email,raw_user_meta_data)
select admin_id,'admin-'||admin_id||'@example.invalid','{"display_name":"Administrador de prueba"}'::jsonb from admin_test_ids
union all select user_a,'a-'||user_a||'@example.invalid','{"display_name":"Empleado de prueba"}'::jsonb from admin_test_ids
union all select user_b,'b-'||user_b||'@example.invalid','{"display_name":"Empleado de prueba"}'::jsonb from admin_test_ids;
update public.profiles set role='admin' where id=current_setting('test.admin')::uuid;
insert into public.institutions(id,name) values(current_setting('test.place')::uuid,'Prueba-'||current_setting('test.place'));
update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
select pg_temp.assert_true(not public.app_month_closed('2197-01-05'),'El período de prueba debe estar abierto');
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select e.id,current_setting('test.place')::uuid,x.kind::public.event_type,x.at::timestamptz,'Prueba de cálculo',e.profile_id
from public.employees e cross join (values
  ('entry','2197-01-05 18:00:00-03'),('exit','2197-01-05 21:00:00-03'),
  ('entry','2197-01-06 18:00:00-03'),('entry','2197-01-06 18:10:00-03'),('exit','2197-01-06 21:00:00-03')
) as x(kind,at) where e.profile_id=current_setting('test.user_a')::uuid order by x.at;
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select id,current_setting('test.place')::uuid,'exit','2197-01-05 19:00:00-03','Salida sin entrada',profile_id from public.employees where profile_id=current_setting('test.user_b')::uuid;
select set_config('test.session',(select s.id::text from public.work_sessions s join public.employees e on e.id=s.employee_id where e.profile_id=current_setting('test.user_a')::uuid and s.work_date='2197-01-05'),true);
select set_config('test.pending',(select s.id::text from public.work_sessions s join public.employees e on e.id=s.employee_id where e.profile_id=current_setting('test.user_a')::uuid and s.work_date='2197-01-06' and s.entry_event_id is not null order by s.starts_at limit 1),true);

-- Usuario A: lectura propia, RLS, rechazo de operaciones administrativas.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.user_a'),true);
select pg_temp.assert_true(jsonb_array_length(public.get_app_data()->'records')=4,'Solo se leen los cuatro períodos del usuario A');
select pg_temp.assert_true(jsonb_array_length(public.get_app_data()->'employees')=1,'El empleado solo ve su propio legajo');
select pg_temp.assert_true(jsonb_array_length(public.get_app_data()->'events')=5,'Todos los fichajes originales se conservan');
select pg_temp.assert_true(public.get_app_data()->'audit'='[]'::jsonb,'No se expone auditoría a empleados');
select pg_temp.assert_true(not exists(select 1 from public.time_events t join public.employees e on e.id=t.employee_id where e.profile_id<>auth.uid()),'RLS oculta eventos de otros usuarios');
select pg_temp.expect_error('select public.admin_close_month(''2197-01-01'')','administrador');
select pg_temp.expect_error('select public.admin_reopen_month(''2197-01-01'',''Prueba'')','administrador');
select pg_temp.expect_error('select public.admin_review_session('''||current_setting('test.pending')||''',''rejected'')','administrador');
select pg_temp.expect_error('select public.admin_save_employee('''||(public.get_app_data()->'profile'->>'employeeId')||''',''Fraude'',''X'',true,''admin'')','administrador');
select pg_temp.expect_error('select public.admin_save_settings(''08:00'',''17:00'',array[1],array[''Lugar''],array[]::date[])','administrador');
select pg_temp.expect_error('select public.app_process_event(gen_random_uuid())','permission denied');
select pg_temp.expect_error('update public.profiles set role=''admin'' where id=auth.uid()','permission denied');
select pg_temp.expect_error('insert into public.time_events(employee_id,reason,event_type) values(gen_random_uuid(),''Prueba'',''entry'')','permission denied');

-- Usuario B: un período propio con entrada inferida y dos horas extras.
select set_config('request.jwt.claim.sub',current_setting('test.user_b'),true);
select pg_temp.assert_true(jsonb_array_length(public.get_app_data()->'records')=1,'El usuario B no recibe períodos de A');
select pg_temp.assert_true((public.get_app_data()->'records'->0->>'inferredEntry')::boolean,'Se infiere la entrada laboral');
select pg_temp.assert_true((public.get_app_data()->'records'->0->>'minutes')::integer=120,'Se calculan dos horas después de la jornada');

-- Administrador: cálculo, ambigüedad, revisión, corrección y cierre.
select set_config('request.jwt.claim.sub',current_setting('test.admin'),true);
select pg_temp.assert_true(public.get_app_data()->'profile'->>'role'='admin','Se reconoce el administrador');
select pg_temp.assert_true((select (r->>'minutes')::integer=180 from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.session')),'18:00 a 21:00 cuenta tres horas');
select pg_temp.assert_true((select count(*)=3 from jsonb_array_elements(public.get_app_data()->'records') r where r->>'isoDate'='2197-01-06' and r->>'employeeId'=(select id::text from public.employees where profile_id=current_setting('test.user_a')::uuid) and r->>'status'='Pendiente'),'Dos entradas ambiguas no se emparejan automáticamente');
select pg_temp.expect_error('select public.admin_close_month(''2197-01-01'')','pendientes');
select public.admin_review_session(current_setting('test.pending')::uuid,'corrected','18:00','19:00','Horario verificado');
select pg_temp.expect_error('select public.admin_review_session('''||current_setting('test.pending')||''',''rejected'')','ya fue resuelto');
select pg_temp.assert_true((select (r->>'minutes')::integer=60 from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.pending')),'La corrección recalcula los minutos');
select pg_temp.assert_true((select count(*)=5 from public.time_events t join public.employees e on e.id=t.employee_id where e.profile_id=current_setting('test.user_a')::uuid),'La corrección no cambia los eventos originales');
do $$
declare item jsonb;
begin
  for item in select r from jsonb_array_elements(public.get_app_data()->'records') r where r->>'isoDate'='2197-01-06' and r->>'status'='Pendiente' loop
    perform public.admin_review_session((item->>'id')::uuid,'rejected',null,null,'Duplicado ambiguo');
  end loop;
end $$;
select public.admin_close_month('2197-01-01');
select pg_temp.assert_true(public.get_app_data()->'closures' ? '2197-01','El cierre está disponible en el panel');
select pg_temp.assert_true(jsonb_array_length(public.get_app_data()->'closures'->'2197-01'->'records')=5,'El cierre guarda una copia completa');
select pg_temp.expect_error('select public.admin_reopen_month(''2197-01-01'','''')','motivo');
select public.admin_reopen_month('2197-01-01','Revisión administrativa');
select pg_temp.assert_true(not (public.get_app_data()->'closures' ? '2197-01'),'La reapertura desbloquea el período');
select public.admin_close_month('2197-01-01');

-- Un fichaje con fecha de un mes cerrado es rechazado también por el trigger.
reset role;
select pg_temp.expect_error('insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by) select id,'''||current_setting('test.place')||''',''entry'',''2197-01-07 18:00:00-03'',''Bloqueado'',profile_id from public.employees where profile_id='''||current_setting('test.user_a')||'''','cerrado');
select pg_temp.assert_true((select max(version)=2 from public.monthly_closures where year=2197 and month=1),'Un cierre nuevo conserva la versión anterior');
select pg_temp.assert_true((select sum(total_minutes)=360 from public.monthly_closure_items i join public.monthly_closures c on c.id=i.closure_id where c.year=2197 and c.month=1 and c.version=2),'Los rechazados no se suman en el cierre');

-- Reintentos: misma solicitud devuelve el mismo evento sin duplicarlo.
-- Desbloquear temporalmente el mes actual solo dentro de esta transacción.
update public.monthly_closures set closed_at=null where year=extract(year from now() at time zone 'America/Argentina/Buenos_Aires')::integer and month=extract(month from now() at time zone 'America/Argentina/Buenos_Aires')::integer;
select set_config('test.request',gen_random_uuid()::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.user_a'),true);
select set_config('test.event',(select id::text from public.register_time_event('entry',current_setting('test.place')::uuid,'Inicio de prueba','',current_setting('test.request')::uuid)),true);
select pg_temp.assert_true((select id::text=current_setting('test.event') from public.register_time_event('entry',current_setting('test.place')::uuid,'Inicio de prueba','',current_setting('test.request')::uuid)),'El reintento devuelve el evento original');
select pg_temp.expect_error('select public.register_time_event(''entry'','''||current_setting('test.place')||''',''Duplicado'','''',gen_random_uuid())','duplicado');
select pg_temp.assert_true((select count(*)=1 from public.time_events where client_request_id=current_setting('test.request')::uuid),'No se duplica una solicitud');

-- Legajo inactivo no puede fichar ni administrar.
reset role;
update public.employees set active=false where profile_id=current_setting('test.user_a')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.user_a'),true);
select pg_temp.expect_error('select public.register_time_event(''exit'','''||current_setting('test.place')||''',''Bloqueado'','''',gen_random_uuid())','no habilitado');
reset role;
update public.employees set active=false where profile_id=current_setting('test.admin')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.admin'),true);
select pg_temp.assert_true(public.get_app_data()->'profile'->>'role'='employee','Un administrador inactivo pierde la vista del equipo');
select pg_temp.expect_error('select public.admin_close_month(''2197-01-01'')','administrador');

set local role anon;
select pg_temp.expect_error('select public.get_app_data()','permission denied');
select pg_temp.expect_error('select public.register_time_event(''entry'','''||current_setting('test.place')||''',''Anónimo'','''',gen_random_uuid())','permission denied');
reset role;
rollback;
select 'Pruebas de administración terminadas; todos los datos de prueba fueron revertidos.' as resultado;
