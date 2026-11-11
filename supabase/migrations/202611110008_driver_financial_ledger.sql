-- MITHAQ financial ledger: immutable ride snapshots, commission accounting and driver payouts.
-- The seeded 10% rate is provisional for the closed test environment only.
-- It must be approved by the business owner before any production collection.

create table public.platform_commission_policies (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique check (version > 0),
  commission_bps integer not null check (commission_bps between 0 and 3000),
  is_active boolean not null default false,
  is_provisional boolean not null default true,
  effective_at timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create unique index platform_commission_one_active
  on public.platform_commission_policies(is_active) where is_active;

insert into public.platform_commission_policies(version, commission_bps, is_active, is_provisional)
values (1, 1000, true, true);

create table public.ride_financials (
  ride_id uuid primary key references public.rides(id),
  passenger_id uuid not null references public.profiles(id),
  driver_id uuid not null references public.driver_profiles(id),
  currency_code char(3) not null,
  gross_fare_minor bigint not null check (gross_fare_minor >= 0),
  commission_policy_version integer not null references public.platform_commission_policies(version),
  commission_bps integer not null check (commission_bps between 0 and 3000),
  commission_minor bigint not null check (commission_minor >= 0),
  driver_net_minor bigint not null check (driver_net_minor >= 0),
  payment_method text not null default 'cash_to_driver'
    check (payment_method in ('cash_to_driver','cash_to_platform','manual_transfer_to_platform')),
  payment_status text not null default 'pending'
    check (payment_status in ('pending','collected','refunded','disputed')),
  commission_status text not null default 'pending'
    check (commission_status in ('pending','due','settled','waived')),
  created_at timestamptz not null default now(),
  collected_at timestamptz,
  check (commission_minor + driver_net_minor = gross_fare_minor)
);
create index ride_financials_driver_created_idx
  on public.ride_financials(driver_id, created_at desc);

create table public.driver_ledger_entries (
  id bigint generated always as identity primary key,
  driver_id uuid not null references public.driver_profiles(id),
  ride_id uuid references public.rides(id),
  payout_id uuid,
  entry_type text not null check (entry_type in (
    'cash_commission_due','commission_remittance','platform_fare_credit','payout_debit','refund_reversal','admin_adjustment'
  )),
  amount_minor bigint not null check (amount_minor <> 0),
  currency_code char(3) not null default 'DZD',
  description text not null default '',
  created_at timestamptz not null default now(),
  check ((ride_id is not null)::integer + (payout_id is not null)::integer <= 1)
);
create unique index driver_ledger_ride_entry_once
  on public.driver_ledger_entries(ride_id, entry_type) where ride_id is not null;
create unique index driver_ledger_payout_entry_once
  on public.driver_ledger_entries(payout_id, entry_type) where payout_id is not null;
create index driver_ledger_driver_created_idx
  on public.driver_ledger_entries(driver_id, created_at desc);

create table public.driver_payout_requests (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles(id),
  amount_minor bigint not null check (amount_minor > 0),
  currency_code char(3) not null default 'DZD',
  status text not null default 'pending'
    check (status in ('pending','approved','paid','rejected')),
  payout_reference text,
  admin_note text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references public.profiles(id)
);
create index driver_payout_requests_queue_idx
  on public.driver_payout_requests(status, requested_at);

alter table public.platform_commission_policies enable row level security;
alter table public.ride_financials enable row level security;
alter table public.driver_ledger_entries enable row level security;
alter table public.driver_payout_requests enable row level security;

revoke all on public.platform_commission_policies, public.ride_financials,
  public.driver_ledger_entries, public.driver_payout_requests from public, anon, authenticated;
grant select on public.ride_financials, public.driver_ledger_entries, public.driver_payout_requests to authenticated;

create policy driver_financials_read_own on public.ride_financials
  for select to authenticated using (
    exists (select 1 from public.driver_profiles d
      where d.id = ride_financials.driver_id and d.user_id = (select auth.uid()))
  );
create policy driver_ledger_read_own on public.driver_ledger_entries
  for select to authenticated using (
    exists (select 1 from public.driver_profiles d
      where d.id = driver_ledger_entries.driver_id and d.user_id = (select auth.uid()))
  );
create policy driver_payout_read_own on public.driver_payout_requests
  for select to authenticated using (
    exists (select 1 from public.driver_profiles d
      where d.id = driver_payout_requests.driver_id and d.user_id = (select auth.uid()))
  );

create or replace function public.prevent_driver_ledger_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'financial_ledger_is_immutable' using errcode = '55000';
end;
$$;
create trigger driver_ledger_no_update
before update or delete on public.driver_ledger_entries
for each row execute function public.prevent_driver_ledger_mutation();
revoke all on function public.prevent_driver_ledger_mutation() from public, anon, authenticated;

create or replace function public.create_ride_financial_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_policy public.platform_commission_policies%rowtype;
  v_gross bigint;
  v_commission bigint;
begin
  if new.status = 'completed' and old.status is distinct from new.status then
    if new.driver_id is null or new.final_amount_minor is null then
      raise exception 'completed_ride_missing_driver_or_final_fare' using errcode = '23514';
    end if;
    select * into v_policy from public.platform_commission_policies
      where is_active order by version desc limit 1;
    if not found then
      raise exception 'active_commission_policy_required' using errcode = '55000';
    end if;
    v_gross := new.final_amount_minor;
    v_commission := round(v_gross::numeric * v_policy.commission_bps / 10000)::bigint;
    insert into public.ride_financials(
      ride_id, passenger_id, driver_id, currency_code, gross_fare_minor,
      commission_policy_version, commission_bps, commission_minor, driver_net_minor
    ) values (
      new.id, new.passenger_id, new.driver_id, new.currency_code, v_gross,
      v_policy.version, v_policy.commission_bps, v_commission, v_gross - v_commission
    ) on conflict (ride_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists rides_create_financial_snapshot on public.rides;
create trigger rides_create_financial_snapshot
after update of status on public.rides
for each row execute function public.create_ride_financial_snapshot();
revoke all on function public.create_ride_financial_snapshot() from public, anon, authenticated;

create or replace function public.record_driver_ledger_on_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver_id uuid;
  v_amount bigint;
  v_currency char(3);
  v_description text;
  v_entry_type text;
begin
  if new.payment_status = 'collected' and old.payment_status is distinct from new.payment_status then
    if new.payment_method = 'cash_to_driver' then
      v_amount := -new.commission_minor;
      v_entry_type := 'cash_commission_due';
      v_description := 'عمولة المنصة المستحقة عن رحلة نقدية';
      update public.ride_financials set commission_status = 'due' where ride_id = new.ride_id;
    else
      v_amount := new.driver_net_minor;
      v_entry_type := 'platform_fare_credit';
      v_description := 'صافي أجرة رحلة محصلة للمنصة ومستحقة للسائق';
    end if;
    if v_amount <> 0 then
      insert into public.driver_ledger_entries(driver_id, ride_id, entry_type, amount_minor, currency_code, description)
      values(new.driver_id, new.ride_id, v_entry_type, v_amount, new.currency_code, v_description)
      on conflict do nothing;
    end if;
    update public.ride_financials set collected_at = now() where ride_id = new.ride_id;
  elsif new.payment_status = 'refunded' and old.payment_status = 'collected' then
    select driver_id, currency_code into v_driver_id, v_currency
      from public.ride_financials where ride_id = new.ride_id;
    select -amount_minor into v_amount
      from public.driver_ledger_entries
      where ride_id = new.ride_id and entry_type in ('cash_commission_due','platform_fare_credit')
      limit 1;
    if v_amount is not null and v_amount <> 0 then
      insert into public.driver_ledger_entries(driver_id, ride_id, entry_type, amount_minor, currency_code, description)
      values(v_driver_id, new.ride_id, 'refund_reversal', v_amount, v_currency, 'عكس قيد مالي بسبب رد المبلغ')
      on conflict do nothing;
    end if;
  end if;
  return new;
end;
$$;
create trigger ride_financials_record_ledger
after update of payment_status on public.ride_financials
for each row execute function public.record_driver_ledger_on_payment();
revoke all on function public.record_driver_ledger_on_payment() from public, anon, authenticated;

create or replace function public.admin_set_platform_commission(p_commission_bps integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_version integer;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles where user_id = v_actor and role = 'admin'
  ) then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_commission_bps is null or p_commission_bps not between 0 and 3000 then
    raise exception 'commission_rate_out_of_range' using errcode = '22023';
  end if;
  perform 1 from public.platform_commission_policies where is_active for update;
  select coalesce(max(version),0)+1 into v_version from public.platform_commission_policies;
  update public.platform_commission_policies set is_active = false where is_active;
  insert into public.platform_commission_policies(version, commission_bps, is_active, is_provisional, created_by)
  values(v_version, p_commission_bps, true, false, v_actor);
  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'platform_commission_changed', 'commission_policy', v_version::text,
    'Admin changed the platform commission rate',
    jsonb_build_object('commission_bps',p_commission_bps,'version',v_version));
  return v_version;
end;
$$;

create or replace function public.admin_record_ride_payment(
  p_ride_id uuid, p_payment_method text, p_reference text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles where user_id = v_actor and role = 'admin'
  ) then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_payment_method not in ('cash_to_driver','cash_to_platform','manual_transfer_to_platform') then
    raise exception 'invalid_payment_method' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reference,''))) < 3 then
    raise exception 'payment_reference_required' using errcode = '22023';
  end if;
  update public.ride_financials
    set payment_method = p_payment_method, payment_status = 'collected',
        commission_status = case when p_payment_method = 'cash_to_driver' then 'due' else 'pending' end
  where ride_id = p_ride_id and payment_status = 'pending';
  if not found then raise exception 'pending_ride_payment_not_found' using errcode = 'P0002'; end if;
  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'ride_payment_recorded', 'ride_financial', p_ride_id::text,
    nullif(trim(coalesce(p_reference,'')), ''),
    jsonb_build_object('payment_method',p_payment_method));
