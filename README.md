# MITHAQ

**Smart mobility platform concept for Algeria.**


## Connected test features

- Supabase email/password authentication and role-aware passenger, driver, and admin screens.
- MapLibre map with GPS-based pickup selection, destination selection, and trusted route geometry.
- Server-calculated quotes bound to an active service-area boundary and its fare policy.
- Atomic ride requests, nearby-driver dispatch, expiring offers, boarding PINs, and controlled ride transitions.
- Realtime ride/offer updates and participant-only driver tracking during active trips.
- Driver application/vehicle submission, audited admin approval, and safety-report review.
- Scheduled maintenance function for expired offers and redispatch retry.

See [the closed-test setup runbook](docs/BACKEND_SETUP.md) before connecting a hosted test project. It explains the one-time admin bootstrap, service-area configuration, Edge Function secrets, scheduler, GitHub Pages variables, and two-phone test sequence.

## Current software status

The repository currently contains a runnable Arabic RTL web demonstration:
- Responsive passenger, driver, and admin-placeholder screens.
- Simulated ride lifecycle and illustrative fare display.
- PWA manifest for install-to-home-screen testing.

**This is not a live ride-hailing service.** It does not yet authenticate users, locate drivers, dispatch trips, calculate road fares, send notifications, process payments, or provide emergency response. The visible booking and driver actions are simulations.

## Engineering work committed (2026-11-10)

- `src/domain/ride.ts`: typed ride states, actor transition rules, integer-money validation, and snapshot invariants.
- `docs/OPEN_SOURCE_BASES.md`: review of candidate open-source foundations, licence boundaries, and operational caveats.
- `202611100001_initial_schema.sql`: initial PostgreSQL data model and restrictive baseline RLS policies.
- `202611100002_secure_ride_commands.sql` and `202611100003_auth_bootstrap.sql`: first server-side command and account-bootstrap drafts.
- `202611100004_security_hardening.sql`: removes client-supplied fare amounts from ride creation. A ride now requires a short-lived, single-use fare quote written by a trusted server; the browser cannot write or alter quote rows.
- `202611100005_auth_hardening.sql`: stops trusting user-editable metadata as a verified phone number and pins privileged function search paths.
- `202611100006_dispatch_and_presence.sql`: adds private driver location storage, validated driver location/availability RPCs, server-only nearby dispatch, and expiring-offer lifecycle.
- `202611100007_transaction_hardening.sql`: uses cryptographically generated boarding PINs and consistent ride-first lock ordering for offer acceptance.
- `supabase/tests/database/001_security_contract.sql`: adds pgTAP checks for private coordinates, fare quote permissions, and server-only dispatch.
- `supabase/functions/create-fare-quote/index.ts`: authenticated Edge Function for road-route validation, server-side fare calculation, rate-limited quote creation, and single-use quote storage.
- `docs/BACKEND_SETUP.md`: exact migration order, required server secrets, deployment boundary, and outstanding release gates.
- Removed the fabricated distance-based fare and invented driver offer amount from the visible demo. The UI now labels pricing as unavailable until real routing and fare policy are connected.

These are committed source migrations, **not evidence of a deployed or tested backend**. They have not yet been applied to a Supabase project or validated against a live PostgreSQL instance. The Edge Function source is committed but not deployed or tested; a trusted routing endpoint and active fare policy must be configured. Actual database test execution, Supabase connection, realtime client, and mobile integration remain outstanding.

## Run the current web demonstration

Requirements: Node.js LTS and npm.

```bash
npm install
npm run dev
```

Build check:

```bash
npm run build
```

## Architecture direction

Keep the initial product narrow: one launch area, passenger and driver workflows, controlled driver onboarding, server-authoritative fares and trip state, and a closed pilot before any public launch. Use PostgreSQL transactions for consistency, RLS for row access, and narrowly granted server functions for privileged commands. Use Edge Functions for trusted integrations such as route-provider calls and dispatch orchestration.

Never place a Supabase service-role key in browser code. Do not expose a live booking flow until the fare quote, dispatch, identity, safety, monitoring, and support paths have been tested.

## Legal and operational boundary

MITHAQ is software under development, not an operating transport company. Before a real pilot, validate Algerian transport permissions, operator and driver eligibility, insurance, consumer terms, privacy requirements, support coverage, and emergency escalation with qualified local sources.

## Development principles

- Synthetic data only until security and privacy controls are reviewed.
- Server-side authorization and pricing; never trust the client for ride state or fare.
- No biometric recognition in the MVP.
- No real payments until legal, accounting, and security reviews are complete.
