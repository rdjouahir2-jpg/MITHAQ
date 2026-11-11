-- Participant-authorized cancellation with an auditable reason.
-- Cancellation is allowed only before boarding; no automatic fees are charged.
create or replace function public.cancel_ride(p_ride_id uuid, p_reason text)
returns public.ride_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_passenger uuid;
  v_driver_id uuid;
  v_driver_user uuid;
  v_old_status public.ride_status;
  v_actor text;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_reason is null or p_reason not in (
    'passenger_changed_plans', 'driver_unavailable',
    'pickup_issue', 'safety_concern', 'other'
  ) then
    raise exception 'invalid_cancellation_reason' using errcode = '22023';
  end if;

  -- Lock ride first, preserving the shared ride-command lock order.
  select r.passenger_id, r.driver_id, r.status
    into v_passenger, v_driver_id, v_old_status
  from public.rides r where r.id = p_ride_id for update;
  if not found then
    raise exception 'ride_not_found' using errcode = 'P0002';
  end if;

  if v_user = v_passenger then
    v_actor := 'passenger';
  elsif v_driver_id is not null then
    select d.user_id into v_driver_user
    from public.driver_profiles d where d.id = v_driver_id;
    if v_driver_user = v_user then v_actor := 'driver'; end if;
  end if;
  if v_actor is null then
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;
  if v_old_status not in ('requested','offered','accepted','driver_arriving','arrived','no_driver_found') then
    raise exception 'ride_cannot_be_cancelled_at_this_stage' using errcode = '22023';
  end if;
  if v_actor = 'driver' and v_old_status not in ('accepted','driver_arriving','arrived') then
    raise exception 'driver_cannot_cancel_unassigned_ride' using errcode = '42501';
  end if;
  if v_actor = 'driver' and p_reason <> 'driver_unavailable' then
    raise exception 'invalid_driver_cancellation_reason' using errcode = '22023';
  end if;

  update public.rides
    set status = 'cancelled', cancelled_at = now(),
        cancellation_reason = v_actor || ':' || p_reason
  where id = p_ride_id;

  update public.ride_offers
    set status = 'withdrawn', responded_at = now()
  where ride_id = p_ride_id and status = 'sent';

  update public.fare_negotiations
    set status = 'rejected', updated_at = now()
  where ride_id = p_ride_id and status = 'open';

  if v_actor = 'driver' then
    update public.driver_profiles
      set availability_status = 'offline', updated_at = now()
    where id = v_driver_id;
  end if;

  insert into public.ride_events(
    ride_id, actor_user_id, event_type, from_status, to_status, reason_code, metadata
  ) values (
    p_ride_id, v_user, 'ride_cancelled', v_old_status, 'cancelled', p_reason,
    jsonb_build_object('cancelled_by', v_actor)
  );
  return 'cancelled'::public.ride_status;
end;
$$;

revoke all on function public.cancel_ride(uuid,text) from public, anon;
grant execute on function public.cancel_ride(uuid,text) to authenticated;
comment on function public.cancel_ride(uuid,text) is
'Cancels a pre-boarding ride for its passenger or assigned driver, records actor and reason, withdraws outstanding offers, closes open negotiations, and takes a cancelling driver offline. No cancellation fee is charged.';
