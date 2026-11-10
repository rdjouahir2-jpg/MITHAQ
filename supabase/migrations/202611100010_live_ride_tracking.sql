-- Controlled ride tracking: only the passenger assigned to a live ride
-- and its assigned driver can read the latest driver position.
create or replace function public.get_my_ride_tracking(p_ride_id uuid)
returns table (
  ride_id uuid,
  ride_status public.ride_status,
  pickup_latitude double precision,
  pickup_longitude double precision,
  destination_latitude double precision,
  destination_longitude double precision,
  driver_latitude double precision,
  driver_longitude double precision,
  driver_location_recorded_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ride public.rides%rowtype;
  v_is_passenger boolean;
  v_is_driver boolean;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  select * into v_ride
  from public.rides r
  where r.id = p_ride_id;

  if not found then
    raise exception 'ride_not_found' using errcode = 'P0002';
  end if;

  v_is_passenger := v_ride.passenger_id = v_user;
  v_is_driver := exists (
    select 1 from public.driver_profiles d
    where d.id = v_ride.driver_id and d.user_id = v_user
  );

  if not (v_is_passenger or v_is_driver) then
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;

  if v_ride.status not in ('accepted','driver_arriving','arrived','boarded','in_progress') then
    raise exception 'ride_tracking_not_available' using errcode = 'P0001';
  end if;

  return query
  select
    v_ride.id,
    v_ride.status,
    extensions.st_y(v_ride.pickup_point::extensions.geometry),
    extensions.st_x(v_ride.pickup_point::extensions.geometry),
    extensions.st_y(v_ride.destination_point::extensions.geometry),
    extensions.st_x(v_ride.destination_point::extensions.geometry),
    case when l.updated_at >= now() - interval '90 seconds' then l.latitude else null end,
    case when l.updated_at >= now() - interval '90 seconds' then l.longitude else null end,
    case when l.updated_at >= now() - interval '90 seconds' then l.recorded_at else null end
  from (select 1) seed
  left join public.driver_locations l on l.driver_id = v_ride.driver_id;
end;
$$;

revoke all on function public.get_my_ride_tracking(uuid) from public, anon;
grant execute on function public.get_my_ride_tracking(uuid) to authenticated;
