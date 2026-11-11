# MITHAQ Android background driver location

## Current status

MITHAQ is currently a Vite/React web application. Browser geolocation is foreground-only for this use case; a service worker cannot keep GPS active after the page is suspended. The `driver-location` Supabase Edge Function is a protected ingestion endpoint, **not** an Android background GPS client. No native Android application or background tracker is integrated yet.

## Preferred SDK candidate: Traccar Client SDK

Repository: https://github.com/traccar/traccar-client-sdk  
Reviewed upstream commit: `e56ca0840656e785629d7d3d2b0b275a6c110489`  
Licence: Apache-2.0

The SDK is a Kotlin Multiplatform library with native Android/iOS APIs and Flutter/React Native wrappers. It provides:
- Android location foreground service and persistent notification.
- Local SQLite-backed position queue that survives app/process restarts.
- Retry with exponential backoff and wait-for-connectivity behavior.
- Battery-aware stationary detection and configurable location filtering.
- Custom HTTP headers, allowing authenticated delivery to a MITHAQ adapter.

Official documentation: https://www.traccar.org/traccar-client-sdk/

### Important permission and protocol findings

The current upstream Android manifest declares `ACCESS_BACKGROUND_LOCATION`, activity recognition, foreground-service location, notifications, boot receiver and wake lock. The SDK's permission flow checks for background location on Android 10+. This is broader than the previous Capgo proposal. Before integration, MITHAQ must implement a clear driver-facing explanation, request permissions only in the driver-online flow, document purpose/retention, and complete a Google Play policy review. Do not quietly merge or request broad location permission.

The SDK posts form-encoded OsmAnd-style fields:
- `id`: SDK device identifier
- `lat`, `lon`: coordinates
- `timestamp`: Unix seconds
- Optional `accuracy`, `altitude`, `speed`, `bearing`, `batt`, `charge`

Its `Config` supports custom HTTP headers. The current MITHAQ Edge Function expects a bearer-authenticated JSON body, so the SDK cannot call it directly. A dedicated adapter endpoint must validate a short-lived, revocable device credential bound to one approved driver/device, validate coordinate/time/accuracy bounds, enforce driver online/busy status, and call the existing protected database RPC. A device identifier alone is not authentication. Never embed a Supabase service-role key in the app.

## Integration architecture

1. Generate the Capacitor Android project for the existing Vite app and pin compatible Capacitor versions.
2. Implement a small native Kotlin Capacitor plugin that wraps Traccar SDK start/stop/state/log APIs.
3. On explicit driver Online action, verify driver approval and foreground session, present the disclosure, request required permissions, mint/refresh a revocable device credential, then start tracking.
4. Send SDK reports to a dedicated adapter endpoint. The adapter authenticates the device credential and forwards validated coordinates to the existing `record_driver_location` RPC; never write directly to the private location table from a client.
5. On Offline, logout, driver suspension, credential revocation or account deactivation, stop the SDK and revoke the device credential. The server must expire stale presence independently of the client.
6. Show tracking state, last successful upload time and errors in the driver UI. Never display Online as healthy when location reports are stale.

## Alternative

A custom native foreground service using Android Location APIs could avoid adopting the SDK's broad background permission flow, but would require MITHAQ to implement durable offline storage, retry, boot behavior, diagnostics and battery handling itself. Compare both options in a small Android proof of concept before committing.

## Two-device release test

Use two independent Android devices (or one physical device and one Android emulator) with separate accounts:

1. Device A signs in as passenger; Device B signs in as an approved driver.
2. Driver explicitly presses Online and sees the location disclosure and permission rationale.
3. Verify the persistent tracking notification appears.
4. Minimize the driver app, lock its screen for at least 10 minutes, and move the device a known distance. Verify fresh passenger-map positions and timestamps.
5. Accept the passenger request, confirm pickup with the PIN, start and complete the ride.
6. Disconnect mobile data briefly, restore it, and verify queued positions are retried without corrupting latest location.
7. Press Offline and verify tracking stops, the notification disappears, and server presence/location freshness is handled correctly.
8. Test denied/revoked permissions, expired/revoked device credentials, poor GPS accuracy, force-stop, reboot, Android battery restrictions, and network loss.
9. Confirm a passenger cannot submit driver location or read another driver's private location.

A web CI run cannot replace this physical-device test. Do not release background tracking until the Android build and this checklist pass on target Android versions and an OEM device with aggressive battery management.
