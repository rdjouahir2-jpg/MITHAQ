# MITHAQ

**منصة تنقّل ذكية قيد البناء للاختبار المغلق في الجزائر.**

MITHAQ is an Arabic RTL ride-hailing web application prototype connected to a dedicated Supabase test project. The current deployment is for invited, non-commercial testing only. It is not a licensed transport service and must not be used to carry paying passengers.

## Current verified deployment

As of 2026-11-10:

- GitHub Pages frontend is deployed: https://rdjouahir2-jpg.github.io/MITHAQ/
- The frontend build, TypeScript check, and both Edge Function Deno checks passed in GitHub Actions.
- All 23 committed database migrations were applied to the hosted Supabase test project.
- Server-only function configuration was set successfully.
- Both `create-fare-quote` and `dispatch-maintenance` Edge Functions were deployed successfully.
- A real email/password account was created through the deployed app.

These checks confirm deployment, not end-to-end ride readiness. The first administrator has not yet been bootstrapped, the test service area/fare policy and maintenance schedule still need configuration, and a complete two-phone trip has not yet been verified.

## Implemented in source

- Email/password authentication and role-aware passenger, driver, and admin screens.
- Interactive MapLibre map with pickup/destination selection, browser GPS, and road-route geometry.
- Server-side, area-specific fare quotes; the browser cannot choose the fare.
- PostGIS-based dispatch with approved driver/vehicle checks, fresh GPS, and radius matching.
- Timed driver offers, accept/decline, one active ride per passenger, and one-time boarding PIN.
- Ride state machine, participant-scoped tracking, and foreground driver GPS.
- Admin account/vehicle/driver review, ride operations, safety reports, audit records, and mutual post-trip ratings.
- Location minimization: one current driver fix, cleared on offline and cleaned when stale.

These are source capabilities. A feature is not considered verified merely because its screen or function exists.

## Repository and preview

- GitHub repository: https://github.com/rdjouahir2-jpg/MITHAQ
- GitHub Pages: https://rdjouahir2-jpg.github.io/MITHAQ/

The browser configuration in `src/lib/public-config.ts` contains only the Supabase project URL and publishable/anon key. These are public client values protected by database RLS. Never put a service-role key, database password, access token, or cron secret in browser code.

## Local development

Requirements: Node.js 22 and npm.

```sh
npm ci
cp .env.example .env.local
# Add the test project's public URL and anon/publishable key to .env.local
npm run build
```

## Backend and test runbooks

- [Backend setup and closed-test runbook](docs/BACKEND_SETUP.md)
- [Two-device test plan](docs/TEST_PLAN.md)
- [Implementation status](docs/IMPLEMENTATION_STATUS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Feature backlog](docs/FEATURE_BACKLOG.md)
- [Privacy and data inventory](docs/PRIVACY_AND_DATA.md)
- [Algeria legal review](docs/ALGERIA_LEGAL_REVIEW.md)

## Release restrictions

Do not launch publicly or carry paying passengers until the operating model and required Algerian permissions, insurance, driver/vehicle verification, privacy, emergency/support operations, security review, monitoring, backups, and Android background-location behavior have been independently verified. An in-app admin approval is not a legal transport permit.
