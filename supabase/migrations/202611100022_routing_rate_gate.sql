-- Project-wide one-request-per-second gate for the public OSRM demo endpoint.
-- This is a safety limit for the tiny non-commercial closed test only.
create table public.routing_request_gate (
  gate_id boolean primary key default true check (gate_id),
  last_request_at timestamptz
);

insert into public.routing_request_gate(gate_id, last_request_at)
values(true, null)
on conflict(gate_id) do nothing;

alter table public.routing_request_gate enable row level security;
revoke all on table public.routing_request_gate from public, anon, authenticated;
grant all on table public.routing_request_gate to service_role;

create or replace function public.claim_routing_request_slot()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last_request timestamptz;
  v_now timestamptz := clock_timestamp();
begin
  select last_request_at into v_last_request
  from public.routing_request_gate
  where gate_id = true
  for update;

  if not found then
    raise exception 'routing_gate_not_initialized' using errcode = 'P0001';
  end if;

  if v_last_request is not null and v_last_request > v_now - interval '1 second' then
    return false;
  end if;

  update public.routing_request_gate
    set last_request_at = v_now
  where gate_id = true;
  return true;
end;
$$;

revoke all on function public.claim_routing_request_slot() from public, anon, authenticated;
grant execute on function public.claim_routing_request_slot() to service_role;
