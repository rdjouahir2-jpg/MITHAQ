-- Tighten server-managed table grants, optimize participant RLS predicates,
-- and add covering indexes for foreign keys used by operational workflows.

revoke all on table public.fare_policies, public.service_areas
  from public, anon, authenticated;

-- The platform event trigger remains attached and continues to enforce RLS on
-- new public tables. Its trigger function is not an RPC and needs no client EXECUTE.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke all on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$$;

alter policy driver_profile_select_own on public.driver_profiles
  using (user_id = (select auth.uid()));
alter policy profile_select_own on public.profiles
  using (id = (select auth.uid()));
alter policy events_select_participant on public.ride_events
  using (
    exists (
      select 1 from public.rides r
      where r.id = ride_events.ride_id
        and (
          r.passenger_id = (select auth.uid())
          or exists (
            select 1 from public.driver_profiles d
            where d.id = r.driver_id and d.user_id = (select auth.uid())
          )
        )
    )
  );
alter policy offers_select_involved on public.ride_offers
  using (
    exists (
      select 1 from public.rides r
      where r.id = ride_offers.ride_id
        and r.passenger_id = (select auth.uid())
    )
    or exists (
      select 1 from public.driver_profiles d
      where d.id = ride_offers.driver_id and d.user_id = (select auth.uid())
    )
  );
alter policy ride_ratings_select_participants on public.ride_ratings
  using (
    rater_user_id = (select auth.uid())
    or rated_user_id = (select auth.uid())
  );
alter policy rides_select_participant on public.rides
  using (
    passenger_id = (select auth.uid())
    or exists (
      select 1 from public.driver_profiles d
      where d.id = rides.driver_id and d.user_id = (select auth.uid())
    )
  );
alter policy safety_report_insert_self on public.safety_reports
  with check (reporter_user_id = (select auth.uid()));
alter policy safety_report_select_self on public.safety_reports
  using (reporter_user_id = (select auth.uid()));
alter policy support_ticket_insert_self on public.support_tickets
  with check (user_id = (select auth.uid()));
alter policy support_ticket_select_self on public.support_tickets
  using (user_id = (select auth.uid()));
alter policy roles_select_own on public.user_roles
  using (user_id = (select auth.uid()));
alter policy vehicles_select_owner on public.vehicles
  using (
    exists (
      select 1 from public.driver_profiles d
      where d.id = vehicles.driver_id and d.user_id = (select auth.uid())
    )
  );

create index if not exists audit_logs_actor_user_id_idx
  on public.audit_logs(actor_user_id);
create index if not exists fare_quotes_service_area_id_idx
  on public.fare_quotes(service_area_id);
create index if not exists ride_events_actor_user_id_idx
  on public.ride_events(actor_user_id);
create index if not exists ride_events_ride_id_idx
  on public.ride_events(ride_id);
create index if not exists ride_ratings_rated_user_id_idx
  on public.ride_ratings(rated_user_id);
create index if not exists ride_ratings_rater_user_id_idx
  on public.ride_ratings(rater_user_id);
create index if not exists safety_reports_reporter_user_id_idx
  on public.safety_reports(reporter_user_id);
create index if not exists safety_reports_ride_id_idx
  on public.safety_reports(ride_id);
create index if not exists support_tickets_ride_id_idx
  on public.support_tickets(ride_id);
create index if not exists support_tickets_user_id_idx
  on public.support_tickets(user_id);
create index if not exists vehicles_driver_id_idx
  on public.vehicles(driver_id);
