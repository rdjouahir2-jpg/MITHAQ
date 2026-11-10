# Competitor Feature Benchmark — MITHAQ (Draft 0.1)

Research basis: publicly described features and official product pages/app listings reviewed on 2026-11-10. Availability varies by country, city, account type, and app version. This is a product benchmark, not reverse engineering of private systems.

## Competitor patterns worth learning from

| Pattern | Publicly described example | MITHAQ decision |
|---|---|---|
| Upfront fare estimate | Yassir describes prices shown before booking | Adopt: show estimated/final fare and fee breakdown before confirmation |
| Passenger-proposed fare and driver counter-offers | inDrive describes direct fare negotiation and driver choice | Evaluate as an optional mode after MVP; add guardrails and offer expiry |
| Compare driver offers | inDrive describes choosing by rating, vehicle, ETA, and trip history | Adopt a concise, fair comparison if multiple offers are available |
| Driver availability toggle | Yassir driver app listing | Adopt |
| Driver earnings and trip history | Yassir driver app listing | Adopt |
| Live trip location sharing and safety support | inDrive app listing | Adopt only with scoped access, retention limits, and a real support process |
| Driver/vehicle onboarding and validation | Yassir driver onboarding pages | Adopt a documented manual-review workflow before automation |
| Scheduled trips | Uber help pages describe scheduled rides in selected markets | Defer until dispatch reliability and driver commitment rules are tested |
| Intercity rides | Public Yassir and inDrive descriptions include intercity services | Consider later; separate service rules and pricing required |
| Courier/freight/food/grocery services | inDrive and Yassir public descriptions | Do not include in the first ride-hailing MVP; preserve modular expansion paths |

## MITHAQ product decisions

### Adopt for MVP
- Clear pickup and destination selection.
- Fare estimate before request, with transparent components.
- Passenger request and driver offer/accept flow.
- Driver and vehicle identity details before boarding.
- Driver availability control.
- Trip status timeline and event history.
- Trip PIN to confirm correct boarding.
- Rating and structured feedback after trip.
- Support/safety report entry point with an honest explanation of response availability.
- Driver trip history and transparent earnings summary.
- Admin review of driver and vehicle onboarding.

### Evaluate after core MVP
- Passenger-proposed price with driver counter-offer.
- Scheduled rides.
- Multiple vehicle classes and accessibility/child-seat preferences.
- Intercity trips.
- Trusted-contact trip sharing.
- Corporate/fleet accounts.

### Explicitly not copied
- Competitors' source code, private APIs, private datasets, trade secrets, proprietary visual assets, or confidential operating rules.
- Opaque dynamic pricing or punitive driver acceptance scoring.
- Safety features that imply 24/7 human response unless MITHAQ can actually staff it.

## First release positioning

MITHAQ should compete on clarity and trust, not feature count:
1. Transparent price and trip terms.
2. Driver choice within safe, practical limits.
3. Reliable pickup and boarding verification.
4. Fair driver economics and visible earnings.
5. Responsive local support with clearly stated hours and escalation.
6. Arabic/French-first UX, with English support when feasible.

## Evidence to gather before launch

- Observe publicly available app flows using test accounts and permitted access.
- Record user-visible screens, choices, and edge cases without collecting other users' personal data.
- Interview passengers and drivers about price comprehension, cancellations, trust, and preferred service categories.
- Re-check local availability, rules, and app behavior immediately before making implementation decisions.
