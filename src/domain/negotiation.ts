/**
 * Deterministic rules for a bounded passenger/driver fare negotiation.
 *
 * This is domain logic only. The server must repeat every check transactionally;
 * never trust a browser to enforce price limits, actor identity, or expiry.
 */
export type NegotiationActor = 'passenger' | 'driver'
export type NegotiationStatus = 'open' | 'accepted' | 'rejected' | 'expired'

export interface FareNegotiation {
  id: string
  passengerId: string
  driverId: string
  status: NegotiationStatus
  quotedAmountMinor: number
  currentAmountMinor: number
  minimumAmountMinor: number
  maximumAmountMinor: number
  expiresAtMs: number
  round: number
  maxRounds: number
  lastActor: NegotiationActor | null
}

export type NegotiationAction =
  | { type: 'counter'; amountMinor: number }
  | { type: 'accept' }
  | { type: 'reject' }

function assertAmount(value: number, label: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${label} must be a non-negative safe integer`)
  }
}

export function createFareNegotiation(input: Omit<FareNegotiation, 'status' | 'round' | 'lastActor'>): FareNegotiation {
  if (!input.id || !input.passengerId || !input.driverId) {
    throw new Error('Negotiation and participant identifiers are required')
  }
  assertAmount(input.quotedAmountMinor, 'Quoted amount')
  assertAmount(input.currentAmountMinor, 'Current amount')
  assertAmount(input.minimumAmountMinor, 'Minimum amount')
  assertAmount(input.maximumAmountMinor, 'Maximum amount')
  if (input.minimumAmountMinor > input.maximumAmountMinor) throw new Error('Minimum fare exceeds maximum fare')
  if (input.quotedAmountMinor < input.minimumAmountMinor || input.quotedAmountMinor > input.maximumAmountMinor) {
    throw new Error('Quoted fare is outside the allowed range')
  }
  if (input.currentAmountMinor < input.minimumAmountMinor || input.currentAmountMinor > input.maximumAmountMinor) {
    throw new Error('Proposed fare is outside the allowed range')
  }
  if (!Number.isSafeInteger(input.expiresAtMs) || input.expiresAtMs <= 0) throw new Error('Expiry timestamp is invalid')
  if (!Number.isSafeInteger(input.maxRounds) || input.maxRounds < 1 || input.maxRounds > 5) {
    throw new Error('Negotiation rounds must be between 1 and 5')
  }
  return { ...input, status: 'open', round: 0, lastActor: null }
}

export function applyNegotiationAction(
  current: FareNegotiation,
  actor: NegotiationActor,
  action: NegotiationAction,
  nowMs: number,
): FareNegotiation {
  if (current.status !== 'open') throw new Error('Negotiation is no longer open')
  if (nowMs >= current.expiresAtMs) return { ...current, status: 'expired' }
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) throw new Error('Current timestamp is invalid')
  if (current.lastActor === actor) throw new Error('Participants must alternate negotiation turns')

  if (action.type === 'accept') return { ...current, status: 'accepted', lastActor: actor }
  if (action.type === 'reject') return { ...current, status: 'rejected', lastActor: actor }

  assertAmount(action.amountMinor, 'Counter-offer')
  if (current.round >= current.maxRounds) throw new Error('Maximum negotiation rounds reached')
  if (action.amountMinor < current.minimumAmountMinor || action.amountMinor > current.maximumAmountMinor) {
    throw new Error('Counter-offer is outside the allowed fare range')
  }
  return {
    ...current,
    currentAmountMinor: action.amountMinor,
    round: current.round + 1,
    lastActor: actor,
  }
}
