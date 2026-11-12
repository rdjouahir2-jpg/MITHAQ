# MITHAQ backend setup and closed-test runbook

This runbook connects the committed client and database to a dedicated test Supabase project. It does not create a production transport service. Never place a Supabase service-role key in the browser, GitHub Pages variables or an Android package.

## 1. Configure a dedicated test Supabase project

Use the existing MITHAQ test project only after confirming it is the intended non-production project. Keep it separate from any future production project.

In Supabase Auth settings:

- Enable email/password sign-up.
- For a closed test only, email confirmation may be disabled if immediate two-phone testing is required. Re-enable it before any wider pilot.
- Set the Site URL to https://rdjouahir2-jpg.github.io/MITHAQ/.
- Add https://rdjouahir2-jpg.github.io/MITHAQ/ and https://rdjouahir2-jpg.github.io/MITHAQ to allowed redirect URLs.

## 2. Apply database migrations

The repository currently contains 31 ordered migrations: 202611100001 through 202611100023, followed by 202611110001 through 202611110008. The latter add fare negotiation, final fare snapshots, security/performance hardening, driver earnings, cancellation, document verification, support/notifications and the financial ledger.

The branch has not applied these new migrations to the hosted test project. Do not treat a green frontend build as evidence that the hosted database is current.

The approved deployment workflow applies migrations and deploys functions, but it requires an explicit manual DEPLOY confirmation and configured GitHub secrets. Review the target project and migration diff before authorizing it. Do not paste secrets into chat.

Run the database suite locally or through GitHub Actions before any hosted rollout:

~~~sh
supabase start
supabase test db
~~~

## 3. Bootstrap the first test administrator

Create your own account from the MITHAQ sign-up screen and confirm the email if confirmation is enabled. Then open the Supabase SQL Editor and run the following after replacing the email with the exact email you registered:

~~~sql
do $$
declare
  v_admin_id uuid;
begin
  select id into v_admin_id
  from auth.users
  where lower(email) = lower('YOUR_ADMIN_EMAIL');

  if v_admin_id is null then
    raise exception 'Register and confirm the admin email first';
  end if;

  update public.profiles
    set account_status='active', updated_at=now()
  where id=v_admin_id;

  insert into public.user_roles(user_id,role)
  values(v_admin_id,'admin')
  on conflict do nothing;
end;
$$;
~~~

This is a one-time manual bootstrap because no user can grant themselves the administrator role. After this, use the in-app admin screen to activate other test accounts and review driver applications.

## 4. Configure a small non-commercial test area and fare policy

The quote service refuses trips outside an active service area and refuses to invent a fare when no area-specific policy exists.

In the SQL Editor, create a polygon for the actual test area. Replace the four longitude/latitude values with the corners of the area you intend to use:

~~~sql
insert into public.service_areas(name,boundary,is_active)
values (
  'MITHAQ CLOSED TEST AREA',
  extensions.st_multi(
    extensions.st_makeenvelope(MIN_LONGITUDE,MIN_LATITUDE,MAX_LONGITUDE,MAX_LATITUDE,4326)
  )::extensions.geography,
  true
)
returning id;
~~~

Use the returned UUID to add an area-specific fare policy. Amounts are in centimes; choose clearly labelled test values and do not leave placeholders in the SQL:

~~~sql
insert into public.fare_policies(
  service_area_id,version,currency_code,base_amount_minor,
  distance_rate_minor,time_rate_minor,minimum_amount_minor,is_active
)
values (
  'PASTE_RETURNED_SERVICE_AREA_UUID',1,'DZD',
  BASE_CENTIMES,PER_KM_CENTIMES,PER_MINUTE_CENTIMES,MINIMUM_CENTIMES,true
);
~~~

The service area must contain both phones and the route. Keep the first test small and non-commercial.

## 5. Deploy the Edge Functions

The approved backend workflow deploys:

- create-fare-quote with JWT verification enabled.
- dispatch-maintenance with its separate cron-secret check.
- driver-location with gateway JWT verification disabled because the function itself validates the Supabase bearer token before calling record_driver_location.

