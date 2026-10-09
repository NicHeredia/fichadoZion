-- Solo para un proyecto NUEVO. Incluye las tres migraciones.
-- En un proyecto que ya funciona, ejecutar solamente 003_admin_dashboard.sql.
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

commit;
