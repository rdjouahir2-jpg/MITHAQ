import {
  assertMoneyAmount,
  assertRideSnapshot,
  assertTransition,
  canTransition,
  formatDzd,
} from '../src/domain/ride.ts'

function equal(actual: unknown, expected: unknown, label: string): void {
  if (actual !== expected) throw new Error(`${label}: expected ${String(expected)}, received ${String(actual)}`)
}

function throws(action: () => unknown, messagePart?: string): void {
  try {
    action()
  } catch (error) {
    if (messagePart && (!(error instanceof Error) || !error.message.includes(messagePart))) {
      throw new Error(`Expected error containing "${messagePart}"`)
    }
    return
  }
  throw new Error('Expected the operation to throw')
}

Deno.test('driver can advance an accepted ride toward pickup', () => {
  equal(canTransition({ from: 'accepted', to: 'driver_arriving', actor: 'driver' }), true, 'accepted → driver_arriving')
  equal(canTransition({ from: 'driver_arriving', to: 'arrived', actor: 'driver' }), true, 'driver_arriving → arrived')
})

Deno.test('passenger cannot perform driver-only transitions', () => {
  equal(canTransition({ from: 'accepted', to: 'driver_arriving', actor: 'passenger' }), false, 'passenger transition')
  throws(() => assertTransition({ from: 'accepted', to: 'driver_arriving', actor: 'passenger' }), 'Invalid ride transition')
})

Deno.test('terminal rides cannot be reopened', () => {
  equal(canTransition({ from: 'completed', to: 'cancelled', actor: 'admin' }), false, 'completed is terminal')
  throws(() => assertTransition({ from: 'completed', to: 'cancelled', actor: 'admin' }), 'Invalid ride transition')
})


Deno.test('no-driver result is retryable by the dispatch system', () => {
  equal(canTransition({ from: 'no_driver_found', to: 'offered', actor: 'system' }), true, 'retry dispatch')
  equal(canTransition({ from: 'no_driver_found', to: 'cancelled', actor: 'passenger' }), true, 'passenger can cancel while retrying')
  equal(canTransition({ from: 'no_driver_found', to: 'accepted', actor: 'driver' }), false, 'driver cannot accept without a new offer')
  throws(() => assertTransition({ from: 'no_driver_found', to: 'accepted', actor: 'driver' }), 'Invalid ride transition')
})

Deno.test('money uses non-negative safe integer minor units', () => {
  assertMoneyAmount(0)
  assertMoneyAmount(12550)
  throws(() => assertMoneyAmount(-1))
  throws(() => assertMoneyAmount(1.5))
  throws(() => assertMoneyAmount(Number.MAX_SAFE_INTEGER + 1))
})

Deno.test('assigned ride states require a driver', () => {
  throws(() => assertRideSnapshot({
    id: 'ride-1', status: 'accepted', passengerId: 'passenger-1', driverId: null,
    quotedAmountMinor: 1000, finalAmountMinor: null, currency: 'DZD', version: 1,
  }), 'An assigned driver is required')
})

Deno.test('completed rides require a finalized amount', () => {
  throws(() => assertRideSnapshot({
    id: 'ride-1', status: 'completed', passengerId: 'passenger-1', driverId: 'driver-1',
    quotedAmountMinor: 1000, finalAmountMinor: null, currency: 'DZD', version: 2,
  }), 'completed ride must have a finalized amount')
})

Deno.test('valid requested ride snapshot passes invariants', () => {
  assertRideSnapshot({
    id: 'ride-1', status: 'requested', passengerId: 'passenger-1', driverId: null,
    quotedAmountMinor: 12500, finalAmountMinor: null, currency: 'DZD', version: 0,
  })
})

Deno.test('DZD display formatting rejects invalid amounts', () => {
  equal(typeof formatDzd(1000), 'string', 'formatted amount')
  throws(() => formatDzd(-100))
})
