# MITHAQ

**منصة تنقّل ذكية قيد البناء للاختبار المغلق في الجزائر.**

MITHAQ is an Arabic RTL ride-hailing application foundation. The repository now contains a connected-client implementation and a Supabase backend, but the hosted test project has not yet been created or connected. This is **not a live transport service**.

## Implemented in source

- Email/password authentication and role-aware passenger, driver, and admin screens.
- Interactive MapLibre map with pickup/destination selection, browser GPS, and road-route geometry.
- Server-side area-specific fare quotes; no client-supplied price.
- PostGIS dispatch using approved drivers/vehicles, fresh GPS, and exact radius matching.
- Timed driver offers, accept/decline, one active ride per passenger, and one-time boarding PIN.
- Ride state machine, participant-only tracking, and foreground driver GPS while online/on a trip.
- Assigned driver and vehicle details for passengers; passenger name for the assigned driver.
- Admin account/vehicle/driver review, ride operations, safety reports, and audit records.
- Mutual post-trip ratings and scheduled offer-expiry/redispatch maintenance.
- Location minimization: one current driver fix, deleted on offline and cleaned when stale.

These are committed source capabilities. They are not evidence of a deployed backend or a successful two-phone trip.

## Repository and live preview

- GitHub repository: https://github.com/rdjouahir2-jpg/MITHAQ
- GitHub Pages: https://rdjouahir2-jpg.github.io/MITHAQ/

The public Supabase configuration file `src/lib/public-config.ts` is intentionally blank until a dedicated test project is connected. Until then, the Pages site displays a clear “backend not configured” screen rather than pretending to book rides.

## Local development

Requirements: Node.js 22 and npm.

```sh
npm ci
cp .env.example .env.local
# Add the test project's public URL and anon/publishable key to .env.local
npm run dev
```

Build:

```sh
npm run build
```

## Backend

There are currently 23 ordered SQL migrations in `supabase/migrations/`, local Supabase configuration, pgTAP security-contract tests, and GitHub Actions workflows for frontend/Deno checks and database tests.

Read [BACKEND_SETUP.md](docs/BACKEND_SETUP.md) before creating a test project. It covers:

- first-admin bootstrap without self-granting roles;
- service-area polygon and test fare policy;
- deploying the two Edge Functions and configuring server-only secrets;
- scheduling offer expiry and dispatch retry;
- connecting the public browser configuration;
- preparing two separate accounts for the two-phone test.

## Validation and release gates

- [Two-device test plan](docs/TEST_PLAN.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Prioritized feature backlog](docs/FEATURE_BACKLOG.md)
- [Privacy and data inventory](docs/PRIVACY_AND_DATA.md)
- [Algeria legal review](docs/ALGERIA_LEGAL_REVIEW.md)

**Do not carry paying passengers or launch publicly.** The Algerian VTC/taxi operating model, authorizations, insurance, privacy obligations, and emergency/support operations must be confirmed before any real-world passenger service. Driver approval in this app is a test-platform flag, not a legal permit.
