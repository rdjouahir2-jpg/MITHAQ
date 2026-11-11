export type DriverLocationPayload = {
  source: "native";
  latitude: number;
  longitude: number;
  accuracy: number;
  time: number;
  simulated?: boolean;
};

function validNumber(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max;
}

export function isValidDriverLocationPayload(
  payload: unknown,
  now = Date.now(),
): payload is DriverLocationPayload {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) return false;
  const value = payload as Record<string, unknown>;
  return value.source === "native" &&
    validNumber(value.latitude, -90, 90) &&
    validNumber(value.longitude, -180, 180) &&
    validNumber(value.accuracy, 0, 100) &&
    validNumber(value.time, now - 120_000, now + 30_000) &&
    value.simulated !== true;
}
