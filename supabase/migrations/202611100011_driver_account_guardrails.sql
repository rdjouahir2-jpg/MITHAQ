-- Enforce account standing consistently across driver workflows.
create or replace function public.set_driver_availability(p_online boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver_id uuid;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  select d.id, d.availability_status into v_driver_id, v_status
  from public.driver_profiles d
  where d.user_id = auth.uid()
    and d.onboarding_status = 'approved'
    and exists (
      select 1 from public.vehicles v
      where v.driver_id = d.id and v.eligibility_status = 'approved'
    )
  for update;

  if v_driver_id is null then
    raise exception 'approved_driver_and_vehicle_required' using errcode = '42501';
  end if;

  if p_online then
    if v_status = 'busy' then
      raise exception 'driver_is_busy' using errcode = 'P0001';
    end if;
    update public.driver_profiles set availability_status = 'online', updated_at = now()
    where id = v_driver_id;
    return 'online';
  end if;

  if v_status = 'busy' then
    raise exception 'cannot_go_offline_during_active_ride' using errcode = 'P0001';
  end if;
  update public.driver_profiles set availability_status = 'offline', updated_at = now()
  where id = v_driver_id;
  return 'offline';
end;
$$;

create or replace function public.record_driver_location(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision,
  p_recorded_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver_id uuid;
  v_now timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  if p_latitude is null or p_latitude not between -90 and 90
     or p_longitude is null or p_longitude not between -180 and 180
     or p_accuracy_m is null or p_accuracy_m not between 0 and 100
     or p_recorded_at is null
     or p_recorded_at > v_now + interval '30 seconds'
     or p_recorded_at < v_now - interval '2 minutes' then
    raise exception 'invalid_or_stale_location' using errcode = '22023';
  end if;

  select d.id into v_driver_id
  from public.driver_profiles d
  where d.user_id = auth.uid()
    and d.onboarding_status = 'approved'
    and d.availability_status = 'online'
    and exists (
      select 1 from public.vehicles v
      where v.driver_id = d.id and v.eligibility_status = 'approved'
    )
  for update;

  if v_driver_id is null then
    raise exception 'approved_online_driver_required' using errcode = '42501';
  end if;

  insert into public.driver_locations(
    driver_id, latitude, longitude, accuracy_m, recorded_at, updated_at
  ) values(v_driver_id, p_latitude, p_longitude, p_accuracy_m, p_recorded_at, v_now)
  on conflict(driver_id) do update set
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    accuracy_m = excluded.accuracy_m,
    recorded_at = excluded.recorded_at,
    updated_at = v_now
  where public.driver_locations.recorded_at <= excluded.recorded_at;

  return v_now;
end;
$$;

create or replace function public.submit_driver_vehicle(
  p_make text,
  p_model text,
  p_model_year integer,
  p_color text,
  p_seat_capacity integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_driver_id uuid;
  v_vehicle_id uuid;
begin
  if v_user is null or not exists (
    select 1 from public.profiles p where p.id = v_user and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_make,''))) not between 2 and 60
     or length(trim(coalesce(p_model,''))) not between 1 and 60
     or (p_model_year is not null and p_model_year not between 1980 and extract(year from now())::integer + 1)
     or (p_color is not null and length(trim(p_color)) > 40)
     or p_seat_capacity not between 2 and 9 then
    raise exception 'invalid_vehicle_details' using errcode = '22023';
  end if;

  select d.id into v_driver_id
  from public.driver_profiles d
  where d.user_id = v_user and d.onboarding_status in ('pending','under_review','rejected')
  for update;
  if v_driver_id is null then
    raise exception 'driver_application_required' using errcode = '42501';
  end if;

  insert into public.vehicles(driver_id, make, model, model_year, color, seat_capacity)
  values(v_driver_id, trim(p_make), trim(p_model), p_model_year, nullif(trim(p_color),''), p_seat_capacity)
  returning id into v_vehicle_id;

  update public.driver_profiles
    set onboarding_status = 'under_review', availability_status = 'offline', updated_at = now()
  where id = v_driver_id;
  return v_vehicle_id;
end;
$$;

revoke all on function public.set_driver_availability(boolean) from public, anon;
revoke all on function public.record_driver_location(double precision,double precision,double precision,timestamptz) from public, anon;
revoke all on function public.submit_driver_vehicle(text,text,integer,text,integer) from public, anon;
grant execute on function public.set_driver_availability(boolean) to authenticated;
grant execute on function public.record_driver_location(double precision,double precision,double precision,timestamptz) to authenticated;
grant execute on function public.submit_driver_vehicle(text,text,integer,text,integer) to authenticated;
