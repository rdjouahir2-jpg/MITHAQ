# MITHAQ Android driver location

Updated: 2026-11-12

## Implemented in the feature branch

MITHAQ now has a Capacitor Android wrapper for the existing Vite/React client:

- Capacitor Core, Android and CLI are pinned to version 8.6.0.
- Capgo Background Geolocation is pinned to version 8.6.0 (MPL-2.0).
- The Android build uses relative asset paths and does not register the PWA service worker inside the native shell.
- Android uses a location foreground service with a visible ongoing notification. The service starts only after the driver explicitly enables availability and confirms the location-sharing explanation.
- The plugin sends location JSON directly from native Android code to the driver-location Edge Function. This does not depend on the WebView JavaScript callback remaining active.
- Requests include the driver's Supabase access token and public publishable/anon key. The Edge Function validates the JWT, native source marker, coordinates, accuracy, timestamp and simulated-location flag, then calls the protected record_driver_location RPC.
- The service stops when the driver turns availability off or signs out. Session token refresh events update native request headers while the app is running.
- The service requests foreground location and notification permissions. It does not request ACCESS_BACKGROUND_LOCATION; the location foreground service is started by the driver's explicit Online action while the app is visible.
- A zero distance filter and 15-second minimum native POST interval keep location heartbeats flowing while the driver is stationary.

The driver-location function is configured with verify_jwt = false because it validates the bearer token itself. The deployment workflow now includes this function. The hosted function is not deployed by this branch automatically.

## Important reliability limits

- Native location uploads are best-effort. This plugin version does not provide a durable offline queue or automatic retry for location POSTs; failed uploads can be dropped. Keep both phones on mobile data for the first closed test.
- The Android service persists its configured request headers so it can restart after the app process is killed. Supabase access tokens expire, however. When the app is running, auth refresh updates the headers; if the app remains terminated until the token expires, native uploads can be rejected until the app is opened and the session refreshes.
- Android manufacturer battery controls can still interrupt location collection. A user force-stop from Android settings prevents automatic service restart.
- This is a foreground location service, not a promise of uninterrupted tracking under every Android power-management condition.
- Firebase/FCM push delivery is not integrated. MITHAQ currently has durable in-app notifications, Realtime updates and polling; background push alerts are a separate task.
- No physical Android device test has been completed yet. CI compilation cannot prove GPS accuracy, OEM battery behavior or real-world delivery.

## Build and artifact

The GitHub Actions android-apk job generates the Android project, syncs Capacitor plugins and builds a debug APK. A successful run publishes the installable artifact named mithaq-android-debug-apk. This is a debug/sideload build, not a Play Store release or a production-signed APK.

## Closed test: two phones about 500 metres apart

1. First deploy the approved database migrations and Edge Functions to the dedicated test Supabase project. The feature branch is not deployed automatically.
2. Install the same debug APK on both Android phones.
3. Use separate accounts: one passenger account and one approved driver account.
4. The driver account must be active, have an approved vehicle, and have the four current required documents reviewed and approved by an administrator.
5. Configure a non-commercial test service area and fare policy that include both phone locations and the intended destination.
6. Put the phones about 500 metres apart. Keep mobile data and GPS enabled.
7. On the driver phone, tap Online, accept the location-sharing explanation, grant location and notification permissions, and verify the persistent MITHAQ tracking notification appears.
8. On the passenger phone, select pickup and destination points inside the test area, request a ride, and verify the driver receives an offer.
9. Accept the offer, confirm arrival and boarding with the one-time PIN, then advance and complete the trip. Confirm the passenger sees fresh driver positions and the correct ride states.
10. Lock the driver phone screen for 10 minutes while moving a short, safe distance. Confirm fresh positions continue to reach the passenger view.
11. Tap Offline and confirm the tracking notification disappears and the server stops accepting new location updates.

Keep this test non-commercial and limited to consenting participants. If legal permission for a real passenger journey is unclear, test the full workflow with stationary vehicles or on private property only.

## Further work before a wider pilot

- Durable offline location queue and idempotent replay.
- Device-bound revocable credentials or another safe token-refresh strategy for long-lived native service restarts.
- Firebase/FCM push delivery and end-to-end notification tests.
- Physical testing on the target Infinix/Android device and a second Android model, including screen lock, app swipe-away, force-stop, reboot, OEM battery restrictions, denied permissions and mobile-data loss.
- Privacy/Google Play policy review for location disclosure and retention.
