-- MITHAQ security hardening v2
-- Apply after migrations 001-003. This migration removes client-controlled fare input.
-- Fare quotes are written only by a trusted server/Edge Function after validating
-- route coordinates and a server-side routing result. The browser never sets a price.

create table if not exists public.fare_quotes (
  id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.profiles(id) on delete cascade,
  pickup_label text not null check (length(trim(pickup_label)) between 2 and 180),
  destination_label text not null check (length(trim(destination_label)) between 2 and 180),
  pickup_latitude double precision not null check (pickup_latitude between -90 and 90),
  pickup_longitude double precision not null check (pickup_longitude between -180 and 180),
  destination_latitude double precision not null check (destination_latitude between -90 and 90),
  destination_longitude double precision not null check (destination_longitude between -180 and 180),
  category text not null check (category in ('economy','comfort','family')),
  amount_minor bigint not null check (amount_minor >= 0 and amount_minor <= 100000000),
  currency_code char(3) not null default 'DZD',
  route_distance_m integer not null check (route_distance_m > 0),
  route_duration_s integer not null check (route_duration_s > 0),
  fare_policy_version integer not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.fare_quotes enable row level security;
revoke all on table public.fare_quotes from public, anon, authenticated;
grant all on table public.fare_quotes to service_role;
create index if not exists fare_quotes_passenger_expiry_idx
  on public.fare_quotes(passenger_id, expires_at desc)
  where consumed_at is null;

-- Only a trusted server holding the service role can create quotes.
-- The client can consume only a quote bound to its authenticated identity.
drop function if exists public.request_ride(text,text,text,bigint);
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

  v_pin := lpad((floor(random() * 1000000))::int::text, 6, '0');

  insert into public.rides (
    passenger_id, pickup_label, destination_label, category,
    status, quoted_amount_minor, currency_code, trip_pin_hash
  ) values (
    v_user, v_quote.pickup_label, v_quote.destination_label, v_quote.category,
    'requested', v_quote.amount_minor, v_quote.currency_code,
    extensions.crypt(v_pin, extensions.gen_salt('bf'))
  ) returning id into v_ride_id;

  update public.fare_quotes set consumed_at = now()
  where id = v_quote.id and consumed_at is null;

  insert into public.ride_events(ride_id, actor_user_id, event_type, to_status)
  values(v_ride_id, v_user, 'ride_requested', 'requested');

  return query select v_ride_id, v_pin, 'requested'::public.ride_status;
end;
$$;

-- Never mark a stale offer inside a transaction that immediately raises:
-- PostgreSQL would roll the update back with the exception. Expiry is checked
-- here; a scheduled cleanup can mark stale offers separately.
create or replace function public.accept_ride_offer(p_offer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_driver_id uuid;
  v_ride_id uuid;
  v_old_status public.ride_status;
  v_expires timestamptz;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  select d.id into v_driver_id
  from public.driver_profiles d
  where d.user_id = v_user
    and d.onboarding_status = 'approved'
    and d.availability_status = 'online'
  for update;

  if v_driver_id is null then
    raise exception 'approved_online_driver_required' using errcode = '42501';
  end if;

  select o.ride_id, o.expires_at into v_ride_id, v_expires
  from public.ride_offers o
  where o.id = p_offer_id and o.driver_id = v_driver_id and o.status = 'sent'
  for update;

  if v_ride_id is null then
    raise exception 'offer_not_available' using errcode = 'P0002';
  end if;
  if v_expires <= now() then
    raise exception 'offer_expired' using errcode = 'P0001';
  end if;

  select r.status into v_old_status
  from public.rides r where r.id = v_ride_id for update;

  if v_old_status not in ('requested','offered') then
    raise exception 'ride_no_longer_available' using errcode = 'P0001';
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

-- A completed or cancelled driver must explicitly opt back in to availability.
-- This prevents the system from silently making a driver online again.
create or replace function public.advance_ride(
  p_ride_id uuid,
  p_next_status public.ride_status,
  p_boarding_pin text default null
)
returns public.ride_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_driver_id uuid;
  v_passenger_id uuid;
  v_old public.ride_status;
  v_pin_hash text;
  v_actor public.app_role;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  select r.driver_id, r.passenger_id, r.status, r.trip_pin_hash
    into v_driver_id, v_passenger_id, v_old, v_pin_hash
    from public.rides r where r.id = p_ride_id for update;

  if not found then
    raise exception 'ride_not_found' using errcode = 'P0002';
  end if;

  if v_user = v_passenger_id then
    v_actor := 'passenger';
  elsif exists (
    select 1 from public.driver_profiles d
    where d.id = v_driver_id and d.user_id = v_user
  ) then
    v_actor := 'driver';
  else
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;

  if v_actor = 'passenger' then
    if p_next_status <> 'cancelled'
       or v_old not in ('requested','offered','accepted','driver_arriving','arrived') then
      raise exception 'passenger_transition_not_allowed' using errcode = '42501';
    end if;
  elsif not (
    (v_old = 'accepted' and p_next_status = 'driver_arriving') or
    (v_old = 'driver_arriving' and p_next_status = 'arrived') or
    (v_old = 'arrived' and p_next_status = 'boarded') or
    (v_old = 'boarded' and p_next_status = 'in_progress') or
    (v_old = 'in_progress' and p_next_status = 'completed')
  ) then
    raise exception 'invalid_driver_transition' using errcode = '22023';
  end if;

  if v_old = 'arrived' and p_next_status = 'boarded' then
    if p_boarding_pin is null or p_boarding_pin !~ '^[0-9]{6}$'
       or v_pin_hash is null
       or extensions.crypt(p_boarding_pin, v_pin_hash) <> v_pin_hash then
      raise exception 'invalid_boarding_pin' using errcode = '22023';
    end if;
  end if;

  update public.rides set
    status = p_next_status,
    started_at = case when p_next_status = 'in_progress' then now() else started_at end,
    completed_at = case when p_next_status = 'completed' then now() else completed_at end,
    cancelled_at = case when p_next_status = 'cancelled' then now() else cancelled_at end
  where id = p_ride_id;

  if p_next_status in ('completed','cancelled') and v_driver_id is not null then
    update public.driver_profiles
      set availability_status = 'offline', updated_at = now()
      where id = v_driver_id;
  end if;

  insert into public.ride_events(ride_id, actor_user_id, event_type, from_status, to_status)
  values(p_ride_id, v_user, 'ride_status_changed', v_old, p_next_status);

  return p_next_status;
end;
$$;

revoke all on function public.request_ride(uuid) from public, anon;
revoke all on function public.accept_ride_offer(uuid) from public, anon;
revoke all on function public.advance_ride(uuid,public.ride_status,text) from public, anon;
grant execute on function public.request_ride(uuid) to authenticated;
grant execute on function public.accept_ride_offer(uuid) to authenticated;
grant execute on function public.advance_ride(uuid,public.ride_status,text) to authenticated;

comment on table public.fare_quotes is
'Short-lived server-generated fare quotes. Clients have no direct table privileges; each quote is single-use and bound to one passenger.';
