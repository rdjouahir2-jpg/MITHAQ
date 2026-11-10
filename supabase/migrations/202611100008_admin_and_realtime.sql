-- MITHAQ operational workflow and realtime v8.
-- Admin operations are explicit, role-checked, and audited. No client writes
-- directly to approval, role, fare-policy, or audit tables.

create or replace function public.submit_driver_vehicle(
  p_make text,
  p_model text,
  p_model_year integer,
  p_color text,
  p_seat_capacity integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_driver_id uuid;
  v_vehicle_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if length(trim(coalesce(p_make,''))) not between 2 and 60
     or length(trim(coalesce(p_model,''))) not between 1 and 60
     or (p_model_year is not null and p_model_year not between 1980 and extract(year from now())::integer + 1)
     or (p_color is not null and length(trim(p_color)) > 40)
     or p_seat_capacity not between 2 and 9 then
    raise exception 'invalid_vehicle_details' using errcode = '22023';
  end if;

  select d.id into v_driver_id
  from public.driver_profiles d
  where d.user_id = v_user and d.onboarding_status in ('pending','under_review','rejected')
  for update;

  if v_driver_id is null then
    raise exception 'driver_application_required' using errcode = '42501';
  end if;

  insert into public.vehicles(driver_id, make, model, model_year, color, seat_capacity)
  values(v_driver_id, trim(p_make), trim(p_model), p_model_year, nullif(trim(p_color),''), p_seat_capacity)
  returning id into v_vehicle_id;

  update public.driver_profiles
    set onboarding_status = 'under_review', availability_status = 'offline', updated_at = now()
  where id = v_driver_id;

  return v_vehicle_id;
end;
$$;

create or replace function public.get_my_driver_offers()
returns table (
  offer_id uuid,
  ride_id uuid,
  pickup_label text,
  destination_label text,
  pickup_latitude double precision,
  pickup_longitude double precision,
  category text,
  proposed_amount_minor bigint,
  currency_code char(3),
  expires_at timestamptz
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
  where d.user_id = auth.uid()
    and o.status = 'sent'
    and o.expires_at > now()
    and d.onboarding_status = 'approved'
    and d.availability_status = 'online';
$$;

create or replace function public.decline_ride_offer(p_offer_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
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
    and o.expires_at > now();

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

create or replace function public.admin_set_account_status(
  p_user_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_actor and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_status not in ('active','restricted','closed')
     or length(trim(coalesce(p_reason,''))) not between 5 and 500 then
    raise exception 'invalid_account_review' using errcode = '22023';
  end if;
  if p_user_id = v_actor and p_status <> 'active' then
    raise exception 'cannot_restrict_own_admin_account' using errcode = '42501';
  end if;

  update public.profiles
    set account_status = p_status, updated_at = now()
  where id = p_user_id;
  if not found then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;

  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason)
  values(v_actor, 'account_status_changed', 'profile', p_user_id::text, trim(p_reason));
end;
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
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_actor and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_decision not in ('approved','rejected','suspended')
     or length(trim(coalesce(p_reason,''))) not between 5 and 500 then
    raise exception 'invalid_driver_review' using errcode = '22023';
  end if;

  select onboarding_status into v_old_status
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

  update public.driver_profiles
    set onboarding_status = p_decision,
        availability_status = case when p_decision = 'approved' then 'offline' else 'offline' end,
        updated_at = now()
  where id = p_driver_id;

  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'driver_reviewed', 'driver_profile', p_driver_id::text, trim(p_reason),
    jsonb_build_object('from', v_old_status, 'to', p_decision));
end;
$$;

create or replace function public.admin_review_vehicle(
  p_vehicle_id uuid,
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
  v_driver_id uuid;
  v_old_status text;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = v_actor and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_decision not in ('approved','rejected','suspended')
     or length(trim(coalesce(p_reason,''))) not between 5 and 500 then
    raise exception 'invalid_vehicle_review' using errcode = '22023';
  end if;

  select driver_id, eligibility_status into v_driver_id, v_old_status
  from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'vehicle_not_found' using errcode = 'P0002';
  end if;

  update public.vehicles set eligibility_status = p_decision where id = p_vehicle_id;
  if p_decision <> 'approved' then
    update public.driver_profiles
      set availability_status = 'offline', updated_at = now()
    where id = v_driver_id;
  end if;

  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'vehicle_reviewed', 'vehicle', p_vehicle_id::text, trim(p_reason),
    jsonb_build_object('from', v_old_status, 'to', p_decision));
end;
$$;

create or replace function public.admin_list_driver_applications()
returns table (
  driver_id uuid,
  user_id uuid,
  display_name text,
  account_status text,
  onboarding_status text,
  vehicle_id uuid,
  vehicle_make text,
  vehicle_model text,
  vehicle_year integer,
  vehicle_color text,
  seat_capacity integer,
  vehicle_status text,
  submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select d.id, d.user_id, p.display_name, p.account_status, d.onboarding_status,
    v.id, v.make, v.model, v.model_year, v.color, v.seat_capacity, v.eligibility_status,
    d.created_at
  from public.driver_profiles d
  join public.profiles p on p.id = d.user_id
  left join lateral (
    select vv.* from public.vehicles vv
    where vv.driver_id = d.id
    order by vv.created_at desc limit 1
  ) v on true
  order by d.created_at asc;
end;
$$;

create or replace function public.admin_list_pending_accounts()
returns table (user_id uuid, display_name text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role = 'admin'
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select p.id, p.display_name, p.created_at
  from public.profiles p
  where p.account_status = 'pending'
  order by p.created_at asc;
end;
$$;

revoke all on function public.submit_driver_vehicle(text,text,integer,text,integer) from public, anon;
revoke all on function public.get_my_driver_offers() from public, anon;
revoke all on function public.decline_ride_offer(uuid) from public, anon;
revoke all on function public.admin_set_account_status(uuid,text,text) from public, anon, authenticated;
revoke all on function public.admin_review_driver(uuid,text,text) from public, anon, authenticated;
revoke all on function public.admin_review_vehicle(uuid,text,text) from public, anon, authenticated;
revoke all on function public.admin_list_driver_applications() from public, anon, authenticated;
revoke all on function public.admin_list_pending_accounts() from public, anon, authenticated;

grant execute on function public.submit_driver_vehicle(text,text,integer,text,integer) to authenticated;
grant execute on function public.get_my_driver_offers() to authenticated;
grant execute on function public.decline_ride_offer(uuid) to authenticated;
grant execute on function public.admin_set_account_status(uuid,text,text) to authenticated;
grant execute on function public.admin_review_driver(uuid,text,text) to authenticated;
grant execute on function public.admin_review_vehicle(uuid,text,text) to authenticated;
grant execute on function public.admin_list_driver_applications() to authenticated;
grant execute on function public.admin_list_pending_accounts() to authenticated;

-- Supabase Realtime: enable row-change streams where the publication exists.
do $$
declare
  v_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array array['rides','ride_offers','driver_profiles','vehicles'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = v_table
      ) then
        execute format('alter publication supabase_realtime add table public.%I', v_table);
      end if;
    end loop;
  end if;
end;
$$;
