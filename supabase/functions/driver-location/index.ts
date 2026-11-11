import { createClient } from "npm:@supabase/supabase-js@2";
import { isValidDriverLocationPayload } from "./validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(status: number, body: Record<string, unknown>, origin: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Access-Control-Allow-Origin": origin,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

Deno.serve(async (req: Request) => {
  const configuredOrigin = Deno.env.get("ALLOWED_ORIGIN");
  const requestOrigin = req.headers.get("origin");
  const allowedOrigin = configuredOrigin ?? "null";

  if (!configuredOrigin) return json(503, { error: "allowed_origin_not_configured" }, "null");
  if (requestOrigin && requestOrigin !== configuredOrigin) {
    return json(403, { error: "origin_not_allowed" }, configuredOrigin);
  }
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: { ...corsHeaders, "Access-Control-Allow-Origin": allowedOrigin },
    });
  }
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" }, allowedOrigin);
  const contentLength = Number(req.headers.get("content-length") ?? 0);
  if (contentLength > 8_192) return json(413, { error: "request_too_large" }, allowedOrigin);
  const contentType = req.headers.get("content-type")?.split(";")[0].trim().toLowerCase();
  if (contentType !== "application/json") {
    return json(415, { error: "application_json_required" }, allowedOrigin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");
  if (!supabaseUrl || !anonKey) return json(503, { error: "server_configuration_incomplete" }, allowedOrigin);
  if (!authorization?.startsWith("Bearer ") || authorization.length > 8_192) {
    return json(401, { error: "authentication_required" }, allowedOrigin);
  }

  try {
    const rawBody = await req.text();
    if (new TextEncoder().encode(rawBody).byteLength > 8_192) {
      return json(413, { error: "request_too_large" }, allowedOrigin);
    }
    let payload: unknown;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      return json(400, { error: "invalid_json" }, allowedOrigin);
    }
    if (!isValidDriverLocationPayload(payload)) {
      return json(422, { error: "invalid_or_simulated_location" }, allowedOrigin);
    }
    const { latitude, longitude, accuracy, time: timestamp } = payload;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return json(401, { error: "invalid_session" }, allowedOrigin);

    const { error: locationError } = await userClient.rpc("record_driver_location", {
      p_latitude: latitude,
      p_longitude: longitude,
      p_accuracy_m: accuracy,
      p_recorded_at: new Date(timestamp).toISOString(),
    });
    if (locationError) {
      const message = String(locationError.message ?? "");
      if (message.includes("approved_online_driver_required") ||
          message.includes("active_account_required")) {
        return json(403, { error: "driver_not_authorized_for_location_tracking" }, allowedOrigin);
      }
      if (message.includes("invalid_or_stale_location")) {
        return json(422, { error: "stale_or_invalid_location" }, allowedOrigin);
      }
      throw locationError;
    }

    return json(202, { accepted: true, received_at: new Date().toISOString() }, allowedOrigin);
  } catch (error) {
    console.error("driver-location failed", error);
    return json(500, { error: "location_update_failed" }, allowedOrigin);
  }
});
