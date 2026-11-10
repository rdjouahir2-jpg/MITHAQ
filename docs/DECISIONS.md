# MITHAQ — Decision Log

Decisions are provisional until validated. Record important changes here with date, context, and consequences.

## D-001 — Start with a modular monolith
**Status:** Accepted for initial design  
**Decision:** Keep the first backend as a modular monolith with clear domain boundaries.  
**Reason:** A solo developer benefits from simpler deployment and debugging; microservices add operational overhead before scale requires them.  
**Revisit when:** team size, load, or independent scaling needs justify service separation.

## D-002 — Keep the repository private
**Status:** Accepted  
**Decision:** The source repository remains private during early development.  
**Reason:** Product and implementation are still evolving. Open-source dependencies may be used only after license review.

## D-003 — Synthetic data only during development
**Status:** Accepted  
**Decision:** Use fake users, drivers, vehicles, locations, and trip records in development and tests.  
**Reason:** Avoid unnecessary exposure of personal data and reduce compliance risk.

## D-004 — Do not build biometric recognition in the MVP
**Status:** Accepted  
**Decision:** Face recognition/templates are excluded from the first MVP pending a separate legal, privacy, necessity, and security assessment.  
**Reason:** Biometrics create high-impact risks and may not be necessary to achieve basic trip verification. A trip PIN and controlled onboarding are safer initial mechanisms to evaluate.

## D-005 — No real payments in the proof of concept
**Status:** Accepted  
**Decision:** Model fare quotes and trip accounting with test values only. No payment processing or custody of funds until legal, accounting, provider, and security requirements are reviewed.  
**Reason:** Avoid financial and regulatory complexity before validating the core ride workflow.
