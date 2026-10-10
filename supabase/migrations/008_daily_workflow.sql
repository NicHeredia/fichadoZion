-- Aplicar una sola vez después de 007. Operaciones atómicas y solicitudes auditadas.
begin;

create table public.manual_session_requests (
  id uuid primary key, actor uuid not null references public.profiles(id), payload jsonb not null,
  session_id uuid not null references public.work_sessions(id)
);
alter table public.manual_session_requests enable row level security;
revoke all on public.manual_session_requests from public,anon,authenticated;

create function public.admin_register_manual_session(p_employee uuid,p_institution uuid,p_date date,
  p_entry time,p_exit time,p_reason text,p_notes text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare payload jsonb; old_request public.manual_session_requests; event_id uuid; session_id uuid;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_entry is null or p_exit is null or p_exit<=p_entry or p_exit>='24:00'::time or p_request_id is null then
    raise exception 'Ingresá entrada y salida válidas del mismo día';
  end if;
  payload := jsonb_build_object('employee',p_employee,'institution',p_institution,'date',p_date,
    'entry',p_entry,'exit',p_exit,'reason',trim(p_reason),'notes',trim(coalesce(p_notes,'')));
  select * into old_request from public.manual_session_requests where id=p_request_id;
  if found then
    if old_request.actor=auth.uid() and old_request.payload=payload then return old_request.session_id; end if;
    raise exception 'La solicitud ya corresponde a otra carga';
  end if;
  event_id := public.admin_register_manual_event(p_employee,'entry',p_institution,p_date,p_entry,p_reason,p_notes,gen_random_uuid(),null);
  select id into strict session_id from public.work_sessions where entry_event_id=event_id;
  perform public.admin_register_manual_event(p_employee,'exit',p_institution,p_date,p_exit,p_reason,p_notes,gen_random_uuid(),session_id);
  insert into public.manual_session_requests values(p_request_id,auth.uid(),payload,session_id);
  return session_id;
end $$;
revoke all on function public.admin_register_manual_session(uuid,uuid,date,time,time,text,text,uuid) from public,anon,authenticated;
grant execute on function public.admin_register_manual_session(uuid,uuid,date,time,time,text,text,uuid) to authenticated;

create table public.correction_requests (
  id uuid primary key, employee_id uuid not null references public.employees(id),
  session_id uuid references public.work_sessions(id), institution_id uuid not null references public.institutions(id),
  work_date date not null, proposed_entry time not null, proposed_exit time not null,
  reason text not null check(length(trim(reason)) between 1 and 1000),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  session_snapshot jsonb, created_at timestamptz not null default now(),
  resolved_at timestamptz, resolved_by uuid references public.profiles(id), resolution_notes text,
  check(proposed_exit>proposed_entry and proposed_exit<'24:00'::time)
);
create unique index correction_pending_session on public.correction_requests(session_id) where status='pending' and session_id is not null;
create unique index correction_pending_new on public.correction_requests(employee_id,work_date,institution_id) where status='pending' and session_id is null;
alter table public.correction_requests enable row level security;
revoke all on public.correction_requests from public,anon,authenticated;

create function public.get_correction_requests() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare employee uuid; admin boolean;
begin
  select e.id,(p.role='admin' and e.active) into employee,admin
    from public.employees e join public.profiles p on p.id=e.profile_id where p.id=auth.uid();
  if employee is null then raise exception 'Se requiere iniciar sesión'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r)-'session_snapshot' order by r.created_at desc)
    from public.correction_requests r where admin or r.employee_id=employee),'[]'::jsonb);
end $$;
revoke all on function public.get_correction_requests() from public,anon,authenticated;
grant execute on function public.get_correction_requests() to authenticated;

