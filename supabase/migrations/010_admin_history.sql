-- Aplicar una vez después de 009. Edición auditada de cualquier jornada por administrador.
begin;
create or replace function public.get_checkout_capabilities() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  return jsonb_build_object('specificCheckout',true,'adminHistory',true);
end $$;

create function public.admin_edit_history(p_id uuid,p_expected jsonb,p_status public.review_status,
  p_institution uuid,p_entry time,p_exit time,p_institution_only boolean,p_notes text)
returns void language plpgsql security definer set search_path='' as $$
declare s public.work_sessions; old_data jsonb; a timestamptz; b timestamptz;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_status is null or p_status not in ('corrected','rejected') then raise exception 'Acción inválida'; end if;
  if length(trim(coalesce(p_notes,'')))=0 or length(p_notes)>2000 then raise exception 'Indicá un motivo de hasta 2000 caracteres'; end if;
  if p_institution_only is null then raise exception 'Acción incompleta'; end if;
  select * into s from public.work_sessions where id=p_id for update;
  if not found then raise exception 'Registro inexistente'; end if;
  if public.app_month_closed(s.work_date) then raise exception 'El mes está cerrado. Reabrilo antes de modificar fichajes'; end if;
  if p_expected is null or public.app_record(p_id) is distinct from p_expected then raise exception 'El fichaje cambió. Actualizá el historial y volvé a abrir la edición'; end if;
  old_data:=to_jsonb(s); a:=s.starts_at; b:=s.ends_at;
  if p_status='rejected' then
    if s.status='rejected' then raise exception 'El fichaje ya está desestimado'; end if;
    if p_institution_only or p_entry is not null or p_exit is not null or p_institution is distinct from s.institution_id then raise exception 'Desestimar no modifica horarios ni institución'; end if;
  else
    if p_institution is null then raise exception 'Seleccioná una institución'; end if;
    if p_institution is distinct from s.institution_id and not exists(select 1 from public.institutions where id=p_institution and active) then raise exception 'La institución no está habilitada'; end if;
    if p_institution_only then
      if p_entry is not null or p_exit is not null or p_institution is not distinct from s.institution_id then raise exception 'Seleccioná una institución diferente'; end if;
    else
      if p_entry is null or p_exit is null or p_entry>='24:00'::time or p_exit>='24:00'::time or p_exit<=p_entry then raise exception 'Completá ambos horarios. La salida debe ser posterior a la entrada'; end if;
      a:=(s.work_date+p_entry) at time zone 'America/Argentina/Buenos_Aires';
      b:=(s.work_date+p_exit) at time zone 'America/Argentina/Buenos_Aires';
      if b>now() then raise exception 'No se pueden guardar horarios futuros'; end if;
      if exists(select 1 from public.work_sessions w where w.employee_id=s.employee_id and w.work_date=s.work_date and w.id<>s.id and w.status<>'rejected' and w.starts_at is not null and w.ends_at is not null and a<w.ends_at and b>w.starts_at) then raise exception 'El horario se superpone con otra jornada del empleado'; end if;
    end if;
  end if;
  update public.work_sessions set
    institution_id=case when p_status='corrected' then p_institution else institution_id end,
    starts_at=a,ends_at=b,
    status=case when p_institution_only then s.status else p_status end,
    entry_inferred=case when p_status='corrected' and not p_institution_only then false else entry_inferred end,
    exit_inferred=case when p_status='corrected' and not p_institution_only then false else exit_inferred end,
    updated_at=now() where id=p_id;
  perform public.app_calculate(p_id);
  if (public.app_compensation_balance(s.employee_id)->>'available')::bigint<0 then raise exception 'El cambio dejaría sin respaldo horas ya compensadas o reservadas'; end if;
  if not p_institution_only then
    update public.review_cases set status=p_status,resolution_notes=trim(p_notes),resolved_by=auth.uid(),resolved_at=now(),updated_at=now() where session_id=p_id;
  end if;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'work_session',p_id,case when p_status='rejected' then 'desestimación administrativa' else 'corrección administrativa' end,old_data,jsonb_build_object('record',public.app_record(p_id),'notes',trim(p_notes)));
end $$;
revoke all on function public.admin_edit_history(uuid,jsonb,public.review_status,uuid,time,time,boolean,text) from public,anon,authenticated;
grant execute on function public.admin_edit_history(uuid,jsonb,public.review_status,uuid,time,time,boolean,text) to authenticated;
commit;
