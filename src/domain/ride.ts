/**
 * MITHAQ ride-domain rules.
 *
 * These functions are deterministic domain helpers, not a security boundary.
 * The same rules MUST be enforced transactionally by the backend before pilot.
 */
export type RideStatus =
  | 'requested' | 'offered' | 'accepted' | 'driver_arriving'
  | 'arrived' | 'boarded' | 'in_progress' | 'completed'
  | 'cancelled' | 'expired' | 'no_driver_found'

export type RideActor = 'passenger' | 'driver' | 'system' | 'admin'

export interface RideSnapshot {
  id: string
  status: RideStatus
  passengerId: string
  driverId: string | null
  quotedAmountMinor: number
  finalAmountMinor: number | null
  currency: 'DZD'
  version: number
}

export interface RideTransition {
  from: RideStatus
  to: RideStatus
  actor: RideActor
}

const terminal = new Set<RideStatus>([
  'completed', 'cancelled', 'expired', 'no_driver_found',
])

const allowed: Record<RideStatus, Partial<Record<RideActor, RideStatus[]>>> = {
  requested: { system: ['offered', 'no_driver_found', 'expired'], passenger: ['cancelled'], admin: ['cancelled'] },
  offered: { driver: ['accepted'], system: ['no_driver_found', 'expired'], passenger: ['cancelled'], admin: ['cancelled'] },
  accepted: { driver: ['driver_arriving'], passenger: ['cancelled'], admin: ['cancelled'] },
  driver_arriving: { driver: ['arrived'], passenger: ['cancelled'], admin: ['cancelled'] },
  arrived: { driver: ['boarded'], passenger: ['cancelled'], admin: ['cancelled'] },
  boarded: { driver: ['in_progress'] },
  in_progress: { driver: ['completed'], admin: ['completed'] },
  completed: {},
  cancelled: {},
  expired: {},
  no_driver_found: {},
}

export function canTransition(transition: RideTransition): boolean {
  return allowed[transition.from][transition.actor]?.includes(transition.to) ?? false
}

export function assertTransition(transition: RideTransition): void {
  if (terminal.has(transition.from) || !canTransition(transition)) {
    throw new Error(`Invalid ride transition: ${transition.actor} cannot move ${transition.from} to ${transition.to}`)
  }
}

export function assertMoneyAmount(amountMinor: number): void {
  if (!Number.isSafeInteger(amountMinor) || amountMinor < 0) {
    throw new Error('Money must be a non-negative safe integer in minor units')
  }
}

export function assertRideSnapshot(ride: RideSnapshot): void {
  if (!ride.id || !ride.passengerId) throw new Error('Ride and passenger identifiers are required')
  if (!Number.isSafeInteger(ride.version) || ride.version < 0) throw new Error('Ride version is invalid')
  assertMoneyAmount(ride.quotedAmountMinor)
  if (ride.finalAmountMinor !== null) assertMoneyAmount(ride.finalAmountMinor)
  if (['accepted', 'driver_arriving', 'arrived', 'boarded', 'in_progress', 'completed'].includes(ride.status) && !ride.driverId) {
    throw new Error('An assigned driver is required for this ride status')
  }
  if (ride.status === 'completed' && ride.finalAmountMinor === null) {
    throw new Error('A completed ride must have a finalized amount')
  }
}

/** Display-only formatting. Never use floating-point values for stored money. */
export function formatDzd(amountMinor: number, locale = 'ar-DZ'): string {
  assertMoneyAmount(amountMinor)
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: 'DZD',
    maximumFractionDigits: 2,
  }).format(amountMinor / 100)
}
