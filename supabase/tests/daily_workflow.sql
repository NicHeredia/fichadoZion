-- Datos ficticios. Ejecutar después de 008; todo se revierte.
begin;
create function pg_temp.workflow_assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
create function pg_temp.workflow_error(statement text,fragment text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then if position(lower(fragment) in lower(sqlerrm))=0 then raise; end if; return; end;
  raise exception 'La operación no fue rechazada: %',statement;
end $$;
grant execute on function pg_temp.workflow_assert(boolean,text),pg_temp.workflow_error(text,text) to authenticated;
select set_config('test.workflow_admin',gen_random_uuid()::text,true),set_config('test.workflow_user',gen_random_uuid()::text,true),
  set_config('test.workflow_other',gen_random_uuid()::text,true),set_config('test.workflow_place',gen_random_uuid()::text,true),
  set_config('test.workflow_pair',gen_random_uuid()::text,true),set_config('test.workflow_correction',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,id||'@example.invalid','{"display_name":"Flujo diario"}'::jsonb
from unnest(array[current_setting('test.workflow_admin'),current_setting('test.workflow_user'),current_setting('test.workflow_other')]) id;
update public.profiles set role='admin' where id=current_setting('test.workflow_admin')::uuid;
select set_config('test.workflow_employee',(select id::text from public.employees where profile_id=current_setting('test.workflow_user')::uuid),true);
insert into public.institutions(id,name) values(current_setting('test.workflow_place')::uuid,'Flujo diario');
update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
delete from public.holidays where holiday_date between '2003-01-05' and '2003-01-08';
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.workflow_admin'),true);
select set_config('test.workflow_session',public.admin_register_manual_session(current_setting('test.workflow_employee')::uuid,
  current_setting('test.workflow_place')::uuid,'2003-01-05','07:45','20:45','Jornada verificada','',current_setting('test.workflow_pair')::uuid)::text,true);
select public.admin_register_manual_session(current_setting('test.workflow_employee')::uuid,
  current_setting('test.workflow_place')::uuid,'2003-01-05','07:45','20:45','Jornada verificada','',current_setting('test.workflow_pair')::uuid);
select pg_temp.workflow_assert((select count(*)=2 from jsonb_array_elements(public.get_app_data()->'events') e
  where e->>'employeeId'=current_setting('test.workflow_employee')),'Reintento de jornada sin duplicar movimientos');
select pg_temp.workflow_assert((select r->>'scheduleStart'='08:00' and r->>'scheduleEnd'='17:00'
  and (r->>'beforeMinutes')::int=15 and (r->>'afterMinutes')::int=225 and (r->>'minutes')::int=240
  from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.workflow_session')),'Desglose 15 + 225 = 240 y horario histórico');
-- La entrada está fuera del período existente, pero su salida se superpone: todo debe revertirse.
select pg_temp.workflow_error('select public.admin_register_manual_session('''||current_setting('test.workflow_employee')||''','''||current_setting('test.workflow_place')||''',''2003-01-05'',''06:00'',''09:00'',''Superposición'','''',gen_random_uuid())','superpone');
select pg_temp.workflow_assert((select count(*)=2 from jsonb_array_elements(public.get_app_data()->'events') e
  where e->>'employeeId'=current_setting('test.workflow_employee')),'Fallo de salida revierte también la entrada');
select set_config('request.jwt.claim.sub',current_setting('test.workflow_user'),true);
select public.request_session_correction(current_setting('test.workflow_correction')::uuid,current_setting('test.workflow_session')::uuid,
  current_setting('test.workflow_place')::uuid,'2003-01-05','07:45','20:00','Salí antes');
select public.request_session_correction(current_setting('test.workflow_correction')::uuid,current_setting('test.workflow_session')::uuid,
  current_setting('test.workflow_place')::uuid,'2003-01-05','07:45','20:00','Salí antes');
select pg_temp.workflow_assert(jsonb_array_length(public.get_correction_requests())=1,'Solicitud propia y reintento sin duplicados');
select pg_temp.workflow_error('select public.request_session_correction(gen_random_uuid(),'''||current_setting('test.workflow_session')||''','''||current_setting('test.workflow_place')||''',''2003-01-05'',''07:45'',''20:00'',''Duplicada'')','pendiente');
select pg_temp.workflow_assert((select (r->>'minutes')::int=240 from jsonb_array_elements(public.get_app_data()->'records') r
  where r->>'id'=current_setting('test.workflow_session')),'La solicitud no cambia el cálculo');
select pg_temp.workflow_error('select public.admin_resolve_correction('''||current_setting('test.workflow_correction')||''',true,''Intento sin permiso'')','administrador');
select set_config('request.jwt.claim.sub',current_setting('test.workflow_other'),true);
select pg_temp.workflow_assert(jsonb_array_length(public.get_correction_requests())=0,'No se ven solicitudes ajenas');
select pg_temp.workflow_error('select public.request_session_correction(gen_random_uuid(),'''||current_setting('test.workflow_session')||''','''||current_setting('test.workflow_place')||''',''2003-01-05'',''07:45'',''20:00'',''Ajena'')','disponible');
select set_config('request.jwt.claim.sub',current_setting('test.workflow_admin'),true);
select pg_temp.workflow_error('select public.admin_close_month(''2003-01-01'')','solicitudes');
select public.admin_resolve_correction(current_setting('test.workflow_correction')::uuid,true,'Horario confirmado');
select public.admin_resolve_correction(current_setting('test.workflow_correction')::uuid,true,'Horario confirmado');
select pg_temp.workflow_assert((select r->>'exit'='20:00' and (r->>'minutes')::int=195
  from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.workflow_session')),'Aprobación actualiza jornada y cálculo');
select pg_temp.workflow_assert((select count(*)=2 from jsonb_array_elements(public.get_app_data()->'events') e
  where e->>'employeeId'=current_setting('test.workflow_employee')),'Corrección conserva fichajes originales');
-- Nueva jornada solicitada por olvido de ambos movimientos.
select set_config('request.jwt.claim.sub',current_setting('test.workflow_user'),true);
select set_config('test.workflow_new',gen_random_uuid()::text,true);
select public.request_session_correction(current_setting('test.workflow_new')::uuid,null,current_setting('test.workflow_place')::uuid,
  '2003-01-06','08:00','19:00','Olvidé ambos movimientos');
select set_config('request.jwt.claim.sub',current_setting('test.workflow_admin'),true);
select public.admin_resolve_correction(current_setting('test.workflow_new')::uuid,true,'Confirmado');
select pg_temp.workflow_assert((select count(*)=4 from jsonb_array_elements(public.get_app_data()->'events') e
  where e->>'employeeId'=current_setting('test.workflow_employee')),'Nueva solicitud crea dos movimientos auditados');
-- Horario inferido visible y revisable.
reset role;
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
values(current_setting('test.workflow_employee')::uuid,current_setting('test.workflow_place')::uuid,'exit','2003-01-07 20:00:00-03','Salida sola',current_setting('test.workflow_user')::uuid);
select set_config('test.workflow_inferred',(select id::text from public.work_sessions where employee_id=current_setting('test.workflow_employee')::uuid and work_date='2003-01-07'),true);
set local role authenticated;
select public.admin_review_session(current_setting('test.workflow_inferred')::uuid,'corrected','09:00','20:00','Entrada confirmada');
select pg_temp.workflow_assert((select r->>'entry'='09:00' and not (r->>'inferredEntry')::boolean
  from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.workflow_inferred')),'Corrección de jornada automática inferida');
-- Solicitud obsoleta: no sobrescribe una modificación posterior.
select set_config('request.jwt.claim.sub',current_setting('test.workflow_user'),true);
select set_config('test.workflow_stale',gen_random_uuid()::text,true);
select public.request_session_correction(current_setting('test.workflow_stale')::uuid,current_setting('test.workflow_session')::uuid,
  current_setting('test.workflow_place')::uuid,'2003-01-05','07:45','19:45','Ajuste');
select set_config('request.jwt.claim.sub',current_setting('test.workflow_admin'),true);
select public.admin_review_session(current_setting('test.workflow_session')::uuid,'corrected','07:45','19:30','Nueva evidencia');
select pg_temp.workflow_error('select public.admin_resolve_correction('''||current_setting('test.workflow_stale')||''',true,''Confirmado'')','cambió');
select public.admin_resolve_correction(current_setting('test.workflow_stale')::uuid,false,'La jornada cambió');
select pg_temp.workflow_assert((select r->>'status'='rejected' from jsonb_array_elements(public.get_correction_requests()) r
  where r->>'id'=current_setting('test.workflow_stale')),'Rechazo con motivo conservado');
select pg_temp.workflow_error('select * from public.correction_requests','permission denied');
select pg_temp.workflow_error('select * from public.manual_session_requests','permission denied');
reset role;
rollback;
