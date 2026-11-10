# MITHAQ — Roadmap (Updated 2026-11-10)

## Phase 0 — Product and operating foundations
- [x] Establish product scope, Arabic RTL client, architecture, and repository.
- [x] Document Algeria-specific legal questions and non-production boundaries.
- [ ] Select one candidate test/launch area.
- [ ] Validate the lawful operator/partner model and required authorizations.
- [ ] Define the safety, support, insurance, and incident-response operating model.

**Exit gate:** one area and a legally viable operating model are documented. A code deployment does not satisfy this gate.

## Phase 1 — Technical foundation (deployment complete)
- [x] TypeScript/Vite client and automated build checks.
- [x] Supabase schema and 23 ordered migrations.
- [x] Authentication and role authorization foundations.
- [x] Ride state machine, secure RPC commands, dispatch, offers, and boarding PIN.
- [x] Passenger/driver/admin demonstration workflows.
- [x] Hosted test database migrations applied.
- [x] Both Edge Functions deployed with server-only configuration.
- [x] GitHub Pages deployment and frontend/Deno CI passed.

**Exit gate:** deployment verified. This phase is complete as a deployment milestone, not as proof of an end-to-end operational service.

## Phase 2 — Closed technical test (current)
- [ ] Bootstrap the first administrator and verify admin permissions.
- [ ] Configure a small test service area and fare policy.
- [ ] Configure private scheduled maintenance and verify offer expiry/redispatch.
- [ ] Verify hosted extensions, Realtime, and grants.
- [ ] Run the complete two-phone flow, including negative/security cases.
- [ ] Fix and document every failed test.

**Exit gate:** repeatable successful end-to-end tests on two Android phones, with no payment or public passenger service.

## Phase 3 — Lawful controlled pilot (blocked pending external validation)
- [ ] Confirm written legal/transport permissions and operator model.
- [ ] Establish insurance, driver/vehicle verification, staffed support, and incident response.
- [ ] Complete privacy and independent security reviews.
- [ ] Choose reliable production mapping/routing and notification infrastructure.
- [ ] Conduct a limited pilot only after all approvals and operational safeguards are in place.

**Exit gate:** documented authority to operate a limited pilot, backed by real safety and support operations.

## Phase 4 — Production readiness and expansion
- [ ] Native Android app with reliable background location and push notifications.
- [ ] Monitoring, backups, restore drills, load testing, and incident response.
- [ ] Payments/settlement only after legal, accounting, and security review.
- [ ] Expand service areas only after local validation and operational capacity.

## Working principle

Build fewer features to a higher standard. Every task must end with a passing test, a verified operational result, or a documented blocker. Never describe a feature as complete solely because its UI or source code exists.
