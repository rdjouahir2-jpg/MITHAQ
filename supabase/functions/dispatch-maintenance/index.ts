import { createClient } from "npm:@supabase/supabase-js@2";

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return difference === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }

  const expectedSecret = Deno.env.get("CRON_SECRET");
  const suppliedSecret = req.headers.get("x-mithaq-cron-secret") ?? "";
  if (!expectedSecret || !constantTimeEqual(expectedSecret, suppliedSecret)) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return Response.json({ error: "server_configuration_incomplete" }, { status: 503 });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const now = new Date().toISOString();
    const { data: offeredRides, error: offeredError } = await admin
      .from("rides")
      .select("id")
      .eq("status", "offered")
      .limit(200);
    if (offeredError) throw offeredError;

    let expiredCount = 0;
    for (const ride of offeredRides ?? []) {
      const { data, error } = await admin.rpc("expire_ride_offers", { p_ride_id: ride.id });
      if (error) throw error;
      expiredCount += Number(data ?? 0);
    }

    const retrySince = new Date(Date.now() - 20 * 60_000).toISOString();
    const { data: retryRides, error: retryError } = await admin
      .from("rides")
      .select("id")
      .eq("status", "no_driver_found")
      .gte("requested_at", retrySince)
      .order("requested_at", { ascending: true })
      .limit(50);
    if (retryError) throw retryError;

    let dispatchAttempts = 0;
    let newOffers = 0;
    for (const ride of retryRides ?? []) {
      const { data, error } = await admin.rpc("dispatch_ride", {
        p_ride_id: ride.id,
        p_radius_m: 7000,
        p_max_drivers: 5,
      });
      if (error) {
        if (String(error.message ?? "").includes("ride_not_dispatchable")) continue;
        throw error;
      }
      dispatchAttempts += 1;
      newOffers += Number(data ?? 0);
    }

    const quoteCleanupBefore = new Date(Date.now() - 24 * 60 * 60_000).toISOString();
    const { error: cleanupError } = await admin
      .from("fare_quotes")
      .delete()
      .lt("expires_at", quoteCleanupBefore);
    if (cleanupError) throw cleanupError;

    const staleLocationBefore = new Date(Date.now() - 5 * 60_000).toISOString();
    const { error: locationCleanupError } = await admin
      .from("driver_locations")
      .delete()
      .lt("updated_at", staleLocationBefore);
    if (locationCleanupError) throw locationCleanupError;

    return Response.json({
      expired_offers: expiredCount,
      rides_retried: dispatchAttempts,
      new_driver_offers: newOffers,
    });
  } catch (error) {
    console.error("dispatch-maintenance failed", error);
    return Response.json({ error: "maintenance_failed" }, { status: 500 });
  }
});
