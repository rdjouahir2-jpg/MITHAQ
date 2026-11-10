# MITHAQ test plan

All scenarios below are for a dedicated test project and invited accounts only. They do not authorize commercial or public transport activity.

## A. Account and onboarding

- [ ] Create an admin/passenger account and confirm its email if enabled.
- [ ] Bootstrap the first admin through the SQL procedure in `BACKEND_SETUP.md`.
- [ ] Create a second account on the driver's phone.
- [ ] Confirm the admin can activate the second account.
- [ ] Confirm a pending account cannot request a ride or become an online driver.
- [ ] Submit driver and vehicle details from the second account.
- [ ] Approve the vehicle, then approve the driver.
- [ ] Confirm a rejected vehicle/driver cannot become available.

## B. Passenger quote and request

- [ ] Select pickup and destination points inside the test polygon.
- [ ] Confirm the server route is displayed on the map and the fare is calculated from the configured test policy.
- [ ] Confirm a point outside the service area is rejected.
- [ ] Confirm malformed coordinates and unsupported categories are rejected.
- [ ] Confirm a quote expires after three minutes.
- [ ] Confirm a quote can be consumed only once.
- [ ] Confirm a passenger cannot create a second active ride.
- [ ] Confirm the client cannot insert or alter fare quotes or quoted amounts directly.

## C. Driver matching and offer lifecycle

- [ ] Driver must have an approved profile, approved vehicle, active account, online status, and fresh GPS with accuracy no worse than 100 m.
- [ ] Confirm drivers outside the 7 km radius do not receive the offer.
- [ ] Confirm the same driver does not receive multiple simultaneous offers.
- [ ] Confirm an offer expires after 45 seconds.
- [ ] Confirm decline is recorded and the worker can exhaust/retry the offer set.
- [ ] Confirm a driver cannot accept an expired offer.
- [ ] Confirm two sessions cannot accept the same ride.
- [ ] Confirm a busy driver is excluded from new dispatch but continues sending location for the active ride.

## D. Boarding and trip state

- [ ] Driver moves through accepted → driver_arriving → arrived.
- [ ] Wrong PIN is rejected.
- [ ] Correct six-digit PIN allows boarding.
- [ ] Driver can then start and complete the trip.
- [ ] Passenger and driver see state changes.
- [ ] Passenger sees assigned driver and approved vehicle details only after assignment.
- [ ] Driver sees only the assigned passenger name and trip details.
- [ ] Participant-only tracking returns the driver's fresh position; unrelated accounts are denied.
- [ ] Passenger cannot cancel after boarding or during an in-progress trip.
- [ ] Driver returns offline after completion.

## E. Safety, rating, and administration

- [ ] Passenger can submit a safety report for their own trip.
- [ ] An unrelated account cannot attach a report to someone else's ride.
- [ ] Admin can view and update safety reports; changes are audited.
- [ ] Passenger and driver can each submit one rating after completion.
- [ ] Duplicate ratings and ratings before completion are rejected.
- [ ] Admin can view recent rides and pending onboarding.
- [ ] Non-admin accounts cannot use admin RPCs.

## F. Device and operational checks

- [ ] Test on two Android phones over mobile data, not only the same Wi-Fi.
- [ ] Test location permission granted, denied, revoked, and GPS accuracy poor.
- [ ] Keep the driver app foregrounded; background GPS is not supported by the browser test.
- [ ] Test a lost connection and reconnection on both phones.
- [ ] Confirm no service-role key appears in browser source, network requests, or GitHub Pages variables.
- [ ] Confirm Realtime publication and scheduled maintenance are active.
- [ ] Confirm error logs contain no PIN, password, service-role key, or precise location beyond what is operationally required.

## Release decision

A test passes only when the server response and database state agree. Screenshots or a successful button click alone are not sufficient. Record failures and fix them before inviting a friend. If legal permission for a real passenger journey is unclear, test the full app workflow with stationary vehicles or on private property only.
