-- Aplicar una sola vez después de 005. Conserva los fichajes originales.
begin;
alter table public.time_events add column is_manual boolean not null default false,
  add column target_session_id uuid references public.work_sessions(id);

create function public.app_process_manual_event(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare e public.time_events; s public.work_sessions; old_data jsonb; d date;
begin
  select * into strict e from public.time_events where id=p_id;
  d := (e.occurred_at at time zone 'America/Argentina/Buenos_Aires')::date;
  if e.target_session_id is null then
    if exists(select 1 from public.work_sessions w where w.employee_id=e.employee_id
      and w.work_date=d and w.institution_id=e.institution_id and w.status in ('pending','automatic')
      and ((e.event_type='entry' and w.entry_event_id is null)
        or (e.event_type='exit' and w.exit_event_id is null))) then
      raise exception 'Seleccioná la jornada existente para completar el movimiento';
    end if;
    if e.event_type='entry' and exists(select 1 from public.work_sessions w where w.employee_id=e.employee_id
      and w.work_date=d and w.institution_id=e.institution_id and w.status='pending'
      and w.entry_event_id is not null and w.exit_event_id is null) then
      raise exception 'Ya existe una entrada pendiente para ese día y lugar';
    end if;
    perform public.app_process_event(e.id);
    select * into strict s from public.work_sessions where entry_event_id=e.id or exit_event_id=e.id;
  else
    select * into s from public.work_sessions where id=e.target_session_id for update;
    if not found or s.employee_id<>e.employee_id or s.work_date<>d or s.institution_id is distinct from e.institution_id then
      raise exception 'La jornada debe coincidir con el empleado, día e institución';
    end if;
    if s.status not in ('pending','automatic') then raise exception 'Esta jornada ya fue revisada; no admite nuevos fichajes'; end if;
    old_data := to_jsonb(s);
    if e.event_type='entry' then
      if s.entry_event_id is not null or (s.starts_at is not null and not s.entry_inferred) then raise exception 'La jornada ya tiene una entrada real'; end if;
      if s.ends_at is not null and e.occurred_at>=date_trunc('minute',s.ends_at) then raise exception 'La entrada debe ser anterior a la salida'; end if;
      update public.work_sessions set entry_event_id=e.id,starts_at=e.occurred_at,entry_inferred=false where id=s.id;
    else
      if s.exit_event_id is not null or (s.ends_at is not null and not s.exit_inferred) then raise exception 'La jornada ya tiene una salida real'; end if;
      if s.starts_at is not null and e.occurred_at<=date_trunc('minute',s.starts_at) then raise exception 'La salida debe ser posterior a la entrada'; end if;
      update public.work_sessions set exit_event_id=e.id,ends_at=e.occurred_at,exit_inferred=false where id=s.id;
    end if;
    update public.work_sessions set status=case when starts_at is not null and ends_at is not null then 'corrected'::public.review_status else 'pending'::public.review_status end,
      reason=concat_ws(' / ',nullif(reason,''),e.reason),notes=nullif(concat_ws(' / ',notes,e.notes),''),updated_at=now() where id=s.id;
    perform public.app_calculate(s.id);
    update public.review_cases set status=(select status from public.work_sessions where id=s.id),
      resolution_notes=e.reason,resolved_by=e.created_by,resolved_at=now(),updated_at=now()
      where session_id=s.id and status='pending' and (select status from public.work_sessions where id=s.id)<>'pending';
    insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
      values(e.created_by,'work_session',s.id,'Jornada completada con fichaje manual',old_data,
        (select to_jsonb(w) from public.work_sessions w where id=s.id));
    select * into strict s from public.work_sessions where id=s.id;
  end if;
  -- Evitar contar dos veces intervalos completos o entradas dentro de otro período.
  if exists(select 1 from public.work_sessions w where w.employee_id=s.employee_id
    and w.work_date=s.work_date and w.id<>s.id and w.status<>'rejected'
    and ((s.starts_at is not null and s.ends_at is not null and w.starts_at is not null and w.ends_at is not null
      and s.starts_at<w.ends_at and s.ends_at>w.starts_at)
      or (s.ends_at is null and w.starts_at is not null and w.ends_at is not null
        and s.starts_at>=w.starts_at and s.starts_at<w.ends_at))) then
    raise exception 'El horario se superpone con otra jornada del empleado';
  end if;
  if (public.app_compensation_balance(e.employee_id)->>'available')::bigint<0 then
    raise exception 'La corrección dejaría sin respaldo horas ya compensadas o reservadas';
  end if;
end $$;
revoke all on function public.app_process_manual_event(uuid) from public,anon,authenticated;

create or replace function public.app_event_inserted() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform pg_advisory_xact_lock(73482001);
  if public.app_month_closed((new.occurred_at at time zone 'America/Argentina/Buenos_Aires')::date) then
    raise exception 'El período está cerrado. Reabrilo antes de fichar';
  end if;
  if new.is_manual then perform public.app_process_manual_event(new.id);
  else perform public.app_process_event(new.id); end if;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,after_data)
    values(new.created_by,'time_event',new.id,case when new.is_manual then 'Fichaje manual' else 'fichaje' end,to_jsonb(new));
  return new;
end $$;

