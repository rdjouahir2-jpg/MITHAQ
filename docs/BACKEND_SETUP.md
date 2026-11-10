# MITHAQ backend setup and closed-test runbook

This runbook connects the committed client and database to a **separate test Supabase project**. It does not create a production transport service. Never place a Supabase service-role key in the browser, GitHub Pages variables, or an Android package.

## 1. Create and configure a test Supabase project

Create a new, empty Supabase project for MITHAQ testing. Keep it separate from any future production project.

In Supabase Auth settings:

- Enable email/password sign-up.
- For the closed test only, email confirmation may be disabled if you need immediate two-phone testing. Re-enable it before any wider pilot.
- Set the Site URL to `https://rdjouahir2-jpg.github.io/MITHAQ/`.
- Add `https://rdjouahir2-jpg.github.io/MITHAQ/` and `https://rdjouahir2-jpg.github.io/MITHAQ` to allowed redirect URLs.

## 2. Apply database migrations

Install the Supabase CLI, link the new project, then push migrations in order:

```sh
supabase login
supabase link --project-ref YOUR_TEST_PROJECT_REF
supabase db push
```

The repository currently contains migrations `202611100001` through `202611100019`. They install PostGIS and pgcrypto in the `extensions` schema, create RLS-protected tables, ride commands, dispatch, driver onboarding, service-area pricing, tracking, admin workflows, safety reporting, post-trip ratings, and offer-decline/driver-location lifecycle guardrails.

Run the database test suite locally before linking any real project:

```sh
supabase start
supabase test db
```

GitHub Actions also runs the local Supabase migration and pgTAP test workflow when database files change. A passing frontend build alone is not a database test.

## 3. Bootstrap the first test administrator

Create your own account from the MITHAQ sign-up screen and confirm the email if confirmation is enabled. Then open the Supabase SQL Editor and run the following after replacing the email with the exact email you registered:

```sql
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
    set account_status = 'active', updated_at = now()
  where id = v_admin_id;

  insert into public.user_roles(user_id, role)
  values (v_admin_id, 'admin')
  on conflict do nothing;
end;
$$;
```

This is a one-time manual bootstrap because no user can grant themselves the administrator role. After this, use the in-app admin screen to activate other test accounts and review driver applications.

## 4. Configure a test service area and fare policy

The quote service deliberately refuses trips outside an active service area. It also refuses to invent a fare if no area-specific policy exists.

In the SQL Editor, create a polygon for the test area you have actually chosen. Replace the four longitude/latitude values with the corners of that area; do not use a rectangle that extends into places you do not intend to test:

```sql
insert into public.service_areas(name, boundary, is_active)
values (
  'MITHAQ CLOSED TEST AREA',
  extensions.st_multi(
    extensions.st_makeenvelope(MIN_LONGITUDE, MIN_LATITUDE, MAX_LONGITUDE, MAX_LATITUDE, 4326)
  )::extensions.geography,
  true
)
returning id;
```

Use the returned UUID to add an area-specific fare policy. Amount fields are in the smallest DZD unit (centimes); set values only after deciding the test tariff:

```sql
insert into public.fare_policies(
  service_area_id, version, currency_code, base_amount_minor,
  distance_rate_minor, time_rate_minor, minimum_amount_minor, is_active
)
values (
  'PASTE_RETURNED_SERVICE_AREA_UUID', 1, 'DZD',
  BASE_CENTIMES, PER_KM_CENTIMES, PER_MINUTE_CENTIMES, MINIMUM_CENTIMES, true
);
```

Do not leave placeholder words in the SQL. This policy is for the closed test only, not a recommended public tariff.

## 5. Deploy the Edge Functions

Deploy the fare quote and dispatch maintenance functions:

```sh
supabase functions deploy create-fare-quote
supabase functions deploy dispatch-maintenance --no-verify-jwt
```

Configure these Edge Function secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` — server-side secret only.
- `ROUTING_BASE_URL` — HTTPS base URL of a trusted OSRM-compatible routing service.
- `ALLOWED_ORIGIN` — for GitHub Pages, `https://rdjouahir2-jpg.github.io` (origin only, no path).
- `CRON_SECRET` — a long, random secret used only by the scheduled maintenance caller.

The quote function authenticates the user, checks account standing, validates that both endpoints are in the same active service area, gets a road route, calculates the price from the area's active fare policy, validates the route geometry, and writes a short-lived single-use quote.

The public OSRM demo server and public demo map tiles are not production infrastructure. The current map style is a development-friendly OpenFreeMap style; before public launch, review tile-provider terms and choose a reliable map/routing hosting arrangement.

## 6. Schedule dispatch maintenance

The `dispatch-maintenance` function expires timed-out offers, retries recent requests that did not find a driver, and removes old expired fare quotes. Configure a scheduled HTTP POST in Supabase Cron or a trusted external scheduler to call:

```
https://YOUR_PROJECT_REF.supabase.co/functions/v1/dispatch-maintenance
```

Include header `x-mithaq-cron-secret: YOUR_CRON_SECRET`. Run it once per minute during the closed test. The function is not JWT-authenticated; the separate random cron secret is mandatory. Do not expose that secret in the browser.

## 7. Connect GitHub Pages

In GitHub repository Settings → Secrets and variables → Actions → Variables, create:

- `VITE_SUPABASE_URL` = the test project's Project URL.
- `VITE_SUPABASE_ANON_KEY` = the test project's publishable/anon key.

These are public client configuration values, not service-role secrets. The Pages build reads them at build time. Never add `SUPABASE_SERVICE_ROLE_KEY` as a `VITE_*` variable.

For local development, copy `.env.example` to `.env.local` and enter the same two public values.

## 8. Two-phone test sequence

1. Sign in with your administrator account on your phone.
2. Ask your friend to create a separate account on their phone.
3. Activate your friend's account from the admin screen.
4. On your friend's account, open Driver, apply, and submit the test vehicle details.
5. From your admin screen, approve the vehicle first, then approve the driver.
6. On your phone, choose two points inside the configured test area, enter clear pickup/destination labels, calculate the fare, and request the trip.
7. On your friend's phone, enable driver availability and allow location access while keeping the app open.
8. Accept the offer, advance through arrival, enter the passenger's one-time PIN, start and complete the trip.
9. Verify that both phones see the correct status changes and that the admin screen records the ride.

Keep the two devices on HTTPS, allow location permission, and keep the driver screen open during this web test. Browser GPS can be suspended in the background; reliable background tracking needs a properly packaged native Android app and additional permission/security work.

## 9. What this closed test does not prove

- It does not verify identity documents, driving licence, vehicle registration, insurance, or legal eligibility.
- It does not provide emergency dispatch, 24/7 support, passenger protection operations, or production incident response.
- It does not process payments or settle driver earnings.
- It does not provide dependable background GPS or push notifications.
- It does not establish Algerian transport permissions, insurance coverage, consumer terms, or privacy compliance.

Do not carry paying passengers or launch publicly until those matters, the database/security tests, monitoring, backups, and device tests have been independently verified.
