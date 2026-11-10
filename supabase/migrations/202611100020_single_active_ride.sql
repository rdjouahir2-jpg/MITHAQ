-- Enforce one active ride per passenger even under concurrent requests.
create unique index if not exists rides_one_active_per_passenger
on public.rides(passenger_id)
where status in ('requested','offered','accepted','driver_arriving','arrived','boarded','in_progress');

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

  perform 1 from public.profiles p
  where p.id = v_user and p.account_status = 'active'
  for update;
  if not found then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.rides r
    where r.passenger_id = v_user
      and r.status in ('requested','offered','accepted','driver_arriving','arrived','boarded','in_progress')
  ) then
    raise exception 'active_ride_already_exists' using errcode = 'P0001';
  end if;

  select * into v_quote
  from public.fare_quotes q
  where q.id = p_quote_id
    and q.passenger_id = v_user
    and q.consumed_at is null
    and q.expires_at > now()
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

  update public.fare_quotes set consumed_at = now()
  where id = v_quote.id and consumed_at is null;

  insert into public.ride_events(ride_id, actor_user_id, event_type, to_status)
  values(v_ride_id, v_user, 'ride_requested', 'requested');

  perform public.dispatch_ride(v_ride_id, 7000, 5);

  return query select r.id, v_pin, r.status
  from public.rides r where r.id = v_ride_id;
end;
$$;

revoke all on function public.request_ride(uuid) from public, anon;
grant execute on function public.request_ride(uuid) to authenticated;
