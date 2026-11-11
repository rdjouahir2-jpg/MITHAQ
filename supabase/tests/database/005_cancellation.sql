begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(5);
insert into auth.users (id,aud,role,email,created_at,updated_at) values
 ('11000000-0000-4000-8000-000000000001','authenticated','authenticated','cancel-passenger@example.invalid',now(),now()),
 ('11000000-0000-4000-8000-000000000002','authenticated','authenticated','cancel-driver@example.invalid',now(),now()),
 ('11000000-0000-4000-8000-000000000003','authenticated','authenticated','cancel-outsider@example.invalid',now(),now())
on conflict(id) do nothing;
update public.profiles set account_status='active'
where id in ('11000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000003');
insert into public.driver_profiles(id,user_id,onboarding_status,availability_status)
values ('21000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','approved','busy')
on conflict(id) do nothing;
insert into public.rides(id,passenger_id,driver_id,pickup_label,destination_label,status,quoted_amount_minor)
values
 ('31000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001',null,'A','B','offered',10000),
 ('31000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000001','C','D','accepted',12000),
 ('31000000-0000-4000-8000-000000000003','11000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000001','E','F','in_progress',13000)
on conflict(id) do nothing;

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000003',true);
select extensions.throws_ok(
 $$select public.cancel_ride('31000000-0000-4000-8000-000000000001','other')$$,
 '42501','ride_access_denied','unrelated account cannot cancel a ride'
);
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
select public.cancel_ride('31000000-0000-4000-8000-000000000001','passenger_changed_plans');
select extensions.is((select cancellation_reason from public.rides where id='31000000-0000-4000-8000-000000000001'),
 'passenger:passenger_changed_plans','passenger cancellation reason is recorded');
select extensions.is((select status::text from public.rides where id='31000000-0000-4000-8000-000000000001'),
 'cancelled','passenger can cancel before assignment');
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
select public.cancel_ride('31000000-0000-4000-8000-000000000002','driver_unavailable');
select extensions.is((select availability_status from public.driver_profiles where id='21000000-0000-4000-8000-000000000001'),
 'offline','driver is taken offline after cancelling');
select extensions.throws_ok(
 $$select public.cancel_ride('31000000-0000-4000-8000-000000000003','driver_unavailable')$$,
 '22023','ride_cannot_be_cancelled_at_this_stage','driver cannot cancel after trip start'
);
select * from extensions.finish();
rollback;
