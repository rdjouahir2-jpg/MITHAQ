create or replace function public.decline_ride_offer(p_offer_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ride_id uuid;
  v_updated integer;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  update public.ride_offers o
    set status = 'declined', responded_at = now()
  from public.driver_profiles d
  where o.id = p_offer_id
    and o.driver_id = d.id
    and d.user_id = v_user
    and o.status = 'sent'
    and o.expires_at > now()
  returning o.ride_id into v_ride_id;

  get diagnostics v_updated = row_count;
  if v_updated = 1 then
    insert into public.ride_events(ride_id, actor_user_id, event_type, metadata)
    values(v_ride_id, v_user, 'offer_declined', jsonb_build_object('offer_id', p_offer_id));
  end if;
  return v_updated = 1;
end;
$$;

revoke all on function public.decline_ride_offer(uuid) from public, anon;
grant execute on function public.decline_ride_offer(uuid) to authenticated;
