-- Comprobaciones básicas de permisos. Ejecutar después de la migración 003 o el setup.sql actualizado.
-- No sustituye las pruebas de dos usuarios reales sobre la API.
begin;
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
