-- Return only the counterpart and approved vehicle details needed by a participant.
-- No phone numbers, identity documents, or raw profile records are exposed.
create or replace function public.get_my_passenger_ride_details(p_limit integer default 20)
returns table (
  id uuid,
  pickup_label text,
  destination_label text,
  category text,
  status public.ride_status,
  quoted_amount_minor bigint,
  currency_code char(3),
  requested_at timestamptz,
  driver_id uuid,
  driver_name text,
  vehicle_make text,
  vehicle_model text,
  vehicle_color text,
  vehicle_seat_capacity integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_limit is null or p_limit not between 1 and 20 then
    raise exception 'invalid_limit' using errcode = '22023';
  end if;

  return query
  select r.id, r.pickup_label, r.destination_label, r.category, r.status,
    r.quoted_amount_minor, r.currency_code, r.requested_at, r.driver_id,
    dp.display_name,
    v.make, v.model, v.color, v.seat_capacity
  from public.rides r
  left join public.driver_profiles d on d.id = r.driver_id
  left join public.profiles dp on dp.id = d.user_id
  left join lateral (
    select vv.make, vv.model, vv.color, vv.seat_capacity
    from public.vehicles vv
    where vv.driver_id = d.id and vv.eligibility_status = 'approved'
    order by vv.created_at desc
    limit 1
  ) v on true
  where r.passenger_id = auth.uid()
  order by r.requested_at desc
  limit p_limit;
end;
$$;

create or replace function public.get_my_driver_ride_details(p_limit integer default 5)
returns table (
  id uuid,
  pickup_label text,
  destination_label text,
  category text,
  status public.ride_status,
  quoted_amount_minor bigint,
  currency_code char(3),
  requested_at timestamptz,
  driver_id uuid,
  passenger_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_limit is null or p_limit not between 1 and 20 then
    raise exception 'invalid_limit' using errcode = '22023';
  end if;

  return query
  select r.id, r.pickup_label, r.destination_label, r.category, r.status,
    r.quoted_amount_minor, r.currency_code, r.requested_at, r.driver_id,
    p.display_name
  from public.rides r
  join public.driver_profiles d on d.id = r.driver_id and d.user_id = auth.uid()
  join public.profiles p on p.id = r.passenger_id
  where r.status in ('accepted','driver_arriving','arrived','boarded','in_progress','completed')
  order by r.requested_at desc
  limit p_limit;
end;
$$;

revoke all on function public.get_my_passenger_ride_details(integer) from public, anon;
revoke all on function public.get_my_driver_ride_details(integer) from public, anon;
grant execute on function public.get_my_passenger_ride_details(integer) to authenticated;
grant execute on function public.get_my_driver_ride_details(integer) to authenticated;
