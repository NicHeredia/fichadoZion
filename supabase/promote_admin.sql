-- Ejecutar en SQL Editor con el correo de tu propia cuenta.
-- No hace cambios si no encuentra ese usuario.
begin;
do $$
declare target_email text := 'REEMPLAZAR_CON_TU_CORREO';
        target_id uuid;
begin
  perform pg_advisory_xact_lock(73482001);
  select id into target_id from auth.users where lower(email)=lower(trim(target_email));
  if target_id is null then raise exception 'No se encontró el correo indicado. Reemplazá REEMPLAZAR_CON_TU_CORREO'; end if;
  if not exists(select 1 from public.employees where profile_id=target_id) then raise exception 'Falta el legajo del usuario. Verificá la migración 002'; end if;
  update public.profiles set role='admin',updated_at=now() where id=target_id;
  update public.employees set active=true,updated_at=now() where profile_id=target_id;
  insert into public.audit_logs(entity_type,entity_id,action,after_data)
    values('employee',target_id,'habilitación inicial de administrador',jsonb_build_object('role','admin'));
  raise notice 'Administrador habilitado para %',target_email;
end $$;
commit;
