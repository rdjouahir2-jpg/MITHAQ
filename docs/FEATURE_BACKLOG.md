# MITHAQ feature backlog and prioritization

This backlog distinguishes working source code from features that require hosted services, legal review, operational staff, or native Android capabilities.

## Core closed-test slice — implemented in source

- [x] Arabic-first account creation and sign-in.
- [x] Passenger route-point selection, server route calculation, and area-bound fare quote.
- [x] Driver application and test vehicle submission.
- [x] Admin account activation and driver/vehicle test review.
- [x] PostGIS driver matching, expiring offers, accept/decline, and retry worker.
- [x] Ride state machine and one-time boarding PIN.
- [x] Realtime trip status and foreground GPS during active trips.
- [x] Passenger sees assigned driver and approved vehicle details.
- [x] Driver sees assigned passenger name and pickup/destination labels.
- [x] Participant-only trip tracking.
- [x] Safety-report workflow and two-way post-trip ratings.

Source implementation is not proof of a hosted deployment. See `docs/IMPLEMENTATION_STATUS.md`.

## Implemented in the current feature branch

- Driver-only completed-trip earnings history with finalized gross fare and completion time; explicitly not represented as net pay or settlement.
- Participant-authorized pre-boarding cancellation with reason audit, offer withdrawal, negotiation closure, and driver offline handling. No cancellation fee is charged.

## P1 — required before an invited field pilot

1. **Driver document verification:** private storage for driving licence, vehicle registration, insurance, expiry dates, manual review, and automatic expiry suspension. Use short-lived signed URLs; never expose document buckets publicly.
2. **Phone verification:** OTP flow and account recovery suitable for Algerian carriers; anti-SMS abuse limits.
3. **Native Android driver app:** background location permission, foreground service notification, battery-optimization guidance, crash reporting, and device matrix. A browser tab is not a reliable background tracker.
4. **Trip sharing:** expiring, revocable, read-only trusted-contact link with minimal data, access logs, and no public searchability.
5. **Real support operations:** support ticket queues, staffed hours, incident severity, escalation, and documented response ownership.
6. **Emergency operations:** only add an emergency button when an actual staffed response channel and escalation agreement exist. A button alone is not a safety service.
7. **French localization:** complete translations, language persistence, dates/numbers, and accessibility checks.
8. **Pickup search and geocoding:** trusted address search, reverse-geocoding provider, POI selection, and map attribution/usage review.
9. **Driver earnings ledger:** trip gross amount, platform commission, adjustments, cash collection, and transparent statements. Do not label gross fare as driver net earnings.
10. **Operational resilience:** monitoring, alerting, backups, restore drills, idempotency, rate limits, abuse detection, and load tests.

## Implemented in the current feature branch

- Bounded driver/passenger fare negotiation with alternating turns, expiry, accept/reject, and atomic ride assignment. This is CI-tested locally but not yet applied to the hosted database or validated with two live test accounts.

## P2 — only after the core service is reliable

- Scheduled rides and driver commitment/late-cancellation rules.
- Intercity service with separate operating boundaries, fares, and driver eligibility.
- Additional vehicle classes and accessibility preferences.
- Corporate/fleet accounts and delegated booking.
- Cash/electronic payment integration after legal, tax, and settlement design.
- Multi-wilaya rollout and localized service-area policies.
- Demand forecasting and dispatch optimization after sufficient lawful operational data exists.

## Explicitly deferred

- Automated facial recognition and biometric templates.
- Unstaffed emergency promises.
- Surge pricing without clear policy and fairness testing.
- Wallets or holding customer funds without licensed payment/settlement arrangements.
- Public launch while the legal VTC/taxi operating model remains unresolved.

## Next engineering order

1. Finish and pass migration + authorization tests.
2. Connect a dedicated Supabase test project and two test accounts.
3. Complete the non-commercial two-device functional test.
4. Add driver document upload and phone verification in a privacy-reviewed manner.
5. Build a native Android driver app before any test that depends on background GPS.
6. Obtain written legal and insurance clearance before transporting real passengers.
