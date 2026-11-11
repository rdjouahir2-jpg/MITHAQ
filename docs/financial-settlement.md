# MITHAQ fare collection and driver settlements

## Accounting model

All amounts are integer minor units in DZD. A completed ride creates one immutable `ride_financials` snapshot using the commission policy that was active at completion. The snapshot records gross fare, policy version, commission basis points, commission amount and driver net amount.

The platform commission is deliberately **not preconfigured**. An administrator must enter and approve a percentage (0–30%) before the first ride can be completed in this environment. This avoids silently choosing a commercial rate on behalf of the business owner. The administrator UI labels whether the active rate is still provisional or was explicitly configured.

The signed, append-only driver ledger uses this convention:

- Positive balance: money the platform owes the driver.
- Negative balance: commission or another amount the driver owes the platform.
- Cash paid directly to the driver: records a negative commission due when collection is confirmed.
- Cash/manual transfer collected by the platform: credits the driver's net fare.
- Commission remittance and driver payout: append balancing ledger entries; existing entries cannot be edited or deleted.

Payout requests reserve available positive balance while pending/approved. An administrator must approve a request and then confirm the actual transfer with an external payment reference before it is marked paid.

## Current payment scope

There is no card gateway, wallet top-up, bank API, or Algeria-specific payment processor connected. The current workflow records cash collection and manual transfer evidence; it does not charge a card or initiate a bank/postal transfer automatically. A real provider integration requires a separate provider contract, credentials, webhook verification, refund/reconciliation handling and legal review.

## Operational safeguards

- Commission rates are versioned; a change affects future completed rides only.
- Completed ride fare and commission snapshots are immutable.
- Client roles cannot insert or edit financial ledger rows directly.
- Admin RPCs check the authenticated admin role and write audit records.
- Driver reads are scoped to the driver's own financial history and payout requests.
- A paid payout requires an admin reference and creates a negative ledger entry.
- Do not deploy the migration to the hosted project until the commission percentage, payment method, tax/accounting treatment and payout process have been approved.

## Database tests

`008_driver_financial_ledger.sql` tests policy activation, commission arithmetic, manual collection, payout approval/payment, ledger immutability, and the cash commission remittance path. These are isolated pgTAP tests; they do not move real money.
