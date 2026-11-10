-- Minimize precise location retention. The table stores one current fix per
-- driver, never a location history; remove it immediately when the driver goes offline.
create or replace function public.clear_driver_location_on_offline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.availability_status = 'offline'
     and old.availability_status is distinct from new.availability_status then
    delete from public.driver_locations where driver_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists driver_location_clear_on_offline on public.driver_profiles;
create trigger driver_location_clear_on_offline
after update of availability_status on public.driver_profiles
for each row
execute function public.clear_driver_location_on_offline();

revoke all on function public.clear_driver_location_on_offline() from public, anon, authenticated;
