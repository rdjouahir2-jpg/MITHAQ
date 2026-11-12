-- Transactional integration tests for negotiation authorization and final fare capture.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(4);

-- Isolated fixture users. Auth bootstrap creates their profiles and passenger roles.
insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  ('10000000-0000-4000-8000-000000000001','authenticated','authenticated','mithaq-test-passenger-1@example.invalid',now(),now()),
  ('10000000-0000-4000-8000-000000000002','authenticated','authenticated','mithaq-test-driver-1@example.invalid',now(),now()),
  ('10000000-0000-4000-8000-000000000003','authenticated','authenticated','mithaq-test-attacker@example.invalid',now(),now()),
  ('10000000-0000-4000-8000-000000000004','authenticated','authenticated','mithaq-test-passenger-2@example.invalid',now(),now()),
  ('10000000-0000-4000-8000-000000000005','authenticated','authenticated','mithaq-test-driver-2@example.invalid',now(),now())
on conflict (id) do nothing;

update public.profiles
set account_status = 'active'
where id in (
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000005'
);

insert into public.driver_profiles (id, user_id, onboarding_status, availability_status)
values
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','approved','offline'),
  ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000005','approved','busy')
on conflict (id) do nothing;

insert into public.vehicles (id, driver_id, make, model, eligibility_status)
values
  ('60000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Test','Car','approved'),
  ('60000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','Test','Car','approved')
on conflict (id) do nothing;

insert into public.driver_documents(driver_id,user_id,document_type,object_path,status,expires_on)
values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','identity_card','test/driver1/identity','approved',null),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','driving_license','test/driver1/license','approved',null),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','vehicle_registration','test/driver1/registration','approved',null),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','insurance','test/driver1/insurance','approved',current_date+30);

update public.driver_profiles set availability_status='online'
where id='20000000-0000-4000-8000-000000000001';

insert into public.rides (
  id, passenger_id, driver_id, pickup_label, destination_label, status,
  quoted_amount_minor, currency_code
)
values
  ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',null,'Pickup A','Destination A','offered',10000,'DZD'),
  ('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000002','Pickup B','Destination B','in_progress',12345,'DZD')
on conflict (id) do nothing;

insert into public.ride_offers (id, ride_id, driver_id, proposed_amount_minor, status, expires_at)
values ('40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',10000,'sent',now()+interval '10 minutes')
on conflict (id) do nothing;

insert into public.fare_negotiations (
  id, ride_id, offer_id, driver_id, passenger_id, status,
  quoted_amount_minor, current_amount_minor, minimum_amount_minor, maximum_amount_minor,
  round_number, max_rounds, last_actor, expires_at
)
values (
  '50000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'open',10000,10500,7000,13000,1,5,'driver',now()-interval '1 minute'
)
on conflict (id) do nothing;

-- A signed-in non-participant must be rejected before the expired state is changed.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
select extensions.throws_ok(
  $$select public.respond_fare_negotiation(
    '50000000-0000-4000-8000-000000000001','accept',null
  )$$,
  '42501',
  'negotiation_access_denied',
  'non-participants cannot mutate an expired negotiation'
);
select extensions.ok(
  (select status = 'open' from public.fare_negotiations
   where id = '50000000-0000-4000-8000-000000000001'),
  'unauthorized expiry attempt leaves negotiation state unchanged'
);

-- The financial snapshot trigger requires an explicitly configured test policy.
insert into public.platform_commission_policies(version, commission_bps, is_active, is_provisional)
values (1, 1000, true, true);

-- Completing a trip snapshots the agreed amount into the final fare field.
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
select public.advance_ride(
  '30000000-0000-4000-8000-000000000002','completed',null
);
select extensions.is(
  (select final_amount_minor from public.rides where id = '30000000-0000-4000-8000-000000000002'),
  12345::bigint,
  'completed ride stores the agreed amount as its final fare'
);
select extensions.is(
  (select status::text from public.rides where id = '30000000-0000-4000-8000-000000000002'),
  'completed',
  'ride completion transition still succeeds'
);

select * from extensions.finish();
rollback;
