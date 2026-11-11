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


## Geospatial and background-tracking review — 2026-11-11

| Component | Upstream | Licence / role | MITHAQ decision |
|---|---|---|---|
| Map renderer | [MapLibre GL JS](https://github.com/maplibre/maplibre-gl-js) | BSD-3-Clause; already installed and used by `src/components/MapPicker.tsx` | Keep. Do not replace the working map renderer. |
| Vector map tiles | [OpenFreeMap](https://openfreemap.org/) | Hosted tile/style service built on open map data; service terms and capacity are separate from MapLibre's software licence | Keep as a development source only until a sustainable production tile strategy is selected. |
| Road routing | [OSRM](https://github.com/Project-OSRM/osrm-backend) | BSD-2-Clause; route, table, nearest and GPS map-matching APIs | Keep the current gated public-demo use for closed tests only. Benchmark regional Algeria extracts before selecting production routing. |
| Alternative routing | [Valhalla](https://github.com/valhalla/valhalla) | MIT; OSM routing with flexible costing and regional tiled graph | Benchmark against OSRM for Algeria; do not run a national graph on the current free Supabase setup. |
| Place search / geocoding | [Photon](https://github.com/komoot/photon) | Open-source OSM geocoder with multilingual search, reverse geocoding and location bias | Candidate for Arabic/French pickup and destination search. Public demo is rate-limited and has no SLA; self-host or procure a reliable service before launch. |
| Native background GPS | [Traccar Client SDK](https://github.com/traccar/traccar-client-sdk) | Apache-2.0; Kotlin Multiplatform, native Android/iOS, Flutter and React Native wrappers | Strong candidate for a native Android integration. It provides a persistent location service, local SQLite queue, retry/backoff and custom HTTP headers. It is not integrated yet. |

### Traccar SDK integration constraints

- The SDK's uploader sends OsmAnd-style form fields (`id`, `lat`, `lon`, `timestamp`, and optional accuracy/speed/battery) and supports custom HTTP headers. This means an authenticated adapter can be built without exposing the private Supabase location table.
- The SDK requires Android background-location permission in its current manifest/runtime permission flow. This is a material change from the earlier Capgo proposal and requires a dedicated Google Play policy/privacy review. Do not request it silently or before the driver-facing disclosure and permission rationale are implemented.
- MITHAQ currently has a Vite/React web app, not a generated Capacitor/Android application. The likely integration path is Capacitor plus a small native Kotlin plugin wrapping the SDK; this must be prototyped and built in CI before being called complete.
- The adapter must authenticate every device report with a short-lived, revocable credential bound to one approved driver/device. A raw device ID is not authentication. Never put a Supabase service-role key in the Android app.
- The current `driver-location` Edge Function expects a bearer-authenticated JSON request, not the SDK's form protocol. Add a dedicated adapter endpoint or custom uploader; do not point the SDK directly at the existing function.
- Test offline queue replay, duplicate/idempotent reports, expired/revoked device credentials, sign-out, driver Offline, app force-stop, reboot, OEM battery restrictions, and location freshness before rollout.
