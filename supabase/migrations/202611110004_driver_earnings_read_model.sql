-- Driver-facing completed-trip earnings history.
-- Amounts are gross completed fares only; commission and settlement are not yet configured.
create or replace function public.get_my_driver_earnings(p_limit integer default 20)
returns table (
  ride_id uuid,
  pickup_label text,
  destination_label text,
  completed_at timestamptz,
  gross_fare_minor bigint,
  currency_code char(3)
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception 'invalid_limit' using errcode = '22023';
  end if;

  return query
  select r.id, r.pickup_label, r.destination_label, r.completed_at,
    r.final_amount_minor, r.currency_code
  from public.rides r
  join public.driver_profiles d on d.id = r.driver_id
  where d.user_id = auth.uid()
    and r.status = 'completed'
    and r.final_amount_minor is not null
  order by r.completed_at desc nulls last, r.requested_at desc
  limit p_limit;
end;
$$;

revoke all on function public.get_my_driver_earnings(integer) from public, anon;
grant execute on function public.get_my_driver_earnings(integer) to authenticated;

comment on function public.get_my_driver_earnings(integer) is
'Returns only the authenticated driver own completed trips and gross final fares; it does not represent net earnings or settlement.';
