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


## Latest engineering verification (2026-11-11)

- Fare negotiation is implemented in the feature branch, including participant-scoped reads, transactional RPCs, UI actions, alternating turns, expiry, and bounded amounts.
- GitHub CI passed the web build, Edge Function type checks, domain tests, local Supabase migration replay, and pgTAP security contract.
- Follow-up hardening now ensures non-participants are rejected before an expired negotiation can be mutated.
- A completion trigger snapshots the agreed amount into `rides.final_amount_minor`; an integration test covers both protections.
- These checks run against an ephemeral local Supabase stack in CI. The hosted project still has only the original 23 migrations; the new fare-negotiation migrations have not been applied there.
- No merge to `main`, hosted database migration, or deployment is implied by these source and CI checks.


## Database hardening follow-up (2026-11-11)

- Revoked direct client table privileges on server-managed fare policies and service-area configuration.
- Revoked client EXECUTE on the RLS DDL event-trigger function when present; the event trigger itself remains installed.
- Rewrote participant RLS predicates to evaluate `auth.uid()` as an init-plan rather than per row.
- Added covering indexes for 11 foreign keys identified by Supabase performance advisors.
- Added pgTAP checks for these privilege and index guarantees. The migration remains branch-only until hosted rollout is explicitly approved.


## Driver earnings read model (2026-11-11)

- Added `get_my_driver_earnings(p_limit)` as a stable, authenticated, driver-scoped read function over completed rides with a finalized fare.
- Added driver UI history for the latest 20 completed rides and their gross fare.
- The UI explicitly distinguishes gross trip fare from net driver earnings; commission, adjustments, cash reconciliation, and settlement remain unimplemented.
- Added pgTAP coverage for own-trip visibility, finalized fare integrity, cross-account isolation, and invalid limits. CI must pass before this is treated as verified.


## Pre-boarding cancellation (2026-11-11)

- Added a participant-only `cancel_ride` RPC for passengers and assigned drivers before boarding.
- Cancellation records actor and reason, withdraws outstanding offers, closes open fare negotiations, and takes a cancelling driver offline.
- The client exposes cancellation to passengers and assigned drivers before boarding.
- No cancellation fee or penalty is applied; fee policy is deferred pending legal and product review.
- pgTAP covers unauthorized cancellation, passenger cancellation, driver offline handling, and denial after trip start.
- Migration is branch-only until CI passes and a test rollout is explicitly approved.
