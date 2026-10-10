-- Solo para un proyecto NUEVO. Incluye las cuatro migraciones.
-- En un proyecto que ya funciona, aplicar solamente las migraciones que falten, en orden.
begin;

-- Esquema inicial para la segunda etapa. Todas las fechas se almacenan en UTC.
create extension if not exists "pgcrypto";
create type public.app_role as enum ('admin', 'employee');
create type public.event_type as enum ('entry', 'exit');
create type public.review_status as enum ('automatic', 'pending', 'approved', 'rejected', 'corrected');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role not null default 'employee',
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id),
  employee_number text unique not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.work_schedules (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid references public.employees(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  valid_from date not null,
  valid_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.time_events (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  institution_id uuid references public.institutions(id),
  event_type public.event_type not null,
  occurred_at timestamptz not null default now(),
  reason text not null,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index time_events_employee_occurred_idx on public.time_events(employee_id, occurred_at desc);
create table public.work_sessions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  entry_event_id uuid references public.time_events(id),
  exit_event_id uuid references public.time_events(id),
  starts_at timestamptz,
  ends_at timestamptz,
  entry_inferred boolean not null default false,
  exit_inferred boolean not null default false,
  status public.review_status not null default 'automatic',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index work_sessions_employee_start_idx on public.work_sessions(employee_id, starts_at desc);
create table public.overtime_calculations (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.work_sessions(id) on delete cascade,
  work_date date not null,
  before_minutes integer not null default 0 check (before_minutes >= 0),
  after_minutes integer not null default 0 check (after_minutes >= 0),
  total_minutes integer not null default 0 check (total_minutes >= 0),
  calculation_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.review_cases (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.work_sessions(id),
  reason text not null,
  status public.review_status not null default 'pending',
  resolution_notes text,
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.monthly_closures (
  id uuid primary key default gen_random_uuid(),
  year integer not null,
  month integer not null check (month between 1 and 12),
  version integer not null default 1,
  closed_by uuid references public.profiles(id),
  closed_at timestamptz,
  reopened_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(year, month, version)
);
create table public.monthly_closure_items (
  id uuid primary key default gen_random_uuid(),
  closure_id uuid not null references public.monthly_closures(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  total_minutes integer not null,
  approved_minutes integer not null,
  pending_minutes integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(closure_id, employee_id)
);
create table public.holidays (
  id uuid primary key default gen_random_uuid(),
  holiday_date date unique not null,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.employees enable row level security;
alter table public.time_events enable row level security;
alter table public.work_sessions enable row level security;
alter table public.notifications enable row level security;

create function public.is_admin() returns boolean language sql stable security definer
set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;
create policy "profiles own or admin" on public.profiles for select
using (id = auth.uid() or public.is_admin());
create policy "employees own or admin" on public.employees for select
using (profile_id = auth.uid() or public.is_admin());
create policy "events own or admin" on public.time_events for select
using (public.is_admin() or employee_id in (select id from public.employees where profile_id = auth.uid()));
create policy "employees create own events" on public.time_events for insert
with check (employee_id in (select id from public.employees where profile_id = auth.uid()));
create policy "sessions own or admin" on public.work_sessions for select
using (public.is_admin() or employee_id in (select id from public.employees where profile_id = auth.uid()));
create policy "notifications own" on public.notifications for select
using (profile_id = auth.uid() or public.is_admin());

-- En producción, el registro de hora oficial, las aprobaciones y los cierres
-- deben exponerse mediante funciones security definer con validación de rol.

-- Aplicar después de 001_initial_schema.sql.
-- Tablas sin flujos de producción permanecen cerradas al cliente.
alter table public.time_events add column client_request_id uuid not null default gen_random_uuid();
create unique index time_events_request_idx on public.time_events(created_by, client_request_id);

do $$
declare table_name text;
begin
  foreach table_name in array array['profiles','employees','work_schedules','institutions','time_events','work_sessions','overtime_calculations','review_cases','monthly_closures','monthly_closure_items','holidays','notifications','audit_logs'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon, authenticated', table_name);
  end loop;
end $$;
grant select on public.profiles, public.employees, public.time_events, public.work_sessions, public.notifications, public.institutions to authenticated;
create policy "active institutions" on public.institutions for select to authenticated using (active);
-- Las inserciones directas quedan revocadas. El fichaje usa solamente RPC.
drop policy "employees create own events" on public.time_events;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

create function public.provision_employee() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name) values (new.id, coalesce(nullif(new.raw_user_meta_data->>'display_name',''), split_part(new.email,'@',1), 'Empleado'));
  insert into public.employees(profile_id, employee_number) values(new.id, 'U-' || new.id::text);
  return new;
end $$;
revoke all on function public.provision_employee() from public, anon, authenticated;
create trigger provision_employee after insert on auth.users
for each row execute function public.provision_employee();
-- También provisionar usuarios creados antes de ejecutar esta migración.
insert into public.profiles(id, display_name)
select id, coalesce(nullif(raw_user_meta_data->>'display_name',''), split_part(email,'@',1), 'Empleado') from auth.users
on conflict(id) do nothing;
insert into public.employees(profile_id, employee_number)
select id, 'U-' || id::text from public.profiles where not exists(select 1 from public.employees e where e.profile_id = profiles.id);
insert into public.institutions(name) values ('Institución A'), ('Institución B'), ('Institución C');

create function public.register_time_event(p_event_type public.event_type, p_institution_id uuid, p_reason text, p_notes text, p_request_id uuid)
returns setof public.time_events language plpgsql security definer set search_path = '' as $$
declare current_employee uuid; existing_event public.time_events;
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  if p_event_type is null or p_request_id is null then raise exception 'Movimiento inválido'; end if;
  if p_reason is null or length(trim(p_reason)) not between 1 and 1000 then raise exception 'Motivo inválido'; end if;
  if length(coalesce(p_notes,'')) > 2000 then raise exception 'Observaciones demasiado largas'; end if;
  select id into current_employee from public.employees where profile_id = auth.uid() and active;
  if current_employee is null then raise exception 'Empleado no habilitado'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  select * into existing_event from public.time_events where created_by = auth.uid() and client_request_id = p_request_id;
  if found then return next existing_event; return; end if;
  if not exists(select 1 from public.institutions where id = p_institution_id and active) then raise exception 'Institución no habilitada'; end if;
  if exists(select 1 from public.time_events where employee_id = current_employee and event_type = p_event_type and occurred_at > now() - interval '1 minute') then raise exception 'Movimiento duplicado reciente'; end if;
  return query insert into public.time_events(employee_id, institution_id, event_type, reason, notes, created_by, client_request_id)
  values(current_employee, p_institution_id, p_event_type, trim(p_reason), nullif(trim(p_notes),''), auth.uid(), p_request_id) returning *;
end $$;
revoke all on function public.register_time_event(public.event_type, uuid, text, text, uuid) from public, anon;
grant execute on function public.register_time_event(public.event_type, uuid, text, text, uuid) to authenticated;

-- Aplicar una sola vez después de 002_secure_registration.sql.
-- No borra fichajes. Procesa también los movimientos anteriores.

create table public.app_settings (
  singleton boolean primary key default true check (singleton),
  starts_at time not null default '08:00',
  ends_at time not null default '17:00',
  weekdays integer[] not null default array[1,2,3,4,5],
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
insert into public.app_settings(singleton) values(true);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from public, anon, authenticated;
alter table public.work_sessions
  add column work_date date,
  add column institution_id uuid references public.institutions(id),
  add column reason text not null default '',
  add column notes text,
  add column schedule_start time not null default '08:00',
  add column schedule_end time not null default '17:00',
  add column working_day boolean not null default true;
alter table public.monthly_closures add column snapshot jsonb not null default '[]';
create unique index sessions_entry_unique on public.work_sessions(entry_event_id) where entry_event_id is not null;
create unique index sessions_exit_unique on public.work_sessions(exit_event_id) where exit_event_id is not null;
create unique index calculations_session_unique on public.overtime_calculations(session_id);
create index sessions_date_idx on public.work_sessions(work_date);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles p join public.employees e on e.profile_id=p.id
    where p.id=auth.uid() and p.role='admin' and e.active);
$$;

create function public.app_assert_admin() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_admin() or not exists(
    select 1 from public.employees where profile_id = auth.uid() and active
  ) then raise exception 'Se requiere un administrador habilitado'; end if;
end $$;

create function public.app_month_closed(p_date date) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.monthly_closures
    where year = extract(year from p_date)::integer and month = extract(month from p_date)::integer and closed_at is not null);
$$;

create function public.app_calculate(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare s public.work_sessions; a timestamp; b timestamp; before_m integer := 0; after_m integer := 0; total_m integer := 0;
begin
  select * into strict s from public.work_sessions where id = p_id;
  a := date_trunc('minute', s.starts_at at time zone 'America/Argentina/Buenos_Aires');
  b := date_trunc('minute', s.ends_at at time zone 'America/Argentina/Buenos_Aires');
  if a is not null and b is not null and b > a then
    if s.working_day then
      before_m := greatest(0, floor(extract(epoch from (least(b, s.work_date + s.schedule_start) - a))/60)::integer);
      after_m := greatest(0, floor(extract(epoch from (b - greatest(a, s.work_date + s.schedule_end)))/60)::integer);
      total_m := before_m + after_m;
    else total_m := floor(extract(epoch from (b-a))/60)::integer; end if;
  end if;
  insert into public.overtime_calculations(session_id, work_date, before_minutes, after_minutes, total_minutes)
    values(s.id, s.work_date, before_m, after_m, total_m)
  on conflict(session_id) do update set before_minutes=excluded.before_minutes,
    after_minutes=excluded.after_minutes, total_minutes=excluded.total_minutes, updated_at=now();
end $$;

create function public.app_process_event(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.time_events; cfg public.app_settings; d date; working boolean; s public.work_sessions; open_count integer; new_id uuid; inferred timestamp; state public.review_status;
begin
  select * into strict e from public.time_events where id = p_id;
  if exists(select 1 from public.work_sessions where entry_event_id=e.id or exit_event_id=e.id) then return; end if;
  select * into strict cfg from public.app_settings where singleton;
  d := (e.occurred_at at time zone 'America/Argentina/Buenos_Aires')::date;
  working := extract(dow from d)::integer = any(cfg.weekdays) and not exists(select 1 from public.holidays where holiday_date=d);
  if e.event_type = 'entry' then
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

-- Procesar históricos en orden para conservar el emparejamiento.
do $$
declare event_id uuid;
begin
  for event_id in select id from public.time_events order by occurred_at, created_at, id loop
    perform public.app_process_event(event_id);
  end loop;
end $$;

create function public.app_event_inserted() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(73482001);
  if public.app_month_closed((new.occurred_at at time zone 'America/Argentina/Buenos_Aires')::date) then
    raise exception 'El período está cerrado. Reabrilo antes de fichar';
  end if;
  perform public.app_process_event(new.id);
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,after_data)
    values(new.created_by,'time_event',new.id,'fichaje',to_jsonb(new));
  return new;
end $$;
create trigger app_event_inserted after insert on public.time_events for each row execute function public.app_event_inserted();

create or replace function public.register_time_event(p_event_type public.event_type, p_institution_id uuid, p_reason text, p_notes text, p_request_id uuid)
returns setof public.time_events language plpgsql security definer set search_path = '' as $$
declare current_employee uuid; existing_event public.time_events;
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  if p_event_type is null or p_request_id is null then raise exception 'Movimiento inválido'; end if;
  if p_reason is null or length(trim(p_reason)) not between 1 and 1000 then raise exception 'Motivo inválido'; end if;
  if length(coalesce(p_notes,'')) > 2000 then raise exception 'Observaciones demasiado largas'; end if;
  perform pg_advisory_xact_lock(73482001);
  select id into current_employee from public.employees where profile_id=auth.uid() and active;
  if current_employee is null then raise exception 'Empleado no habilitado'; end if;
  select * into existing_event from public.time_events where created_by=auth.uid() and client_request_id=p_request_id;
  if found then return next existing_event; return; end if;
  if public.app_month_closed((now() at time zone 'America/Argentina/Buenos_Aires')::date) then raise exception 'El período está cerrado'; end if;
  if not exists(select 1 from public.institutions where id=p_institution_id and active) then raise exception 'Institución no habilitada'; end if;
  if exists(select 1 from public.time_events where employee_id=current_employee and event_type=p_event_type and occurred_at > now()-interval '1 minute') then raise exception 'Movimiento duplicado reciente'; end if;
  return query insert into public.time_events(employee_id,institution_id,event_type,reason,notes,created_by,client_request_id)
    values(current_employee,p_institution_id,p_event_type,trim(p_reason),nullif(trim(p_notes),''),auth.uid(),p_request_id) returning *;
end $$;

create function public.app_record(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
select jsonb_build_object(
  'id',s.id,'employeeId',e.id,'employeeNumber',e.employee_number,'employee',p.display_name,
  'initials',upper(left(p.display_name,1) || coalesce(left(split_part(p.display_name,' ',2),1),'')),
  'isoDate',s.work_date,'date',to_char(s.work_date,'DD/MM/YYYY'),
  'entry',to_char(s.starts_at at time zone 'America/Argentina/Buenos_Aires','HH24:MI'),
  'exit',to_char(s.ends_at at time zone 'America/Argentina/Buenos_Aires','HH24:MI'),
  'inferredEntry',s.entry_inferred,'inferredExit',s.exit_inferred,
  'institution',coalesce(i.name,'Sin institución'),'reason',s.reason,'notes',s.notes,
  'capturedAt',coalesce(a.occurred_at,b.occurred_at),
  'lastEventAt',coalesce(b.occurred_at,a.occurred_at),
  'minutes',coalesce(c.total_minutes,0),
  'status',case s.status when 'automatic' then 'Automático' when 'pending' then 'Pendiente' when 'approved' then 'Aprobado' when 'rejected' then 'Rechazado' else 'Corregido' end)
from public.work_sessions s join public.employees e on e.id=s.employee_id
join public.profiles p on p.id=e.profile_id left join public.institutions i on i.id=s.institution_id
left join public.overtime_calculations c on c.session_id=s.id
left join public.time_events a on a.id=s.entry_event_id left join public.time_events b on b.id=s.exit_event_id
where s.id=p_id;
$$;

create function public.get_app_data() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare own_profile public.profiles; own_employee public.employees; admin boolean; result jsonb;
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  select * into own_profile from public.profiles where id=auth.uid();
  select * into own_employee from public.employees where profile_id=auth.uid();
  if own_profile.id is null or own_employee.id is null then raise exception 'El usuario no tiene un perfil y legajo. Revisá la migración 002'; end if;
  admin := own_profile.role='admin' and own_employee.active;
  select jsonb_build_object(
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
      'occurredAt',t.occurred_at,'reason',t.reason,'notes',t.notes) order by t.occurred_at desc,t.id)
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

create function public.admin_review_session(p_id uuid, p_status public.review_status, p_entry time default null, p_exit time default null, p_notes text default '')
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
  if s.status <> 'pending' then raise exception 'Este registro ya fue resuelto. Actualizá los datos'; end if;
  old_data := to_jsonb(s);
  a := s.starts_at; b := s.ends_at;
  if p_status='corrected' then
    if p_entry is null or p_exit is null or p_exit<=p_entry or length(trim(coalesce(p_notes,'')))=0 then raise exception 'Completá ambos horarios y el motivo de corrección. La salida debe ser posterior a la entrada'; end if;
    a := (s.work_date+p_entry) at time zone 'America/Argentina/Buenos_Aires';
    b := (s.work_date+p_exit) at time zone 'America/Argentina/Buenos_Aires';
  end if;
  if p_status in ('approved','corrected') and (a is null or b is null or b<=a) then raise exception 'El período está incompleto o es inválido'; end if;
  update public.work_sessions set starts_at=a,ends_at=b,status=p_status,
    entry_inferred=case when p_status='corrected' then false else entry_inferred end,
    exit_inferred=case when p_status='corrected' then false else exit_inferred end,
    updated_at=now() where id=p_id;
  perform public.app_calculate(p_id);
  update public.review_cases set status=p_status,resolution_notes=nullif(trim(p_notes),''),resolved_by=auth.uid(),resolved_at=now(),updated_at=now() where session_id=p_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'work_session',p_id,'revisión',old_data,jsonb_build_object('record',public.app_record(p_id),'notes',p_notes));
end $$;

create function public.admin_save_settings(p_start time,p_end time,p_weekdays integer[],p_institutions text[],p_holidays date[])
returns void language plpgsql security definer set search_path = '' as $$
declare place text; old_data jsonb;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_start is null or p_end is null or p_end<=p_start or p_weekdays is null
    or exists(select 1 from unnest(p_weekdays) x where x is null or x<0 or x>6)
    or p_institutions is null or coalesce(array_length(p_institutions,1),0)=0
    or exists(select 1 from unnest(p_institutions) x where x is null or length(trim(x)) not between 1 and 150)
    or p_holidays is null or exists(select 1 from unnest(p_holidays) x where x is null)
    then raise exception 'Revisá horarios, días, instituciones y feriados'; end if;
  select to_jsonb(s) into old_data from public.app_settings s where singleton;
  update public.app_settings set starts_at=p_start,ends_at=p_end,weekdays=p_weekdays,updated_at=now() where singleton;
  update public.institutions set active=false,updated_at=now() where active;
  foreach place in array p_institutions loop
    place := trim(place);
    update public.institutions set active=true,updated_at=now() where name=place;
    if not found then insert into public.institutions(name) values(place); end if;
  end loop;
  delete from public.holidays;
  insert into public.holidays(holiday_date,name) select distinct x,'Feriado' from unnest(p_holidays) x;
  insert into public.audit_logs(actor_id,entity_type,action,before_data,after_data)
    values(auth.uid(),'settings','configuración',old_data,jsonb_build_object('startsAt',p_start,'endsAt',p_end,'weekdays',p_weekdays,'institutions',p_institutions,'holidays',p_holidays));
end $$;

create function public.admin_save_employee(p_id uuid,p_name text,p_number text,p_active boolean,p_role public.app_role)
returns void language plpgsql security definer set search_path = '' as $$
declare e public.employees; old_data jsonb;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_name is null or length(trim(p_name)) not between 1 and 150 or p_number is null or length(trim(p_number)) not between 1 and 100 or p_active is null or p_role is null then raise exception 'Revisá nombre, legajo y rol'; end if;
  select * into e from public.employees where id=p_id for update;
  if not found then raise exception 'Empleado inexistente'; end if;
  if e.profile_id=auth.uid() and (not p_active or p_role<>'admin') then raise exception 'No podés quitar tu propio acceso administrativo'; end if;
  select jsonb_build_object('employee',to_jsonb(e),'profile',to_jsonb(p)) into old_data from public.profiles p where id=e.profile_id;
  update public.employees set employee_number=trim(p_number),active=p_active,updated_at=now() where id=p_id;
  update public.profiles set display_name=trim(p_name),role=p_role,updated_at=now() where id=e.profile_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'employee',p_id,'empleado',old_data,jsonb_build_object('name',p_name,'number',p_number,'active',p_active,'role',p_role));
exception when unique_violation then raise exception 'Ese legajo ya está en uso';
end $$;

create function public.admin_close_month(p_month date) returns void
language plpgsql security definer set search_path = '' as $$
declare closure_id uuid; period_start date; next_version integer; data jsonb;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
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

create function public.admin_reopen_month(p_month date,p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare c public.monthly_closures;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_month is null or p_reason is null or length(trim(p_reason)) not between 1 and 2000 then raise exception 'Indicá el motivo de reapertura'; end if;
  select * into c from public.monthly_closures where year=extract(year from p_month)::integer and month=extract(month from p_month)::integer and closed_at is not null for update;
  if not found then raise exception 'El período no está cerrado'; end if;
  update public.monthly_closures set closed_at=null,reopened_reason=trim(p_reason),updated_at=now() where id=c.id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'monthly_closure',c.id,'reapertura',to_jsonb(c),jsonb_build_object('reason',p_reason));
end $$;

-- Funciones internas inaccesibles desde el navegador.
revoke all on function public.app_assert_admin(),public.app_month_closed(date),public.app_calculate(uuid),public.app_process_event(uuid),public.app_event_inserted(),public.app_record(uuid) from public,anon,authenticated;
revoke all on function public.get_app_data(),public.admin_review_session(uuid,public.review_status,time,time,text),public.admin_save_settings(time,time,integer[],text[],date[]),public.admin_save_employee(uuid,text,text,boolean,public.app_role),public.admin_close_month(date),public.admin_reopen_month(date,text) from public,anon,authenticated;
grant execute on function public.get_app_data(),public.admin_review_session(uuid,public.review_status,time,time,text),public.admin_save_settings(time,time,integer[],text[],date[]),public.admin_save_employee(uuid,text,text,boolean,public.app_role),public.admin_close_month(date),public.admin_reopen_month(date,text) to authenticated;
revoke all on function public.register_time_event(public.event_type,uuid,text,text,uuid) from public,anon;
grant execute on function public.register_time_event(public.event_type,uuid,text,text,uuid) to authenticated;

-- Proyecto existente: ejecutar después de 003_admin_dashboard.sql.
-- El job corre en el servidor; no necesita tener la aplicación abierta.
create extension if not exists pg_cron with schema pg_catalog;

create or replace function public.app_finalize_open_sessions(p_now timestamptz default now())
returns integer language plpgsql security definer set search_path = '' as $$
declare s public.work_sessions; finish timestamptz; processed integer := 0;
begin
  -- Mismo bloqueo que fichajes, revisiones y cierres: evita carreras.
  perform pg_advisory_xact_lock(73482001);
  for s in
    select w.* from public.work_sessions w
    where w.status='pending' and w.entry_event_id is not null
      and w.exit_event_id is null and w.ends_at is null and w.starts_at is not null
      and w.work_date < (p_now at time zone 'America/Argentina/Buenos_Aires')::date
      and w.working_day and not public.app_month_closed(w.work_date)
      and (w.starts_at at time zone 'America/Argentina/Buenos_Aires')::date=w.work_date
      and w.starts_at < (w.work_date+w.schedule_end) at time zone 'America/Argentina/Buenos_Aires'
      -- Otra entrada sin resolver, salida huérfana o intervalo superpuesto
      -- del mismo empleado requiere revisión; no inventar horas duplicadas.
      and not exists (
        select 1 from public.work_sessions other
        where other.employee_id=w.employee_id and other.work_date=w.work_date
          and other.id<>w.id and other.status<>'rejected'
          and (other.status='pending' or
            (other.starts_at < (w.work_date+w.schedule_end) at time zone 'America/Argentina/Buenos_Aires'
              and other.ends_at > w.starts_at))
      )
    order by w.work_date,w.id for update of w
  loop
    finish := (s.work_date+s.schedule_end) at time zone 'America/Argentina/Buenos_Aires';
    update public.work_sessions set ends_at=finish,exit_inferred=true,
      status='automatic',updated_at=now() where id=s.id;
    perform public.app_calculate(s.id);
    update public.review_cases set status='automatic',
      resolution_notes='Salida habitual inferida automáticamente al finalizar el día',
      resolved_by=null,resolved_at=now(),updated_at=now()
      where session_id=s.id and status='pending';
    insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
      values(null,'work_session',s.id,'Salida automática al finalizar el día',
        to_jsonb(s),(select to_jsonb(w) from public.work_sessions w where w.id=s.id));
    processed := processed+1;
  end loop;
  return processed;
end $$;
revoke all on function public.app_finalize_open_sessions(timestamptz) from public,anon,authenticated;

-- Verifica la fecha argentina cada minuto, independientemente de la zona del cron.
-- Es idempotente y recupera pendientes de días anteriores si hubo una interrupción.
select cron.schedule('zion-close-missing-exits','* * * * *',
  'select public.app_finalize_open_sessions();');
-- Retener siete días de historial solamente de este job.
select cron.schedule('zion-close-missing-exits-history','15 3 * * *',
  $job$delete from cron.job_run_details
    where jobid in (select jobid from cron.job where jobname in
      ('zion-close-missing-exits','zion-close-missing-exits-history'))
      and end_time < now()-interval '7 days';$job$);
-- También resuelve entradas abiertas anteriores elegibles, sin tocar meses cerrados.
select public.app_finalize_open_sessions();

commit;

-- Compensaciones de horas extras por descanso (005).
-- Proyecto existente: aplicar una sola vez después de 004. No repetir setup.sql.
begin;
create table public.overtime_compensations (
  id uuid primary key,
  employee_id uuid not null references public.employees(id),
  minutes integer not null check (minutes > 0),
  rest_date date not null,
  reason text not null check (length(trim(reason)) between 1 and 2000),
  status text not null check (status in ('scheduled','completed','cancelled')),
  cancellation_reason text,
  created_by uuid not null references public.profiles(id),
  updated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index compensations_employee_date_idx on public.overtime_compensations(employee_id,rest_date);
alter table public.overtime_compensations enable row level security;
revoke all on public.overtime_compensations from public,anon,authenticated;
grant select on public.overtime_compensations to authenticated;
create policy "compensations own or admin" on public.overtime_compensations for select to authenticated
using (public.is_admin() or employee_id in (select id from public.employees where profile_id=auth.uid()));

create function public.app_compensation_balance(p_employee uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('employeeId',p_employee,'earned',earned,'reserved',reserved,
    'used',used,'available',earned-reserved-used)
  from (select coalesce((select sum(c.total_minutes) from public.work_sessions s
      join public.overtime_calculations c on c.session_id=s.id where s.employee_id=p_employee
        and s.status in ('automatic','approved','corrected')),0)::bigint as earned,
    coalesce((select sum(minutes) from public.overtime_compensations where employee_id=p_employee and status='scheduled'),0)::bigint as reserved,
    coalesce((select sum(minutes) from public.overtime_compensations where employee_id=p_employee and status='completed'),0)::bigint as used) totals;
$$;
revoke all on function public.app_compensation_balance(uuid) from public,anon,authenticated;

create function public.get_compensation_data() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare own_employee uuid; admin boolean;
begin
  if auth.uid() is null then raise exception 'Se requiere iniciar sesión'; end if;
  select id into own_employee from public.employees where profile_id=auth.uid();
  if own_employee is null then raise exception 'El usuario no tiene legajo'; end if;
  admin := public.is_admin();
  return jsonb_build_object(
    'compensations',coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'employeeId',employee_id,'minutes',minutes,'restDate',rest_date,
      'reason',reason,'status',status,'cancellationReason',cancellation_reason,
      'createdAt',created_at,'updatedAt',updated_at) order by rest_date desc,created_at desc)
      from public.overtime_compensations where admin or employee_id=own_employee),'[]'::jsonb),
    'balances',coalesce((select jsonb_agg(public.app_compensation_balance(id) order by id)
      from public.employees where admin or id=own_employee),'[]'::jsonb));
end $$;

create function public.admin_create_compensation(p_id uuid,p_employee uuid,p_minutes integer,p_date date,p_reason text,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare existing public.overtime_compensations; available bigint; today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_id is null or p_employee is null or p_minutes is null or p_minutes<=0 or p_date is null
    or p_reason is null or length(trim(p_reason)) not between 1 and 2000
    or p_status is null or p_status not in ('scheduled','completed') then raise exception 'Completá empleado, horas, fecha y motivo'; end if;
  select * into existing from public.overtime_compensations where id=p_id;
  if found then
    if existing.employee_id=p_employee and existing.minutes=p_minutes and existing.rest_date=p_date
      and existing.reason=trim(p_reason) and existing.created_by=auth.uid() then return; end if;
    raise exception 'El identificador ya pertenece a otra compensación';
  end if;
  if p_status='scheduled' and p_date<today then raise exception 'Un descanso programado debe ser hoy o en una fecha futura'; end if;
  if p_status='completed' and p_date>today then raise exception 'No se puede confirmar un descanso futuro'; end if;
  if public.app_month_closed(p_date) then raise exception 'El período del descanso está cerrado'; end if;
  if not exists(select 1 from public.employees where id=p_employee and active) then raise exception 'Empleado no habilitado'; end if;
  available := (public.app_compensation_balance(p_employee)->>'available')::bigint;
  if p_minutes>available then raise exception 'Las horas solicitadas superan el saldo disponible'; end if;
  insert into public.overtime_compensations(id,employee_id,minutes,rest_date,reason,status,created_by,updated_by)
    values(p_id,p_employee,p_minutes,p_date,trim(p_reason),p_status,auth.uid(),auth.uid());
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,after_data)
    values(auth.uid(),'compensation',p_id,'Compensación registrada',
      (select to_jsonb(c) from public.overtime_compensations c where id=p_id));
end $$;

create function public.admin_change_compensation(p_id uuid,p_status text,p_reason text default '')
returns void language plpgsql security definer set search_path='' as $$
declare item public.overtime_compensations;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_status is null or p_status not in ('completed','cancelled') then raise exception 'Estado inválido'; end if;
  select * into item from public.overtime_compensations where id=p_id for update;
  if not found then raise exception 'Compensación inexistente'; end if;
  if item.status=p_status then return; end if;
  if item.status='cancelled' then raise exception 'La compensación ya está cancelada'; end if;
  if public.app_month_closed(item.rest_date) then raise exception 'El período del descanso está cerrado'; end if;
  if p_status='completed' and item.rest_date>(now() at time zone 'America/Argentina/Buenos_Aires')::date then raise exception 'No se puede confirmar un descanso futuro'; end if;
  if p_status='cancelled' and (p_reason is null or length(trim(p_reason)) not between 1 and 2000) then raise exception 'Ingresá el motivo de cancelación'; end if;
  update public.overtime_compensations set status=p_status,updated_by=auth.uid(),updated_at=now(),
    cancellation_reason=case when p_status='cancelled' then trim(p_reason) else null end where id=p_id;
  insert into public.audit_logs(actor_id,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),'compensation',p_id,case when p_status='completed' then 'Descanso confirmado' else 'Compensación cancelada' end,
      to_jsonb(item),(select to_jsonb(c) from public.overtime_compensations c where id=p_id));
end $$;
revoke all on function public.get_compensation_data(),public.admin_create_compensation(uuid,uuid,integer,date,text,text),public.admin_change_compensation(uuid,text,text) from public,anon,authenticated;
grant execute on function public.get_compensation_data(),public.admin_create_compensation(uuid,uuid,integer,date,text,text),public.admin_change_compensation(uuid,text,text) to authenticated;
commit;

-- Fichajes manuales de administradores (006).
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

-- Guardado de instituciones compatible con protección de DELETE (007).
-- Aplicar después de 006. Corrige DELETE sin filtro al guardar instituciones/configuración.
begin;
create or replace function public.admin_save_settings(p_start time,p_end time,p_weekdays integer[],p_institutions text[],p_holidays date[])
returns void language plpgsql security definer set search_path = '' as $$
declare place text; old_data jsonb;
begin
  perform pg_advisory_xact_lock(73482001);
  perform public.app_assert_admin();
  if p_start is null or p_end is null or p_end<=p_start or p_weekdays is null
    or exists(select 1 from unnest(p_weekdays) x where x is null or x<0 or x>6)
    or p_institutions is null or coalesce(array_length(p_institutions,1),0)=0
    or exists(select 1 from unnest(p_institutions) x where x is null or length(trim(x)) not between 1 and 150)
    or p_holidays is null or exists(select 1 from unnest(p_holidays) x where x is null)
    then raise exception 'Revisá horarios, días, instituciones y feriados'; end if;
  select to_jsonb(s) into old_data from public.app_settings s where singleton;
  update public.app_settings set starts_at=p_start,ends_at=p_end,weekdays=p_weekdays,updated_at=now() where singleton;
  update public.institutions set active=false,updated_at=now() where active;
  foreach place in array p_institutions loop
    place := trim(place);
    update public.institutions set active=true,updated_at=now() where name=place;
    if not found then insert into public.institutions(name) values(place); end if;
  end loop;
  delete from public.holidays where not (holiday_date = any(p_holidays));
  insert into public.holidays(holiday_date,name) select distinct x,'Feriado' from unnest(p_holidays) x on conflict (holiday_date) do nothing;
  insert into public.audit_logs(actor_id,entity_type,action,before_data,after_data)
    values(auth.uid(),'settings','configuración',old_data,jsonb_build_object('startsAt',p_start,'endsAt',p_end,'weekdays',p_weekdays,'institutions',p_institutions,'holidays',p_holidays));
end $$;


commit;

-- Mejoras de uso diario (008).
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

-- Cierre específico de entradas y corrección de institución (009).
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
