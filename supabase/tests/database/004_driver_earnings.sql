-- Driver earnings read-model authorization and amount integrity.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(4);

-- Reuse the completed fixture ride from the negotiation integration test.
-- A fresh transaction creates its own minimal driver and completed trip.
insert into auth.users (id, aud, role, email, created_at, updated_at)
values
 ('11000000-0000-4000-8000-000000000001','authenticated','authenticated','mithaq-earnings-driver@example.invalid',now(),now()),
 ('11000000-0000-4000-8000-000000000002','authenticated','authenticated','mithaq-earnings-other@example.invalid',now(),now())
on conflict (id) do nothing;
update public.profiles set account_status='active'
where id in ('11000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002');
insert into public.driver_profiles (id,user_id,onboarding_status,availability_status)
values ('21000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','approved','offline')
on conflict (id) do nothing;
insert into public.platform_commission_policies(version, commission_bps, is_active, is_provisional)
values (1, 1000, true, true);

insert into public.rides (id,passenger_id,driver_id,pickup_label,destination_label,status,quoted_amount_minor,final_amount_minor,currency_code,completed_at)
values ('31000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000001','A','B','completed',18750,18750,'DZD',now())
on conflict (id) do nothing;

insert into public.ride_financials(
 ride_id, passenger_id, driver_id, currency_code, gross_fare_minor,
 commission_policy_version, commission_bps, commission_minor, driver_net_minor
) values (
 '31000000-0000-4000-8000-000000000001',
 '11000000-0000-4000-8000-000000000002',
 '21000000-0000-4000-8000-000000000001',
 'DZD', 18750, 1, 1000, 1875, 16875
);

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
select extensions.is(
 (select count(*)::bigint from public.get_my_driver_earnings(20)),
 1::bigint,
 'driver sees only own completed trips'
);
select extensions.is(
 (select gross_fare_minor from public.get_my_driver_earnings(20) limit 1),
 18750::bigint,
 'earnings history returns the finalized gross fare'
);
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
select extensions.is(
 (select count(*)::bigint from public.get_my_driver_earnings(20)),
 0::bigint,
 'another account cannot read a drivers earnings'
);
select extensions.throws_ok(
 $$select * from public.get_my_driver_earnings(0)$$,
 '22023',
 'invalid_limit',
 'invalid history limits are rejected'
);
select * from extensions.finish();
rollback;
