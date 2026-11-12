# MITHAQ — Open-source foundations review

Reviewed on 2026-11-12. This is a technical shortlist, not an endorsement or proof of production readiness. Upstream code, dependencies, security posture, maintainers and licence notices must be reviewed before copying code or deploying.

## Candidates and integrated components

| Project | Licence observed | Useful material | Decision |
|---|---|---|---|
| [Kova / uber-lyft-clone](https://github.com/rajkandula/uber-lyft-clone) | MIT (upstream LICENSE checked) | Rider/driver/admin workflows, realtime dispatch, MapLibre, Photon/OSRM integration | Reference for product flows and architecture. Do not transplant its full stack blindly. |
| [OpenRide](https://github.com/adam-nelson/openride) | Apache-2.0 (upstream LICENSE checked) | Compliance-first operator model, driver/vehicle eligibility, incidents, fatigue and audit concepts | Reference for operational/compliance domain and modular boundaries. |
| [Namma Yatri](https://github.com/nammayatri/nammayatri) | AGPL-3.0 (repository licence metadata) | Large-scale direct-to-driver mobility domain and product decisions | Study only unless MITHAQ explicitly accepts AGPL obligations and legal review approves reuse. |
| [Taluxi](https://github.com/sitatec/Taluxi-Open-Source) | GPL-3.0 | Flutter passenger/driver structure and location services | Educational reference only; GPL obligations and backend dependencies make it unsuitable for blind copying. |
| [Capgo Background Geolocation](https://github.com/Cap-go/capacitor-background-geolocation) | MPL-2.0 | Android/iOS native background location, foreground service notification, native HTTP delivery | Integrated as a pinned Capacitor 8 plugin for the Android proof of concept. Native device testing remains required. |
| [Traccar Client SDK](https://github.com/traccar/traccar-client-sdk) | Apache-2.0 | Native location service, offline queue and retry architecture | Reviewed alternative only; not integrated in the current build. |

## MITHAQ integration policy

1. Prefer independently implemented domain logic and maintained libraries over copying entire applications.
2. Preserve upstream copyright and licence notices whenever code is reused. Keep a software bill of materials and record exact package versions.
3. Never copy secrets, demo credentials, production data, branding or proprietary assets.
4. A GitHub project describing itself as “production-ready” is not evidence of security, legal compliance, reliability or real-world suitability.
5. Public OSM tiles, public geocoders and demo routing endpoints have usage policies and are not guaranteed free production backends. Select a compliant provider or self-host before a public pilot.
6. Keep payment, wallet, biometric recognition and live passenger tracking disabled until their legal, privacy, security and operational requirements are met.

## Current implementation boundary

MITHAQ is a Vite/React application wrapped by Capacitor for Android. The Android shell is generated in CI and includes the Capgo background-location plugin. The native service posts authenticated locations to a Supabase Edge Function, which validates and calls the protected database RPC. This is code-level integration only: APK compilation, physical-device GPS, background reliability and the full two-phone ride lifecycle still require verification. The native plugin currently has no durable offline location queue.

The app still depends on Supabase migrations, Edge Functions, Realtime and server-side authorization. Client-side domain validation never replaces authoritative database validation or RLS.
