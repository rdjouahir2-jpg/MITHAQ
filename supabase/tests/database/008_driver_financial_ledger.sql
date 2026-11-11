begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(34);

select extensions.has_table('public','ride_financials','completed rides have a financial snapshot');
select extensions.has_table('public','driver_ledger_entries','driver balances use an append-only ledger');
select extensions.has_table('public','driver_payout_requests','driver payouts have a review queue');
select extensions.ok((select relrowsecurity from pg_class where oid='public.ride_financials'::regclass),'ride financial snapshots use RLS');
select extensions.ok((select relrowsecurity from pg_class where oid='public.driver_ledger_entries'::regclass),'driver ledger uses RLS');
select extensions.ok((select relrowsecurity from pg_class where oid='public.driver_payout_requests'::regclass),'payout requests use RLS');
select extensions.ok(not has_function_privilege('anon','public.request_driver_payout(bigint)','EXECUTE'),'anonymous users cannot request payouts');
select extensions.ok(not has_table_privilege('authenticated','public.driver_ledger_entries','INSERT'),'clients cannot forge driver ledger entries');
select extensions.ok(not has_table_privilege('authenticated','public.ride_financials','UPDATE'),'clients cannot alter fare or commission snapshots');
select extensions.is((select count(*)::integer from public.platform_commission_policies where is_active),0,'no commission rate is silently assumed before admin approval');

insert into auth.users (id,aud,role,email,created_at,updated_at)
values
 ('51000000-0000-4000-8000-000000000001','authenticated','authenticated','mithaq-finance-admin@example.invalid',now(),now()),
 ('51000000-0000-4000-8000-000000000002','authenticated','authenticated','mithaq-finance-driver@example.invalid',now(),now()),
 ('51000000-0000-4000-8000-000000000003','authenticated','authenticated','mithaq-finance-passenger@example.invalid',now(),now())
on conflict (id) do nothing;
update public.profiles set account_status='active'
where id in (
 '51000000-0000-4000-8000-000000000001',
 '51000000-0000-4000-8000-000000000002',
 '51000000-0000-4000-8000-000000000003'
);
insert into public.user_roles(user_id,role)
values('51000000-0000-4000-8000-000000000001','admin')
on conflict do nothing;
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
select public.admin_set_platform_commission(1000);
select extensions.is((select commission_bps from public.platform_commission_policies where is_active),1000,'admin-configured 10 percent commission rate is active');

insert into public.driver_profiles(id,user_id,onboarding_status,availability_status)
values('52000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000002','approved','offline')
on conflict (id) do nothing;

insert into public.rides(id,passenger_id,driver_id,pickup_label,destination_label,status,quoted_amount_minor,final_amount_minor,currency_code)
values('53000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000003',
 '52000000-0000-4000-8000-000000000001','A','B','in_progress',18750,null,'DZD');
update public.rides set status='completed',completed_at=now()
where id='53000000-0000-4000-8000-000000000001';

select extensions.is((select count(*)::integer from public.ride_financials),1,'completion creates one financial snapshot');
select extensions.is((select gross_fare_minor from public.ride_financials where ride_id='53000000-0000-4000-8000-000000000001'),18750::bigint,'gross fare is snapshotted');
select extensions.is((select commission_minor from public.ride_financials where ride_id='53000000-0000-4000-8000-000000000001'),1875::bigint,'commission is calculated in integer minor units');
select extensions.is((select driver_net_minor from public.ride_financials where ride_id='53000000-0000-4000-8000-000000000001'),16875::bigint,'driver net equals gross less commission');
select extensions.throws_ok(
  $$update public.ride_financials set gross_fare_minor=1 where ride_id='53000000-0000-4000-8000-000000000001'$$,
 '55000','financial_snapshot_is_immutable','completed ride fare and commission snapshots cannot be edited'
);
select extensions.is((select count(*)::integer from public.driver_ledger_entries),0,'no balance entry is created before collection is confirmed');

