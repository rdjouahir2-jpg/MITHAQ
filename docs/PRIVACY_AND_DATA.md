# MITHAQ privacy and data-handling notes

This is a technical inventory for the closed test, not a complete privacy notice or legal assessment.

## Data currently processed

| Data | Why it is used | Current storage / access |
|---|---|---|
| Email and display name | Authentication and account identification | Supabase Auth and the user's profile |
| Pickup/destination labels and coordinates | Quote calculation, dispatch, and trip display | Short-lived fare quote and ride record; passenger and assigned driver receive only the trip data required |
| Road route geometry | Display the route and preserve the quoted route | Fare quote and ride JSON geometry |
| Driver GPS fix and accuracy | Find nearby drivers and show the assigned driver during an active trip | One current row per driver; no location history table |
| Boarding PIN hash | Verify the passenger boards the correct trip | Hash stored on the ride; plaintext PIN returned only once to the passenger |
| Ride events | State history and auditability | Ride event table, participant read access |
| Safety reports and ratings | Handle issues and quality feedback | Restricted participant RPCs and admin-only review functions |
| Admin audit records | Accountability for account/driver/vehicle/safety decisions | Admin/server-only access |

## Location minimization

- A driver location is accepted only from an authenticated, approved driver with an active account, an approved vehicle, online or busy status, and GPS accuracy up to 100 metres.
- Dispatch uses only recent fixes (90 seconds) and an exact PostGIS radius check.
- The passenger receives the assigned driver's location only during an active ride and only as a participant.
- The location table stores one latest fix per driver, not a trail/history.
- A trigger deletes the fix immediately when the driver transitions to offline.
- The maintenance worker deletes any remaining fix older than five minutes.
- No background GPS is claimed in the browser build; the driver must keep the web app foregrounded for this test.

## Retention and deletion still to define

- Expired fare quotes are deleted by the maintenance worker after they are more than 24 hours past expiry.
- Ride records, route geometry, ride events, ratings, safety reports, and audit logs currently have no automatic retention/deletion schedule.
- Before a pilot, define retention periods, account deletion/export workflows, legal holds for incidents, backup expiry, and deletion from backups.
- Avoid entering real identity documents, licence scans, phone numbers, or sensitive personal information in the closed test.

## Security boundaries

- The browser receives only the Supabase URL and anon/publishable key. The service-role key remains in server-side Edge Function secrets.
- RLS is enabled on protected tables; privileged commands use security-definer RPCs with explicit role/participant checks.
- Raw driver coordinates, fare quote writes, route validation, dispatch, audit writes, and safety-report writes are not direct client table operations.
- No biometrics or facial recognition are collected in this build.

## Before a real pilot

Complete a data-protection impact review, publish an accurate Arabic/French privacy notice, define controller/processor roles and hosting location, confirm applicable Algerian data-protection requirements, obtain necessary consent/notice for GPS tracking, establish access logging and breach response, and document retention/deletion. Do not treat these technical controls as legal compliance by themselves.