end;
$$;


create or replace function public.admin_record_driver_commission_payment(
  p_ride_id uuid, p_reference text
)
returns void
language plpgsql
security definer
set search_path = ''
as $
declare
  v_actor uuid := auth.uid();
  v_driver uuid;
  v_commission bigint;
  v_currency char(3);
  v_status text;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles where user_id=v_actor and role='admin'
  ) then raise exception 'admin_required' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reference,''))) < 3 then
    raise exception 'payment_reference_required' using errcode = '22023';
  end if;
  select driver_id, commission_minor, currency_code, commission_status
    into v_driver, v_commission, v_currency, v_status
  from public.ride_financials where ride_id=p_ride_id and payment_method='cash_to_driver'
    and payment_status='collected' for update;
  if not found or v_status <> 'due' then
    raise exception 'commission_not_due' using errcode = 'P0002';
  end if;
  if v_commission > 0 then
    insert into public.driver_ledger_entries(driver_id,ride_id,entry_type,amount_minor,currency_code,description)
    values(v_driver,p_ride_id,'commission_remittance',v_commission,v_currency,
      'تسديد عمولة المنصة من السائق');
  end if;
  update public.ride_financials set commission_status='settled' where ride_id=p_ride_id;
  insert into public.audit_logs(actor_user_id,action,target_type,target_id,reason,metadata)
  values(v_actor,'driver_commission_settled','ride_financial',p_ride_id::text,trim(p_reference),
    jsonb_build_object('commission_minor',v_commission));
