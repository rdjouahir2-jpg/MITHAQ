-- Database platform hardening contract.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(3);

select extensions.ok(
  not has_table_privilege('anon','public.fare_policies','SELECT')
  and not has_table_privilege('anon','public.fare_policies','INSERT')
  and not has_table_privilege('anon','public.fare_policies','UPDATE')
  and not has_table_privilege('anon','public.fare_policies','DELETE')
  and not has_table_privilege('authenticated','public.fare_policies','SELECT')
  and not has_table_privilege('authenticated','public.fare_policies','INSERT')
  and not has_table_privilege('authenticated','public.fare_policies','UPDATE')
  and not has_table_privilege('authenticated','public.fare_policies','DELETE')
  and not has_table_privilege('anon','public.service_areas','SELECT')
  and not has_table_privilege('anon','public.service_areas','INSERT')
  and not has_table_privilege('anon','public.service_areas','UPDATE')
  and not has_table_privilege('anon','public.service_areas','DELETE')
  and not has_table_privilege('authenticated','public.service_areas','SELECT')
  and not has_table_privilege('authenticated','public.service_areas','INSERT')
  and not has_table_privilege('authenticated','public.service_areas','UPDATE')
  and not has_table_privilege('authenticated','public.service_areas','DELETE'),
  'fare policies and service areas are server-managed only'
);

select extensions.ok(
  to_regprocedure('public.rls_auto_enable()') is null
  or (
    not has_function_privilege('anon',to_regprocedure('public.rls_auto_enable()'),'EXECUTE')
    and not has_function_privilege('authenticated',to_regprocedure('public.rls_auto_enable()'),'EXECUTE')
  ),
  'RLS DDL event trigger function is not exposed as a client RPC'
);

select extensions.ok(
  (select count(*) = 11 from pg_indexes
   where schemaname='public' and indexname in (
     'audit_logs_actor_user_id_idx',
     'fare_quotes_service_area_id_idx',
     'ride_events_actor_user_id_idx',
     'ride_events_ride_id_idx',
     'ride_ratings_rated_user_id_idx',
     'ride_ratings_rater_user_id_idx',
     'safety_reports_reporter_user_id_idx',
     'safety_reports_ride_id_idx',
     'support_tickets_ride_id_idx',
     'support_tickets_user_id_idx',
     'vehicles_driver_id_idx'
   )),
  'all identified foreign keys have covering indexes'
);

select * from extensions.finish();
rollback;
