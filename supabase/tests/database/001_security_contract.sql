-- pgTAP contract tests for MITHAQ's database security boundary.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(10);

select extensions.has_table('public', 'driver_locations', 'driver location table exists');
select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.driver_locations'::regclass),
  'driver locations has row-level security enabled'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.driver_locations', 'SELECT'),
  'authenticated clients cannot read raw driver coordinates'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.driver_locations', 'INSERT'),
  'authenticated clients cannot write raw driver coordinates'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.fare_quotes', 'INSERT'),
  'authenticated clients cannot mint or alter fare quotes'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.fare_quotes', 'UPDATE'),
  'authenticated clients cannot change quote amounts or expiry'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.request_ride(uuid)', 'EXECUTE'),
  'authenticated passengers can call the quote-bound ride request command'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.record_driver_location(double precision,double precision,double precision,timestamp with time zone)', 'EXECUTE'),
  'authenticated drivers can submit location through the validated RPC'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'public.dispatch_ride(uuid,integer,integer)', 'EXECUTE'),
  'clients cannot directly dispatch rides'
);
select extensions.ok(
  has_function_privilege('service_role', 'public.dispatch_ride(uuid,integer,integer)', 'EXECUTE'),
  'only the trusted server role can invoke dispatch'
);

select * from finish();
rollback;
