-- MITHAQ account bootstrap and driver application v1
-- Supabase Auth user creation provisions a minimal profile. No role is accepted from client metadata.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles(id, display_name, phone_e164)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), ''),
    nullif(trim(new.raw_user_meta_data ->> 'phone_e164'), '')
  )
  on conflict (id) do nothing;

  insert into public.user_roles(user_id, role)
  values(new.id, 'passenger')
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_mithaq on auth.users;
create trigger on_auth_user_created_mithaq
after insert on auth.users
for each row execute procedure public.handle_new_auth_user();

create or replace function public.apply_as_driver()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_driver uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if not exists(select 1 from public.profiles p where p.id = v_user and p.account_status = 'active') then
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

revoke all on function public.apply_as_driver() from public, anon;
grant execute on function public.apply_as_driver() to authenticated;

-- Auth trigger is owned by the database and is not callable by clients.
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
