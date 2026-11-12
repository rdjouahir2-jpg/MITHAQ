-- Snapshot the agreed quote as the final fare when a trip is completed.
-- This covers both normal offer acceptance and negotiated fare acceptance.
create or replace function public.snapshot_final_fare_on_completion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status is distinct from new.status then
    new.final_amount_minor := new.quoted_amount_minor;
  end if;
  return new;
end;
$$;

drop trigger if exists rides_snapshot_final_fare on public.rides;
create trigger rides_snapshot_final_fare
before update of status on public.rides
for each row
execute function public.snapshot_final_fare_on_completion();

revoke all on function public.snapshot_final_fare_on_completion() from public, anon, authenticated;

comment on function public.snapshot_final_fare_on_completion() is
'Copies the agreed ride quote into final_amount_minor exactly when the ride is completed.';
