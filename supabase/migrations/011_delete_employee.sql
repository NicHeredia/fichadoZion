-- Aplicar después de 010. Instala la función; no elimina datos al ejecutarse.
begin;

-- Quita registros del empleado de instantáneas y auditorías compartidas.
create function public.app_purge_employee_json(value jsonb, employee uuid) returns jsonb
language plpgsql immutable set search_path='' as $$
declare result jsonb;
begin
  if jsonb_typeof(value)='object' then
    if value->>'employeeId'=employee::text or value->>'employee_id'=employee::text then return null; end if;
    select coalesce(jsonb_object_agg(key,public.app_purge_employee_json(v,employee)),'{}'::jsonb)
      into result from jsonb_each(value) as x(key,v);
    return result;
  elsif jsonb_typeof(value)='array' then
    select coalesce(jsonb_agg(clean order by n) filter(where clean is not null),'[]'::jsonb)
      into result from (select public.app_purge_employee_json(v,employee) clean,n
        from jsonb_array_elements(value) with ordinality as x(v,n)) q;
    return result;
  end if;
  return value;
end $$;
revoke all on function public.app_purge_employee_json(jsonb,uuid) from public,anon,authenticated;

create function public.admin_delete_employee(p_id uuid,p_confirmation text) returns void
language plpgsql security definer set search_path='' as $$
declare target public.employees; related_ids uuid[];
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  select * into target from public.employees where id=p_id for update;
  if not found then raise exception 'El empleado ya no existe'; end if;
  if target.profile_id=auth.uid() then raise exception 'No podés eliminar tu propia cuenta administradora'; end if;
  if p_confirmation is distinct from target.employee_number then raise exception 'El legajo de confirmación no coincide'; end if;

  select array_agg(id) into related_ids from (
    select p_id id union select target.profile_id
    union select id from public.time_events where employee_id=p_id
    union select id from public.work_sessions where employee_id=p_id
    union select id from public.overtime_calculations where session_id in (select id from public.work_sessions where employee_id=p_id)
    union select id from public.review_cases where session_id in (select id from public.work_sessions where employee_id=p_id)
    union select id from public.correction_requests where employee_id=p_id
    union select id from public.overtime_compensations where employee_id=p_id
    union select id from public.monthly_closure_items where employee_id=p_id
  ) ids;
  delete from public.audit_logs where actor_id=target.profile_id or entity_id=any(related_ids);
  update public.audit_logs set before_data=public.app_purge_employee_json(before_data,p_id),
    after_data=public.app_purge_employee_json(after_data,p_id)
    where before_data::text like '%'||p_id::text||'%' or after_data::text like '%'||p_id::text||'%';
  update public.monthly_closures set snapshot=public.app_purge_employee_json(snapshot,p_id),updated_at=now()
    where snapshot::text like '%'||p_id::text||'%';
  delete from public.monthly_closure_items where employee_id=p_id;
  delete from public.correction_requests where employee_id=p_id;
  delete from public.manual_session_requests where actor=target.profile_id
    or session_id in (select id from public.work_sessions where employee_id=p_id);
  delete from public.review_cases where session_id in (select id from public.work_sessions where employee_id=p_id);
  update public.time_events set target_session_id=null where target_session_id in (select id from public.work_sessions where employee_id=p_id);
  delete from public.work_sessions where employee_id=p_id;
  delete from public.time_events where employee_id=p_id;
  delete from public.overtime_compensations where employee_id=p_id;

  -- Conserva las operaciones que esta persona realizó sobre otros empleados.
  update public.time_events set created_by=null where created_by=target.profile_id;
  update public.review_cases set resolved_by=null where resolved_by=target.profile_id;
  update public.correction_requests set resolved_by=null where resolved_by=target.profile_id;
  update public.monthly_closures set closed_by=null where closed_by=target.profile_id;
  -- Estas dos columnas no admiten NULL: la purga queda a cargo del administrador actual.
  update public.overtime_compensations set created_by=auth.uid() where created_by=target.profile_id;
  update public.overtime_compensations set updated_by=auth.uid() where updated_by=target.profile_id;
  delete from public.employees where id=p_id;
  delete from public.profiles where id=target.profile_id;
  delete from auth.users where id=target.profile_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action)
    values(auth.uid(),'employee',p_id,'eliminación definitiva de empleado e historial');
end $$;
revoke all on function public.admin_delete_employee(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_delete_employee(uuid,text) to authenticated;
commit;
