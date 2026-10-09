-- Ejecutar tras 006. Datos ficticios dentro de una transacción; ROLLBACK revierte todo.
begin;
create function pg_temp.manual_assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
create function pg_temp.manual_error(statement text,fragment text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if position(lower(fragment) in lower(sqlerrm))=0 then raise; end if;
    return;
  end;
  raise exception 'La operación no fue rechazada: %',statement;
end $$;
grant execute on function pg_temp.manual_assert(boolean,text),pg_temp.manual_error(text,text) to authenticated;
select set_config('test.manual_admin',gen_random_uuid()::text,true),set_config('test.manual_user',gen_random_uuid()::text,true),
  set_config('test.manual_place',gen_random_uuid()::text,true),set_config('test.manual_request',gen_random_uuid()::text,true),
  set_config('test.manual_reservation',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select id::uuid,id||'@example.invalid','{"display_name":"Prueba manual"}'::jsonb
from unnest(array[current_setting('test.manual_admin'),current_setting('test.manual_user')]) id;
update public.profiles set role='admin' where id=current_setting('test.manual_admin')::uuid;
select set_config('test.manual_employee',(select id::text from public.employees where profile_id=current_setting('test.manual_user')::uuid),true);
insert into public.institutions(id,name) values(current_setting('test.manual_place')::uuid,'Prueba manual');
update public.app_settings set starts_at='08:00',ends_at='17:00',weekdays=array[0,1,2,3,4,5,6];
delete from public.holidays where holiday_date between '2002-01-05' and '2002-01-07';
select pg_temp.manual_assert(not public.app_month_closed('2002-01-05'),'Mes de prueba abierto');
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.manual_admin'),true);
select public.admin_register_manual_event(current_setting('test.manual_employee')::uuid,'entry',current_setting('test.manual_place')::uuid,
  '2002-01-05','06:00','Olvido de entrada','',current_setting('test.manual_request')::uuid);
-- El mismo identificador devuelve el mismo evento sin duplicarlo.
select public.admin_register_manual_event(current_setting('test.manual_employee')::uuid,'entry',current_setting('test.manual_place')::uuid,
  '2002-01-05','06:00','Olvido de entrada','',current_setting('test.manual_request')::uuid);
select set_config('test.manual_session',(select id::text from public.work_sessions where employee_id=current_setting('test.manual_employee')::uuid and work_date='2002-01-05'),true);
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''exit'','''||current_setting('test.manual_place')||''',''2002-01-05'',''20:00'',''Olvido'','''',gen_random_uuid())','Seleccioná');
select public.admin_register_manual_event(current_setting('test.manual_employee')::uuid,'exit',current_setting('test.manual_place')::uuid,
  '2002-01-05','20:00','Olvido de salida','',gen_random_uuid(),current_setting('test.manual_session')::uuid);
select pg_temp.manual_assert((select r->>'status'='Corregido' and (r->>'minutes')::int=300
  from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.manual_session')),'Dos movimientos manuales, una jornada y cinco horas extra');
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''entry'','''||current_setting('test.manual_place')||''',''2002-01-05'',''06:00'',''Duplicado'','''',gen_random_uuid())','mismo minuto');
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''entry'','''||current_setting('test.manual_place')||''',''2002-01-05'',''07:00'',''Superpuesto'','''',gen_random_uuid())','superpone');
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''entry'','''||current_setting('test.manual_place')||''',((now() at time zone ''America/Argentina/Buenos_Aires'')::date+1),''06:00'',''Futuro'','''',gen_random_uuid())','futuros');
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''entry'','''||current_setting('test.manual_place')||''',''2002-01-05'',''05:00'','' '','''',gen_random_uuid())','Completá');

-- Entrada real sin salida: Cron la completa; el administrador agrega la salida real.
reset role;
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
values(current_setting('test.manual_employee')::uuid,current_setting('test.manual_place')::uuid,'entry','2002-01-06 06:00:00-03','Entrada real',current_setting('test.manual_user')::uuid);
select public.app_finalize_open_sessions();
select set_config('test.manual_inferred',(select id::text from public.work_sessions where employee_id=current_setting('test.manual_employee')::uuid and work_date='2002-01-06'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.manual_admin'),true);
select public.admin_register_manual_event(current_setting('test.manual_employee')::uuid,'exit',current_setting('test.manual_place')::uuid,
  '2002-01-06','20:00','Salida verificada','',gen_random_uuid(),current_setting('test.manual_inferred')::uuid);
select pg_temp.manual_assert((select not (r->>'inferredExit')::boolean and r->>'exit'='20:00' and (r->>'minutes')::int=300
  from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.manual_inferred')),
  'Salida real reemplaza la inferida sin crear otra jornada');

-- Salida real sin entrada: al cargar la entrada olvidada, proteger el saldo comprometido.
reset role;
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
values(current_setting('test.manual_employee')::uuid,current_setting('test.manual_place')::uuid,'exit','2002-01-07 20:00:00-03','Salida real',current_setting('test.manual_user')::uuid);
select set_config('test.manual_orphan',(select id::text from public.work_sessions where employee_id=current_setting('test.manual_employee')::uuid and work_date='2002-01-07'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.manual_admin'),true);
select public.admin_create_compensation(current_setting('test.manual_reservation')::uuid,current_setting('test.manual_employee')::uuid,780,
  (now() at time zone 'America/Argentina/Buenos_Aires')::date,'Reservar saldo','scheduled');
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''entry'','''||current_setting('test.manual_place')||''',''2002-01-07'',''18:00'',''Entrada verificada'','''',gen_random_uuid(),'''||current_setting('test.manual_orphan')||''')','sin respaldo');
select public.admin_change_compensation(current_setting('test.manual_reservation')::uuid,'cancelled','Liberar reserva para corregir');
select public.admin_register_manual_event(current_setting('test.manual_employee')::uuid,'entry',current_setting('test.manual_place')::uuid,
  '2002-01-07','18:00','Entrada verificada','',gen_random_uuid(),current_setting('test.manual_orphan')::uuid);
select pg_temp.manual_assert((select not (r->>'inferredEntry')::boolean and (r->>'minutes')::int=120
  from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.manual_orphan')),'La entrada real recalcula el saldo');

-- Autorización, RLS y trazabilidad para el empleado.
select set_config('request.jwt.claim.sub',current_setting('test.manual_user'),true);
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''entry'','''||current_setting('test.manual_place')||''',''2002-01-08'',''06:00'',''Fraude'','''',gen_random_uuid())','administrador');
select pg_temp.manual_assert(jsonb_array_length(public.get_app_data()->'records')=3 and jsonb_array_length(public.get_app_data()->'events')=6,
  'Solo tres jornadas y seis movimientos originales');
