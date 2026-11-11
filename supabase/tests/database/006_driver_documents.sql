begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(7);

insert into auth.users (id,aud,role,email,created_at,updated_at) values
 ('61000000-0000-4000-8000-000000000001','authenticated','authenticated','docs-driver@example.invalid',now(),now()),
 ('61000000-0000-4000-8000-000000000002','authenticated','authenticated','docs-admin@example.invalid',now(),now())
on conflict(id) do nothing;
insert into public.profiles(id,display_name,account_status)
values
 ('61000000-0000-4000-8000-000000000001','Docs Driver','active'),
 ('61000000-0000-4000-8000-000000000002','Docs Admin','active')
on conflict(id) do update set account_status='active';
insert into public.user_roles(user_id,role)
values ('61000000-0000-4000-8000-000000000002','admin')
on conflict do nothing;
insert into public.driver_profiles(id,user_id,onboarding_status,availability_status)
values ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','under_review','offline')
on conflict(id) do nothing;
insert into public.vehicles(driver_id,make,model,model_year,seat_capacity,eligibility_status)
values ('62000000-0000-4000-8000-000000000001','Test','Car',2022,4,'approved');

select extensions.is(
  public.driver_documents_complete('62000000-0000-4000-8000-000000000001'),
  false,
  'driver without documents is not document-complete'
);

select extensions.throws_ok(
 $$update public.driver_profiles set onboarding_status='approved' where id='62000000-0000-4000-8000-000000000001'$$,
 '23514','required_driver_documents_not_approved',
 'database blocks approval until all required documents are approved'
);

insert into public.driver_documents(driver_id,user_id,document_type,object_path,status,expires_on)
values
 ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','identity_card','test/identity','approved',null),
 ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','driving_license','test/license','approved',null),
 ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','vehicle_registration','test/registration','approved',null),
 ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','insurance','test/insurance','approved',current_date+30);

select extensions.is(
  public.driver_documents_complete('62000000-0000-4000-8000-000000000001'),
  true,
  'all four approved and current documents satisfy the gate'
);

insert into public.driver_documents(driver_id,user_id,document_type,object_path,status,uploaded_at)
values ('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001',
        'identity_card','test/new-identity','pending',now()+interval '1 second');
select extensions.is(
  public.driver_documents_complete('62000000-0000-4000-8000-000000000001'),
  false,
  'a newer pending replacement supersedes the previously approved document'
);
update public.driver_documents set status='approved'
where object_path='test/new-identity';
select extensions.is(
  public.driver_documents_complete('62000000-0000-4000-8000-000000000001'),
  true,
  'a newly approved replacement restores document completeness'
);

select set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000001',true);
select extensions.throws_ok(
 $select * from public.admin_list_driver_documents()$,
 '42501','admin_required','drivers cannot list the administrative document queue'
);
select set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000002',true);

update public.driver_profiles set onboarding_status='approved'
where id='62000000-0000-4000-8000-000000000001';
select extensions.is(
  (select onboarding_status from public.driver_profiles where id='62000000-0000-4000-8000-000000000001'),
  'approved',
  'driver approval succeeds after all required documents are approved'
);

select * from extensions.finish();
rollback;
