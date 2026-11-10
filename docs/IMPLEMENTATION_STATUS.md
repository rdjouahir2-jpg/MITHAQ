# MITHAQ Implementation Status

Updated: 2026-11-10

## Hosted test deployment — verified

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

This proves deployment and CI checks. It does **not** prove the complete ride lifecycle works across two phones.

## Implemented in repository (source committed)

- [x] Arabic RTL responsive client with Supabase email/password sign-up, sign-in, and sign-out.
- [x] Passenger booking flow using server-generated single-use fare quotes and quote-bound ride requests.
- [x] MapLibre map, pickup/destination selection, browser GPS, and road-route geometry.
- [x] Passenger ride history/status, scoped tracking lookup, and cancellation workflow.
- [x] Driver application, vehicle submission, availability, and foreground GPS.
- [x] Driver offer inbox with accept/decline and ride lifecycle, including six-digit boarding PIN verification.
- [x] Realtime subscriptions for ride, offer, and driver-profile changes.
- [x] Admin bootstrap instructions and audited account/vehicle/driver approval commands.
- [x] Admin operations view, safety reports, and post-trip ratings.
- [x] Server-side dispatch with PostGIS radius matching, approved vehicle checks, fresh GPS, and duplicate-offer protection.
- [x] Service-area boundary enforcement, area-specific fare policy, and shared routing rate gate.
- [x] Driver location minimization and stale-location cleanup.
- [x] Twenty-three SQL migrations and 25 pgTAP security-contract assertions passed in local Supabase CI.
- [x] Eight deterministic ride-domain tests cover allowed/forbidden transitions, terminal states, money validation, and ride snapshot invariants; the expanded CI workflow passed.

## Remaining before a two-phone closed test

- [ ] Bootstrap the first administrator account using the one-time SQL procedure in `BACKEND_SETUP.md`.
- [ ] Verify hosted PostGIS extension, Realtime publication, and expected function grants.
- [ ] Configure one deliberately small test service-area polygon and a clearly labelled non-commercial test fare policy.
- [ ] Configure and verify the private once-per-minute maintenance schedule using the cron secret; do not expose it in browser code.
- [ ] Confirm admin can activate a second test account.
- [ ] Submit and approve a test driver profile and vehicle.
- [ ] Test quote creation, out-of-area rejection, expiry and single-use enforcement.
- [ ] Test dispatch, offer expiry/decline/retry, concurrent acceptance, and no-driver cases.
- [ ] Test the complete ride state machine and wrong/correct boarding PIN behavior.
- [ ] Test participant-only tracking and unauthorized access denial.
- [ ] Test on two Android phones over mobile data, with GPS permission and reconnection scenarios.
- [ ] Record results and fix failures before inviting additional testers.

## Not yet implemented or independently verified for production

- [ ] Secure driver document upload and review for identity, driving licence, vehicle registration, and insurance.
- [ ] Phone verification and abuse controls suitable for the operating model.
- [ ] Push notifications, reliable Android background GPS, native Android packaging, and battery/permission handling.
- [ ] Payment and driver settlement, only after legal and financial validation.
- [ ] Independent security review, monitoring, backup/restore drills, load testing, and incident response.
- [ ] Written Algerian legal/transport clearance, appropriate insurance, privacy/consumer terms, and staffed emergency/support operations.

## Closed-test gate

Keep testing restricted to consenting invited users, with no payment and no public passenger service. Do not invite a friend to perform a real trip until the remaining setup items above are completed. If legal permission for an actual passenger journey is unclear, test with stationary vehicles or on private property only.

## Production gate

Do not launch publicly or carry paying passengers until all legal, insurance, safety, privacy, operational, security, reliability, and native Android requirements have been verified independently.