create function public.request_session_correction(p_id uuid,p_session uuid,p_institution uuid,p_date date,
  p_entry time,p_exit time,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare employee uuid; s public.work_sessions; old_request public.correction_requests;
begin
  perform pg_advisory_xact_lock(73482001);
  select id into employee from public.employees where profile_id=auth.uid() and active;
  if employee is null then raise exception 'Empleado no habilitado'; end if;
  if p_id is null or p_institution is null or p_date is null or p_entry is null or p_exit is null
    or p_entry>=p_exit or p_exit>='24:00'::time or p_reason is null or length(trim(p_reason)) not between 1 and 1000 then
    raise exception 'Completá fecha, lugar, ambos horarios y motivo';
  end if;
  select * into old_request from public.correction_requests where id=p_id;
  if found then
    if old_request.employee_id=employee and old_request.session_id is not distinct from p_session
      and old_request.institution_id=p_institution and old_request.work_date=p_date
      and old_request.proposed_entry=p_entry and old_request.proposed_exit=p_exit and old_request.reason=trim(p_reason) then return p_id; end if;
    raise exception 'La solicitud ya corresponde a otros datos';
  end if;
  if (p_date+p_exit) at time zone 'America/Argentina/Buenos_Aires'>now() then raise exception 'No se pueden solicitar horarios futuros'; end if;
  if public.app_month_closed(p_date) then raise exception 'El período está cerrado. Solicitá su reapertura al administrador'; end if;
  if p_session is not null then
    select * into s from public.work_sessions where id=p_session;
    if not found or s.employee_id<>employee then raise exception 'Jornada no disponible'; end if;
    if s.work_date<>p_date or s.institution_id is distinct from p_institution then raise exception 'Conservá la fecha y el lugar de la jornada'; end if;
    if s.status='rejected' then raise exception 'Consultá al administrador por la jornada rechazada'; end if;
  elsif not exists(select 1 from public.institutions where id=p_institution and active) then raise exception 'Institución no habilitada';
  end if;
  if exists(select 1 from public.correction_requests where employee_id=employee and status='pending'
    and ((p_session is not null and session_id=p_session) or (p_session is null and session_id is null and work_date=p_date and institution_id=p_institution))) then
    raise exception 'Ya tenés una solicitud pendiente para esta jornada';
  end if;
  insert into public.correction_requests(id,employee_id,session_id,institution_id,work_date,proposed_entry,proposed_exit,reason,session_snapshot)
    values(p_id,employee,p_session,p_institution,p_date,p_entry,p_exit,trim(p_reason),case when p_session is not null then to_jsonb(s) end);
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,after_data)
    values(auth.uid(),'correction_request',p_id,'Solicitud de corrección',(select to_jsonb(r) from public.correction_requests r where id=p_id));
  return p_id;
end $$;
revoke all on function public.request_session_correction(uuid,uuid,uuid,date,time,time,text) from public,anon,authenticated;
grant execute on function public.request_session_correction(uuid,uuid,uuid,date,time,time,text) to authenticated;

create function public.admin_resolve_correction(p_id uuid,p_approve boolean,p_notes text) returns void
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
      select * into s from public.work_sessions where id=r.session_id;
      if to_jsonb(s) is distinct from r.session_snapshot then raise exception 'La jornada cambió desde la solicitud. Rechazala y pedí una nueva'; end if;
      perform public.admin_review_session(r.session_id,'corrected',r.proposed_entry,r.proposed_exit,r.reason || ' / ' || p_notes);
    end if;
  end if;
  update public.correction_requests set status=case when p_approve then 'approved' else 'rejected' end,
    resolution_notes=trim(p_notes),resolved_by=auth.uid(),resolved_at=now() where id=p_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'correction_request',p_id,'Resolución de solicitud',to_jsonb(r),(select to_jsonb(c) from public.correction_requests c where id=p_id));
