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
- [x] Passenger sees assigned driver and approved vehicle details; driver sees only the assigned passenger name.
- [x] Database enforces one active ride per passenger and blocks redispatch of a stale request after a new active booking.
- [x] Server verifies the entire road route remains inside the active service-area polygon, not just the pickup and destination points.
- [x] Shared database rate gate limits the public test routing endpoint to one request per second across the project.
- [x] Passenger safety-report submission and audited admin review.
- [x] Mutual one-time post-trip ratings, stored through a participant-checked RPC.
- [x] Continue driver GPS during an active trip while keeping busy drivers out of new dispatch matching.
- [x] Maintenance handles declined as well as expired offers, then retries dispatch safely.
- [x] Added Algeria-specific legal research and made clear that test approval is not a transport permit.
- [x] Server-side dispatch using PostGIS exact-radius distance, approved vehicle checks, fresh GPS, and no duplicate pending driver offers.
- [x] Scheduled maintenance Edge Function source for offer expiry, redispatch retries, and expired quote cleanup.
- [x] Service-area boundary enforcement and area-specific fare policy lookup.
- [x] Twenty-two ordered SQL migrations, Supabase local configuration, pgTAP security tests, and GitHub Actions database-test workflow.
- [x] Deno type-check workflow for both Edge Functions.
- [x] Dependency lockfile generation integrated into CI; lockfile commit/push must complete successfully before it is considered persisted.
- [x] GitHub Pages build reads a dedicated public-only Supabase config file; no service-role secret is required by the browser.

## Not yet deployed or independently verified

- [ ] Create and connect a dedicated Supabase test project.
- [ ] Complete a full successful local database migration run and pgTAP test run after the latest migration changes, including the new ratings migration.
- [ ] Confirm PostGIS, Realtime publication, and function grants on the hosted test project.
- [ ] Fill `src/lib/public-config.ts` with the new test project's public URL and anon/publishable key after the Supabase project is connected.
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
- [ ] Obtain written Algerian legal/transport clearance for the VTC or taxi operating model, insurance, privacy, consumer terms, and emergency operations. See `docs/ALGERIA_LEGAL_REVIEW.md`.

## Closed-test gate

The source code is not the same as a deployed service. Do not ask a friend to test until the hosted test project is connected, all twenty-two migrations and database tests pass, both Edge Functions are deployed, the service area and test fare are configured, and the two-phone flow has passed internal checks. Keep the first trial non-commercial and do not carry paying passengers.

## Production gate

Do not launch publicly or carry paying passengers until driver identity/documents, vehicle eligibility, insurance, local legal permissions, privacy, safety operations, support, incident escalation, security review, monitoring, backups, and Android background-location behavior are verified.
