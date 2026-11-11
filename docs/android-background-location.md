# MITHAQ Android background driver location

## Architecture

The current hosted experience is a Vite/PWA. Browser geolocation is foreground-only for this use case; a service worker cannot keep GPS active after the page is suspended. Background driver tracking therefore runs in the Android native runtime, not in the service worker.

Use Capacitor 8 with `@capgo/background-geolocation` 8.4.0. The plugin runs a location foreground service and displays a persistent notification. MITHAQ deliberately does **not** request Android's broad `ACCESS_BACKGROUND_LOCATION` permission for ordinary driver-online tracking: the driver explicitly starts tracking while the app is visible, and Android's location foreground-service permission is the narrower fit. Revisit the permission only if a separate background-geofencing feature is introduced and approved.

## Native package versions

Pin the following versions together when generating the Android project:

- `@capacitor/core@8.6.0`
- `@capacitor/android@8.6.0`
- `@capacitor/cli@8.6.0` (development dependency)
- `@capgo/background-geolocation@8.4.0`

Then generate and sync the native project with Capacitor CLI. Do not hand-edit generated Gradle files before the first `cap sync`.

## Capacitor configuration

Use this configuration (merge it with any future platform settings):

```json
{
  "appId": "dz.mithaq.app",
  "appName": "MITHAQ",
  "webDir": "dist",
  "android": {
    "useLegacyBridge": true
  }
}
```

The legacy bridge option is required by the selected plugin to avoid its Android location watcher stopping after several minutes in the background.

## Android manifest requirements

The Android app manifest must include:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-feature android:name="android.hardware.location.gps" android:required="true" />
```

Do not add `ACCESS_BACKGROUND_LOCATION` for this flow. Android 14+ requires the location foreground-service type and its specific permission. Start the service only from the driver's visible, explicit Online action, after foreground location permission is granted. Android 13+ notification permission must also be requested so the persistent tracking notice is visible.

## Native start/stop flow

After the driver presses Online and the app has verified the driver is approved, fetch the current Supabase session and request only foreground location plus notification permissions. Start the native watcher with:

```ts
await BackgroundGeolocation.start({
  requestPermissions: false,
  backgroundTitle: "MITHAQ — موقع السائق",
  backgroundMessage: "موقعك يُرسل أثناء اتصالك لاستقبال الرحلات. اضغط لإيقاف الاتصال.",
  stale: false,
  distanceFilter: 20,
  minIntervalMs: 15000,
  url: `${SUPABASE_URL}/functions/v1/driver-location`,
  headers: {
    apikey: SUPABASE_PUBLISHABLE_KEY,
    Authorization: `Bearer ${session.access_token}`,
  },
}, (location, error) => {
  if (error) {
    // Show a visible tracking warning; never silently claim the driver is online.
    reportLocationError(error);
  }
});
```

The native endpoint validates the user JWT, rejects stale/low-accuracy/mock points, and calls the existing authenticated `record_driver_location` RPC. The RPC still enforces active account, approved driver, online/busy state, approved vehicle, coordinate bounds and timestamp freshness. It does not expose the private location table.

On Supabase auth token refresh, call `BackgroundGeolocation.updateHeaders({ headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${newAccessToken}` } })`. On Offline, logout, driver suspension, or trip termination when the driver has no further active work, call `BackgroundGeolocation.stop()` and set the driver offline through the existing RPC. A native service must never continue tracking a driver who has opted Offline.

## Reliability and limits

- Android can restart the foreground service after the app process is reclaimed, but a user force-stop, revoked permission, disabled location service, OEM battery policy, or expired JWT can stop delivery.
- The plugin's native HTTP delivery is best-effort and has no durable offline queue or automatic retry. The server's latest location is intentionally a single current fix, not a route history.
- Refresh the native Authorization header whenever Supabase refreshes the session. If the process is killed long enough for the JWT to expire, the endpoint rejects updates until the user reopens the app and refreshes the session. The UI must surface stale location and automatically mark the driver unavailable after the server-side freshness window.
- Never describe PWA-only geolocation as background tracking.
- Google Play review may require a location foreground-service declaration and a clear in-app disclosure because location is used for a core driver feature. The service must stop when that user-initiated work ends.

## Two-device release test

Use two independent Android devices (or one physical device and one Android emulator) with separate accounts:

1. Device A signs in as passenger; Device B signs in as approved driver.
2. Driver presses Online while the app is visible and grants location + notification permission.
3. Verify the persistent MITHAQ tracking notification appears on Device B.
4. Minimize the driver app, lock its screen for at least 10 minutes, and move the device a known distance. Verify the passenger map receives fresh timestamps and the driver's location changes.
5. Accept the passenger request on Device B, confirm pickup with the PIN, start and complete the ride.
6. Verify both devices receive ride status changes and the server creates exactly one financial snapshot.
7. Disable mobile data briefly, restore it, and verify recovery; record any missed interval because the native plugin does not queue offline points.
8. Press Offline and verify the persistent notification disappears and the private driver location row is deleted.
9. Repeat with denied location permission, denied notification permission, poor GPS accuracy, expired session, and Android battery optimization enabled.
10. Confirm a passenger account cannot call the driver location RPC or read another driver's private location.

A web CI run cannot replace this physical-device test. Do not release background tracking as production-ready until this checklist passes on the target Android versions and at least one OEM device with aggressive battery management.
