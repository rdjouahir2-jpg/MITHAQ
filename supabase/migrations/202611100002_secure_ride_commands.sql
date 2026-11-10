-- MITHAQ secure ride commands v1
-- Server-authoritative functions. Apply after 202611100001_initial_schema.sql.
-- No service-role key is ever exposed to clients.

create extension if not exists pgcrypto;

create or replace function public.request_ride(
  p_pickup_label text,
  p_destination_label text,
  p_category text,
  p_quoted_amount_minor bigint
)
returns table (ride_id uuid, boarding_pin text, current_status public.ride_status)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_pin text;
  v_ride_id uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if length(trim(coalesce(p_pickup_label,''))) not between 2 and 180
     or length(trim(coalesce(p_destination_label,''))) not between 2 and 180 then
    raise exception 'invalid_location_label' using errcode = '22023';
  end if;
  if p_category not in ('economy','comfort','family') then
    raise exception 'invalid_vehicle_category' using errcode = '22023';
  end if;
  if p_quoted_amount_minor is null or p_quoted_amount_minor < 0 or p_quoted_amount_minor > 100000000 then
    raise exception 'invalid_quote' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_user and p.account_status = 'active'
  ) then raise exception 'active_account_required' using errcode = '42501'; end if;

  v_pin := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into public.rides (
    passenger_id, pickup_label, destination_label, category,
    status, quoted_amount_minor, trip_pin_hash
  ) values (
    v_user, trim(p_pickup_label), trim(p_destination_label), p_category,
    'requested', p_quoted_amount_minor, crypt(v_pin, gen_salt('bf'))
  ) returning id into v_ride_id;

  insert into public.ride_events(ride_id, actor_user_id, event_type, to_status)
  values(v_ride_id, v_user, 'ride_requested', 'requested');

  return query select v_ride_id, v_pin, 'requested'::public.ride_status;
end;
$$;

