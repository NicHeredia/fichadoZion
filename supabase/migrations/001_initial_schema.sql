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
