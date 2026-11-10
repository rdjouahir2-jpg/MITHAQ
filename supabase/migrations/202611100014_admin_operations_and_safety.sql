-- Operational visibility and safety-report workflow for the closed test environment.
create or replace function public.admin_set_account_status(
  p_user_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_previous text;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles ur where ur.user_id = v_actor and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_status not in ('active','restricted','closed')
     or length(trim(coalesce(p_reason,''))) not between 5 and 500 then
    raise exception 'invalid_account_review' using errcode = '22023';
  end if;
  if p_user_id = v_actor and p_status <> 'active' then
    raise exception 'cannot_restrict_own_admin_account' using errcode = '42501';
  end if;

  select account_status into v_previous from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;

  update public.profiles set account_status = p_status, updated_at = now()
  where id = p_user_id;
  if p_status <> 'active' then
    update public.driver_profiles set availability_status = 'offline', updated_at = now()
    where user_id = p_user_id and availability_status <> 'busy';
  end if;

  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'account_status_changed', 'profile', p_user_id::text, trim(p_reason),
    jsonb_build_object('from', v_previous, 'to', p_status));
end;
$$;

create or replace function public.submit_safety_report(
  p_ride_id uuid,
  p_category text,
  p_severity text,
  p_description text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_report_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if length(trim(coalesce(p_category,''))) not between 2 and 60
     or p_severity not in ('low','normal','high','critical')
     or length(trim(coalesce(p_description,''))) not between 5 and 2000 then
    raise exception 'invalid_safety_report' using errcode = '22023';
  end if;
  if p_ride_id is not null and not exists (
    select 1 from public.rides r
    where r.id = p_ride_id and (
      r.passenger_id = v_user or exists (
        select 1 from public.driver_profiles d
        where d.id = r.driver_id and d.user_id = v_user
      )
    )
  ) then
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;

  insert into public.safety_reports(ride_id, reporter_user_id, category, severity, description)
  values(p_ride_id, v_user, trim(p_category), p_severity, trim(p_description))
  returning id into v_report_id;
  return v_report_id;
end;
$$;

create or replace function public.admin_list_recent_rides()
returns table (
  ride_id uuid,
  passenger_name text,
  driver_name text,
  pickup_label text,
  destination_label text,
  ride_status public.ride_status,
  quoted_amount_minor bigint,
  currency_code char(3),
  requested_at timestamptz,
  completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select r.id, pp.display_name, dp.display_name,
    r.pickup_label, r.destination_label, r.status,
    r.quoted_amount_minor, r.currency_code, r.requested_at, r.completed_at
  from public.rides r
  join public.profiles pp on pp.id = r.passenger_id
  left join public.driver_profiles d on d.id = r.driver_id
  left join public.profiles dp on dp.id = d.user_id
  order by r.requested_at desc
  limit 100;
end;
$$;

create or replace function public.admin_list_safety_reports()
returns table (
  report_id uuid,
  ride_id uuid,
  reporter_name text,
  category text,
  severity text,
  description text,
  report_status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select sr.id, sr.ride_id, p.display_name, sr.category, sr.severity,
    sr.description, sr.status, sr.created_at
  from public.safety_reports sr
  join public.profiles p on p.id = sr.reporter_user_id
  order by case sr.severity when 'critical' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,
    sr.created_at desc
  limit 100;
end;
$$;

create or replace function public.admin_update_safety_report(
  p_report_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_previous text;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles ur where ur.user_id = v_actor and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_status not in ('investigating','resolved','closed')
     or length(trim(coalesce(p_reason,''))) not between 5 and 500 then
    raise exception 'invalid_safety_report_update' using errcode = '22023';
  end if;

  select status into v_previous from public.safety_reports where id = p_report_id for update;
  if not found then
    raise exception 'safety_report_not_found' using errcode = 'P0002';
  end if;

  update public.safety_reports set status = p_status where id = p_report_id;
  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'safety_report_updated', 'safety_report', p_report_id::text, trim(p_reason),
    jsonb_build_object('from', v_previous, 'to', p_status));
end;
$$;

revoke all on function public.submit_safety_report(uuid,text,text,text) from public, anon;
revoke all on function public.admin_list_recent_rides() from public, anon, authenticated;
revoke all on function public.admin_list_safety_reports() from public, anon, authenticated;
revoke all on function public.admin_update_safety_report(uuid,text,text) from public, anon, authenticated;
grant execute on function public.submit_safety_report(uuid,text,text,text) to authenticated;
grant execute on function public.admin_list_recent_rides() to authenticated;
grant execute on function public.admin_list_safety_reports() to authenticated;
grant execute on function public.admin_update_safety_report(uuid,text,text) to authenticated;