select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
select public.admin_record_ride_payment('53000000-0000-4000-8000-000000000001','manual_transfer_to_platform','BANK-REF-001');
select extensions.is((select amount_minor from public.driver_ledger_entries where ride_id='53000000-0000-4000-8000-000000000001' and entry_type='platform_fare_credit'),16875::bigint,'platform collection credits the driver net amount');
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000002',true);
select extensions.is((select payout_available_minor from public.get_my_driver_financial_summary()),16875::bigint,'driver summary reports available net payout');
select extensions.ok(public.request_driver_payout(16875) is not null,'driver can request a payout within available balance');
select extensions.is((select status from public.driver_payout_requests limit 1),'pending','new payout requests require administrative review');
select extensions.throws_ok(
 $select public.admin_process_driver_payout((select id from public.driver_payout_requests limit 1),'approve',null,null)$,
 '42501','admin_required','drivers cannot approve their own payout'
);
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
select public.admin_process_driver_payout((select id from public.driver_payout_requests limit 1),'approve',null,'تمت مراجعة الطلب');
select public.admin_process_driver_payout((select id from public.driver_payout_requests limit 1),'pay','TRANSFER-2026-001','تم التحويل');
select extensions.is((select status from public.driver_payout_requests limit 1),'paid','payout is marked paid only after admin confirmation');
select extensions.is((select amount_minor from public.driver_ledger_entries where entry_type='payout_debit'),-16875::bigint,'paid payout creates a negative immutable ledger entry');
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000002',true);
select extensions.is((select payout_available_minor from public.get_my_driver_financial_summary()),0::bigint,'paid payout reduces the available balance to zero');
select extensions.throws_ok(
 $$select public.request_driver_payout(1)$$,
 '22023','payout_exceeds_available_balance','driver cannot request more than the remaining ledger balance'
);
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
select extensions.throws_ok(
 $$select public.admin_process_driver_payout((select id from public.driver_payout_requests limit 1),'pay','TRANSFER-DUPLICATE','duplicate attempt')$$,
 'P0002','payout_not_pending','a paid payout cannot be processed twice'
);
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000002',true);
select extensions.throws_ok(
 $$update public.driver_ledger_entries set description='tampered' where entry_type='payout_debit'$$,
 '55000','financial_ledger_is_immutable','ledger entries cannot be edited after posting'
);

insert into public.rides(id,passenger_id,driver_id,pickup_label,destination_label,status,quoted_amount_minor,final_amount_minor,currency_code)
values('53000000-0000-4000-8000-000000000002','51000000-0000-4000-8000-000000000003',
 '52000000-0000-4000-8000-000000000001','C','D','in_progress',20000,null,'DZD');
update public.rides set status='completed',completed_at=now()
where id='53000000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
select public.admin_record_ride_payment('53000000-0000-4000-8000-000000000002','cash_to_driver','CASH-RECEIPT-02');
select extensions.is((select amount_minor from public.driver_ledger_entries where ride_id='53000000-0000-4000-8000-000000000002' and entry_type='cash_commission_due'),-2000::bigint,'cash rides record commission owed by the driver');
select public.admin_record_driver_commission_payment('53000000-0000-4000-8000-000000000002','COMMISSION-REMIT-02');
select extensions.is((select commission_status from public.ride_financials where ride_id='53000000-0000-4000-8000-000000000002'),'settled','commission remittance closes the outstanding commission');
select extensions.is((select amount_minor from public.driver_ledger_entries where ride_id='53000000-0000-4000-8000-000000000002' and entry_type='commission_remittance'),2000::bigint,'commission remittance balances the driver ledger');
select extensions.throws_ok(
 $select public.admin_set_platform_commission(1200)$,
 '42501','admin_required','drivers cannot change platform commission'
);
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000003',true);
select extensions.is((select count(*)::bigint from public.get_my_driver_earnings(20)),0::bigint,'passenger cannot read driver earnings');
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000002',true);
select extensions.is((select count(*)::bigint from public.get_my_driver_earnings(20)),2::bigint,'driver earnings history includes only own completed rides');

select * from extensions.finish();
rollback;
