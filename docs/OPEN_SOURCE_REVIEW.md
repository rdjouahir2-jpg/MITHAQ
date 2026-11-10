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
