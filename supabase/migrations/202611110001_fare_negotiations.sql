-- MITHAQ transactional fare negotiation.
-- Client writes are forbidden: every transition is validated in SECURITY DEFINER RPCs.
create table public.fare_negotiations (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  offer_id uuid not null references public.ride_offers(id) on delete cascade,
  driver_id uuid not null references public.driver_profiles(id),
  passenger_id uuid not null references public.profiles(id),
  status text not null default 'open' check (status in ('open','accepted','rejected','expired')),
  quoted_amount_minor bigint not null check (quoted_amount_minor between 0 and 100000000),
  current_amount_minor bigint not null check (current_amount_minor between 0 and 100000000),
  minimum_amount_minor bigint not null check (minimum_amount_minor between 0 and 100000000),
  maximum_amount_minor bigint not null check (maximum_amount_minor between 0 and 100000000),
  round_number integer not null default 1 check (round_number between 1 and 5),
  max_rounds integer not null default 5 check (max_rounds between 1 and 5),
  last_actor text not null check (last_actor in ('passenger','driver')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (minimum_amount_minor <= current_amount_minor),
  check (current_amount_minor <= maximum_amount_minor),
  check (minimum_amount_minor <= maximum_amount_minor)
);

create unique index fare_negotiations_one_open_per_offer
  on public.fare_negotiations(offer_id) where status = 'open';
create index fare_negotiations_passenger_open_idx
  on public.fare_negotiations(passenger_id, status, expires_at);
create index fare_negotiations_driver_open_idx
  on public.fare_negotiations(driver_id, status, expires_at);

alter table public.fare_negotiations enable row level security;
revoke all on table public.fare_negotiations from public, anon, authenticated;
grant select on table public.fare_negotiations to authenticated;
create policy fare_negotiations_participant_read
  on public.fare_negotiations for select to authenticated
  using (
    passenger_id = (select auth.uid())
    or exists (
      select 1 from public.driver_profiles d
      where d.id = driver_id and d.user_id = (select auth.uid())
    )
  );

create or replace function public.start_fare_negotiation(
  p_offer_id uuid,
  p_counter_amount_minor bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ride_id uuid;
  v_driver_id uuid;
  v_passenger_id uuid;
  v_quoted bigint;
  v_offer_amount bigint;
  v_offer_expiry timestamptz;
  v_ride_status public.ride_status;
  v_min bigint;
  v_max bigint;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_counter_amount_minor is null or p_counter_amount_minor < 0 or p_counter_amount_minor > 100000000 then
    raise exception 'invalid_counter_amount' using errcode = '22023';
  end if;

  -- Resolve parent IDs first, then acquire locks in ride -> driver -> offer order.
  select o.ride_id, o.driver_id into v_ride_id, v_driver_id
  from public.ride_offers o
  where o.id = p_offer_id and o.status = 'sent';
  if v_ride_id is null then
    raise exception 'offer_not_available' using errcode = 'P0002';
  end if;

  select r.passenger_id, r.quoted_amount_minor, r.status
    into v_passenger_id, v_quoted, v_ride_status
  from public.rides r where r.id = v_ride_id for update;
  if not found or v_ride_status not in ('requested','offered') then
    raise exception 'ride_no_longer_available' using errcode = 'P0001';
  end if;

  perform 1 from public.driver_profiles d
  where d.id = v_driver_id and d.user_id = v_user
    and d.onboarding_status = 'approved' and d.availability_status = 'online'
    and exists (select 1 from public.profiles p where p.id = d.user_id and p.account_status = 'active')
    and exists (
      select 1 from public.vehicles v
      where v.driver_id = d.id and v.eligibility_status = 'approved'
    )
  for update;
  if not found then
    raise exception 'approved_online_driver_required' using errcode = '42501';
  end if;

  select o.proposed_amount_minor, o.expires_at into v_offer_amount, v_offer_expiry
  from public.ride_offers o
  where o.id = p_offer_id and o.ride_id = v_ride_id
    and o.driver_id = v_driver_id and o.status = 'sent'
  for update;
  if not found or v_offer_expiry <= now() then
    raise exception 'offer_expired_or_unavailable' using errcode = 'P0001';
  end if;

  v_min := greatest(0, floor(v_quoted * 0.70)::bigint);
  v_max := least(100000000, ceil(v_quoted * 1.30)::bigint);
  if p_counter_amount_minor < v_min or p_counter_amount_minor > v_max then
    raise exception 'counter_outside_allowed_range' using errcode = '22023';
  end if;

  insert into public.fare_negotiations(
    ride_id, offer_id, driver_id, passenger_id,
    quoted_amount_minor, current_amount_minor,
    minimum_amount_minor, maximum_amount_minor,
    round_number, max_rounds, last_actor, expires_at
  ) values (
    v_ride_id, p_offer_id, v_driver_id, v_passenger_id,
    v_quoted, p_counter_amount_minor, v_min, v_max,
    1, 5, 'driver', least(v_offer_expiry, now() + interval '3 minutes')
  ) returning id into v_id;

  insert into public.ride_events(ride_id, actor_user_id, event_type, metadata)
  values (v_ride_id, v_user, 'fare_negotiation_started',
    jsonb_build_object('negotiation_id', v_id, 'counter_amount_minor', p_counter_amount_minor));

  return v_id;
end;
$$;

create or replace function public.respond_fare_negotiation(
  p_negotiation_id uuid,
  p_action text,
  p_counter_amount_minor bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ride_id uuid;
  v_driver_id uuid;
  v_passenger_id uuid;
  v_offer_id uuid;
  v_status text;
  v_last_actor text;
  v_round integer;
  v_max_rounds integer;
  v_expiry timestamptz;
  v_min bigint;
  v_max bigint;
  v_amount bigint;
  v_ride_status public.ride_status;
  v_driver_user uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_action is null or p_action not in ('counter','accept','reject') then
    raise exception 'invalid_negotiation_action' using errcode = '22023';
  end if;
  if p_action = 'counter' and (
    p_counter_amount_minor is null or p_counter_amount_minor < 0 or p_counter_amount_minor > 100000000
  ) then
    raise exception 'invalid_counter_amount' using errcode = '22023';
  end if;

  select n.ride_id, n.driver_id, n.passenger_id, n.offer_id
    into v_ride_id, v_driver_id, v_passenger_id, v_offer_id
  from public.fare_negotiations n where n.id = p_negotiation_id;
  if v_ride_id is null then
    raise exception 'negotiation_not_found' using errcode = 'P0002';
  end if;

  -- Global lock order: ride -> driver -> offer -> negotiation.
  select r.status into v_ride_status
  from public.rides r where r.id = v_ride_id for update;
  if not found or v_ride_status not in ('requested','offered') then
    raise exception 'ride_no_longer_available' using errcode = 'P0001';
  end if;

  select d.user_id into v_driver_user
  from public.driver_profiles d where d.id = v_driver_id for update;
  if not found then
    raise exception 'driver_not_found' using errcode = 'P0002';
  end if;

  perform 1 from public.ride_offers o
  where o.id = v_offer_id and o.ride_id = v_ride_id
  for update;
  if not found then
    raise exception 'offer_not_found' using errcode = 'P0002';
  end if;

  select n.status, n.last_actor, n.round_number, n.max_rounds,
         n.expires_at, n.minimum_amount_minor, n.maximum_amount_minor,
         n.current_amount_minor
    into v_status, v_last_actor, v_round, v_max_rounds,
         v_expiry, v_min, v_max, v_amount
  from public.fare_negotiations n
  where n.id = p_negotiation_id and n.ride_id = v_ride_id
  for update;

  if v_status <> 'open' then
    raise exception 'negotiation_not_open' using errcode = 'P0001';
  end if;
  if v_expiry <= now() then
    update public.fare_negotiations set status = 'expired', updated_at = now()
    where id = p_negotiation_id;
    update public.ride_offers set status = 'expired', responded_at = now()
    where id = v_offer_id and status = 'sent' and expires_at <= now();
    return 'expired';
  end if;

  if v_user = v_passenger_id then
    if v_last_actor <> 'driver' then
      raise exception 'participants_must_alternate' using errcode = 'P0001';
    end if;
  elsif v_user = v_driver_user then
    if v_last_actor <> 'passenger' then
      raise exception 'participants_must_alternate' using errcode = 'P0001';
    end if;
  else
    raise exception 'negotiation_access_denied' using errcode = '42501';
  end if;

  if v_user = v_passenger_id and not exists (
    select 1 from public.profiles p where p.id = v_user and p.account_status = 'active'
  ) then
    raise exception 'active_passenger_account_required' using errcode = '42501';
  end if;
  if v_user = v_driver_user and (
    not exists (select 1 from public.profiles p where p.id = v_user and p.account_status = 'active')
    or not exists (
      select 1 from public.driver_profiles d where d.id = v_driver_id
        and d.onboarding_status = 'approved' and d.availability_status = 'online'
    )
    or not exists (select 1 from public.vehicles v where v.driver_id = v_driver_id and v.eligibility_status = 'approved')
  ) then
    raise exception 'approved_online_driver_required' using errcode = '42501';
  end if;

  if p_action = 'counter' then
    if v_round >= v_max_rounds then
      raise exception 'maximum_negotiation_rounds_reached' using errcode = 'P0001';
    end if;
    if p_counter_amount_minor < v_min or p_counter_amount_minor > v_max then
      raise exception 'counter_outside_allowed_range' using errcode = '22023';
    end if;
    update public.fare_negotiations
      set current_amount_minor = p_counter_amount_minor,
          round_number = round_number + 1,
          last_actor = case when v_user = v_passenger_id then 'passenger' else 'driver' end,
          updated_at = now()
    where id = p_negotiation_id;
    insert into public.ride_events(ride_id, actor_user_id, event_type, metadata)
    values (v_ride_id, v_user, 'fare_counter_submitted',
      jsonb_build_object('negotiation_id', p_negotiation_id, 'counter_amount_minor', p_counter_amount_minor));
    return 'open';
  elsif p_action = 'reject' then
    update public.fare_negotiations set status = 'rejected', updated_at = now()
    where id = p_negotiation_id;
    update public.ride_offers set status = 'declined', responded_at = now()
    where id = v_offer_id and status = 'sent';
    insert into public.ride_events(ride_id, actor_user_id, event_type, metadata)
    values (v_ride_id, v_user, 'fare_negotiation_rejected',
      jsonb_build_object('negotiation_id', p_negotiation_id));
    return 'rejected';
  end if;

  -- Acceptance commits the agreed amount and wins the ride atomically.
  if v_user = v_passenger_id then
    if not exists (
      select 1 from public.profiles p where p.id = v_driver_user and p.account_status = 'active'
    ) then
      raise exception 'driver_account_not_active' using errcode = '42501';
    end if;
  end if;
  if not exists (
    select 1 from public.driver_profiles d
    where d.id = v_driver_id and d.onboarding_status = 'approved'
      and d.availability_status = 'online'
  ) or not exists (
    select 1 from public.vehicles v
    where v.driver_id = v_driver_id and v.eligibility_status = 'approved'
  ) then
    raise exception 'approved_online_driver_required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.ride_offers o
    where o.id = v_offer_id and o.status = 'sent' and o.expires_at > now()
  ) then
    raise exception 'offer_expired_or_unavailable' using errcode = 'P0001';
  end if;

  update public.fare_negotiations
    set status = 'accepted', updated_at = now()
  where id = p_negotiation_id;
  update public.ride_offers
    set status = 'accepted', proposed_amount_minor = v_amount, responded_at = now()
  where id = v_offer_id and status = 'sent';
  if not found then
    raise exception 'offer_already_answered' using errcode = 'P0001';
  end if;
  update public.ride_offers
    set status = 'withdrawn', responded_at = now()
  where ride_id = v_ride_id and id <> v_offer_id and status = 'sent';
  update public.rides
    set driver_id = v_driver_id, status = 'accepted',
        quoted_amount_minor = v_amount, accepted_at = now()
  where id = v_ride_id and status in ('requested','offered');
  if not found then
    raise exception 'ride_already_assigned' using errcode = 'P0001';
  end if;
  update public.driver_profiles
    set availability_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.ride_events(ride_id, actor_user_id, event_type, from_status, to_status, metadata)
  values (v_ride_id, v_user, 'fare_negotiation_accepted', v_ride_status, 'accepted',
    jsonb_build_object('negotiation_id', p_negotiation_id, 'agreed_amount_minor', v_amount));

  return 'accepted';
end;
$$;

create or replace function public.get_my_fare_negotiations()
returns table (
  negotiation_id uuid,
  ride_id uuid,
  offer_id uuid,
  driver_id uuid,
  passenger_id uuid,
  status text,
  quoted_amount_minor bigint,
  current_amount_minor bigint,
  minimum_amount_minor bigint,
  maximum_amount_minor bigint,
  round_number integer,
  max_rounds integer,
  last_actor text,
  expires_at timestamptz,
  pickup_label text,
  destination_label text,
  currency_code char(3)
)
language sql
stable
security definer
set search_path = ''
as $$
  select n.id, n.ride_id, n.offer_id, n.driver_id, n.passenger_id,
         case when n.status = 'open' and n.expires_at <= now() then 'expired' else n.status end,
         n.quoted_amount_minor, n.current_amount_minor,
         n.minimum_amount_minor, n.maximum_amount_minor,
         n.round_number, n.max_rounds, n.last_actor, n.expires_at,
         r.pickup_label, r.destination_label, r.currency_code
  from public.fare_negotiations n
  join public.rides r on r.id = n.ride_id
  where auth.uid() is not null
    and (n.passenger_id = auth.uid() or exists (
      select 1 from public.driver_profiles d
      where d.id = n.driver_id and d.user_id = auth.uid()
    ))
  order by n.updated_at desc
  limit 50;
$$;

revoke all on function public.start_fare_negotiation(uuid,bigint) from public, anon;
revoke all on function public.respond_fare_negotiation(uuid,text,bigint) from public, anon;
revoke all on function public.get_my_fare_negotiations() from public, anon;
grant execute on function public.start_fare_negotiation(uuid,bigint) to authenticated;
grant execute on function public.respond_fare_negotiation(uuid,text,bigint) to authenticated;
grant execute on function public.get_my_fare_negotiations() to authenticated;

comment on table public.fare_negotiations is
'Participant-visible negotiation records. All mutations must use authenticated transactional RPCs.';


-- Publish only negotiation row changes; RLS remains the participant visibility boundary.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'fare_negotiations'
     ) then
    alter publication supabase_realtime add table public.fare_negotiations;
  end if;
end;
$$;


-- If a different driver wins the ride, close every remaining negotiation thread.
create or replace function public.close_ride_negotiations_after_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'accepted' and old.status is distinct from new.status then
    update public.fare_negotiations
      set status = 'rejected', updated_at = now()
    where ride_id = new.id and status = 'open';
  end if;
  return new;
end;
$$;

drop trigger if exists rides_close_fare_negotiations on public.rides;
create trigger rides_close_fare_negotiations
after update of status on public.rides
for each row execute function public.close_ride_negotiations_after_assignment();
