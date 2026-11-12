# Third-Party Notices

MITHAQ uses the following third-party packages and services. No third-party ride-hailing application source code has been copied into the repository.

## Integrated software dependencies

- [Capacitor Core](https://github.com/ionic-team/capacitor) — version 8.6.0, MIT. Provides the native runtime bridge.
- [Capacitor Android](https://github.com/ionic-team/capacitor) — version 8.6.0, MIT. Provides the Android application shell.
- [Capacitor CLI](https://github.com/ionic-team/capacitor) — version 8.6.0, MIT. Generates and synchronizes the native project.
- [Capgo Background Geolocation](https://github.com/Cap-go/capacitor-background-geolocation) — version 8.6.0, MPL-2.0. Used for Android location foreground service and native authenticated location POSTs. No upstream source files have been copied or modified.
- [MapLibre GL JS](https://github.com/maplibre/maplibre-gl-js) — version pinned in package-lock.json, BSD-3-Clause; used as the map renderer. Preserve its licence notice in distributed builds.
- [Supabase JS](https://github.com/supabase/supabase-js) — version pinned in package-lock.json, MIT; used for authentication and database access.
- [Lucide](https://github.com/lucide-icons/lucide) — version pinned in package-lock.json, ISC; used for interface icons.

## External data and service references

- [Project OSRM](https://github.com/Project-OSRM/osrm-backend) — BSD-2-Clause; external road-routing software/service. Public demo use is for low-volume non-commercial tests only and has no production SLA.
- [OpenFreeMap](https://openfreemap.org/) — hosted map style/tile service; service terms and capacity are separate from the MapLibre software licence.

## Reviewed but not integrated

- [Traccar Client SDK](https://github.com/traccar/traccar-client-sdk) — Apache-2.0; reviewed as an alternative native tracking SDK, but not integrated. MITHAQ uses Capgo Background Geolocation for the current Android proof of concept.

Preserve upstream copyright and licence notices when distributing dependency binaries. Keep exact package versions and lockfile entries. Update this register whenever a dependency is added, removed or changed.
