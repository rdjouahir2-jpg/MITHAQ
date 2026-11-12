import {
  applyNegotiationAction,
  createFareNegotiation,
} from '../src/domain/negotiation.ts'

function equal(actual: unknown, expected: unknown, label: string): void {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}

function throws(action: () => unknown, messagePart: string): void {
  try {
    action()
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes(messagePart)) {
      throw new Error(`Expected error containing "${messagePart}"`)
    }
    return
  }
  throw new Error('Expected the operation to throw')
}

const base = () => createFareNegotiation({
  id: 'neg-1',
  passengerId: 'passenger-1',
  driverId: 'driver-1',
  quotedAmountMinor: 10000,
  currentAmountMinor: 9500,
  minimumAmountMinor: 8000,
  maximumAmountMinor: 12000,
  expiresAtMs: 5000,
  maxRounds: 3,
})

Deno.test('creates a negotiation inside its configured fare bounds', () => {
  const negotiation = base()
  equal(negotiation.status, 'open', 'initial status')
  equal(negotiation.round, 0, 'initial round')
})

Deno.test('rejects invalid and out-of-range initial fares', () => {
  throws(() => createFareNegotiation({
    id: 'n', passengerId: 'p', driverId: 'd',
    quotedAmountMinor: 7000, currentAmountMinor: 7000,
    minimumAmountMinor: 8000, maximumAmountMinor: 12000,
    expiresAtMs: 5000, maxRounds: 3,
  }), 'outside the allowed range')
  throws(() => createFareNegotiation({
    id: 'n', passengerId: 'p', driverId: 'd',
    quotedAmountMinor: 9000, currentAmountMinor: 9000,
    minimumAmountMinor: 8000, maximumAmountMinor: 12000,
    expiresAtMs: 5000, maxRounds: 6,
  }), 'between 1 and 5')
})

Deno.test('counter-offers alternate and remain within bounds', () => {
  const first = applyNegotiationAction(base(), 'driver', { type: 'counter', amountMinor: 9000 }, 1000)
  equal(first.currentAmountMinor, 9000, 'driver counter')
  equal(first.round, 1, 'round')
  throws(() => applyNegotiationAction(first, 'driver', { type: 'counter', amountMinor: 8800 }, 1100), 'alternate')
  const second = applyNegotiationAction(first, 'passenger', { type: 'counter', amountMinor: 8800 }, 1200)
  equal(second.currentAmountMinor, 8800, 'passenger counter')
  equal(second.round, 2, 'second round')
  throws(() => applyNegotiationAction(second, 'driver', { type: 'counter', amountMinor: 7000 }, 1300), 'outside the allowed fare range')
})

Deno.test('enforces maximum rounds and allows either participant to accept', () => {
  const one = applyNegotiationAction(base(), 'driver', { type: 'counter', amountMinor: 9000 }, 1000)
  const two = applyNegotiationAction(one, 'passenger', { type: 'counter', amountMinor: 8800 }, 1100)
  const three = applyNegotiationAction(two, 'driver', { type: 'counter', amountMinor: 8700 }, 1200)
  throws(() => applyNegotiationAction(three, 'passenger', { type: 'counter', amountMinor: 8600 }, 1300), 'Maximum negotiation rounds')
  equal(applyNegotiationAction(three, 'passenger', { type: 'accept' }, 1300).status, 'accepted', 'accepted status')
})

Deno.test('expires at the deadline and rejects later actions', () => {
  const expired = applyNegotiationAction(base(), 'driver', { type: 'accept' }, 5000)
  equal(expired.status, 'expired', 'expiry status')
  throws(() => applyNegotiationAction(expired, 'passenger', { type: 'accept' }, 5100), 'no longer open')
})

Deno.test('reject action closes the negotiation', () => {
  equal(applyNegotiationAction(base(), 'driver', { type: 'reject' }, 1000).status, 'rejected', 'rejected status')
})
