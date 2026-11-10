import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(status: number, body: Record<string, unknown>, origin = "*") {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Access-Control-Allow-Origin": origin, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
  });
}

function validCoordinate(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max;
}

Deno.serve(async (req: Request) => {
  const configuredOrigin = Deno.env.get("ALLOWED_ORIGIN");
  const requestOrigin = req.headers.get("origin");
  const allowedOrigin = configuredOrigin ?? "null";

  if (!configuredOrigin) {
    return json(503, { error: "allowed_origin_not_configured" }, "null");
  }
  if (requestOrigin && requestOrigin !== configuredOrigin) {
    return json(403, { error: "origin_not_allowed" }, configuredOrigin);
  }
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: { ...corsHeaders, "Access-Control-Allow-Origin": allowedOrigin },
    });
  }
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" }, allowedOrigin);
  }
  const requestBytes = Number(req.headers.get("content-length") ?? 0);
  if (requestBytes > 16_384) {
    return json(413, { error: "request_too_large" }, allowedOrigin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const routingBase = Deno.env.get("ROUTING_BASE_URL");
  if (!supabaseUrl || !anonKey || !serviceKey || !routingBase) {
    return json(503, { error: "server_configuration_incomplete" }, allowedOrigin);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json(401, { error: "authentication_required" }, allowedOrigin);
  }

  try {
    const payload = await req.json();
    const pickup = payload?.pickup;
    const destination = payload?.destination;
    const category = payload?.category;
    const pickupLabel = typeof payload?.pickup_label === "string" ? payload.pickup_label.trim() : "";
    const destinationLabel = typeof payload?.destination_label === "string" ? payload.destination_label.trim() : "";

    if (
      !validCoordinate(pickup?.latitude, -90, 90) ||
      !validCoordinate(pickup?.longitude, -180, 180) ||
      !validCoordinate(destination?.latitude, -90, 90) ||
      !validCoordinate(destination?.longitude, -180, 180) ||
      pickupLabel.length < 2 || pickupLabel.length > 180 ||
      destinationLabel.length < 2 || destinationLabel.length > 180 ||
      !["economy", "comfort", "family"].includes(category)
    ) {
      return json(400, { error: "invalid_quote_request" }, allowedOrigin);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userResult, error: authError } = await userClient.auth.getUser();
    if (authError || !userResult.user) {
      return json(401, { error: "invalid_session" }, allowedOrigin);
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("account_status")
      .eq("id", userResult.user.id)
      .maybeSingle();

    if (profileError) throw profileError;
    if (profile?.account_status !== "active") {
      return json(403, { error: "active_account_required" }, allowedOrigin);
    }

    const oneMinuteAgo = new Date(Date.now() - 60_000).toISOString();
    const { count: recentQuoteCount, error: rateLimitError } = await admin
      .from("fare_quotes")
      .select("id", { count: "exact", head: true })
      .eq("passenger_id", userResult.user.id)
      .gte("created_at", oneMinuteAgo);

    if (rateLimitError) throw rateLimitError;
    if ((recentQuoteCount ?? 0) >= 10) {
      return json(429, { error: "quote_rate_limit_exceeded" }, allowedOrigin);
    }

    const { data: policyRows, error: policyError } = await admin.rpc(
      "resolve_fare_policy_for_route",
      {
        p_pickup_latitude: pickup.latitude,
        p_pickup_longitude: pickup.longitude,
        p_destination_latitude: destination.latitude,
        p_destination_longitude: destination.longitude,
      },
    );

    if (policyError) {
      const code = String(policyError.message ?? "");
      if (code.includes("route_outside_active_service_area") ||
          code.includes("active_service_area_fare_policy_required")) {
        return json(422, { error: "route_not_in_configured_service_area" }, allowedOrigin);
      }
      throw policyError;
    }
    const policy = Array.isArray(policyRows) ? policyRows[0] : null;
    if (!policy) {
      return json(503, { error: "no_active_area_fare_policy" }, allowedOrigin);
    }

    let routeUrl: URL;
    try {
      routeUrl = new URL(
        `/route/v1/driving/${pickup.longitude},${pickup.latitude};${destination.longitude},${destination.latitude}`,
        routingBase,
      );
      if (routeUrl.protocol !== "https:" && routeUrl.hostname !== "localhost") {
        return json(503, { error: "secure_routing_endpoint_required" }, allowedOrigin);
      }
    } catch {
      return json(503, { error: "invalid_routing_configuration" }, allowedOrigin);
    }
    routeUrl.searchParams.set("overview", "full");
    routeUrl.searchParams.set("geometries", "geojson");
    routeUrl.searchParams.set("steps", "false");

    const routeResponse = await fetch(routeUrl, {
      signal: AbortSignal.timeout(10_000),
      redirect: "error",
      headers: { Accept: "application/json" },
    });
    if (!routeResponse.ok) {
      return json(502, { error: "routing_provider_unavailable" }, allowedOrigin);
    }

    const routeBody = await routeResponse.text();
    if (routeBody.length > 2_000_000) {
      return json(502, { error: "routing_response_too_large" }, allowedOrigin);
    }
    let routeData: any;
    try {
      routeData = JSON.parse(routeBody);
    } catch {
      return json(502, { error: "invalid_routing_response" }, allowedOrigin);
    }
    const route = routeData?.code === "Ok" && Array.isArray(routeData.routes)
      ? routeData.routes[0]
      : null;
    const distanceM = Math.round(Number(route?.distance));
    const durationS = Math.round(Number(route?.duration));
    const geometry = route?.geometry;
    const coordinates = geometry?.type === "LineString" ? geometry.coordinates : null;
    const validGeometry = Array.isArray(coordinates) &&
      coordinates.length >= 2 && coordinates.length <= 5000 &&
      coordinates.every((point: unknown) =>
        Array.isArray(point) && point.length >= 2 &&
        validCoordinate(point[0], -180, 180) &&
        validCoordinate(point[1], -90, 90)
      );
    if (
      !Number.isSafeInteger(distanceM) || distanceM <= 0 || distanceM > 300_000 ||
      !Number.isSafeInteger(durationS) || durationS <= 0 || durationS > 28_800 ||
      !validGeometry
    ) {
      return json(422, { error: "route_not_found_or_out_of_service_range" }, allowedOrigin);
    }

    const base = Number(policy.base_amount_minor);
    const perKm = Number(policy.distance_rate_minor);
    const perMinute = Number(policy.time_rate_minor);
    const minimum = Number(policy.minimum_amount_minor);
    if (![base, perKm, perMinute, minimum].every(Number.isSafeInteger) ||
        [base, perKm, perMinute, minimum].some((n) => n < 0)) {
      return json(503, { error: "invalid_fare_policy" }, allowedOrigin);
    }

    const amountMinor = Math.max(
      minimum,
      base + Math.ceil(distanceM / 1000) * perKm + Math.ceil(durationS / 60) * perMinute,
    );
    if (!Number.isSafeInteger(amountMinor) || amountMinor > 100_000_000) {
      return json(422, { error: "fare_out_of_supported_range" }, allowedOrigin);
    }

    const expiresAt = new Date(Date.now() + 3 * 60_000).toISOString();
    const { data: quote, error: insertError } = await admin
      .from("fare_quotes")
      .insert({
        passenger_id: userResult.user.id,
        pickup_label: pickupLabel,
        destination_label: destinationLabel,
        pickup_latitude: pickup.latitude,
        pickup_longitude: pickup.longitude,
        destination_latitude: destination.latitude,
        destination_longitude: destination.longitude,
        category,
        amount_minor: amountMinor,
        currency_code: policy.currency_code,
        route_distance_m: distanceM,
        route_duration_s: durationS,
        route_geometry: geometry,
        fare_policy_version: policy.version,
        service_area_id: policy.service_area_id,
        expires_at: expiresAt,
      })
      .select("id, amount_minor, currency_code, route_distance_m, route_duration_s, expires_at")
      .single();

    if (insertError) throw insertError;

    return json(200, {
      quote_id: quote.id,
      amount_minor: Number(quote.amount_minor),
      currency_code: quote.currency_code,
      route_distance_m: quote.route_distance_m,
      route_duration_s: quote.route_duration_s,
      route_geometry: geometry,
      expires_at: quote.expires_at,
    }, allowedOrigin);
  } catch (error) {
    console.error("create-fare-quote failed", error);
    return json(500, { error: "quote_creation_failed" }, allowedOrigin);
  }
});
