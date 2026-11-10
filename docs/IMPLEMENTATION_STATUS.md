# MITHAQ Implementation Status

Updated: 2026-11-10

## Implemented in repository (source committed)

- [x] Arabic RTL responsive web client with real Supabase email/password sign-up, sign-in, and sign-out flows.
- [x] Passenger booking flow wired to server-generated single-use quotes and the quote-bound ride request RPC.
- [x] Interactive MapLibre map with point selection, browser GPS, and trusted road-route geometry.
- [x] Passenger ride history/status, participant-only tracking lookup, and cancellation workflow.
- [x] Driver application and vehicle submission workflow.
- [x] Driver availability and foreground GPS updates with server-side freshness/accuracy validation.
- [x] Driver offer inbox with accept/decline and the ride lifecycle, including six-digit boarding PIN verification.
- [x] Realtime subscriptions for passenger rides, driver offers, and driver profile changes.
- [x] Admin bootstrap instructions and audited account/vehicle/driver approval commands.
- [x] Admin operational view for recent rides and safety reports.
- [x] Passenger safety-report submission and audited admin review.
- [x] Mutual one-time post-trip ratings, stored through a participant-checked RPC.
- [x] Server-side dispatch using PostGIS exact-radius distance, approved vehicle checks, fresh GPS, and no duplicate pending driver offers.
- [x] Scheduled maintenance Edge Function source for offer expiry, redispatch retries, and expired quote cleanup.
- [x] Service-area boundary enforcement and area-specific fare policy lookup.
- [x] Fifteen ordered SQL migrations, Supabase local configuration, pgTAP security tests, and GitHub Actions database-test workflow.
- [x] Deno type-check workflow for both Edge Functions.
- [x] Dependency lockfile generation integrated into CI; lockfile commit/push must complete successfully before it is considered persisted.
- [x] GitHub Pages build receives only public Supabase URL/anon-key repository variables; no service-role secret is required by the browser.

## Not yet deployed or independently verified

- [ ] Create and connect a dedicated Supabase test project.
- [ ] Complete a full successful local database migration run and pgTAP test run after the latest migration changes, including the new ratings migration.
- [ ] Confirm PostGIS, Realtime publication, and function grants on the hosted test project.
- [ ] Add GitHub Actions repository variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
- [ ] Configure the test service-area polygon and its fare policy.
- [ ] Deploy `create-fare-quote` and `dispatch-maintenance` with server-side secrets.
- [ ] Schedule the dispatch maintenance function with a private cron secret.
- [ ] Run end-to-end tests with two separate authenticated users and two physical phones.
- [ ] Add stronger application-level tests for concurrent offer acceptance, quote reuse/expiry, invalid PINs, unauthorized tracking, and all state transitions.
- [ ] Add secure driver document uploads and review for identity, driving licence, vehicle registration, and insurance.
- [ ] Add phone verification and abuse controls appropriate to Algeria.
- [ ] Add push notifications, robust Android background GPS, native Android packaging, and device-specific battery/permission handling.
- [ ] Add payment/settlement only after legal and financial model validation.
- [ ] Complete independent security review, monitoring, backup/restore, load testing, and incident response.
- [ ] Confirm Algerian transport permissions, insurance, privacy, consumer terms, and emergency operations with qualified local sources.

## Closed-test gate

The source code is not the same as a deployed service. Do not ask a friend to test until the hosted test project is connected, all fifteen migrations and database tests pass, both Edge Functions are deployed, the service area and test fare are configured, and the two-phone flow has passed internal checks. Keep the first trial non-commercial and do not carry paying passengers.

## Production gate

Do not launch publicly or carry paying passengers until driver identity/documents, vehicle eligibility, insurance, local legal permissions, privacy, safety operations, support, incident escalation, security review, monitoring, backups, and Android background-location behavior are verified.
