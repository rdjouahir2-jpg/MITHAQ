# MITHAQ — Open-source foundations review

Reviewed on 2026-11-10. This is a technical shortlist, not an endorsement or proof of production readiness. Upstream code, dependencies, security posture, maintainers, and licence notices must be reviewed again before copying code or deploying.

## Candidates

| Project | Licence observed | Useful material | Decision |
|---|---|---|---|
| [Kova / uber-lyft-clone](https://github.com/rajkandula/uber-lyft-clone) | MIT (upstream LICENSE checked) | Rider/driver/admin workflows, realtime dispatch, MapLibre, Photon/OSRM integration, deployment and test patterns | Reference implementation for product flows and architecture. Do not transplant its full stack blindly into the current Vite project. Review its dependencies, security and API limits first. |
| [OpenRide](https://github.com/adam-nelson/openride) | Apache-2.0 (upstream LICENSE checked) | Compliance-first operator model, driver/vehicle eligibility, incidents, fatigue and audit concepts; Supabase and MapLibre architecture | Reference for operational/compliance domain and modular boundaries. Its stated MVP status still requires independent validation. |
| [Namma Yatri](https://github.com/nammayatri/nammayatri) | AGPL-3.0 (repository licence metadata) | Large-scale direct-to-driver mobility domain and product decisions | Study only unless MITHAQ explicitly accepts AGPL obligations and legal review approves reuse. Not a drop-in starter. |
| [Taluxi](https://github.com/sitatec/Taluxi-Open-Source) | GPL-3.0 | Flutter passenger/driver structure and location services | Educational reference only: upstream explicitly warns its straight-line driver matching is not production routing. GPL obligations and backend dependencies make it unsuitable for blind copying. |

## MITHAQ integration policy

1. Prefer independently implemented domain logic and well-maintained libraries over copying entire applications.
2. Preserve upstream copyright and licence notices whenever code is reused. Keep a software bill of materials and record exact commit hashes for copied components.
3. Never copy secrets, demo credentials, production data, branding, or proprietary assets.
4. A GitHub project describing itself as “production-ready” is not evidence of security, legal compliance, reliability, or real-world suitability.
5. Public OSM tiles, public geocoders and demo routing endpoints have usage policies and are not a guaranteed free production backend. MITHAQ must select a compliant provider or self-host before a public pilot.
6. Keep payment, wallet, biometric recognition, and live passenger tracking disabled until their legal, privacy, security and operational requirements are met.

## Current implementation boundary

The repository currently remains a Vite/React web shell with a draft Supabase schema. The new `src/domain/ride.ts` file provides reusable client-side domain validation only. It does not replace authoritative server-side validation, database transactions, authentication, dispatch, or realtime services.
