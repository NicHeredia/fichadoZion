-- Aplicar una sola vez después de 008. Conserva la salida sola por urgencias.
begin;
alter table public.time_events add column standalone_exit_confirmed boolean not null default false;

create function public.get_checkout_capabilities() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  return jsonb_build_object('specificCheckout',true);
end $$;
revoke all on function public.get_checkout_capabilities() from public,anon,authenticated;
grant execute on function public.get_checkout_capabilities() to authenticated;

create function public.register_time_event_v2(p_event_type public.event_type,p_institution_id uuid,p_reason text,p_notes text,
  p_request_id uuid,p_target uuid default null,p_confirm_without_entry boolean default false)
returns setof public.time_events language plpgsql security definer set search_path='' as $$
declare employee uuid; existing public.time_events; s public.work_sessions; d date;
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  perform pg_advisory_xact_lock(73482001);
  select id into employee from public.employees where profile_id=auth.uid() and active;
  if employee is null then raise exception 'Empleado no habilitado'; end if;
  if p_event_type is null or p_request_id is null or p_institution_id is null
    or p_reason is null or length(trim(p_reason)) not between 1 and 1000 or length(coalesce(p_notes,''))>2000
    or p_confirm_without_entry is null then raise exception 'Completá movimiento, lugar y motivo'; end if;
  select * into existing from public.time_events where created_by=auth.uid() and client_request_id=p_request_id;
  if found then
    if not existing.is_manual and existing.employee_id=employee and existing.event_type=p_event_type
      and existing.institution_id=p_institution_id and existing.reason=trim(p_reason)
      and existing.notes is not distinct from nullif(trim(coalesce(p_notes,'')),'')
      and existing.target_session_id is not distinct from p_target
      and existing.standalone_exit_confirmed=p_confirm_without_entry then return next existing; return; end if;
    raise exception 'La solicitud ya corresponde a otro movimiento';
  end if;
  d := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  if public.app_month_closed(d) then raise exception 'El período está cerrado'; end if;
  if p_event_type='entry' then
    if p_target is not null or p_confirm_without_entry then raise exception 'La entrada no admite una jornada a cerrar'; end if;
  elsif p_target is not null then
    select * into s from public.work_sessions where id=p_target for update;
    if not found or s.employee_id<>employee or s.work_date<>d or s.status<>'pending'
      or s.entry_event_id is null or s.exit_event_id is not null or s.ends_at is not null or s.starts_at is null then
      raise exception 'La entrada elegida ya no está abierta para hoy. Actualizá los datos';
    end if;
    if s.institution_id is distinct from p_institution_id then raise exception 'La institución debe coincidir con la entrada elegida'; end if;
    if p_confirm_without_entry or s.starts_at>=now() then raise exception 'Salida inválida para la entrada seleccionada'; end if;
  else
    if exists(select 1 from public.work_sessions where employee_id=employee and work_date=d and status='pending'
      and entry_event_id is not null and exit_event_id is null and ends_at is null) then
      raise exception 'Tenés entradas abiertas. Elegí cuál querés cerrar y conservá su institución';
    end if;
    if not p_confirm_without_entry then raise exception 'Confirmá que querés registrar solo la salida por una urgencia u otro motivo'; end if;
  end if;
  -- Una institución deshabilitada puede cerrar una entrada ya existente de ese lugar.
  if p_target is null and not exists(select 1 from public.institutions where id=p_institution_id and active) then raise exception 'Institución no habilitada'; end if;
  if exists(select 1 from public.time_events where employee_id=employee and event_type=p_event_type
    and occurred_at>now()-interval '1 minute') then raise exception 'Movimiento duplicado reciente'; end if;
  return query insert into public.time_events(employee_id,institution_id,event_type,reason,notes,created_by,client_request_id,target_session_id,standalone_exit_confirmed)
    values(employee,p_institution_id,p_event_type,trim(p_reason),nullif(trim(coalesce(p_notes,'')),''),auth.uid(),p_request_id,p_target,p_confirm_without_entry) returning *;
