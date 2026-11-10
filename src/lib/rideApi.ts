import { supabase } from './supabase'

export type FareQuoteInput = {
  pickup_label: string
  destination_label: string
  pickup: { latitude: number; longitude: number }
  destination: { latitude: number; longitude: number }
  category: 'economy' | 'comfort' | 'family'
}

export type FareQuote = {
  quote_id: string
  amount_minor: number
  currency_code: string
  route_distance_m: number
  route_duration_s: number
  expires_at: string
}

export type RideRequestResult = {
  ride_id: string
  boarding_pin: string
  current_status: string
}

function requireSupabase() {
  if (!supabase) {
    throw new Error('MITHAQ backend is not configured on this build.')
  }
  return supabase
}

export async function createFareQuote(input: FareQuoteInput): Promise<FareQuote> {
  const client = requireSupabase()
  const { data, error } = await client.functions.invoke<FareQuote>('create-fare-quote', {
    body: input,
  })
  if (error) throw error
  if (!data?.quote_id) throw new Error('The fare service returned an invalid quote.')
  return data
}

export async function requestRide(quoteId: string): Promise<RideRequestResult> {
  const client = requireSupabase()
  const { data, error } = await client.rpc('request_ride', { p_quote_id: quoteId })
  if (error) throw error
  const row = Array.isArray(data) ? data[0] : data
  if (!row?.ride_id || !row?.boarding_pin) {
    throw new Error('The ride service returned an invalid booking response.')
  }
  return row as RideRequestResult
}

export async function setDriverAvailability(online: boolean): Promise<string> {
  const client = requireSupabase()
  const { data, error } = await client.rpc('set_driver_availability', {
    p_online: online,
  })
  if (error) throw error
  return String(data)
}

export async function recordDriverLocation(input: {
  latitude: number
  longitude: number
  accuracyM: number
  recordedAt: string
}): Promise<string> {
  const client = requireSupabase()
  const { data, error } = await client.rpc('record_driver_location', {
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_accuracy_m: input.accuracyM,
    p_recorded_at: input.recordedAt,
  })
  if (error) throw error
  return String(data)
}
