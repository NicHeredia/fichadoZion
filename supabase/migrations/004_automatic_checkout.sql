-- Proyecto existente: ejecutar después de 003_admin_dashboard.sql.
-- El job corre en el servidor; no necesita tener la aplicación abierta.
begin;
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
