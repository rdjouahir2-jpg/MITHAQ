# MITHAQ Implementation Status

Updated: 2026-11-10

## Implemented in repository (source committed)

- [x] Responsive Arabic RTL web demonstration.
- [x] Simulated passenger booking, driver availability, offer acceptance, and ride lifecycle.
- [x] Initial PostgreSQL schema with RLS enabled and baseline policies.
- [x] Typed ride-domain rules in TypeScript.
- [x] Draft server-side ride commands with participant checks and boarding PIN validation.
- [x] Auth bootstrap trigger and pending driver application command.
- [x] Fare quote table design: server-written, passenger-bound, expiring, single-use quotes; client-supplied fare values removed from ride creation.
- [x] Hardening of auth metadata handling, privileged function search paths, stale-offer behavior, and driver availability after trip completion/cancellation.
- [x] GitHub Actions build and demo deployment succeeded for commit `1f1ffc5012dc65dfedea93de4a29efddc710ca23` before the two newest hardening migrations were added.

## Not implemented or not verified

- [ ] Apply all migrations to a real Supabase project.
- [ ] Run SQL migrations against PostgreSQL and resolve any platform-specific issues.
- [ ] Automated database tests: authentication, RLS isolation, concurrent offer acceptance, quote reuse/expiry, PIN failure/success, and every legal ride transition.
- [ ] Trusted fare-quote Edge Function with server-side route validation and active fare-policy lookup.
- [ ] Dispatch engine and driver location ingestion with freshness, radius, and eligibility checks.
- [ ] Supabase Auth UI and real session handling.
- [ ] Realtime passenger/driver trip updates.
- [ ] Real map, geocoding, routing, and GPS permission flows.
- [ ] Admin authorization, driver document review, and vehicle verification.
- [ ] Push notifications and incident escalation.
- [ ] Payment integration and accounting.
- [ ] Android packaging and device testing.
- [ ] Dependency pinning, lockfile, vulnerability audit, and final CI verification after the latest migrations.

## Gate before any closed pilot

Do not carry real passengers until the database and security tests pass, dispatch and location freshness are reliable, driver/vehicle approval is operational, support and emergency escalation are staffed, and local legal/insurance/privacy requirements are confirmed. A successful frontend build is not proof of backend correctness or operational readiness.
