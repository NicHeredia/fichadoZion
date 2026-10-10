-- Pruebas aisladas: se revierten todos los datos.
begin;
create function pg_temp.history_assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
create function pg_temp.history_error(statement text,fragment text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then if position(lower(fragment) in lower(sqlerrm))=0 then raise; end if; return; end;
  raise exception 'La operación no fue rechazada: %',statement;
end $$;
do $$
declare adm uuid:=gen_random_uuid(); usr uuid:=gen_random_uuid(); emp uuid;
  place uuid:=gen_random_uuid(); other_place uuid:=gen_random_uuid(); sid uuid; before_record jsonb;
  event_snapshot jsonb; audit_count bigint;
begin
  insert into auth.users(id,email,raw_user_meta_data) values
    (adm,adm||'@example.invalid','{"display_name":"Admin historial"}'),
    (usr,usr||'@example.invalid','{"display_name":"Empleado historial"}');
  update public.profiles set role='admin' where id=adm;
  select id into emp from public.employees where profile_id=usr;
  insert into public.institutions(id,name) values(place,'Historial A'),(other_place,'Historial B');
  update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
  delete from public.holidays where holiday_date='2002-02-04';
  perform set_config('request.jwt.claim.sub',adm::text,true);
  sid:=public.admin_register_manual_session(emp,place,'2002-02-04','08:00','20:00','Prueba historial','',gen_random_uuid());
  update public.work_sessions set status='approved' where id=sid;
  before_record:=public.app_record(sid);
  select jsonb_agg(to_jsonb(e) order by id) into event_snapshot from public.time_events e where employee_id=emp;
  perform set_config('request.jwt.claim.sub',usr::text,true);
  perform pg_temp.history_error(format('select public.admin_edit_history(%L,%L::jsonb,''rejected'',%L,null,null,false,''Sin permiso'')',sid,before_record,place),'administrador');
  perform set_config('request.jwt.claim.sub',adm::text,true);
  perform pg_temp.history_error(format('select public.admin_edit_history(%L,%L::jsonb,''rejected'',%L,null,null,false,'''')',sid,before_record,place),'motivo');
  perform public.admin_edit_history(sid,before_record,'corrected',other_place,'08:00','19:00',false,'Horario e institución reales');
  perform pg_temp.history_assert((select status='corrected' and institution_id=other_place from public.work_sessions where id=sid),'Corrige un aceptado y cambia institución');
  perform pg_temp.history_assert((public.app_record(sid)->>'minutes')::int=120,'Recalcula horas');
  perform pg_temp.history_error(format('select public.admin_edit_history(%L,%L::jsonb,''rejected'',%L,null,null,false,''Vista vieja'')',sid,before_record,other_place),'cambió');
  before_record:=public.app_record(sid);
  perform public.admin_edit_history(sid,before_record,'corrected',place,null,null,true,'Solo institución');
  perform pg_temp.history_assert(public.app_record(sid)->>'entry'='08:00' and public.app_record(sid)->>'exit'='19:00','Solo institución conserva horarios');
  perform public.admin_create_compensation(gen_random_uuid(),emp,60,(now() at time zone 'America/Argentina/Buenos_Aires')::date,'Reserva de prueba','scheduled');
  before_record:=public.app_record(sid);
  select count(*) into audit_count from public.audit_logs;
  perform pg_temp.history_error(format('select public.admin_edit_history(%L,%L::jsonb,''rejected'',%L,null,null,false,''Desestimar'')',sid,before_record,place),'respaldo');
  perform pg_temp.history_error(format('select public.admin_edit_history(%L,%L::jsonb,''corrected'',%L,''08:00'',''17:00'',false,''Reducir horas'')',sid,before_record,place),'respaldo');
  perform pg_temp.history_assert(public.app_record(sid)=before_record and (select count(*)=audit_count from public.audit_logs),'Saldo protegido revierte cambios y auditoría');
  perform public.admin_close_month('2002-02-01');
  perform pg_temp.history_error(format('select public.admin_edit_history(%L,%L::jsonb,''corrected'',%L,''08:00'',''20:00'',false,''Mes cerrado'')',sid,before_record,place),'cerrado');
  perform public.admin_reopen_month('2002-02-01','Prueba de reapertura');
  update public.overtime_compensations set status='cancelled' where employee_id=emp;
  perform public.admin_edit_history(sid,before_record,'rejected',place,null,null,false,'Registro de prueba desestimado');
  perform pg_temp.history_assert((select status='rejected' from public.work_sessions where id=sid),'Desestima un corregido');
  perform pg_temp.history_assert((public.app_compensation_balance(emp)->>'available')::int=0,'Desestimado sin crédito');
  perform public.admin_edit_history(sid,public.app_record(sid),'corrected',place,'08:00','20:00',false,'Restablecer con horarios verificados');
  perform pg_temp.history_assert((select status='corrected' from public.work_sessions where id=sid),'Recupera rechazado mediante corrección explícita');
  perform pg_temp.history_assert(event_snapshot=(select jsonb_agg(to_jsonb(e) order by id) from public.time_events e where employee_id=emp),'Conserva fichajes originales');
  perform pg_temp.history_assert(exists(select 1 from public.audit_logs where entity_id=sid and action='desestimación administrativa' and after_data->>'notes'='Registro de prueba desestimado'),'Audita motivo de desestimación');
end $$;
rollback;
