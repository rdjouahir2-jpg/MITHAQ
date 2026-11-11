import { supabase } from './supabase'

export type FareNegotiation = {
  negotiation_id: string
  ride_id: string
  offer_id: string
  driver_id: string
  passenger_id: string
  status: 'open' | 'accepted' | 'rejected' | 'expired'
  quoted_amount_minor: number
  current_amount_minor: number
  minimum_amount_minor: number
  maximum_amount_minor: number
  round_number: number
  max_rounds: number
  last_actor: 'passenger' | 'driver'
  expires_at: string
  pickup_label: string
  destination_label: string
  currency_code: string
}

function requireNegotiationClient() {
  if (!supabase) throw new Error('MITHAQ backend is not configured on this build.')
  return supabase
}

/** Starts a driver counter-offer. Server validates ownership, eligibility, expiry and price bounds. */
export async function startFareNegotiation(offerId: string, amountMinor: number): Promise<string> {
  if (!Number.isSafeInteger(amountMinor) || amountMinor < 0) throw new Error('أدخل سعراً صحيحاً بالدينار.')
  const { data, error } = await requireNegotiationClient().rpc('start_fare_negotiation', {
    p_offer_id: offerId,
    p_counter_amount_minor: amountMinor,
  })
  if (error) throw error
  if (typeof data !== 'string') throw new Error('تعذر إنشاء عرض التفاوض.')
  return data
}

/** Participant response. The server atomically validates the turn and, on acceptance, assigns the ride. */
export async function respondFareNegotiation(
  negotiationId: string,
  action: 'counter' | 'accept' | 'reject',
  amountMinor?: number,
): Promise<'open' | 'accepted' | 'rejected' | 'expired'> {
  if (action === 'counter' && (!Number.isSafeInteger(amountMinor) || (amountMinor ?? -1) < 0)) {
    throw new Error('أدخل سعراً صحيحاً بالدينار.')
  }
  const { data, error } = await requireNegotiationClient().rpc('respond_fare_negotiation', {
    p_negotiation_id: negotiationId,
    p_action: action,
    p_counter_amount_minor: amountMinor ?? null,
  })
  if (error) throw error
  if (!['open', 'accepted', 'rejected', 'expired'].includes(data)) {
    throw new Error('أعاد الخادم حالة تفاوض غير معروفة.')
  }
  return data
}

export async function getMyFareNegotiations(): Promise<FareNegotiation[]> {
  const { data, error } = await requireNegotiationClient().rpc('get_my_fare_negotiations')
  if (error) throw error
  return (data ?? []) as FareNegotiation[]
}