end $$;
revoke all on function public.register_time_event_v2(public.event_type,uuid,text,text,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.register_time_event_v2(public.event_type,uuid,text,text,uuid,uuid,boolean) to authenticated;

-- Los clientes anteriores también deben cumplir la validación del servidor.
create or replace function public.register_time_event(p_event_type public.event_type,p_institution_id uuid,p_reason text,p_notes text,p_request_id uuid)
returns setof public.time_events language sql security definer set search_path='' as $$
  select * from public.register_time_event_v2(p_event_type,p_institution_id,p_reason,p_notes,p_request_id,null,false);
$$;

alter table public.correction_requests add column institution_only boolean not null default false;
alter table public.correction_requests alter column proposed_entry drop not null, alter column proposed_exit drop not null;
alter table public.correction_requests drop constraint correction_requests_check;
alter table public.correction_requests add constraint correction_proposal_valid check(
  (institution_only and session_id is not null and proposed_entry is null and proposed_exit is null)
  or (not institution_only and proposed_entry is not null and proposed_exit is not null and proposed_exit>proposed_entry and proposed_exit<'24:00'::time));

create function public.request_session_correction_v2(p_id uuid,p_session uuid,p_institution uuid,p_date date,
  p_entry time,p_exit time,p_reason text,p_institution_only boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare employee uuid; s public.work_sessions; old_request public.correction_requests;
begin
  perform pg_advisory_xact_lock(73482001);
  select id into employee from public.employees where profile_id=auth.uid() and active;
  if employee is null then raise exception 'Empleado no habilitado'; end if;
  if p_id is null or p_institution is null or p_date is null or p_institution_only is null
    or p_reason is null or length(trim(p_reason)) not between 1 and 1000 then raise exception 'Completá fecha, lugar y motivo'; end if;
  if p_institution_only then
    if p_session is null or p_entry is not null or p_exit is not null then raise exception 'Para corregir solo el lugar, elegí una jornada y conservá sus horarios'; end if;
  elsif p_entry is null or p_exit is null or p_exit<=p_entry or p_exit>='24:00'::time then raise exception 'Completá ambos horarios del mismo día'; end if;
  select * into old_request from public.correction_requests where id=p_id;
  if found then
    if old_request.employee_id=employee and old_request.session_id is not distinct from p_session
      and old_request.institution_id=p_institution and old_request.work_date=p_date
      and old_request.proposed_entry is not distinct from p_entry and old_request.proposed_exit is not distinct from p_exit
      and old_request.institution_only=p_institution_only and old_request.reason=trim(p_reason) then return p_id; end if;
    raise exception 'La solicitud ya corresponde a otros datos';
  end if;
  if p_date>(now() at time zone 'America/Argentina/Buenos_Aires')::date
    or (not p_institution_only and (p_date+p_exit) at time zone 'America/Argentina/Buenos_Aires'>now()) then raise exception 'No se pueden solicitar horarios futuros'; end if;
  if public.app_month_closed(p_date) then raise exception 'El período está cerrado. Solicitá su reapertura al administrador'; end if;
  if p_session is not null then
    select * into s from public.work_sessions where id=p_session;
    if not found or s.employee_id<>employee or s.status='rejected' then raise exception 'Jornada no disponible'; end if;
    if s.work_date<>p_date then raise exception 'Conservá la fecha de la jornada'; end if;
    if p_institution_only and s.institution_id=p_institution then raise exception 'Elegí la institución correcta, distinta a la actual'; end if;
  end if;
  if (p_session is null or s.institution_id is distinct from p_institution)
    and not exists(select 1 from public.institutions where id=p_institution and active) then raise exception 'Institución no habilitada'; end if;
  if exists(select 1 from public.correction_requests where employee_id=employee and status='pending'
    and ((p_session is not null and session_id=p_session) or (p_session is null and session_id is null and work_date=p_date and institution_id=p_institution))) then
    raise exception 'Ya tenés una solicitud pendiente para esta jornada';
  end if;
  insert into public.correction_requests(id,employee_id,session_id,institution_id,work_date,proposed_entry,proposed_exit,reason,session_snapshot,institution_only)
    values(p_id,employee,p_session,p_institution,p_date,p_entry,p_exit,trim(p_reason),case when p_session is not null then to_jsonb(s) end,p_institution_only);
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,after_data)
    values(auth.uid(),'correction_request',p_id,'Solicitud de corrección',(select to_jsonb(r) from public.correction_requests r where id=p_id));
  return p_id;
end $$;
revoke all on function public.request_session_correction_v2(uuid,uuid,uuid,date,time,time,text,boolean) from public,anon,authenticated;
grant execute on function public.request_session_correction_v2(uuid,uuid,uuid,date,time,time,text,boolean) to authenticated;

create or replace function public.admin_resolve_correction(p_id uuid,p_approve boolean,p_notes text) returns void
language plpgsql security definer set search_path='' as $$
declare r public.correction_requests; s public.work_sessions;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  select * into r from public.correction_requests where id=p_id for update;
  if not found or p_approve is null then raise exception 'Solicitud inexistente'; end if;
  if r.status<>'pending' then
    if r.status=(case when p_approve then 'approved' else 'rejected' end) then return; end if;
    raise exception 'La solicitud ya fue resuelta';
  end if;
  if p_notes is null or length(trim(p_notes)) not between 1 and 1000 then raise exception 'Ingresá el motivo de la decisión'; end if;
  if public.app_month_closed(r.work_date) then raise exception 'El período está cerrado'; end if;
  if p_approve then
    if r.session_id is null then
      perform public.admin_register_manual_session(r.employee_id,r.institution_id,r.work_date,r.proposed_entry,r.proposed_exit,r.reason,p_notes,r.id);
    else
      select * into s from public.work_sessions where id=r.session_id for update;
      if to_jsonb(s) is distinct from r.session_snapshot then raise exception 'La jornada cambió desde la solicitud. Rechazala y pedí una nueva'; end if;
      if s.institution_id is distinct from r.institution_id then
        if not exists(select 1 from public.institutions where id=r.institution_id and active) then raise exception 'Institución no habilitada'; end if;
        update public.work_sessions set institution_id=r.institution_id,updated_at=now() where id=s.id;
        insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
          values(auth.uid(),'work_session',s.id,'Institución corregida por solicitud',to_jsonb(s),
            jsonb_build_object('record',public.app_record(s.id),'notes',r.reason || ' / ' || p_notes));
      end if;
      if not r.institution_only then
        perform public.admin_review_session(r.session_id,'corrected',r.proposed_entry,r.proposed_exit,r.reason || ' / ' || p_notes);
      end if;
    end if;
  end if;
  update public.correction_requests set status=case when p_approve then 'approved' else 'rejected' end,
    resolution_notes=trim(p_notes),resolved_by=auth.uid(),resolved_at=now() where id=p_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'correction_request',p_id,'Resolución de solicitud',to_jsonb(r),(select to_jsonb(c) from public.correction_requests c where id=p_id));
