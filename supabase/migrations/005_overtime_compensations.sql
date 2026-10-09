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
