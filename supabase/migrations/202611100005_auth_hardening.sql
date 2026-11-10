-- MITHAQ auth bootstrap hardening
-- User-editable raw_user_meta_data is not a source of verified phone identity.
-- A phone number is copied only by a future explicit verified-phone workflow.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), '')
  )
  on conflict (id) do nothing;

  insert into public.user_roles(user_id, role)
  values(new.id, 'passenger')
  on conflict do nothing;

  return new;
end;
$$;

create or replace function public.apply_as_driver()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_driver uuid;
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

  insert into public.driver_profiles(user_id, onboarding_status, availability_status)
  values(v_user, 'pending', 'offline')
  on conflict(user_id) do update set updated_at = now()
  returning id into v_driver;

  insert into public.user_roles(user_id, role)
  values(v_user, 'driver')
  on conflict do nothing;

  return v_driver;
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.apply_as_driver() from public, anon;
grant execute on function public.apply_as_driver() to authenticated;
