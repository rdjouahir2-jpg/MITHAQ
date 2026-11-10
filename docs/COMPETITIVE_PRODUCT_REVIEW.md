# Competitive product review for MITHAQ

This is a feature-design reference based on publicly observable product patterns, not a claim of access to competitor internals. Do not copy proprietary source code, branding, private data, or protected UI assets.

## Product patterns worth evaluating

| Pattern | Public market examples | MITHAQ product decision |
|---|---|---|
| Fast request and driver dispatch | Uber, Yassir | Clear pickup, destination, category, and request confirmation |
| Passenger-driver price negotiation | inDrive | Optional offer/counter-offer mode only after safety and pricing rules are designed |
| Upfront fare estimate | Uber, Yassir | Show a transparent estimate and explain what can change it |
| Driver profile and vehicle details | Major ride-hailing apps | Show verified driver identity status and vehicle information after assignment |
| Live trip progress | Major ride-hailing apps | Realtime location and trip stages after backend + consent controls exist |
| Trip sharing and emergency help | Major ride-hailing apps | Add a trusted-contact share flow and a staffed incident escalation process before real trips |
| Ratings and support | Major ride-hailing apps | Two-way ratings, report categories, and human review with anti-abuse controls |
| Multiple service categories | Major ride-hailing apps | Economy / Comfort / Family as initial product categories, subject to local fleet realities |

## MITHAQ differentiation to test

1. Clear support for booking on behalf of a relative, with explicit consent and clear passenger identity.
2. Stronger pre-trip clarity: fare type, driver/vehicle details, pickup instructions, and cancellation terms.
3. Low-bandwidth and Arabic-first experience, with French support.
4. A human-verifiable safety process; do not promise AI face recognition or emergency response that is not operational.
5. Driver fairness: transparent commission, dispute process, and understandable offer expiry.

## What not to copy blindly

- Surge pricing or opaque multipliers.
- Cashless-only assumptions where local payment coverage is uncertain.
- Biometric collection before a lawful basis, necessity assessment, and secure retention plan.
- A negotiation feature without anti-harassment, offer limits, and cancellation rules.

## Validation before implementation

Interview passengers and drivers in the proposed pilot area. Test willingness to pay, expected driver earnings, acceptable pickup wait, cash preference, cancellation behavior, and trust concerns. Do not choose pricing from a UI mock-up.
