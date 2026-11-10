import { assertEquals, assertThrows } from 'node:assert/strict'
import {
  assertMoneyAmount,
  assertRideSnapshot,
  assertTransition,
  canTransition,
  formatDzd,
} from './ride.ts'

Deno.test('driver can advance an accepted ride toward pickup', () => {
  assertEquals(canTransition({ from: 'accepted', to: 'driver_arriving', actor: 'driver' }), true)
  assertEquals(canTransition({ from: 'driver_arriving', to: 'arrived', actor: 'driver' }), true)
})

Deno.test('passenger cannot perform driver-only transitions', () => {
  assertEquals(canTransition({ from: 'accepted', to: 'driver_arriving', actor: 'passenger' }), false)
  assertThrows(
    () => assertTransition({ from: 'accepted', to: 'driver_arriving', actor: 'passenger' }),
    Error,
    'Invalid ride transition',
  )
})

Deno.test('terminal rides cannot be reopened', () => {
  assertEquals(canTransition({ from: 'completed', to: 'cancelled', actor: 'admin' }), false)
  assertThrows(() => assertTransition({ from: 'completed', to: 'cancelled', actor: 'admin' }))
})

Deno.test('money uses non-negative safe integer minor units', () => {
  assertMoneyAmount(0)
  assertMoneyAmount(12550)
  assertThrows(() => assertMoneyAmount(-1))
  assertThrows(() => assertMoneyAmount(1.5))
  assertThrows(() => assertMoneyAmount(Number.MAX_SAFE_INTEGER + 1))
})

Deno.test('assigned ride states require a driver', () => {
  assertThrows(() => assertRideSnapshot({
    id: 'ride-1', status: 'accepted', passengerId: 'passenger-1', driverId: null,
    quotedAmountMinor: 1000, finalAmountMinor: null, currency: 'DZD', version: 1,
  }), Error, 'An assigned driver is required')
})

Deno.test('completed rides require a finalized amount', () => {
  assertThrows(() => assertRideSnapshot({
    id: 'ride-1', status: 'completed', passengerId: 'passenger-1', driverId: 'driver-1',
    quotedAmountMinor: 1000, finalAmountMinor: null, currency: 'DZD', version: 2,
  }), Error, 'completed ride must have a finalized amount')
})

Deno.test('valid requested ride snapshot passes invariants', () => {
  assertEquals(assertRideSnapshot({
    id: 'ride-1', status: 'requested', passengerId: 'passenger-1', driverId: null,
    quotedAmountMinor: 12500, finalAmountMinor: null, currency: 'DZD', version: 0,
  }), undefined)
})

Deno.test('DZD display formatting rejects invalid amounts', () => {
  assertEquals(typeof formatDzd(1000), 'string')
  assertThrows(() => formatDzd(-100))
})