end;
$;

drop function if exists public.get_my_driver_earnings(integer);
create function public.get_my_driver_earnings(p_limit integer default 20)
returns table (
  ride_id uuid,
  pickup_label text,
  destination_label text,
  completed_at timestamptz,
  gross_fare_minor bigint,
  commission_minor bigint,
  driver_net_minor bigint,
  payment_status text,
  commission_status text,
  currency_code char(3)
)
language plpgsql
stable
security definer
set search_path = ''
as $
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception 'invalid_limit' using errcode = '22023';
  end if;
  return query
  select r.id, r.pickup_label, r.destination_label, r.completed_at,
    f.gross_fare_minor, f.commission_minor, f.driver_net_minor,
    f.payment_status, f.commission_status, f.currency_code
  from public.ride_financials f
  join public.rides r on r.id=f.ride_id
  join public.driver_profiles d on d.id=f.driver_id
  where d.user_id=auth.uid()
  order by r.completed_at desc nulls last, r.requested_at desc
  limit p_limit;
end;
$;

create or replace function public.request_driver_payout(p_amount_minor bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_driver_id uuid;
  v_balance bigint;
  v_pending bigint;
  v_request uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_payout_amount' using errcode = '22023';
  end if;
  select id into v_driver_id from public.driver_profiles
    where user_id = v_user and onboarding_status = 'approved' for update;
  if v_driver_id is null then raise exception 'approved_driver_required' using errcode = '42501'; end if;
  select coalesce(sum(amount_minor),0) into v_balance
    from public.driver_ledger_entries where driver_id = v_driver_id;
  select coalesce(sum(amount_minor),0) into v_pending
    from public.driver_payout_requests where driver_id = v_driver_id and status in ('pending','approved');
  if p_amount_minor > v_balance - v_pending then
    raise exception 'payout_exceeds_available_balance' using errcode = '22023';
  end if;
  insert into public.driver_payout_requests(driver_id, amount_minor)
  values(v_driver_id, p_amount_minor) returning id into v_request;
  return v_request;
end;
$$;

create or replace function public.admin_process_driver_payout(
  p_payout_id uuid, p_decision text, p_reference text default null, p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_driver uuid;
  v_amount bigint;
  v_currency char(3);
  v_status text;
begin
  if v_actor is null or not exists (
    select 1 from public.user_roles where user_id = v_actor and role = 'admin'
  ) then raise exception 'admin_required' using errcode = '42501'; end if;
  if p_decision not in ('approve','pay','reject') then
    raise exception 'invalid_payout_decision' using errcode = '22023';
  end if;
  select driver_id, amount_minor, currency_code, status
    into v_driver, v_amount, v_currency, v_status
  from public.driver_payout_requests where id = p_payout_id for update;
  if not found or v_status not in ('pending','approved') then
    raise exception 'payout_not_pending' using errcode = 'P0002';
  end if;
  if p_decision = 'approve' then
    update public.driver_payout_requests set status='approved', admin_note=nullif(trim(coalesce(p_note,'')),''),
      processed_by=v_actor, processed_at=now() where id=p_payout_id;
  elsif p_decision = 'reject' then
    update public.driver_payout_requests set status='rejected', admin_note=nullif(trim(coalesce(p_note,'')),''),
      processed_by=v_actor, processed_at=now() where id=p_payout_id;
  else
    if v_status <> 'approved' or length(trim(coalesce(p_reference,''))) < 3 then
      raise exception 'payout_approval_and_reference_required' using errcode = '22023';
    end if;
    update public.driver_payout_requests set status='paid', payout_reference=trim(p_reference),
      admin_note=nullif(trim(coalesce(p_note,'')),''),
      processed_by=v_actor, processed_at=now() where id=p_payout_id;
    insert into public.driver_ledger_entries(driver_id,payout_id,entry_type,amount_minor,currency_code,description)
    values(v_driver,p_payout_id,'payout_debit',-v_amount,v_currency,'تسوية مستحقات السائق');
  end if;
  insert into public.audit_logs(actor_user_id, action, target_type, target_id, reason, metadata)
  values(v_actor, 'driver_payout_'||p_decision, 'driver_payout', p_payout_id::text,
    nullif(trim(coalesce(p_note,'')),''),
    jsonb_build_object('amount_minor',v_amount,'reference',p_reference));
end;
$$;

create or replace function public.get_my_driver_financial_summary()
returns table (
  gross_earned_minor bigint,
  commission_due_minor bigint,
  payout_available_minor bigint,
  payout_pending_minor bigint,
  currency_code char(3)
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_driver_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  select id into v_driver_id from public.driver_profiles where user_id = auth.uid();
  if v_driver_id is null then raise exception 'driver_profile_required' using errcode = '42501'; end if;
  return query
  select
    coalesce((select sum(f.gross_fare_minor) from public.ride_financials f where f.driver_id=v_driver_id),0),
    greatest(0, -coalesce((select sum(e.amount_minor) from public.driver_ledger_entries e
      where e.driver_id=v_driver_id and e.entry_type in ('cash_commission_due','commission_remittance')),0)),
    greatest(0, coalesce((select sum(e.amount_minor) from public.driver_ledger_entries e where e.driver_id=v_driver_id),0)
      - coalesce((select sum(p.amount_minor) from public.driver_payout_requests p
        where p.driver_id=v_driver_id and p.status in ('pending','approved')),0)),
    coalesce((select sum(p.amount_minor) from public.driver_payout_requests p
      where p.driver_id=v_driver_id and p.status in ('pending','approved')),0),
    'DZD'::char(3);
end;
$$;

create or replace function public.admin_list_financials()
returns table (
  ride_id uuid, driver_id uuid, driver_name text, gross_fare_minor bigint,
  commission_minor bigint, driver_net_minor bigint, payment_method text,
  payment_status text, commission_status text, currency_code char(3), created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles where user_id=auth.uid() and role='admin'
  ) then raise exception 'admin_required' using errcode = '42501'; end if;
  return query
  select f.ride_id, f.driver_id, p.display_name, f.gross_fare_minor,
    f.commission_minor, f.driver_net_minor, f.payment_method, f.payment_status,
    f.commission_status, f.currency_code, f.created_at
  from public.ride_financials f
  join public.driver_profiles d on d.id=f.driver_id
  join public.profiles p on p.id=d.user_id
  order by f.created_at desc limit 200;
end;
$$;


create or replace function public.admin_list_payout_requests()
returns table (
  payout_id uuid, driver_id uuid, driver_name text, amount_minor bigint,
  currency_code char(3), payout_status text, payout_reference text, requested_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles where user_id=auth.uid() and role='admin'
  ) then raise exception 'admin_required' using errcode = '42501'; end if;
  return query
  select p.id, p.driver_id, pr.display_name, p.amount_minor, p.currency_code,
    p.status, p.payout_reference, p.requested_at
  from public.driver_payout_requests p
  join public.driver_profiles d on d.id=p.driver_id
  join public.profiles pr on pr.id=d.user_id
  order by case p.status when 'pending' then 1 when 'approved' then 2 else 3 end,
    p.requested_at desc limit 200;
end;
$;

create or replace function public.admin_get_commission_policy()
returns table (commission_bps integer, is_provisional boolean, version integer)
language plpgsql
stable
security definer
set search_path = ''
as $
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles where user_id=auth.uid() and role='admin'
  ) then raise exception 'admin_required' using errcode = '42501'; end if;
  return query select p.commission_bps, p.is_provisional, p.version
    from public.platform_commission_policies p where p.is_active limit 1;
end;
$;

revoke all on function public.admin_set_platform_commission(integer) from public, anon;
revoke all on function public.admin_record_ride_payment(uuid,text,text) from public, anon;
revoke all on function public.admin_record_driver_commission_payment(uuid,text) from public, anon;
revoke all on function public.get_my_driver_earnings(integer) from public, anon;
revoke all on function public.request_driver_payout(bigint) from public, anon;
revoke all on function public.admin_process_driver_payout(uuid,text,text,text) from public, anon;
revoke all on function public.get_my_driver_financial_summary() from public, anon;
revoke all on function public.admin_list_financials() from public, anon;
revoke all on function public.admin_list_payout_requests() from public, anon;
revoke all on function public.admin_get_commission_policy() from public, anon;
grant execute on function public.admin_set_platform_commission(integer) to authenticated;
grant execute on function public.admin_record_ride_payment(uuid,text,text) to authenticated;
grant execute on function public.admin_record_driver_commission_payment(uuid,text) to authenticated;
grant execute on function public.get_my_driver_earnings(integer) to authenticated;
grant execute on function public.request_driver_payout(bigint) to authenticated;
grant execute on function public.admin_process_driver_payout(uuid,text,text,text) to authenticated;
grant execute on function public.get_my_driver_financial_summary() to authenticated;
grant execute on function public.admin_list_financials() to authenticated;
grant execute on function public.admin_list_payout_requests() to authenticated;
grant execute on function public.admin_get_commission_policy() to authenticated;

comment on table public.ride_financials is
'Immutable fare and commission snapshot per completed ride; collection and settlement transitions are audited.';
comment on table public.driver_ledger_entries is
'Append-only signed driver balance ledger in minor currency units. Positive is payable to driver; negative is due to platform.';
comment on table public.driver_payout_requests is
'Manual payout requests; paid transitions require an administrator and an external payment reference.';
