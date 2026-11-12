import { isValidDriverLocationPayload } from "../supabase/functions/driver-location/validation.ts";

const now = 1_800_000_000_000;
const validPayload = {
  source: "native",
  latitude: 36.75,
  longitude: 3.05,
  accuracy: 12,
  time: now,
};

Deno.test("accepts a fresh, bounded native driver location", () => {
  if (!isValidDriverLocationPayload(validPayload, now)) {
    throw new Error("expected valid native location to pass");
  }
});

Deno.test("rejects browser or untrusted location sources", () => {
  if (isValidDriverLocationPayload({ ...validPayload, source: "browser" }, now)) {
    throw new Error("browser location must not pass the native endpoint");
  }
});

Deno.test("rejects out-of-range coordinates and poor accuracy", () => {
  for (const payload of [
    { ...validPayload, latitude: 91 },
    { ...validPayload, longitude: -181 },
    { ...validPayload, accuracy: 101 },
    { ...validPayload, accuracy: Number.NaN },
  ]) {
    if (isValidDriverLocationPayload(payload, now)) {
      throw new Error("invalid coordinate or accuracy passed validation");
    }
  }
});

Deno.test("rejects stale or implausibly future timestamps", () => {
  for (const timestamp of [now - 120_001, now + 30_001, Number.POSITIVE_INFINITY]) {
    if (isValidDriverLocationPayload({ ...validPayload, time: timestamp }, now)) {
      throw new Error("invalid timestamp passed validation");
    }
  }
});

Deno.test("rejects explicitly simulated locations and non-object payloads", () => {
  if (isValidDriverLocationPayload({ ...validPayload, simulated: true }, now)) {
    throw new Error("simulated location must not pass validation");
  }
  for (const payload of [null, [], "location", 42]) {
    if (isValidDriverLocationPayload(payload, now)) {
      throw new Error("non-object payload must not pass validation");
    }
  }
});
