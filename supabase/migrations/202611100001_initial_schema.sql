-- MITHAQ initial schema (prototype baseline)
-- Apply only to a new Supabase project after reviewing this migration.
create extension if not exists pgcrypto;
create extension if not exists postgis;

create type public.app_role as enum ('passenger','driver','support','admin');
create type public.ride_status as enum ('requested','offered','accepted','driver_arriving','arrived','boarded','in_progress','completed','cancelled','expired','no_driver_found');
create type public.offer_status as enum ('sent','accepted','declined','expired','withdrawn');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  phone_e164 text unique,
  account_status text not null default 'pending' check (account_status in ('pending','active','restricted','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);
create table public.driver_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  onboarding_status text not null default 'pending' check (onboarding_status in ('pending','under_review','approved','rejected','suspended')),
  availability_status text not null default 'offline' check (availability_status in ('offline','online','busy')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  make text not null,
  model text not null,
  model_year int check (model_year between 1980 and 2100),
  color text,
  seat_capacity int not null default 4 check (seat_capacity between 1 and 20),
  eligibility_status text not null default 'pending' check (eligibility_status in ('pending','approved','rejected','suspended')),
  created_at timestamptz not null default now()
);
create table public.service_areas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  boundary geography(multipolygon,4326),
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.fare_policies (
  id uuid primary key default gen_random_uuid(),
  service_area_id uuid references public.service_areas(id),
  version int not null,
  currency_code char(3) not null default 'DZD',
  base_amount_minor bigint not null check (base_amount_minor >= 0),
  distance_rate_minor bigint not null default 0 check (distance_rate_minor >= 0),
  time_rate_minor bigint not null default 0 check (time_rate_minor >= 0),
  minimum_amount_minor bigint not null default 0 check (minimum_amount_minor >= 0),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  unique(service_area_id, version)
);
create table public.rides (
  id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.profiles(id),
  driver_id uuid references public.driver_profiles(id),
  pickup_label text not null,
  destination_label text not null,
  pickup_point geography(point,4326),
  destination_point geography(point,4326),
  category text not null default 'economy' check (category in ('economy','comfort','family')),
  status public.ride_status not null default 'requested',
  quoted_amount_minor bigint not null check (quoted_amount_minor >= 0),
  final_amount_minor bigint check (final_amount_minor >= 0),
  currency_code char(3) not null default 'DZD',
  trip_pin_hash text,
  requested_at timestamptz not null default now(),
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default now()
);
create table public.ride_offers (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  driver_id uuid not null references public.driver_profiles(id),
  proposed_amount_minor bigint not null check (proposed_amount_minor >= 0),
  status public.offer_status not null default 'sent',
  offered_at timestamptz not null default now(),
  expires_at timestamptz not null,
  responded_at timestamptz,
  unique(ride_id, driver_id)
);
create unique index one_accepted_offer_per_ride on public.ride_offers(ride_id) where status = 'accepted';
create index rides_passenger_status_idx on public.rides(passenger_id,status,requested_at desc);
create index rides_driver_status_idx on public.rides(driver_id,status,requested_at desc);
create index ride_offers_driver_status_idx on public.ride_offers(driver_id,status,expires_at);
create table public.ride_events (
  id bigint generated always as identity primary key,
  ride_id uuid not null references public.rides(id) on delete cascade,
  actor_user_id uuid references public.profiles(id),
  event_type text not null,
  from_status public.ride_status,
  to_status public.ride_status,
  reason_code text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table public.safety_reports (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid references public.rides(id),
  reporter_user_id uuid not null references public.profiles(id),
  category text not null,
  severity text not null default 'normal' check (severity in ('low','normal','high','critical')),
  description text not null default '',
  status text not null default 'open' check (status in ('open','investigating','resolved','closed')),
  created_at timestamptz not null default now()
);
create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  ride_id uuid references public.rides(id),
  category text not null,
  message text not null,
  status text not null default 'open' check (status in ('open','assigned','resolved','closed')),
  created_at timestamptz not null default now()
);
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.profiles(id),
  action text not null,
  target_type text not null,
  target_id text,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.driver_profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.service_areas enable row level security;
alter table public.fare_policies enable row level security;
alter table public.rides enable row level security;
alter table public.ride_offers enable row level security;
alter table public.ride_events enable row level security;
alter table public.safety_reports enable row level security;
alter table public.support_tickets enable row level security;
alter table public.audit_logs enable row level security;

-- Client-side profile/driver writes are intentionally disabled until controlled RPCs exist.
create policy "profile_select_own" on public.profiles for select to authenticated using (id = auth.uid());
create policy "roles_select_own" on public.user_roles for select to authenticated using (user_id = auth.uid());
create policy "driver_profile_select_own" on public.driver_profiles for select to authenticated using (user_id = auth.uid());
create policy "vehicles_select_owner" on public.vehicles for select to authenticated using (
  exists(select 1 from public.driver_profiles d where d.id = driver_id and d.user_id = auth.uid())
);
create policy "rides_select_participant" on public.rides for select to authenticated using (
  passenger_id = auth.uid() or exists(select 1 from public.driver_profiles d where d.id = driver_id and d.user_id = auth.uid())
);
create policy "offers_select_involved" on public.ride_offers for select to authenticated using (
  exists(select 1 from public.rides r where r.id = ride_id and r.passenger_id = auth.uid())
  or exists(select 1 from public.driver_profiles d where d.id = driver_id and d.user_id = auth.uid())
);
create policy "events_select_participant" on public.ride_events for select to authenticated using (
  exists(select 1 from public.rides r where r.id = ride_id and (
    r.passenger_id = auth.uid() or exists(select 1 from public.driver_profiles d where d.id = r.driver_id and d.user_id = auth.uid())
  ))
);
create policy "safety_report_insert_self" on public.safety_reports for insert to authenticated with check (reporter_user_id = auth.uid());
create policy "safety_report_select_self" on public.safety_reports for select to authenticated using (reporter_user_id = auth.uid());
create policy "support_ticket_insert_self" on public.support_tickets for insert to authenticated with check (user_id = auth.uid());
create policy "support_ticket_select_self" on public.support_tickets for select to authenticated using (user_id = auth.uid());

-- No client write policies for rides, offers, fare policies, audit logs, or role grants.
-- Implement audited server-side RPCs/Edge Functions before enabling live traffic.
