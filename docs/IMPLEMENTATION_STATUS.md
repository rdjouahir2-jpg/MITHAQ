# MITHAQ Implementation Status

Updated: 2026-11-11

## Hosted test deployment — previously verified

The following results were checked in GitHub Actions for commit `9ea7a06eb9d968e73a84fe5d0c882d6622244331`:

- [x] Frontend TypeScript check and production build passed.
- [x] GitHub Pages deployment passed.
- [x] Deno type checks for both Supabase Edge Functions passed.
- [x] All 23 ordered database migrations were applied to the hosted Supabase test project; deployment reported the remote database up to date on the successful run.
- [x] Server-only Edge Function configuration was set successfully.
- [x] `create-fare-quote` Edge Function deployment passed.
- [x] `dispatch-maintenance` Edge Function deployment passed.
- [x] Public browser config points to the dedicated test Supabase project and contains only its public publishable/anon key.
- [x] User successfully reached the deployed app and initiated email/password account creation.

These are historical CI/deployment results, not a fresh verification of this commit or proof of a complete ride lifecycle.

## Implemented in repository

- [x] Arabic RTL responsive client with Supabase email/password sign-up, sign-in, and sign-out.
- [x] Passenger booking flow using server-generated single-use fare quotes and quote-bound ride requests.
- [x] MapLibre map, pickup/destination selection, browser GPS, and road-route geometry.
- [x] Passenger ride history/status, scoped tracking lookup, and cancellation workflow.
- [x] Driver application, vehicle submission, availability, and foreground GPS.
- [x] Driver offer inbox with accept/decline and ride lifecycle, including six-digit boarding PIN verification.
- [x] Realtime subscriptions for ride, offer, and driver-profile changes.
- [x] Admin operations view, safety reports, and post-trip ratings.
- [x] Server-side dispatch with PostGIS radius matching, expiring offers, and retry handling.
- [x] Deterministic ride lifecycle invariants and tests.
- [x] **New:** bounded fare-negotiation domain model with integer-DZD bounds, alternating passenger/driver counter-offers, a configurable 1–5 round cap, expiry, accept, and reject transitions.
- [x] **New:** CI test command includes the negotiation invariant suite.
- [x] **New:** transactional Supabase migration for participant-scoped fare negotiation records and guarded start/respond/read RPCs.
- [x] **New:** server validates driver ownership and eligibility, passenger/driver turn alternation, fare bounds (70–130% of original quote), five-round cap, expiry, and atomic ride assignment on acceptance.
- [x] **New:** pgTAP security-contract assertions for negotiation RLS, blocked direct writes, and RPC grants.
- [x] **New:** typed frontend API wrapper for the negotiation RPCs.
- [x] **New:** passenger screen shows driver counter-offers and supports accept, counter, or reject.
- [x] **New:** driver screen can submit a counter-offer and respond to passenger counters.
- [x] **New:** negotiation updates are subscribed to through Supabase Realtime when the migration is applied.
- [x] **New:** competing negotiation threads close when any driver is assigned to the ride.

## Important limitation on fare negotiation

The domain rules, transactional database migration/RPCs, participant read policy, typed client API, and database security assertions are now present in the feature branch. The migration has not been applied to the hosted Supabase project. The database pgTAP workflow has not yet completed successfully for this migration; runs were cancelled while the branch was still receiving commits. The UI and API are committed, but must be exercised with two real test accounts after the migration is applied to a disposable/test database. Do not offer negotiation to real users until database tests and two-account integration tests pass.

## Remaining before a two-phone closed test

- [ ] Bootstrap the first administrator account using the one-time SQL procedure in `BACKEND_SETUP.md`.
- [ ] Verify hosted PostGIS extension, Realtime publication, and expected function grants.
- [ ] Configure one small, clearly labelled non-commercial test service area and fare policy.
- [ ] Configure and verify the private maintenance schedule.
- [ ] Verify account activation, driver approval, vehicle approval, and the full two-phone ride lifecycle.
- [ ] Test quote expiry/single-use, dispatch, offer expiry/decline/retry, concurrent acceptance, boarding PIN, participant-only tracking, and unauthorized access denial.
- [ ] Test on two Android phones over mobile data, including GPS permission and reconnection.

## Not yet implemented or independently verified for production

- [ ] Connect fare negotiation to secure transactional database functions and both user interfaces.
- [ ] Secure driver document upload and review for identity, driving licence, vehicle registration, and insurance.
- [ ] Phone verification and abuse controls.
- [ ] Native Android driver app, background GPS, push notifications, and battery/permission handling.
- [ ] Payment and driver settlement after legal and financial validation.
- [ ] Independent security review, monitoring, backup/restore drills, load testing, and incident response.
- [ ] Written Algerian legal/transport clearance, appropriate insurance, privacy/consumer terms, and staffed support/emergency operations.

## Safety gates

Keep testing restricted to consenting invited users, with no payment and no public passenger service. Do not carry paying passengers or launch publicly until legal, insurance, safety, privacy, operational, security, reliability, and native Android requirements are independently verified.
