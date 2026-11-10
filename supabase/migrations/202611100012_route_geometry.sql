-- Preserve the server-calculated route for navigation display and auditability.
alter table public.fare_quotes
  add column if not exists route_geometry jsonb;

alter table public.rides
  add column if not exists route_geometry jsonb;

create or replace function public.request_ride(p_quote_id uuid)
returns table (ride_id uuid, boarding_pin text, current_status public.ride_status)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_quote public.fare_quotes%rowtype;
  v_pin text;
  v_ride_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.profiles p where p.id = v_user and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  select * into v_quote
  from public.fare_quotes q
  where q.id = p_quote_id and q.passenger_id = v_user
    and q.consumed_at is null and q.expires_at > now()
  for update;
  if not found then
    raise exception 'valid_fare_quote_required' using errcode = '22023';
  end if;
  if v_quote.route_geometry is null then
    raise exception 'route_geometry_required' using errcode = '22023';
  end if;

  v_pin := lpad(
    ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text),
    6,
    '0'
  );

  insert into public.rides (
    passenger_id, pickup_label, destination_label, pickup_point, destination_point,
    category, status, quoted_amount_minor, currency_code, trip_pin_hash, route_geometry
  ) values (
    v_user, v_quote.pickup_label, v_quote.destination_label,
    extensions.st_setsrid(extensions.st_makepoint(v_quote.pickup_longitude, v_quote.pickup_latitude), 4326)::extensions.geography,
    extensions.st_setsrid(extensions.st_makepoint(v_quote.destination_longitude, v_quote.destination_latitude), 4326)::extensions.geography,
    v_quote.category, 'requested', v_quote.amount_minor, v_quote.currency_code,
    extensions.crypt(v_pin, extensions.gen_salt('bf')), v_quote.route_geometry
  ) returning id into v_ride_id;

  update public.fare_quotes set consumed_at = now() where id = v_quote.id and consumed_at is null;

  insert into public.ride_events(ride_id, actor_user_id, event_type, to_status)
  values(v_ride_id, v_user, 'ride_requested', 'requested');

  perform public.dispatch_ride(v_ride_id, 7000, 5);

  return query
  select r.id, v_pin, r.status from public.rides r where r.id = v_ride_id;
end;
$$;

revoke all on function public.request_ride(uuid) from public, anon;
grant execute on function public.request_ride(uuid) to authenticated;

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
  driver_location_recorded_at timestamptz,
  route_geometry jsonb
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
  select * into v_ride from public.rides r where r.id = p_ride_id;
  if not found then
    raise exception 'ride_not_found' using errcode = 'P0002';
  end if;

  v_is_passenger := v_ride.passenger_id = v_user;
  v_is_driver := exists (
    select 1 from public.driver_profiles d where d.id = v_ride.driver_id and d.user_id = v_user
  );
  if not (v_is_passenger or v_is_driver) then
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;
  if v_ride.status not in ('accepted','driver_arriving','arrived','boarded','in_progress') then
    raise exception 'ride_tracking_not_available' using errcode = 'P0001';
  end if;

  return query
  select v_ride.id, v_ride.status,
    extensions.st_y(v_ride.pickup_point::extensions.geometry),
    extensions.st_x(v_ride.pickup_point::extensions.geometry),
    extensions.st_y(v_ride.destination_point::extensions.geometry),
    extensions.st_x(v_ride.destination_point::extensions.geometry),
    case when l.updated_at >= now() - interval '90 seconds' then l.latitude else null end,
    case when l.updated_at >= now() - interval '90 seconds' then l.longitude else null end,
    case when l.updated_at >= now() - interval '90 seconds' then l.recorded_at else null end,
    v_ride.route_geometry
  from (select 1) seed
  left join public.driver_locations l on l.driver_id = v_ride.driver_id;
end;
$$;

revoke all on function public.get_my_ride_tracking(uuid) from public, anon;
grant execute on function public.get_my_ride_tracking(uuid) to authenticated;
