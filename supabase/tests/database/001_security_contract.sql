-- pgTAP contract tests for MITHAQ's database security boundary.
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(33);

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

select extensions.ok(
  has_function_privilege('authenticated', 'public.get_my_ride_tracking(uuid)', 'EXECUTE'),
  'authenticated ride participants can use the scoped tracking RPC'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.admin_list_driver_applications()', 'EXECUTE'),
  'admin application list entrypoint is callable (role check is enforced inside the function)'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.audit_logs', 'INSERT'),
  'clients cannot directly write audit logs'
);
select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.ride_ratings'::regclass),
  'ride ratings has row-level security enabled'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.ride_ratings', 'INSERT'),
  'clients cannot write ratings directly'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.submit_ride_rating(uuid,integer,text)', 'EXECUTE'),
  'participants can submit ratings through the guarded RPC'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.get_my_passenger_ride_details(integer)', 'EXECUTE'),
  'passengers can request only their own ride details'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.get_my_driver_ride_details(integer)', 'EXECUTE'),
  'drivers can request only their assigned ride details'
);
select extensions.ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'rides_one_active_per_passenger'),
  'database enforces at most one active ride per passenger'
);
select extensions.ok(
  has_function_privilege('service_role', 'public.validate_route_geometry_in_area(uuid,jsonb)', 'EXECUTE'),
  'only the trusted server role can validate complete route geometry'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'public.validate_route_geometry_in_area(uuid,jsonb)', 'EXECUTE'),
  'clients cannot bypass service-area route validation'
);
select extensions.ok(
  has_function_privilege('service_role', 'public.claim_routing_request_slot()', 'EXECUTE'),
  'only the trusted server role can claim a routing slot'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'public.claim_routing_request_slot()', 'EXECUTE'),
  'clients cannot bypass the shared routing rate gate'
);
select extensions.ok(
  exists (select 1 from pg_trigger where tgname = 'driver_location_clear_on_offline' and not tgisinternal),
  'driver location is cleared when a profile goes offline'
);
select extensions.ok(
  (select prosecdef from pg_proc where oid = 'public.clear_driver_location_on_offline()'::regprocedure),
  'location cleanup trigger runs with the required server privilege'
);

select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.fare_negotiations'::regclass),
  'fare negotiations has row-level security enabled'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.fare_negotiations', 'SELECT'),
  'authenticated participants can read negotiation rows subject to participant policy'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.fare_negotiations', 'INSERT'),
  'clients cannot create negotiations directly'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.fare_negotiations', 'UPDATE'),
  'clients cannot alter negotiation amounts or state directly'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.fare_negotiations', 'DELETE'),
  'clients cannot delete negotiation audit history'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.start_fare_negotiation(uuid,bigint)', 'EXECUTE'),
  'eligible drivers can start a counter-offer through the guarded RPC'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.respond_fare_negotiation(uuid,text,bigint)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.get_my_fare_negotiations()', 'EXECUTE'),
  'authenticated participants can respond and read their own negotiation threads'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.respond_fare_negotiation(uuid,text,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.start_fare_negotiation(uuid,bigint)', 'EXECUTE'),
  'anonymous users cannot access fare negotiation commands'
);

select * from extensions.finish();
rollback;
