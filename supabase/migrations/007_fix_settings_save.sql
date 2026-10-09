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
