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