create function public.admin_register_manual_event(p_employee uuid,p_event_type public.event_type,p_institution uuid,
  p_date date,p_time time,p_reason text,p_notes text,p_request_id uuid,p_target uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare moment timestamptz; existing public.time_events; event_id uuid;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_employee is null or p_event_type is null or p_institution is null or p_date is null or p_time is null
    or p_time>='24:00'::time or p_request_id is null or p_reason is null
    or length(trim(p_reason)) not between 1 and 1000 or length(coalesce(p_notes,''))>2000 then
    raise exception 'Completá empleado, movimiento, lugar, fecha, hora y motivo';
  end if;
  moment := (p_date+p_time) at time zone 'America/Argentina/Buenos_Aires';
  moment := date_trunc('minute',moment);
  select * into existing from public.time_events where created_by=auth.uid() and client_request_id=p_request_id;
  if found then
    if existing.is_manual and existing.employee_id=p_employee and existing.event_type=p_event_type
      and existing.institution_id=p_institution and existing.occurred_at=moment
      and existing.reason=trim(p_reason) and existing.notes is not distinct from nullif(trim(p_notes),'')
      and existing.target_session_id is not distinct from p_target then return existing.id; end if;
    raise exception 'La solicitud ya corresponde a otro movimiento';
  end if;
  if moment>now() then raise exception 'No se pueden cargar fichajes futuros'; end if;
  if public.app_month_closed(p_date) then raise exception 'El período está cerrado. Reabrilo antes de fichar'; end if;
  if not exists(select 1 from public.employees where id=p_employee) then raise exception 'Empleado inexistente'; end if;
  if not exists(select 1 from public.institutions where id=p_institution and active) then raise exception 'Institución no habilitada'; end if;
  if exists(select 1 from public.time_events where employee_id=p_employee and event_type=p_event_type
    and date_trunc('minute',occurred_at)=moment) then raise exception 'Ya existe ese movimiento en el mismo minuto'; end if;
  insert into public.time_events(employee_id,institution_id,event_type,occurred_at,reason,notes,created_by,
    client_request_id,is_manual,target_session_id)
    values(p_employee,p_institution,p_event_type,moment,trim(p_reason),nullif(trim(p_notes),''),auth.uid(),p_request_id,true,p_target)
    returning id into event_id;
  return event_id;
end $$;
revoke all on function public.admin_register_manual_event(uuid,public.event_type,uuid,date,time,text,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.admin_register_manual_event(uuid,public.event_type,uuid,date,time,text,text,uuid,uuid) to authenticated;

-- La respuesta de movimientos se amplía más abajo para indicar origen y hora de carga.
create or replace function public.get_app_data() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare own_profile public.profiles; own_employee public.employees; admin boolean; result jsonb;
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  select * into own_profile from public.profiles where id=auth.uid();
  select * into own_employee from public.employees where profile_id=auth.uid();
  if own_profile.id is null or own_employee.id is null then raise exception 'El usuario no tiene un perfil y legajo. Revisá la migración 002'; end if;
  admin := own_profile.role='admin' and own_employee.active;
  select jsonb_build_object(
    'manualPunchAvailable',true,
    'profile',jsonb_build_object('id',own_profile.id,'name',own_profile.display_name,'role',case when admin then 'admin' else 'employee' end,
      'employeeId',own_employee.id,'employeeNumber',own_employee.employee_number,'active',own_employee.active),
    'settings',jsonb_build_object('startsAt',to_char(cfg.starts_at::interval,'HH24:MI'),'endsAt',to_char(cfg.ends_at::interval,'HH24:MI'),
      'weekdays',to_jsonb(cfg.weekdays),'institutions',coalesce((select jsonb_agg(name order by name) from public.institutions where active),'[]'),
      'holidays',coalesce((select jsonb_agg(holiday_date order by holiday_date) from public.holidays),'[]')),
    'institutions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.institutions where active),'[]'),
    'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'profileId',p.id,'name',p.display_name,
      'initials',upper(left(p.display_name,1) || left(split_part(p.display_name,' ',2),1)),
      'user',e.employee_number,'employeeNumber',e.employee_number,'role',case when p.role='admin' then 'Administrador' else 'Empleado' end,
      'appRole',p.role,'status',case when e.active then 'Activo' else 'Inactivo' end,
      'hours',0,'approved',0,'pending',0,'events',0,'last','') order by p.display_name)
      from public.employees e join public.profiles p on p.id=e.profile_id where admin or p.id=auth.uid()),'[]'),
    'records',coalesce((select jsonb_agg(public.app_record(s.id) order by coalesce(s.ends_at,s.starts_at) desc,s.id)
      from public.work_sessions s where admin or s.employee_id=own_employee.id),'[]'),
    'events',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'employeeId',t.employee_id,
      'institution',coalesce(i.name,'Sin institución'),'kind',case when t.event_type='entry' then 'Entrada' else 'Salida' end,
      'occurredAt',t.occurred_at,'recordedAt',t.created_at,'manual',t.is_manual,'reason',t.reason,'notes',t.notes) order by t.occurred_at desc,t.id)
      from public.time_events t left join public.institutions i on i.id=t.institution_id where admin or t.employee_id=own_employee.id),'[]'),
    'closures',case when admin then coalesce((select jsonb_object_agg(
      year::text || '-' || lpad(month::text,2,'0'),jsonb_build_object('closedAt',closed_at,'records',snapshot))
      from public.monthly_closures where closed_at is not null),'{}') else '{}'::jsonb end,
    'audit',case when admin then coalesce((select jsonb_agg(to_jsonb(logs)) from (
      select a.id,a.action,a.entity_type,a.created_at,coalesce(p.display_name,'Sistema') as actor_name
      from public.audit_logs a left join public.profiles p on p.id=a.actor_id order by a.created_at desc limit 100) logs),'[]') else '[]'::jsonb end
  ) into result from public.app_settings cfg where singleton;
  return result;
end $$;


commit;
