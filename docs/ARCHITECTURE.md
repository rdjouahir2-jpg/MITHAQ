# MITHAQ — Proposed Architecture (Draft 0.1)

## 1. Architecture goals

- Secure by default, understandable, and maintainable by a small team.
- Keep business rules on the server; clients are untrusted.
- Start as a modular monolith rather than premature microservices.
- Support low-cost development and a controlled pilot.
- Minimize collection and retention of personal and location data.

## 2. Proposed system context

- **Passenger client:** Android-first mobile application; iOS may follow.
- **Driver client:** Android-first mobile application with driver-specific permissions and flows.
- **Operations console:** responsive web application with role-based access.
- **Backend API:** authentication, profiles, onboarding, ride lifecycle, dispatch, pricing, support, and audit modules.
- **Database:** PostgreSQL; PostGIS for geospatial queries.
- **Realtime channel:** authenticated ride events and carefully limited location updates.
- **Mapping:** evaluate OpenStreetMap data with a suitable renderer/provider and routing service. Review tile/routing terms and operating costs before production.

## 3. Proposed stack (not yet locked)

- Mobile: React Native + Expo + TypeScript.
- Operations web: React + TypeScript.
- Backend: TypeScript modular monolith (framework to be selected after a small technical spike).
- Database: PostgreSQL + PostGIS.
- API: REST initially; OpenAPI contract.
- Validation: shared schema validation between clients and server where appropriate.
- Tests: unit tests for domain rules, integration tests for API/database, and end-to-end tests for critical ride flows.
- CI: GitHub Actions within free-tier limits.

Choose tools based on current support, device constraints, maintenance, licensing, and free-tier limits. Do not commit to a hosted vendor until its data processing, regional availability, pricing, and exit path are understood.

## 4. Backend modules

- `auth`: authentication, sessions, account recovery.
- `users`: passenger profiles and account state.
- `drivers`: driver profile and onboarding workflow.
- `vehicles`: vehicle records and eligibility.
- `service_areas`: pilot boundaries and operating hours.
- `pricing`: versioned fare policies and quote calculation.
- `rides`: authoritative ride state machine and event history.
- `dispatch`: candidate selection, offer expiry, acceptance locking.
- `tracking`: time-limited location updates for active rides.
- `safety`: reports, escalation, emergency contacts and restricted workflows.
- `payments`: initially an interface/ledger boundary only; no money movement until reviewed.
- `support`: tickets and case handling.
- `admin`: permissions, configuration and audit views.

## 5. Core technical rules

- The server is the source of truth for ride state, price calculations, assignment, and permissions.
- Use database transactions and uniqueness/locking rules to prevent multiple drivers accepting the same ride.
- Every state transition creates an immutable ride event with actor, timestamp, and reason.
- Location updates are accepted only from an authenticated, assigned driver during an active trip or approved dispatch window.
- Realtime messages must be authorized per ride; never broadcast all drivers or passenger locations.
- Use idempotency keys for ride creation, offer acceptance, cancellation, and any future payment operation.
- Store timestamps in UTC; render local time in the client.
- Use explicit money units (integer minor units plus ISO currency code); do not use floating-point arithmetic for money.
- Keep secrets in environment/secret management, never in Git.
- Use migrations for all database changes.

## 6. Initial repository layout

```text
MITHAQ/
  apps/
    passenger/
    driver/
    admin/
  backend/
    src/
      modules/
      shared/
    tests/
  packages/
    contracts/
    validation/
    localization/
  database/
    migrations/
    seeds/
  docs/
  .github/
    workflows/
```

Create folders with actual application code only when the stack and first vertical slice are agreed. Avoid empty scaffolding that suggests functionality exists when it does not.

## 7. First vertical slice

Implement a non-production demonstration of:
1. Passenger creates a ride request with mock locations.
2. Backend validates and persists the request.
3. A mock driver receives an offer.
4. Driver accepts with concurrency protection.
5. Passenger sees the updated ride state.
6. Trip PIN is verified before boarding.
7. Trip is completed and an event history is visible.

Use synthetic users and locations only. No real identity documents, live tracking, payments, or production credentials.

## 8. Deployment boundary

Development and test environments must be isolated from any future pilot. Before public deployment, complete security review, privacy assessment, legal/insurance validation, operational support planning, backup/restore testing, and incident response preparation.
