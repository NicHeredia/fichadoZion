-- Ejecutar después de 009 en una base de pruebas con el mes actual abierto.
-- Los usuarios y movimientos ficticios se revierten al terminar.
begin;
create function pg_temp.checkout_assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
create function pg_temp.checkout_error(statement text,fragment text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then if position(lower(fragment) in lower(sqlerrm))=0 then raise; end if; return; end;
  raise exception 'La operación no fue rechazada: %',statement;
end $$;
grant execute on function pg_temp.checkout_assert(boolean,text),pg_temp.checkout_error(text,text) to authenticated;
create temporary table checkout_ids(label text primary key,profile_id uuid default gen_random_uuid(),employee_id uuid);
insert into checkout_ids(label) values('admin'),('target'),('multiple'),('standalone'),('other'),('place');
insert into auth.users(id,email,raw_user_meta_data) select profile_id,profile_id||'@example.invalid','{"display_name":"Prueba cierre"}'::jsonb from checkout_ids;
update checkout_ids t set employee_id=e.id from public.employees e where e.profile_id=t.profile_id;
update public.profiles set role='admin' where id=(select profile_id from checkout_ids where label='admin');
grant select on checkout_ids to authenticated;
select set_config('test.checkout_a',gen_random_uuid()::text,true),set_config('test.checkout_b',gen_random_uuid()::text,true),
  set_config('test.checkout_request',gen_random_uuid()::text,true),set_config('test.checkout_correction',gen_random_uuid()::text,true),
  set_config('test.checkout_today',(now() at time zone 'America/Argentina/Buenos_Aires')::date::text,true);
insert into public.institutions(id,name) values(current_setting('test.checkout_a')::uuid,'Prueba entrada A'),(current_setting('test.checkout_b')::uuid,'Prueba entrada B');
update public.app_settings set starts_at='00:00',ends_at='00:01',weekdays=array[0,1,2,3,4,5,6];
delete from public.holidays where holiday_date=current_setting('test.checkout_today')::date;
select pg_temp.checkout_assert(not public.app_month_closed(current_setting('test.checkout_today')::date),'Mes actual abierto');
-- Preparar entradas abiertas con hora pasada y reglas históricas conocidas.
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select employee_id,current_setting('test.checkout_a')::uuid,'entry',
  (current_setting('test.checkout_today')::date+'00:00'::time) at time zone 'America/Argentina/Buenos_Aires','Inicio',profile_id
  from checkout_ids where label in ('target','multiple','place');
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select employee_id,current_setting('test.checkout_a')::uuid,'entry',
  ((current_setting('test.checkout_today')::date+'00:00'::time) at time zone 'America/Argentina/Buenos_Aires')+interval '1 second','Segunda entrada',profile_id
  from checkout_ids where label='multiple';
select set_config('test.checkout_target',(select s.id::text from public.work_sessions s where employee_id=(select employee_id from checkout_ids where label='target')),true);
select set_config('test.checkout_place',(select s.id::text from public.work_sessions s where employee_id=(select employee_id from checkout_ids where label='place')),true);
select set_config('test.checkout_multiple',(select s.id::text from public.work_sessions s where employee_id=(select employee_id from checkout_ids where label='multiple') order by starts_at desc limit 1),true);
-- Nueva configuración: cerrar una entrada debe conservar las reglas originales.
update public.app_settings set starts_at='01:00',ends_at='02:00';
set local role authenticated;
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='target'),true);
select pg_temp.checkout_assert((public.get_checkout_capabilities()->>'specificCheckout')::boolean,'Capacidad de cierre específico habilitada');
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_b')||''',''Urgencia'','''',gen_random_uuid(),null,true)','entradas abiertas');
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_b')||''',''Fin'','''',gen_random_uuid(),'''||current_setting('test.checkout_target')||''',false)','institución');
select pg_temp.checkout_error('select public.register_time_event(''exit'','''||current_setting('test.checkout_b')||''',''Cliente anterior'','''',gen_random_uuid())','entradas abiertas');
select pg_temp.checkout_assert(jsonb_array_length(public.get_app_data()->'events')=1,'Los intentos inválidos no crean salidas huérfanas');
select public.register_time_event_v2('exit',current_setting('test.checkout_a')::uuid,'Fin','',current_setting('test.checkout_request')::uuid,current_setting('test.checkout_target')::uuid,false);
select public.register_time_event_v2('exit',current_setting('test.checkout_a')::uuid,'Fin','',current_setting('test.checkout_request')::uuid,current_setting('test.checkout_target')::uuid,false);
select pg_temp.checkout_assert(jsonb_array_length(public.get_app_data()->'events')=2 and jsonb_array_length(public.get_app_data()->'records')=1,'Cierre y reintento: una jornada, dos movimientos');
select pg_temp.checkout_assert((select r->>'scheduleStart'='00:00' and r->>'scheduleEnd'='00:01' and r->>'status'='Automático' and not (r->>'inferredEntry')::boolean from jsonb_array_elements(public.get_app_data()->'records') r),'Se conservan las reglas de la entrada y su horario real');
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_a')||''',''Otro motivo'','''','''||current_setting('test.checkout_request')||''','''||current_setting('test.checkout_target')||''',false)','otro movimiento');
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_a')||''',''Otra salida'','''',gen_random_uuid(),'''||current_setting('test.checkout_target')||''',false)','ya no está abierta');
-- No se permite cerrar una jornada ajena o de otro día.
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='other'),true);
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_a')||''',''Ajena'','''',gen_random_uuid(),'''||current_setting('test.checkout_place')||''',false)','ya no está abierta');
-- Varias entradas en un mismo lugar: solo se cierra la elegida.
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='multiple'),true);
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_a')||''',''Sin elegir'','''',gen_random_uuid(),null,false)','entradas abiertas');
select public.register_time_event_v2('exit',current_setting('test.checkout_a')::uuid,'Cerrar segunda','',gen_random_uuid(),current_setting('test.checkout_multiple')::uuid,false);
select pg_temp.checkout_assert((select count(*)=1 from jsonb_array_elements(public.get_app_data()->'records') r where r->>'status'='Pendiente' and r->>'exit' is null),'La otra entrada permanece pendiente');
select pg_temp.checkout_assert((select r->>'status'='Automático' from jsonb_array_elements(public.get_app_data()->'records') r where r->>'id'=current_setting('test.checkout_multiple')),'Se cierra exactamente la entrada seleccionada');
-- Salida por urgencia: sin entrada abierta, se conserva la inferencia habitual.
reset role;
update public.app_settings set starts_at='00:00',ends_at='00:01';
set local role authenticated;
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='standalone'),true);
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_b')||''',''Urgencia'','''',gen_random_uuid(),null,false)','Confirmá');
select public.register_time_event_v2('exit',current_setting('test.checkout_b')::uuid,'Urgencia durante la jornada','',gen_random_uuid(),null,true);
select pg_temp.checkout_assert((select (r->>'inferredEntry')::boolean=((now() at time zone 'America/Argentina/Buenos_Aires')::time>='00:01'::time)
  and (r->>'minutes')::int=greatest(0,floor(extract(epoch from ((now() at time zone 'America/Argentina/Buenos_Aires')::time-'00:01'::time))/60)::int)
  from jsonb_array_elements(public.get_app_data()->'records') r),'Salida sola usa inicio habitual inferido y calcula minutos extra');
-- Corrección solo del lugar de una entrada todavía abierta.
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='place'),true);
select public.request_session_correction_v2(current_setting('test.checkout_correction')::uuid,current_setting('test.checkout_place')::uuid,
  current_setting('test.checkout_b')::uuid,current_setting('test.checkout_today')::date,null,null,'Elegí mal el lugar',true);
select public.request_session_correction_v2(current_setting('test.checkout_correction')::uuid,current_setting('test.checkout_place')::uuid,
  current_setting('test.checkout_b')::uuid,current_setting('test.checkout_today')::date,null,null,'Elegí mal el lugar',true);
select pg_temp.checkout_assert(jsonb_array_length(public.get_correction_requests())=1,'Reintento de corrección solo del lugar sin duplicados');
select pg_temp.checkout_assert((public.get_app_data()->'records'->0->>'institutionId')=current_setting('test.checkout_a'),'Solicitud no altera el lugar antes de aprobar');
select pg_temp.checkout_error('select public.admin_resolve_correction('''||current_setting('test.checkout_correction')||''',true,''Confirmado'')','administrador');
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='other'),true);
select pg_temp.checkout_error('select public.request_session_correction_v2(gen_random_uuid(),'''||current_setting('test.checkout_place')||''','''||current_setting('test.checkout_b')||''','''||current_setting('test.checkout_today')||''',null,null,''Ajena'',true)','disponible');
select pg_temp.checkout_assert(jsonb_array_length(public.get_correction_requests())=0,'Solicitudes de institución no se exponen a otros empleados');
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='admin'),true);
select public.admin_resolve_correction(current_setting('test.checkout_correction')::uuid,true,'Lugar confirmado');
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='place'),true);
select pg_temp.checkout_assert((public.get_app_data()->'records'->0->>'institutionId')=current_setting('test.checkout_b')
  and public.get_app_data()->'records'->0->>'exit' is null and public.get_app_data()->'records'->0->>'status'='Pendiente'
  and public.get_app_data()->'records'->0->>'scheduleEnd'='00:01','Se cambia el lugar sin inventar salida ni modificar reglas');
select pg_temp.checkout_assert((public.get_app_data()->'events'->0->>'institution')='Prueba entrada A','El fichaje original conserva su lugar declarado');
select public.register_time_event_v2('exit',current_setting('test.checkout_b')::uuid,'Fin en lugar corregido','',gen_random_uuid(),current_setting('test.checkout_place')::uuid,false);
select pg_temp.checkout_assert(jsonb_array_length(public.get_app_data()->'records')=1,'La salida cierra la misma jornada con institución corregida');
-- Una entrada histórica no puede seleccionarse para una salida de hoy.
reset role;
insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,created_by)
select employee_id,current_setting('test.checkout_a')::uuid,'entry','2003-02-05 06:00:00-03','Histórica',profile_id from checkout_ids where label='other';
select set_config('test.checkout_old',(select id::text from public.work_sessions where employee_id=(select employee_id from checkout_ids where label='other') and work_date='2003-02-05'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',(select profile_id::text from checkout_ids where label='other'),true);
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'','''||current_setting('test.checkout_a')||''',''Otro día'','''',gen_random_uuid(),'''||current_setting('test.checkout_old')||''',false)','ya no está abierta');
-- Funciones nuevas no están disponibles sin autenticación.
set local role anon;
select pg_temp.checkout_error('select public.get_checkout_capabilities()','permission denied');
select pg_temp.checkout_error('select public.register_time_event_v2(''exit'',gen_random_uuid(),''Anónimo'','''',gen_random_uuid(),null,true)','permission denied');
reset role;
rollback;