end $$;
revoke all on function public.admin_resolve_correction(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.admin_resolve_correction(uuid,boolean,text) to authenticated;

create or replace function public.app_record(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
select jsonb_build_object(
  'id',s.id,'employeeId',e.id,'employeeNumber',e.employee_number,'employee',p.display_name,
  'initials',upper(left(p.display_name,1) || coalesce(left(split_part(p.display_name,' ',2),1),'')),
  'isoDate',s.work_date,'date',to_char(s.work_date,'DD/MM/YYYY'),
  'entry',to_char(s.starts_at at time zone 'America/Argentina/Buenos_Aires','HH24:MI'),
  'exit',to_char(s.ends_at at time zone 'America/Argentina/Buenos_Aires','HH24:MI'),
  'inferredEntry',s.entry_inferred,'inferredExit',s.exit_inferred,
  'institutionId',s.institution_id,'institution',coalesce(i.name,'Sin institución'),'reason',s.reason,'notes',s.notes,
  'capturedAt',coalesce(a.occurred_at,b.occurred_at),
  'lastEventAt',coalesce(b.occurred_at,a.occurred_at),
  'scheduleStart',to_char(s.schedule_start::interval,'HH24:MI'),'scheduleEnd',to_char(s.schedule_end::interval,'HH24:MI'),'workingDay',s.working_day,'beforeMinutes',coalesce(c.before_minutes,0),'afterMinutes',coalesce(c.after_minutes,0),'minutes',coalesce(c.total_minutes,0),
  'status',case s.status when 'automatic' then 'Automático' when 'pending' then 'Pendiente' when 'approved' then 'Aprobado' when 'rejected' then 'Rechazado' else 'Corregido' end)
from public.work_sessions s join public.employees e on e.id=s.employee_id
join public.profiles p on p.id=e.profile_id left join public.institutions i on i.id=s.institution_id
left join public.overtime_calculations c on c.session_id=s.id
left join public.time_events a on a.id=s.entry_event_id left join public.time_events b on b.id=s.exit_event_id
where s.id=p_id;
$$;

create or replace function public.admin_review_session(p_id uuid, p_status public.review_status, p_entry time default null, p_exit time default null, p_notes text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare s public.work_sessions; old_data jsonb; a timestamptz; b timestamptz;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_status is null or p_status not in ('approved','rejected','corrected') then raise exception 'Estado inválido'; end if;
  if length(coalesce(p_notes,''))>2000 then raise exception 'Observaciones demasiado largas'; end if;
  select * into s from public.work_sessions where id=p_id for update;
  if not found then raise exception 'Registro inexistente'; end if;
  if public.app_month_closed(s.work_date) then raise exception 'El período está cerrado'; end if;
  if s.status='rejected' or (p_status<>'corrected' and s.status<>'pending' and not (s.status='automatic' and (s.entry_inferred or s.exit_inferred))) then raise exception 'Este registro ya fue resuelto. Actualizá los datos'; end if;
  old_data := to_jsonb(s);
  a := s.starts_at; b := s.ends_at;
  if p_status='corrected' then
    if p_entry is null or p_exit is null or p_exit>='24:00'::time or p_exit<=p_entry or length(trim(coalesce(p_notes,'')))=0 then raise exception 'Completá ambos horarios y el motivo de corrección. La salida debe ser posterior a la entrada'; end if;
    a := (s.work_date+p_entry) at time zone 'America/Argentina/Buenos_Aires';
    b := (s.work_date+p_exit) at time zone 'America/Argentina/Buenos_Aires';
  end if;
  if p_status in ('approved','corrected') and (a is null or b is null or b<=a) then raise exception 'El período está incompleto o es inválido'; end if;
  if p_status in ('approved','corrected') then
    if b>now() then raise exception 'No se pueden aprobar horarios futuros'; end if;
    if exists(select 1 from public.work_sessions w where w.employee_id=s.employee_id and w.work_date=s.work_date and w.id<>s.id and w.status<>'rejected' and w.starts_at is not null and w.ends_at is not null and a<w.ends_at and b>w.starts_at) then raise exception 'El horario se superpone con otra jornada del empleado'; end if;
  end if;
  update public.work_sessions set starts_at=a,ends_at=b,status=p_status,
    entry_inferred=case when p_status='corrected' then false else entry_inferred end,
    exit_inferred=case when p_status='corrected' then false else exit_inferred end,
    updated_at=now() where id=p_id;
  perform public.app_calculate(p_id);
  if (public.app_compensation_balance(s.employee_id)->>'available')::bigint<0 then raise exception 'La corrección dejaría sin respaldo horas ya compensadas o reservadas'; end if;
  update public.review_cases set status=p_status,resolution_notes=nullif(trim(p_notes),''),resolved_by=auth.uid(),resolved_at=now(),updated_at=now() where session_id=p_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'work_session',p_id,'revisión',old_data,jsonb_build_object('record',public.app_record(p_id),'notes',p_notes));
end $$;
create or replace function public.admin_close_month(p_month date) returns void
language plpgsql security definer set search_path = '' as $$
declare closure_id uuid; period_start date; next_version integer; data jsonb;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if exists(select 1 from public.correction_requests where status='pending' and date_trunc('month',work_date)=date_trunc('month',p_month)) then raise exception 'Resolvé las solicitudes de corrección antes de cerrar el período'; end if;
  if p_month is null then raise exception 'Período inválido'; end if;
  period_start := date_trunc('month',p_month)::date;
  if public.app_month_closed(period_start) then raise exception 'El período ya está cerrado'; end if;
  if not exists(select 1 from public.work_sessions where work_date>=period_start and work_date<(period_start+interval '1 month')::date) then raise exception 'El período no tiene registros'; end if;
  if exists(select 1 from public.work_sessions where work_date>=period_start and work_date<(period_start+interval '1 month')::date and status='pending') then raise exception 'Resolvé las revisiones pendientes antes de cerrar'; end if;
  select coalesce(max(version),0)+1 into next_version from public.monthly_closures where year=extract(year from period_start)::integer and month=extract(month from period_start)::integer;
  select jsonb_agg(public.app_record(id) order by coalesce(ends_at,starts_at) desc,id) into data from public.work_sessions where work_date>=period_start and work_date<(period_start+interval '1 month')::date;
  insert into public.monthly_closures(year,month,version,closed_by,closed_at,snapshot)
    values(extract(year from period_start)::integer,extract(month from period_start)::integer,next_version,auth.uid(),now(),data) returning id into closure_id;
  insert into public.monthly_closure_items(closure_id,employee_id,total_minutes,approved_minutes,pending_minutes)
    select closure_id,s.employee_id,sum(case when s.status<>'rejected' then c.total_minutes else 0 end)::integer,
      sum(case when s.status in ('approved','corrected') then c.total_minutes else 0 end)::integer,0
    from public.work_sessions s join public.overtime_calculations c on c.session_id=s.id
    where s.work_date>=period_start and s.work_date<(period_start+interval '1 month')::date group by s.employee_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,after_data)
    values(auth.uid(),'monthly_closure',closure_id,'cierre',jsonb_build_object('month',period_start,'version',next_version));
end $$;
commit;