end $$;

create or replace function public.app_process_event(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.time_events; cfg public.app_settings; d date; working boolean; s public.work_sessions; open_count integer; new_id uuid; inferred timestamp; state public.review_status;
begin
  select * into strict e from public.time_events where id = p_id;
  if exists(select 1 from public.work_sessions where entry_event_id=e.id or exit_event_id=e.id) then return; end if;
  select * into strict cfg from public.app_settings where singleton;
  d := (e.occurred_at at time zone 'America/Argentina/Buenos_Aires')::date;
  working := extract(dow from d)::integer = any(cfg.weekdays) and not exists(select 1 from public.holidays where holiday_date=d);
  if e.event_type='exit' and not e.is_manual and e.target_session_id is not null then
    select * into s from public.work_sessions where id=e.target_session_id for update;
    if not found or s.employee_id<>e.employee_id or s.work_date<>d or s.institution_id is distinct from e.institution_id
      or s.status<>'pending' or s.entry_event_id is null or s.exit_event_id is not null or s.ends_at is not null
      or s.starts_at is null or s.starts_at>=e.occurred_at or e.standalone_exit_confirmed then
      raise exception 'La entrada seleccionada no admite esta salida. Actualizá los datos';
    end if;
    if exists(select 1 from public.work_sessions w where w.employee_id=s.employee_id and w.work_date=s.work_date
      and w.id<>s.id and w.status<>'rejected' and w.starts_at is not null and w.ends_at is not null
      and s.starts_at<w.ends_at and e.occurred_at>w.starts_at) then
      raise exception 'La jornada se superpone con otro período. Contactá al administrador';
    end if;
    update public.work_sessions set exit_event_id=e.id,ends_at=e.occurred_at,status='automatic',exit_inferred=false,
      reason=concat_ws(' / ',nullif(reason,''),e.reason),notes=nullif(concat_ws(' / ',notes,e.notes),''),updated_at=now() where id=s.id;
    new_id := s.id;
  elsif e.event_type='exit' and not e.is_manual and e.standalone_exit_confirmed then
    if exists(select 1 from public.work_sessions where employee_id=e.employee_id and work_date=d and status='pending'
      and entry_event_id is not null and exit_event_id is null and ends_at is null) then
      raise exception 'Tenés entradas abiertas. Elegí cuál querés cerrar';
    end if;
    inferred := d+cfg.starts_at;
    state := case when working and date_trunc('minute',e.occurred_at at time zone 'America/Argentina/Buenos_Aires')>inferred
      then 'automatic'::public.review_status else 'pending'::public.review_status end;
    insert into public.work_sessions(employee_id,exit_event_id,starts_at,ends_at,entry_inferred,status,work_date,institution_id,
      reason,notes,schedule_start,schedule_end,working_day)
      values(e.employee_id,e.id,case when state='automatic' then inferred at time zone 'America/Argentina/Buenos_Aires' else null end,
        e.occurred_at,state='automatic',state,d,e.institution_id,e.reason,e.notes,cfg.starts_at,cfg.ends_at,working)
      returning id into new_id;
  elsif e.event_type = 'entry' then
    insert into public.work_sessions(employee_id, entry_event_id, starts_at, status, work_date, institution_id, reason, notes, schedule_start, schedule_end, working_day)
    values(e.employee_id, e.id, e.occurred_at, 'pending', d, e.institution_id, e.reason, e.notes, cfg.starts_at, cfg.ends_at, working)
    returning id into new_id;
  else
    select count(*) into open_count from public.work_sessions
      where employee_id=e.employee_id and work_date=d and institution_id=e.institution_id
      and entry_event_id is not null and exit_event_id is null and status='pending' and starts_at < e.occurred_at;
    if open_count = 1 then
      select * into s from public.work_sessions
        where employee_id=e.employee_id and work_date=d and institution_id=e.institution_id
        and entry_event_id is not null and exit_event_id is null and status='pending' and starts_at < e.occurred_at for update;
      update public.work_sessions set exit_event_id=e.id, ends_at=e.occurred_at, status='automatic',
        reason=concat_ws(' / ', nullif(reason,''), e.reason), notes=nullif(concat_ws(' / ', notes,e.notes),''),
        updated_at=now() where id=s.id;
      new_id := s.id;
    else
      inferred := d + cfg.starts_at;
      -- Una salida anterior a la jornada o ambigua necesita intervención.
      state := case when open_count=0 and working and date_trunc('minute', e.occurred_at at time zone 'America/Argentina/Buenos_Aires') > inferred
        then 'automatic'::public.review_status else 'pending'::public.review_status end;
      insert into public.work_sessions(employee_id, exit_event_id, starts_at, ends_at, entry_inferred, status, work_date, institution_id, reason, notes, schedule_start, schedule_end, working_day)
      values(e.employee_id, e.id,
        case when state='automatic' then inferred at time zone 'America/Argentina/Buenos_Aires' else null end,
        e.occurred_at, state='automatic', state, d, e.institution_id, e.reason,e.notes,cfg.starts_at,cfg.ends_at,working)
      returning id into new_id;
    end if;
  end if;
  perform public.app_calculate(new_id);
  insert into public.review_cases(session_id,reason,status)
    select new_id, 'Movimiento incompleto o ambiguo', 'pending'
    where exists(select 1 from public.work_sessions where id=new_id and status='pending')
    and not exists(select 1 from public.review_cases where session_id=new_id);
  update public.review_cases set status='automatic', resolved_at=now()
    where session_id=new_id and status='pending' and exists(select 1 from public.work_sessions where id=new_id and status='automatic');
end $$;
commit;