select pg_temp.manual_assert((select count(*)=4 from jsonb_array_elements(public.get_app_data()->'events') e
  where (e->>'manual')::boolean and (e->>'recordedAt')::timestamptz>(e->>'occurredAt')::timestamptz),'Se distinguen los manuales y su fecha de carga');
reset role;
select pg_temp.manual_assert((select count(*)=4 from public.audit_logs where actor_id=current_setting('test.manual_admin')::uuid and action='Fichaje manual'),
  'Cuatro cargas manuales auditadas, sin eventos de operaciones fallidas');
select pg_temp.manual_assert(not has_function_privilege('anon','public.admin_register_manual_event(uuid,public.event_type,uuid,date,time,text,text,uuid,uuid)','execute'),'Sin acceso anónimo');
insert into public.monthly_closures(year,month,version,closed_by,closed_at) values(2001,1,1,current_setting('test.manual_admin')::uuid,now());
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.manual_admin'),true);
select pg_temp.manual_error('select public.admin_register_manual_event('''||current_setting('test.manual_employee')||''',''entry'','''||current_setting('test.manual_place')||''',''2001-01-05'',''06:00'',''Cerrado'','''',gen_random_uuid())','cerrado');
reset role;
rollback;
select 'OK: fichajes manuales, horas inferidas, permisos, auditoría y saldo. Datos revertidos.' as resultado;
