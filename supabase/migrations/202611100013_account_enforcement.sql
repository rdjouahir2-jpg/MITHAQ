-- A restricted account must not receive new offers or accept work.
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
  if not exists (
    select 1 from public.profiles p where p.id = v_user and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  select o.ride_id into v_ride_id
  from public.ride_offers o
  where o.id = p_offer_id and o.status = 'sent';
  if v_ride_id is null then
    raise exception 'offer_not_available' using errcode = 'P0002';
  end if;

  select r.status into v_old_status
  from public.rides r where r.id = v_ride_id for update;
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
  where o.id = p_offer_id and o.ride_id = v_ride_id
    and o.driver_id = v_driver_id and o.status = 'sent'
  for update;
  if not found then
    raise exception 'offer_not_available' using errcode = 'P0002';
  end if;
  if v_expires <= now() then
    raise exception 'offer_expired' using errcode = 'P0001';
  end if;

  update public.ride_offers set status = 'accepted', responded_at = now()
  where id = p_offer_id and status = 'sent';
  if not found then
    raise exception 'offer_already_answered' using errcode = 'P0001';
  end if;

  update public.ride_offers set status = 'withdrawn', responded_at = now()
  where ride_id = v_ride_id and id <> p_offer_id and status = 'sent';

  update public.rides set driver_id = v_driver_id, status = 'accepted', accepted_at = now()
  where id = v_ride_id;

  update public.driver_profiles set availability_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.ride_events(ride_id, actor_user_id, event_type, from_status, to_status)
  values(v_ride_id, v_user, 'offer_accepted', v_old_status, 'accepted');

  return v_ride_id;
end;
$$;

revoke all on function public.accept_ride_offer(uuid) from public, anon;
grant execute on function public.accept_ride_offer(uuid) to authenticated;

-- Enforce active account status when reviewing drivers and when returning offers.
create or replace function public.get_my_driver_offers()
returns table (
  offer_id uuid, ride_id uuid, pickup_label text, destination_label text,
  pickup_latitude double precision, pickup_longitude double precision,
  category text, proposed_amount_minor bigint, currency_code char(3), expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select o.id, r.id, r.pickup_label, r.destination_label,
    extensions.st_y(r.pickup_point::extensions.geometry),
    extensions.st_x(r.pickup_point::extensions.geometry),
    r.category, o.proposed_amount_minor, r.currency_code, o.expires_at
  from public.ride_offers o
  join public.rides r on r.id = o.ride_id
  join public.driver_profiles d on d.id = o.driver_id
  join public.profiles p on p.id = d.user_id and p.account_status = 'active'
  where d.user_id = auth.uid()
    and o.status = 'sent' and o.expires_at > now()
    and d.onboarding_status = 'approved' and d.availability_status = 'online';
$$;

create or replace function public.admin_review_driver(
  p_driver_id uuid,
  p_decision text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old_status text;
  v_user_id uuid;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles ur where ur.user_id = v_actor and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_decision not in ('approved','rejected','suspended')
     or length(trim(coalesce(p_reason,''))) not between 5 and 500 then
    raise exception 'invalid_driver_review' using errcode = '22023';
  end if;

  select onboarding_status, user_id into v_old_status, v_user_id
  from public.driver_profiles where id = p_driver_id for update;
  if not found then
    raise exception 'driver_not_found' using errcode = 'P0002';
  end if;
  if p_decision = 'approved' and not exists (
    select 1 from public.vehicles v
    where v.driver_id = p_driver_id and v.eligibility_status = 'approved'
  ) then
    raise exception 'approved_vehicle_required' using errcode = '22023';
  end if;
  if p_decision = 'approved' and not exists (
    select 1 from public.profiles p where p.id = v_user_id and p.account_status = 'active'
  ) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  update public.driver_profiles
    set onboarding_status = p_decision, availability_status = 'offline', updated_at = now()
  where id = p_driver_id;

  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'driver_reviewed', 'driver_profile', p_driver_id::text, trim(p_reason),
    jsonb_build_object('from', v_old_status, 'to', p_decision));
end;
$$;

revoke all on function public.get_my_driver_offers() from public, anon;
grant execute on function public.get_my_driver_offers() to authenticated;
revoke all on function public.admin_review_driver(uuid,text,text) from public, anon, authenticated;
grant execute on function public.admin_review_driver(uuid,text,text) to authenticated;
