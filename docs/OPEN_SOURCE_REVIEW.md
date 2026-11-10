# Open-Source Reference Review — MITHAQ (Draft 0.1)

Review date: 2026-11-10. A repository appearing in search results is not automatically safe, maintained, production-ready, or suitable for direct integration. Before importing code, inspect its exact LICENSE file, dependencies, recent commits, security advisories, build instructions, and external service requirements.

## Candidate references

### 1. Autofleet/locomotion
- URL: https://github.com/Autofleet/locomotion
- Public description: React Native passenger app; MIT license is displayed in the repository result.
- Potential value: passenger app UX and React Native patterns.
- Limitation: described as beta and pre-integrated with Autofleet's ride engine; not a self-contained open dispatch backend.
- Decision: reference only; do not import wholesale.

### 2. adam-nelson/openride
- URL: https://github.com/adam-nelson/openride
- Public description: rider, driver, admin apps; Supabase/Postgres, MapLibre, Valhalla; Apache-2.0 is displayed in the repository result.
- Potential value: modular product layout, spatial stack, architecture/compliance documentation.
- Limitation: appears early-stage; verify current source, license text, dependencies, and completeness before any reuse.
- Decision: strongest architecture reference candidate for a deeper manual review, not a dependency to adopt blindly.

### 3. rajkandula/uber-lyft-clone (Kova)
- URL: https://github.com/rajkandula/uber-lyft-clone
- Public description: Next.js rider/driver/admin application, Socket.IO, MongoDB, Redis, H3, MapLibre, Photon, OSRM; MIT is stated in its public description.
- Potential value: dispatch concepts, realtime boundaries, geospatial driver lookup, web admin.
- Limitation: technology choices differ from the proposed mobile-first/PostgreSQL direction; verify LICENSE file and project maturity.
- Decision: study selected patterns; do not copy the whole stack.

### 4. EbubeEvan/Lyfter
- URL: https://github.com/EbubeEvan/Lyfter
- Public description: React Native/Expo ride booking, driver map, payments and history.
- Potential value: UI flow reference.
- Limitation: its page says to see LICENSE for details; license must be verified from the repository before any reuse. Uses external services such as Clerk, Google Maps and Stripe.
- Decision: visual/functional study only until license and dependencies are verified.

## Reuse policy

- Prefer implementing MITHAQ's own domain model and business rules.
- Reuse a library only when its license is compatible with the intended distribution and commercial use.
- Preserve copyright and license notices for any reused source.
- Record the exact upstream repository, commit hash, files reused, modifications, license, and review date in `THIRD_PARTY_NOTICES.md`.
- Do not import code that requires paid services without a cost and vendor-dependency review.
- Never copy competitor proprietary code or private APIs.
- Run dependency and security checks before merging third-party code.

## Current decision

No third-party application source has been merged into MITHAQ yet. This is deliberate: repository search snippets are not enough to establish code quality, complete license obligations, or production suitability. The next step is a file-by-file review of the best candidates and selective adaptation of proven, compatible components.


## Follow-up source inspection — 2026-11-11

The two strongest candidates were inspected beyond search snippets:

### OpenRide — architecture reference, not a ready-made base

- Repository: https://github.com/adam-nelson/openride
- GitHub repository metadata reports Apache-2.0; the upstream LICENSE file was fetched and is the Apache License 2.0.
- Its README describes a multi-app Expo rider/driver + Next.js admin monorepo using Supabase/PostGIS/Realtime/Storage/Edge Functions, MapLibre, Valhalla, and Vitest/Playwright/Maestro.
- Its own README describes the project as an MVP scaffold and says end-to-end testing is still pending, despite its claimed single-operator feature completeness.
- Its last-pushed metadata is 2026-07-28 and the repository is small/early-stage. This is not enough evidence to trust its ride lifecycle or security without a full test run.
- Useful for: mobile-app separation, Valhalla integration, document/compliance records, incident/fatigue concepts, test architecture, and modular boundaries.
- Decision: architecture and checklist reference only. Do not import the monorepo or treat its feature claims as verified.

### Kova — selective product and simulator reference, with a security warning

- Repository: https://github.com/rajkandula/uber-lyft-clone
- GitHub repository metadata reports MIT; the upstream LICENSE file was fetched and contains the MIT grant and notice requirement.
- Its code uses Next.js, MongoDB, Redis, Socket.IO, H3, MapLibre, Photon and OSRM, so it is not a compatible drop-in for MITHAQ's Vite + Supabase/PostGIS architecture.
- Its driver simulator is a useful idea for future automated end-to-end testing: it simulates driver GPS and ride progression. MITHAQ should build its own simulator against its own authenticated RPCs and test database, without copying credentials or insecure shortcuts.
- Security finding in the inspected `server.js`: `isRideMember()` returns `true` when Redis is unavailable or errors. This is fail-open authorization for ride-room subscriptions and location relays. MITHAQ must never adopt that behavior; inability to verify ride membership must deny access.
- Decision: study selected UX and simulator patterns only. Do not transplant its server or realtime implementation.

## Mapping and routing decision update

- Keep MapLibre as the map renderer; it does not lock MITHAQ to a single routing provider.
- Keep OSRM for the current tiny closed test only, with the existing one-request-per-second database gate and no commercial reliance on the public demo server.
- Run a later regional benchmark for Algeria with OSRM and Valhalla using representative city, suburban, rural, and intercity routes. Compare route success, detours, ETA plausibility, geometry, response time, and provider terms.
- Evaluate Photon or another geocoder separately for Arabic/French place search; do not assume that a routing engine supplies reliable address search.
- Do not self-host a country/planet routing graph on the current free Supabase setup; regional graph hosting requires separate compute, storage, updates, and monitoring.

## Integration gate

No upstream application code has been merged as part of this review. Before any future reuse, record the exact upstream commit, affected files, license/NOTICE obligations, dependency changes, security review, and tests in `THIRD_PARTY_NOTICES.md`. A permissive license does not make code secure or production-ready.
