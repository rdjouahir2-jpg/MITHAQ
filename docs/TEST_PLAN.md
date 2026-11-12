# MITHAQ test plan

All scenarios are for a dedicated test project and invited accounts only. They do not authorize commercial or public transport activity.

## A. Account and onboarding

- [ ] Create an admin/passenger account and confirm its email if enabled.
- [ ] Bootstrap the first admin through the SQL procedure in BACKEND_SETUP.md.
- [ ] Create a second account on the driver's phone.
- [ ] Confirm the admin can activate the second account.
- [ ] Confirm a pending account cannot request a ride or become an online driver.
- [ ] Submit driver and vehicle details from the second account.
- [ ] Upload the four required current driver documents: identity card, driving licence, vehicle registration and insurance.
- [ ] Approve the documents, vehicle and driver through the admin workflow.
- [ ] Confirm a rejected or incomplete driver profile cannot become available.

## B. Passenger quote and request

- [ ] Select pickup and destination points inside the configured test polygon.
- [ ] Confirm the server route is displayed and fare is calculated from the active test policy.
- [ ] Confirm a point outside the service area is rejected.
- [ ] Confirm malformed coordinates and unsupported categories are rejected.
- [ ] Confirm a quote expires after three minutes and can be consumed only once.
- [ ] Confirm a passenger cannot create a second active ride.
- [ ] Confirm the client cannot insert or alter fare quotes or quoted amounts directly.

## C. Driver matching and offer lifecycle

- [ ] Driver must have an approved profile, approved vehicle, active account, online status, and fresh GPS with accuracy no worse than 100 m.
- [ ] Confirm drivers outside the 7 km radius do not receive the offer.
- [ ] Confirm the same driver does not receive multiple simultaneous offers.
- [ ] Confirm an offer expires after 45 seconds.
- [ ] Confirm decline is recorded and maintenance can retry the offer set.
- [ ] Confirm a driver cannot accept an expired offer.
- [ ] Confirm two sessions cannot accept the same ride.
- [ ] Confirm a busy driver is excluded from new dispatch but continues sending location for the active ride.

## D. Boarding and trip state

- [ ] Driver moves through accepted → driver_arriving → arrived.
- [ ] Wrong PIN is rejected.
- [ ] Correct six-digit PIN allows boarding.
- [ ] Driver can start and complete the trip.
- [ ] Passenger and driver see state changes.
- [ ] Passenger sees assigned driver and approved vehicle details only after assignment.
- [ ] Driver sees only the assigned passenger name and trip details.
- [ ] Participant-only tracking returns the driver's fresh position; unrelated accounts are denied.
- [ ] Passenger cannot cancel after boarding or during an in-progress trip.
- [ ] Driver returns offline after completion.

## E. Safety, rating and administration

- [ ] Passenger can submit a safety report for their own trip.
- [ ] An unrelated account cannot attach a report to someone else's ride.
- [ ] Admin can view and update safety reports; changes are audited.
- [ ] Passenger and driver can each submit one rating after completion.
- [ ] Duplicate ratings and ratings before completion are rejected.
- [ ] Admin can view recent rides and pending onboarding.
- [ ] Non-admin accounts cannot use admin RPCs.
- [ ] Support ticket creation, staff replies and durable in-app notifications work.

## F. Two-phone and Android device checks

- [ ] Install the same mithaq-android-debug-apk artifact on two Android phones using separate passenger and driver accounts.
- [ ] Put the phones about 500 metres apart and keep them on mobile data.
- [ ] Driver taps Online, accepts the location-sharing explanation and grants location plus notification permissions.
- [ ] Confirm the persistent tracking notification appears.
- [ ] Confirm fresh driver GPS positions reach only the participant-authorized passenger tracking view.
- [ ] Lock the driver phone screen for at least 10 minutes and move a short, safe distance.
- [ ] Confirm location continues while the app is backgrounded; record accuracy and update timestamps.
- [ ] Tap Offline and confirm the notification disappears and new location writes stop.
- [ ] Test denied/revoked location and notification permissions, poor accuracy, expired JWT, app swipe-away, force-stop, reboot and battery saver.
- [ ] Test mobile-data loss and recovery. Current native location delivery is best-effort and has no durable offline queue, so lost points may not be replayed.
- [ ] Confirm no service-role key appears in browser source, network requests, APK or GitHub Pages variables.
- [ ] Confirm logs contain no passwords, PINs, service-role keys or unnecessary precise-location data.

## G. Notification coverage

- [ ] In-app notifications appear while the app is open through Realtime or polling.
- [ ] Record that Firebase/FCM push delivery is not yet integrated; do not treat an in-app notification as a background push notification.

## Release decision

A test passes only when the server response and database state agree. Screenshots or a successful button click alone are not sufficient. Record failures and fix them before inviting a friend. If legal permission for a real passenger journey is unclear, test the workflow with stationary vehicles or on private property only.
