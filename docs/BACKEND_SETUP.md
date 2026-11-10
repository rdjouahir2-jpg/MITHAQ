# MITHAQ backend setup and integration boundary

This document is the handoff checklist for connecting the committed backend to a new Supabase project. No project credentials are stored in this repository.

## Migration order

Apply the SQL files in lexical order to a **new, empty** Supabase project:

1. `202611100001_initial_schema.sql`
2. `202611100002_secure_ride_commands.sql`
3. `202611100003_auth_bootstrap.sql`
4. `202611100004_security_hardening.sql`
5. `202611100005_auth_hardening.sql`
6. `202611100006_dispatch_and_presence.sql`
7. `202611100007_transaction_hardening.sql`

The initial schema installs PostGIS and pgcrypto into the `extensions` schema. Confirm that the project permits those extensions and that the PostGIS types/functions resolve there before applying the migrations. Do not apply this stack to an existing production database without a reviewed backup and migration plan.

## Fare quote Edge Function

Deploy:

```sh
supabase functions deploy create-fare-quote
```

Configure these Edge Function secrets in the Supabase project settings / CLI secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` — server secret only; never place it in browser or Android app configuration.
- `ROUTING_BASE_URL` — HTTPS base URL for a trusted OSRM-compatible routing service.
- `ALLOWED_ORIGIN` — exact production web origin, for example the deployed MITHAQ web origin.

The function validates the user's Supabase session, checks that the account is active, enforces a basic per-user quote limit, obtains a road route from the configured routing service, applies the active global fare policy, and writes a short-lived quote through the service role. It intentionally fails closed if no route service, origin, or active fare policy is configured.

The public OSRM demo server is not a production service and must not be used for commercial traffic. Run a managed or self-hosted routing service with its own capacity and availability plan.

## Passenger ride request

The authenticated client may call `request_ride(p_quote_id)` only after receiving a valid quote. The database command consumes the quote once, creates a cryptographically PIN-protected ride, and invokes server-only dispatch in the same database transaction. It returns the ride ID, one-time boarding PIN, and resulting state. Show the PIN only to the passenger and never log it.

Dispatch creates offers only for drivers whose profile and vehicle are approved, who are online, and whose reported location is recent and accurate enough. Raw driver coordinates are not directly readable or writable by authenticated clients. Driver location updates must use the validated RPC.

## Database tests

Run against the local Supabase database after migrations:

```sh
supabase test db
```

The pgTAP contract test currently checks RLS and function/table grants. It does **not** replace integration tests for concurrent offer acceptance, quote expiry/reuse, incorrect PINs, invalid transitions, GPS staleness, and dispatch matching. Those cases remain a release gate.

## Still required before a real pilot

- Build the authenticated web/mobile client and wire it to the quote and ride RPCs.
- Add an admin-only, audited process to activate passenger accounts and approve driver profiles/vehicles.
- Add a scheduled worker to expire offers and retry dispatch when new eligible drivers appear.
- Add a service-area boundary check and explicit fare policy per launch area.
- Add Realtime subscriptions, route display, background GPS permissions, push notifications, and support escalation.
- Complete database integration/security tests, backups/restore, monitoring, and load testing.
- Confirm Algerian transport permissions, insurance, privacy, consumer terms, and emergency operations with qualified local sources.

A successful frontend build or a committed SQL migration is not evidence that the backend is deployed or safe for passenger trips.
