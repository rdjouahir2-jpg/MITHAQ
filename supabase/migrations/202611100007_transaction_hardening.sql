-- MITHAQ transaction-order and cryptographic PIN hardening.
-- All operations touching a ride acquire the ride row before driver/offer rows.
-- This keeps dispatch, acceptance, and expiry on one lock order and reduces deadlocks.

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
    select 1 from public.profiles p
    where p.id = v_user and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
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

  v_pin := lpad(
    ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text),
    6,
    '0'
  );

  insert into public.rides (
    passenger_id, pickup_label, destination_label,
    pickup_point, destination_point, category,
    status, quoted_amount_minor, currency_code, trip_pin_hash
  ) values (
    v_user, v_quote.pickup_label, v_quote.destination_label,
    extensions.st_setsrid(extensions.st_makepoint(v_quote.pickup_longitude, v_quote.pickup_latitude), 4326)::extensions.geography,
    extensions.st_setsrid(extensions.st_makepoint(v_quote.destination_longitude, v_quote.destination_latitude), 4326)::extensions.geography,
    v_quote.category, 'requested', v_quote.amount_minor, v_quote.currency_code,
    extensions.crypt(v_pin, extensions.gen_salt('bf'))
  ) returning id into v_ride_id;

  update public.fare_quotes set consumed_at = now()
  where id = v_quote.id and consumed_at is null;

  insert into public.ride_events(ride_id, actor_user_id, event_type, to_status)
  values(v_ride_id, v_user, 'ride_requested', 'requested');

  return query select v_ride_id, v_pin, 'requested'::public.ride_status;
end;
$$;

create or replace function public.accept_ride_offer(p_offer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ride_id uuid;
  v_driver_id uuid;
  v_old_status public.ride_status;
  v_expires timestamptz;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  -- Read the parent id without locking, then lock in global order: ride -> driver -> offer.
  select o.ride_id into v_ride_id
  from public.ride_offers o
  where o.id = p_offer_id and o.status = 'sent';

  if v_ride_id is null then
    raise exception 'offer_not_available' using errcode = 'P0002';
  end if;

  select r.status into v_old_status
  from public.rides r
  where r.id = v_ride_id
  for update;

  if not found or v_old_status not in ('requested','offered') then
    raise exception 'ride_no_longer_available' using errcode = 'P0001';
  end if;

  select d.id into v_driver_id
  from public.driver_profiles d
  where d.user_id = v_user
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

  select o.expires_at into v_expires
  from public.ride_offers o
  where o.id = p_offer_id
    and o.ride_id = v_ride_id
    and o.driver_id = v_driver_id
    and o.status = 'sent'
  for update;

  if not found then
    raise exception 'offer_not_available' using errcode = 'P0002';
  end if;
  if v_expires <= now() then
    raise exception 'offer_expired' using errcode = 'P0001';
  end if;

  update public.ride_offers
    set status = 'accepted', responded_at = now()
    where id = p_offer_id and status = 'sent';
  if not found then
    raise exception 'offer_already_answered' using errcode = 'P0001';
  end if;

  update public.ride_offers
    set status = 'withdrawn', responded_at = now()
    where ride_id = v_ride_id and id <> p_offer_id and status = 'sent';

  update public.rides
    set driver_id = v_driver_id, status = 'accepted', accepted_at = now()
    where id = v_ride_id;

  update public.driver_profiles
    set availability_status = 'busy', updated_at = now()
    where id = v_driver_id;

  insert into public.ride_events(ride_id, actor_user_id, event_type, from_status, to_status)
  values(v_ride_id, v_user, 'offer_accepted', v_old_status, 'accepted');

  return v_ride_id;
end;
$$;

revoke all on function public.request_ride(uuid) from public, anon;
revoke all on function public.accept_ride_offer(uuid) from public, anon;
grant execute on function public.request_ride(uuid) to authenticated;
grant execute on function public.accept_ride_offer(uuid) to authenticated;