Equivalent CLI commands:

~~~sh
supabase functions deploy create-fare-quote
supabase functions deploy dispatch-maintenance --no-verify-jwt
supabase functions deploy driver-location --no-verify-jwt
~~~

Configure the required server-side secrets in Supabase/GitHub Actions:

- SUPABASE_ACCESS_TOKEN and SUPABASE_DB_URL for the deployment workflow.
- MITHAQ_CRON_SECRET for scheduled maintenance.
- Supabase runtime environment values SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase; the service-role key must remain server-side.
- ALLOWED_ORIGIN must be the GitHub Pages origin https://rdjouahir2-jpg.github.io (origin only, no path).
- ROUTING_BASE_URL is an HTTPS OSRM-compatible endpoint.

For a tiny non-commercial test only, https://router.project-osrm.org may be used subject to the demo server's usage limits and lack of uptime guarantee. It must not become MITHAQ's commercial routing dependency.

## 6. Schedule dispatch maintenance

The dispatch-maintenance function expires timed-out offers, retries recent requests that did not find a driver, removes old expired fare quotes, and deletes stale driver GPS fixes. A database trigger also deletes the current driver location when the driver goes offline.

Configure a scheduled HTTP POST to:

~~~text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/dispatch-maintenance
~~~

Include header x-mithaq-cron-secret: YOUR_CRON_SECRET. Run it once per minute during the closed test. The cron secret must never appear in the browser or Android package.

## 7. Connect the client

The public browser configuration lives in src/lib/public-config.ts. It contains only the test project's Project URL and public publishable/anon key. Never put SUPABASE_SERVICE_ROLE_KEY or any server secret in this file or a VITE_* variable.

The Android APK is generated by GitHub Actions as a debug artifact. It uses the same public client configuration as the web app; native GPS uploads use the signed-in driver's bearer token and the public key.

## 8. Two-phone test: passenger and driver about 500 metres apart

1. Confirm the approved database migrations and all three Edge Functions are deployed to the dedicated test project.
2. Download the mithaq-android-debug-apk artifact from a successful GitHub Actions run and install it on both Android phones.
3. Create two separate accounts. Use one as passenger and one as driver.
4. An administrator activates both accounts. The driver applies, submits vehicle details, and uploads the four required current documents: identity card, driving licence, vehicle registration and insurance. An administrator reviews and approves each document, the vehicle and the driver.
5. Confirm the service area and fare policy include both phone locations and the planned route.
6. Put the phones about 500 metres apart, enable mobile data and GPS, and keep both apps open.
7. On the driver phone, tap Online and accept the location-sharing explanation. Grant location and notification permissions. Confirm the persistent MITHAQ tracking notification appears.
8. On the passenger phone, choose pickup and destination points inside the test area, calculate the fare and request the ride.
9. On the driver phone, confirm the offer appears, accept it, advance to arrival, and enter the passenger's one-time boarding PIN.
10. Start and complete the trip. Confirm both phones show the expected state changes and the passenger sees fresh driver positions.
11. Lock the driver phone screen for 10 minutes while moving a short, safe distance. Confirm tracking continues.
12. Tap Offline and verify that tracking stops and new location writes are rejected.

Keep the first test non-commercial and use consenting participants. If legal permission for an actual passenger journey is unclear, test with stationary vehicles or on private property only.

## 9. What this test does not prove

- Firebase/FCM push notifications are not yet integrated; current notifications are durable in-app records with Realtime and polling.
- The background GPS plugin does not provide a durable offline location queue; a failed native POST can be dropped.
- This does not verify identity, licence, insurance or legal eligibility beyond the documents reviewed in the app.
- No payment gateway, wallet, bank transfer API or driver cash settlement is connected.
- It does not establish Algerian transport permissions, insurance coverage, consumer terms, privacy compliance, staffed support, emergency response, production monitoring or backup/restore readiness.

Do not carry paying passengers or launch publicly until the relevant legal, insurance, safety, privacy, operational, security and reliability requirements have been independently verified.
