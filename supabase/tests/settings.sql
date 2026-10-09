-- Ejecutar tras 007. Revertir todos los cambios con ROLLBACK.
begin;
create function pg_temp.settings_assert(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Prueba fallida: %',message; end if; end $$;
grant execute on function pg_temp.settings_assert(boolean,text) to authenticated;
select set_config('test.settings_admin',gen_random_uuid()::text,true),
  set_config('test.settings_a','Prueba A '||gen_random_uuid()::text,true),
  set_config('test.settings_b','Prueba B '||gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
values(current_setting('test.settings_admin')::uuid,current_setting('test.settings_admin')||'@example.invalid','{"display_name":"Prueba configuración"}');
update public.profiles set role='admin' where id=current_setting('test.settings_admin')::uuid;
-- Verificar que no queden borrados sin WHERE en la función desplegada.
select pg_temp.settings_assert((select prosrc !~* 'delete\s+from\s+public\.holidays\s*;'
  from pg_proc where oid='public.admin_save_settings(time,time,integer[],text[],date[])'::regprocedure),
  'El guardado no ejecuta DELETE sin filtro');
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.settings_admin'),true);
-- Agregar instituciones y un feriado.
select public.admin_save_settings('08:00','17:00',array[1,2,3,4,5],
  array[current_setting('test.settings_a'),current_setting('test.settings_b')],array['2192-01-05'::date]);
select pg_temp.settings_assert(jsonb_array_length(public.get_app_data()->'institutions')=2,'Se agregan ambas instituciones');
select set_config('test.settings_a_id',(select id::text from public.institutions where name=current_setting('test.settings_a')),true);
reset role;
select set_config('test.settings_holiday_id',(select id::text from public.holidays where holiday_date='2192-01-05'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.settings_admin'),true);
-- Quitar una institución y agregar otro feriado; mantener el anterior.
select public.admin_save_settings('08:00','17:00',array[1,2,3,4,5],
  array[current_setting('test.settings_b')],array['2192-01-05'::date,'2192-01-06'::date]);
select pg_temp.settings_assert(jsonb_array_length(public.get_app_data()->'institutions')=1,'La institución quitada deja de estar activa');
reset role;
select pg_temp.settings_assert(exists(select 1 from public.institutions where id=current_setting('test.settings_a_id')::uuid and not active),'Se conserva la institución quitada y su ID');
select pg_temp.settings_assert(exists(select 1 from public.holidays where id=current_setting('test.settings_holiday_id')::uuid and holiday_date='2192-01-05'),'El feriado conservado mantiene su ID');
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.settings_admin'),true);
-- Reagregar una institución, quitar feriados y guardar sin feriados nuevamente.
select public.admin_save_settings('08:00','17:00',array[1,2,3,4,5],
  array[current_setting('test.settings_a'),current_setting('test.settings_b')],array[]::date[]);
select public.admin_save_settings('08:00','17:00',array[1,2,3,4,5],
  array[current_setting('test.settings_a'),current_setting('test.settings_b')],array[]::date[]);
select pg_temp.settings_assert(jsonb_array_length(public.get_app_data()->'institutions')=2,'Las instituciones se reactivan sin duplicados');
reset role;
select pg_temp.settings_assert(exists(select 1 from public.institutions where id=current_setting('test.settings_a_id')::uuid and active),'La institución reactivada mantiene su ID');
select pg_temp.settings_assert(not exists(select 1 from public.holidays),'Se admite guardar sin feriados');
select pg_temp.settings_assert((select count(*)=4 from public.audit_logs where actor_id=current_setting('test.settings_admin')::uuid and action='configuración'),'Los cambios quedan auditados');
rollback;
select 'OK: altas, bajas y reactivación de instituciones; feriados y auditoría. Cambios revertidos.' as resultado;
