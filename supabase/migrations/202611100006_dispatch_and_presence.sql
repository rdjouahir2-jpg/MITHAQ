-- MITHAQ dispatch and live-driver-presence foundation.
-- Location is deliberately stored as validated coordinates (not exposed publicly).
-- Dispatch is server-only; authenticated drivers can update only their own presence.

create table if not exists public.driver_locations (
  driver_id uuid primary key references public.driver_profiles(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision not null check (accuracy_m between 0 and 1000),
  recorded_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.driver_locations enable row level security;
revoke all on table public.driver_locations from public, anon, authenticated;
grant all on table public.driver_locations to service_role;
create index if not exists driver_locations_freshness_idx
  on public.driver_locations(updated_at desc);
create index if not exists driver_locations_lat_lon_idx
  on public.driver_locations(latitude, longitude);

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

  select d.id, d.availability_status
    into v_driver_id, v_status
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
    update public.driver_profiles
      set availability_status = 'online', updated_at = now()
      where id = v_driver_id;
    return 'online';
  end if;

  update public.driver_profiles
    set availability_status = 'offline', updated_at = now()
    where id = v_driver_id and availability_status <> 'busy';
  if not found and v_status = 'busy' then
    raise exception 'cannot_go_offline_during_active_ride' using errcode = 'P0001';
  end if;
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

  if p_latitude is null or p_latitude < -90 or p_latitude > 90
     or p_longitude is null or p_longitude < -180 or p_longitude > 180
     or p_accuracy_m is null or p_accuracy_m < 0 or p_accuracy_m > 1000
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
  ) values (
    v_driver_id, p_latitude, p_longitude, p_accuracy_m, p_recorded_at, v_now
  )
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

-- This function is intentionally callable only by the server-side service role.
-- It offers a ride to the nearest fresh, approved, available drivers with an
-- approved vehicle. The client cannot create or target offers directly.
create or replace function public.dispatch_ride(
  p_ride_id uuid,
  p_radius_m integer default 7000,
  p_max_drivers integer default 5
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ride public.rides%rowtype;
  v_count integer := 0;
begin
  if p_radius_m is null or p_radius_m < 500 or p_radius_m > 30000
     or p_max_drivers is null or p_max_drivers < 1 or p_max_drivers > 10 then
    raise exception 'invalid_dispatch_parameters' using errcode = '22023';
  end if;

  select * into v_ride
  from public.rides r
  where r.id = p_ride_id
  for update;

  if not found then
    raise exception 'ride_not_found' using errcode = 'P0002';
  end if;

  if v_ride.status not in ('requested','no_driver_found') then
    raise exception 'ride_not_dispatchable' using errcode = 'P0001';
  end if;

  with eligible as (
    select
      d.id as driver_id,
      6371000 * acos(least(1.0, greatest(-1.0,
        sin(radians(v_ride.pickup_point_lat_placeholder))
      ))) as unused_distance
    from public.driver_profiles d
    join public.driver_locations l on l.driver_id = d.id
    where false
  )
  select count(*) into v_count from eligible;

  -- Coordinates are extracted from the PostGIS point stored on the ride.
  -- No location is returned to the passenger or written to a client-readable table.
  with pickup as (
    select
      extensions.st_y(v_ride.pickup_point::extensions.geometry) as lat,
      extensions.st_x(v_ride.pickup_point::extensions.geometry) as lon
  ),
  candidates as (
    select d.id as driver_id,
      6371000 * acos(least(1.0, greatest(-1.0,
        sin(radians(p.lat)) * sin(radians(l.latitude)) +
        cos(radians(p.lat)) * cos(radians(l.latitude)) *
        cos(radians(l.longitude - p.lon))
      ))) as distance_m
    from public.driver_profiles d
    join public.driver_locations l on l.driver_id = d.id
    cross join pickup p
    where d.onboarding_status = 'approved'
      and d.availability_status = 'online'
      and l.updated_at >= now() - interval '90 seconds'
      and l.accuracy_m <= 100
      and abs(l.latitude - p.lat) <= (p_radius_m / 100000.0)
      and abs(l.longitude - p.lon) <= (p_radius_m / 80000.0)
      and exists (
        select 1 from public.vehicles v
        where v.driver_id = d.id
          and v.eligibility_status = 'approved'
          and (v.seat_capacity >= case when v_ride.category = 'family' then 6 else 4 end)
      )
      and not exists (
        select 1 from public.ride_offers o
        where o.ride_id = v_ride.id and o.driver_id = d.id
      )
    order by distance_m asc
    limit p_max_drivers
    for update of d skip locked
  ),
  inserted as (
    insert into public.ride_offers(
      ride_id, driver_id, proposed_amount_minor, status, expires_at
    )
    select v_ride.id, c.driver_id, v_ride.quoted_amount_minor, 'sent', now() + interval '45 seconds'
    from candidates c
    returning id
  )
  select count(*) into v_count from inserted;

  if v_count > 0 then
    update public.rides set status = 'offered' where id = v_ride.id;
    insert into public.ride_events(ride_id, event_type, from_status, to_status, metadata)
    values(v_ride.id, 'dispatch_offers_created', v_ride.status, 'offered',
      jsonb_build_object('offer_count', v_count));
  else
    update public.rides set status = 'no_driver_found' where id = v_ride.id;
    insert into public.ride_events(ride_id, event_type, from_status, to_status)
    values(v_ride.id, 'dispatch_no_driver_found', v_ride.status, 'no_driver_found');
  end if;

  return v_count;
end;
$$;

revoke all on function public.set_driver_availability(boolean) from public, anon;
revoke all on function public.record_driver_location(double precision,double precision,double precision,timestamptz) from public, anon;
revoke all on function public.dispatch_ride(uuid,integer,integer) from public, anon, authenticated;
grant execute on function public.set_driver_availability(boolean) to authenticated;
grant execute on function public.record_driver_location(double precision,double precision,double precision,timestamptz) to authenticated;
grant execute on function public.dispatch_ride(uuid,integer,integer) to service_role;

comment on table public.driver_locations is
'Private latest driver coordinates. Never grant client table access; use the authenticated location RPC and server-only dispatch.';
comment on function public.dispatch_ride(uuid,integer,integer) is
'Server-only dispatch. Matches recent accurate locations and approved drivers/vehicles; creates expiring offers transactionally.';
