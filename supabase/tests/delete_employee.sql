begin;
create function pg_temp.purge_assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
create function pg_temp.purge_error(statement text,fragment text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then if position(lower(fragment) in lower(sqlerrm))=0 then raise; end if; return; end;
  raise exception 'La operación no fue rechazada: %',statement;
end $$;
create table public.purge_test_blocker(id uuid references auth.users(id));
do $$
declare adm uuid:=gen_random_uuid(); usr uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid();
  emp uuid; other_emp uuid; admin_emp uuid; place uuid:=gen_random_uuid(); sid uuid; other_sid uuid;
  legajo text; admin_number text; cid uuid; snapshot_before jsonb;
begin
  insert into auth.users(id,email,raw_user_meta_data) values
    (adm,adm||'@example.invalid','{"display_name":"Admin purga"}'),
    (usr,usr||'@example.invalid','{"display_name":"Prueba a eliminar"}'),
    (other_user,other_user||'@example.invalid','{"display_name":"Conservar"}');
  update public.profiles set role='admin' where id in (adm,usr);
  select id,employee_number into emp,legajo from public.employees where profile_id=usr;
  select id,employee_number into admin_emp,admin_number from public.employees where profile_id=adm;
  select id into other_emp from public.employees where profile_id=other_user;
  insert into public.institutions(id,name) values(place,'Prueba purga');
  update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
  delete from public.holidays where holiday_date='2001-02-05';
  perform set_config('request.jwt.claim.sub',usr::text,true);
  sid:=public.admin_register_manual_session(emp,place,'2001-02-05','08:00','20:00','Prueba purga','',gen_random_uuid());
  other_sid:=public.admin_register_manual_session(other_emp,place,'2001-02-05','08:00','20:00','Conservar','',gen_random_uuid());
  perform public.admin_create_compensation(gen_random_uuid(),emp,30,current_date,'Prueba','scheduled');
  perform public.admin_create_compensation(gen_random_uuid(),other_emp,30,current_date,'Conservar','scheduled');
  insert into public.review_cases(session_id,reason,resolved_by) values(sid,'Prueba',usr),(other_sid,'Conservar',usr);
  insert into public.correction_requests(id,employee_id,session_id,institution_id,work_date,proposed_entry,proposed_exit,reason,status,resolved_by)
    values(gen_random_uuid(),emp,sid,place,'2001-02-05','08:00','20:00','Prueba','rejected',usr),
      (gen_random_uuid(),other_emp,other_sid,place,'2001-02-05','08:00','20:00','Conservar','rejected',usr);
  insert into public.notifications(profile_id,title,body) values(usr,'Prueba','Prueba');
  insert into public.work_schedules(employee_id,weekday,starts_at,ends_at,valid_from) values(emp,1,'08:00','17:00','2001-01-01');
  perform public.admin_close_month('2001-02-01');
  select id into cid from public.monthly_closures where year=2001 and month=2;
  snapshot_before:=public.app_record(other_sid);
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.purge_error(format('select public.admin_delete_employee(%L,%L)',emp,legajo),'administrador');
  perform set_config('request.jwt.claim.sub',other_user::text,true);
  perform pg_temp.purge_error(format('select public.admin_delete_employee(%L,%L)',emp,legajo),'administrador');
  perform set_config('request.jwt.claim.sub',adm::text,true);
  perform pg_temp.purge_error(format('select public.admin_delete_employee(%L,%L)',admin_emp,admin_number),'propia cuenta');
  perform pg_temp.purge_error(format('select public.admin_delete_employee(%L,%L)',emp,'incorrecto'),'legajo');
  update public.employees set active=false where profile_id=adm;
  perform pg_temp.purge_error(format('select public.admin_delete_employee(%L,%L)',emp,legajo),'administrador');
  update public.employees set active=true where profile_id=adm;
  insert into public.purge_test_blocker values(usr);
  perform pg_temp.purge_error(format('select public.admin_delete_employee(%L,%L)',emp,legajo),'foreign key');
  perform pg_temp.purge_assert(exists(select 1 from public.work_sessions where id=sid) and exists(select 1 from public.notifications where profile_id=usr),'Un error revierte toda la purga');
  delete from public.purge_test_blocker where id=usr;
  perform public.admin_delete_employee(emp,legajo);
  perform pg_temp.purge_assert(not exists(select 1 from auth.users where id=usr) and not exists(select 1 from public.profiles where id=usr) and not exists(select 1 from public.employees where id=emp),'Elimina cuenta, perfil y empleado');
  perform pg_temp.purge_assert(not exists(select 1 from public.time_events where employee_id=emp) and not exists(select 1 from public.work_sessions where employee_id=emp),'Elimina fichajes y jornadas');
  perform pg_temp.purge_assert(not exists(select 1 from public.overtime_calculations where session_id=sid) and not exists(select 1 from public.review_cases where session_id=sid),'Elimina cálculo y revisiones');
  perform pg_temp.purge_assert(not exists(select 1 from public.correction_requests where employee_id=emp) and not exists(select 1 from public.manual_session_requests where session_id=sid),'Elimina solicitudes');
  perform pg_temp.purge_assert(not exists(select 1 from public.overtime_compensations where employee_id=emp) and not exists(select 1 from public.notifications where profile_id=usr) and not exists(select 1 from public.work_schedules where employee_id=emp),'Elimina descansos, notificaciones y horarios');
  perform pg_temp.purge_assert(not exists(select 1 from public.monthly_closure_items where employee_id=emp) and (select snapshot=jsonb_build_array(snapshot_before) from public.monthly_closures where id=cid),'Depura cierre y conserva al otro empleado');
  perform pg_temp.purge_assert(public.app_record(other_sid)=snapshot_before and exists(select 1 from public.overtime_compensations where employee_id=other_emp),'Conserva historial ajeno creado por el administrador eliminado');
  perform pg_temp.purge_assert(not exists(select 1 from public.audit_logs where actor_id=usr or entity_id=sid) and exists(select 1 from public.audit_logs where entity_id=emp and actor_id=adm and action='eliminación definitiva de empleado e historial'),'Depura auditoría y deja constancia de la purga');
  perform pg_temp.purge_error(format('select public.admin_delete_employee(%L,%L)',emp,legajo),'ya no existe');
  perform pg_temp.purge_assert(not has_function_privilege('anon','public.admin_delete_employee(uuid,text)','execute') and has_function_privilege('authenticated','public.admin_delete_employee(uuid,text)','execute'),'Permisos de RPC');
end $$;
rollback;