create or replace function public.accept_ride_offer(p_offer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_driver_id uuid;
  v_ride_id uuid;
  v_old_status public.ride_status;
  v_expires timestamptz;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  select d.id into v_driver_id
  from public.driver_profiles d
  where d.user_id = v_user
    and d.onboarding_status = 'approved'
    and d.availability_status = 'online';
  if v_driver_id is null then raise exception 'approved_online_driver_required' using errcode = '42501'; end if;

  select o.ride_id, o.expires_at into v_ride_id, v_expires
  from public.ride_offers o
  where o.id = p_offer_id and o.driver_id = v_driver_id and o.status = 'sent'
  for update;
  if v_ride_id is null then raise exception 'offer_not_available' using errcode = 'P0002'; end if;
  if v_expires <= now() then
    update public.ride_offers set status = 'expired', responded_at = now() where id = p_offer_id;
    raise exception 'offer_expired' using errcode = 'P0001';
  end if;

  select r.status into v_old_status from public.rides r where r.id = v_ride_id for update;
  if v_old_status not in ('requested','offered') then
    raise exception 'ride_no_longer_available' using errcode = 'P0001';
  end if;

  update public.ride_offers
    set status = 'accepted', responded_at = now()
    where id = p_offer_id and status = 'sent';
  if not found then raise exception 'offer_already_answered' using errcode = 'P0001'; end if;

  update public.ride_offers
    set status = 'withdrawn', responded_at = now()
    where ride_id = v_ride_id and id <> p_offer_id and status = 'sent';

  update public.rides
    set driver_id = v_driver_id, status = 'accepted', accepted_at = now()
    where id = v_ride_id;

  update public.driver_profiles set availability_status = 'busy', updated_at = now()
    where id = v_driver_id;

  insert into public.ride_events(ride_id, actor_user_id, event_type, from_status, to_status)
  values(v_ride_id, v_user, 'offer_accepted', v_old_status, 'accepted');

  return v_ride_id;
end;
$$;

create or replace function public.advance_ride(
  p_ride_id uuid,
  p_next_status public.ride_status,
  p_boarding_pin text default null
)
returns public.ride_status
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_driver_id uuid;
  v_passenger_id uuid;
  v_old public.ride_status;
  v_new public.ride_status;
  v_pin_hash text;
  v_actor public.app_role;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  select r.driver_id, r.passenger_id, r.status, r.trip_pin_hash
    into v_driver_id, v_passenger_id, v_old, v_pin_hash
    from public.rides r where r.id = p_ride_id for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;

  if v_user = v_passenger_id then
    v_actor := 'passenger';
  elsif exists(select 1 from public.driver_profiles d where d.id = v_driver_id and d.user_id = v_user) then
    v_actor := 'driver';
  else
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;

  if v_actor = 'passenger' and p_next_status <> 'cancelled' then
    raise exception 'passenger_transition_not_allowed' using errcode = '42501';
  end if;

  if v_actor = 'driver' and not (
    (v_old = 'accepted' and p_next_status = 'driver_arriving') or
    (v_old = 'driver_arriving' and p_next_status = 'arrived') or
    (v_old = 'arrived' and p_next_status = 'boarded') or
    (v_old = 'boarded' and p_next_status = 'in_progress') or
    (v_old = 'in_progress' and p_next_status = 'completed')
  ) then raise exception 'invalid_driver_transition' using errcode = '22023'; end if;

  if v_actor = 'passenger' and v_old not in ('requested','offered','accepted','driver_arriving','arrived') then
    raise exception 'ride_cannot_be_cancelled' using errcode = '22023';
  end if;

  if v_old = 'arrived' and p_next_status = 'boarded' then
    if p_boarding_pin is null or p_boarding_pin !~ '^[0-9]{6}$'
       or v_pin_hash is null or crypt(p_boarding_pin, v_pin_hash) <> v_pin_hash then
      raise exception 'invalid_boarding_pin' using errcode = '22023';
    end if;
  end if;

  if not (
    (v_actor = 'driver' and (
      (v_old = 'accepted' and p_next_status = 'driver_arriving') or
      (v_old = 'driver_arriving' and p_next_status = 'arrived') or
      (v_old = 'arrived' and p_next_status = 'boarded') or
      (v_old = 'boarded' and p_next_status = 'in_progress') or
      (v_old = 'in_progress' and p_next_status = 'completed')
    )) or
    (v_actor = 'passenger' and p_next_status = 'cancelled')
  ) then raise exception 'invalid_ride_transition' using errcode = '22023'; end if;

  update public.rides set
    status = p_next_status,
    started_at = case when p_next_status = 'in_progress' then now() else started_at end,
    completed_at = case when p_next_status = 'completed' then now() else completed_at end,
    cancelled_at = case when p_next_status = 'cancelled' then now() else cancelled_at end
  where id = p_ride_id;

  if p_next_status in ('completed','cancelled') then
    update public.driver_profiles set availability_status = 'online', updated_at = now()
      where id = v_driver_id;
  end if;

  insert into public.ride_events(ride_id, actor_user_id, event_type, from_status, to_status)
  values(p_ride_id, v_user, 'ride_status_changed', v_old, p_next_status);

  return p_next_status;
end;
$$;

revoke all on function public.request_ride(text,text,text,bigint) from public, anon;
revoke all on function public.accept_ride_offer(uuid) from public, anon;
revoke all on function public.advance_ride(uuid,public.ride_status,text) from public, anon;
grant execute on function public.request_ride(text,text,text,bigint) to authenticated;
grant execute on function public.accept_ride_offer(uuid) to authenticated;
grant execute on function public.advance_ride(uuid,public.ride_status,text) to authenticated;

comment on function public.request_ride(text,text,text,bigint) is
'Creates an authenticated passenger request; returns one-time boarding PIN to the requesting passenger only.';
comment on function public.accept_ride_offer(uuid) is
'Atomically accepts an eligible driver offer under a row lock; only one driver can win.';
comment on function public.advance_ride(uuid,public.ride_status,text) is
'Server-authoritative ride state transition; requires correct participant and boarding PIN.';
