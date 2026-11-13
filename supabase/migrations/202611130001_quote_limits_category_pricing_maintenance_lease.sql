-- Patch 1: atomic quote-attempt limiting (failed attempts included),
-- maintenance run lease, fare-category multipliers, and EXECUTE lockdown for
-- functions that are only called by Edge Functions with the service role.
-- Additive only: no existing table, column or function is dropped or replaced.

-- ---------------------------------------------------------------------------
-- 1. Per-user quote attempt limiter
-- ---------------------------------------------------------------------------
create table if not exists public.quote_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists quote_attempts_user_created_idx
  on public.quote_attempts (user_id, created_at desc);

alter table public.quote_attempts enable row level security;
revoke all on table public.quote_attempts from public, anon, authenticated;

create or replace function public.consume_quote_attempt(
  p_user_id uuid,
  p_limit integer default 10,
  p_window_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_user_id is null or p_limit is null or p_limit < 1
     or p_window_seconds is null or p_window_seconds < 1 then
    raise exception 'invalid_rate_limit_arguments';
  end if;

  -- Serialize concurrent attempts of the same user so the count-then-insert
  -- below cannot be raced past the limit.
  perform pg_advisory_xact_lock(
    hashtextextended('mithaq:quote_attempt:' || p_user_id::text, 0)
  );

  select count(*) into v_count
  from public.quote_attempts
  where user_id = p_user_id
    and created_at >= now() - make_interval(secs => p_window_seconds);

  if v_count >= p_limit then
    return false;
  end if;

  insert into public.quote_attempts (user_id) values (p_user_id);
  return true;
end;
$$;

create or replace function public.purge_quote_attempts(
  p_older_than_seconds integer default 3600
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  if p_older_than_seconds is null or p_older_than_seconds < 60 then
    raise exception 'invalid_purge_window';
  end if;
  delete from public.quote_attempts
  where created_at < now() - make_interval(secs => p_older_than_seconds);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.consume_quote_attempt(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_quote_attempt(uuid, integer, integer)
  to service_role;
revoke all on function public.purge_quote_attempts(integer)
  from public, anon, authenticated;
grant execute on function public.purge_quote_attempts(integer) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Maintenance lease (prevents overlapping dispatch-maintenance runs)
-- ---------------------------------------------------------------------------
create table if not exists public.maintenance_leases (
  name text primary key check (length(name) between 1 and 100),
  holder uuid not null,
  locked_until timestamptz not null
);

alter table public.maintenance_leases enable row level security;
revoke all on table public.maintenance_leases from public, anon, authenticated;

create or replace function public.acquire_maintenance_lease(
  p_name text,
  p_holder uuid,
  p_ttl_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_acquired boolean;
begin
  if p_name is null or length(p_name) = 0 or p_holder is null
     or p_ttl_seconds is null or p_ttl_seconds < 1 or p_ttl_seconds > 3600 then
    raise exception 'invalid_lease_arguments';
  end if;

  insert into public.maintenance_leases as l (name, holder, locked_until)
  values (p_name, p_holder, now() + make_interval(secs => p_ttl_seconds))
  on conflict (name) do update
    set holder = excluded.holder,
        locked_until = excluded.locked_until
    where l.locked_until < now()
  returning true into v_acquired;

  return coalesce(v_acquired, false);
end;
$$;

create or replace function public.release_maintenance_lease(
  p_name text,
  p_holder uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from public.maintenance_leases
  where name = p_name and holder = p_holder;
  get diagnostics v_deleted = row_count;
  return v_deleted > 0;
end;
$$;

revoke all on function public.acquire_maintenance_lease(text, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.acquire_maintenance_lease(text, uuid, integer)
  to service_role;
revoke all on function public.release_maintenance_lease(text, uuid)
  from public, anon, authenticated;
grant execute on function public.release_maintenance_lease(text, uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Fare category multipliers (basis points of the economy fare)
-- ---------------------------------------------------------------------------
-- PLACEHOLDER VALUES: economy 100%, comfort 125%, family 140%.
-- These are a product decision; change them with an UPDATE before any test
-- that depends on real prices. The edge function refuses to quote a category
-- that has no row here.
create table if not exists public.fare_category_multipliers (
  category text primary key check (category in ('economy', 'comfort', 'family')),
  multiplier_bp integer not null check (multiplier_bp between 10000 and 30000),
  updated_at timestamptz not null default now()
);

alter table public.fare_category_multipliers enable row level security;
revoke all on table public.fare_category_multipliers from public, anon, authenticated;
grant select on table public.fare_category_multipliers to service_role;

insert into public.fare_category_multipliers (category, multiplier_bp) values
  ('economy', 10000),
  ('comfort', 12500),
  ('family', 14000)
on conflict (category) do nothing;

alter table public.fare_quotes
  add column if not exists category_multiplier_bp integer
  check (category_multiplier_bp is null or category_multiplier_bp between 10000 and 30000);

-- ---------------------------------------------------------------------------
-- 4. Edge-only functions: remove client EXECUTE
-- ---------------------------------------------------------------------------
-- create-fare-quote is the only caller of these (service role). Looked up by
-- name so the migration is a no-op for any that do not exist.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'claim_routing_request_slot',
        'resolve_fare_policy_for_route',
        'validate_route_geometry_in_area'
      )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
  end loop;
end;
$$;