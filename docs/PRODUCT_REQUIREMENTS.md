# MITHAQ — Product Requirements (Draft 0.1)

## 1. Product intent

Design a trustworthy, understandable, and locally adaptable ride-request service for an initial Algerian launch area. MITHAQ should make it easy to request a ride, understand the offer and trip state, identify the assigned driver and vehicle, and get help when something goes wrong.

This document describes a proposed product. It is not evidence of market demand, legal approval, insurance coverage, or operational readiness.

## 2. Users and roles

- **Passenger:** requests and manages rides, sees trip information, shares trip status, and reports a safety or service issue.
- **Driver:** completes onboarding, manages availability, receives and responds to ride offers, and records trip progress.
- **Operations administrator:** reviews onboarding status, monitors active service issues, manages service areas and fare policies, and handles support.
- **Support/safety operator:** handles reports using restricted, auditable access.

Roles must be separated. A driver must not gain administrative access, and support access must be limited to the cases and data required.

## 3. Initial MVP scope

### Passenger
- Sign up and authenticate.
- Manage a minimal profile.
- Set pickup and destination using a map or searchable place.
- Review an estimated fare or clearly described offer mode before confirming.
- Request a ride and view its state.
- See assigned driver and vehicle details relevant to pickup.
- Cancel under clearly stated rules.
- Confirm boarding using a short trip PIN.
- View trip progress and share a trip link or status with a trusted contact.
- Rate the completed trip and submit a support/safety report.

### Driver
- Register and submit required onboarding information through a secure process.
- Set availability.
- Receive a ride offer with pickup, destination, estimated distance/time, and fare terms.
- Accept or decline an offer.
- Navigate to pickup using an external or integrated navigation option.
- Confirm passenger boarding with the trip PIN.
- Start, complete, or report an interrupted trip.
- View trip history and a transparent earnings summary.

### Operations
- Review and approve/reject driver onboarding.
- Configure service areas and fare rules.
- View ride states and operational exceptions.
- Handle support and safety reports with an audit trail.
- Suspend accounts or trips when justified, with recorded reasons.

## 4. Ride lifecycle

Proposed state sequence:

1. `draft` — passenger is preparing a request.
2. `requested` — request submitted and awaiting matching.
3. `offered` — one or more eligible drivers receive an offer.
4. `accepted` — a driver accepts; assignment is reserved.
5. `driver_arriving` — driver is proceeding to pickup.
6. `arrived` — driver indicates arrival.
7. `boarded` — passenger verifies the trip PIN.
8. `in_progress` — trip has started.
9. `completed` — trip ends and fare is finalized.
10. Terminal alternatives: `cancelled`, `expired`, `no_driver_found`, `disputed`.

Every transition must be validated server-side and recorded as an event. Clients must not be able to set arbitrary states.

## 5. Fare modes to evaluate

- **Estimated/fixed quote:** platform calculates a quote from configured rules.
- **Open offer:** passenger proposes a price and eligible drivers can respond.
- **Negotiated smart offer:** system suggests a range and supports a bounded counter-offer flow.

Do not enable all modes by default. Compare user comprehension, driver acceptance, abuse potential, and legal/accounting implications in research before selecting the first MVP mode. All fees and cancellation rules must be shown before confirmation.

## 6. Safety and trust requirements

- Verify driver and vehicle eligibility before enabling driver availability.
- Use a trip PIN to reduce wrong-passenger/wrong-vehicle boarding.
- Provide an in-trip help and emergency pathway appropriate to local realities.
- Allow a passenger to request a ride for another person only with clear consent and accurate contact/boarding details.
- Design guardian-assisted journeys for minors only after legal and safeguarding review; do not enable independent minor accounts by default.
- Offer a documented alternative process for users unable or unwilling to use face verification. Face recognition must not be assumed mandatory or implemented without legal, privacy, security, and proportionality review.
- Do not store raw biometric templates or identity document images in application logs or ordinary analytics.

## 7. Out of scope for the first MVP

- Autonomous or algorithmic surge pricing.
- Cashless wallet or holding customer funds.
- Public launch across multiple wilayas.
- Automated facial recognition.
- Complex subscriptions, loyalty systems, and corporate accounts.
- Predictive driver scoring or opaque passenger/driver ranking.
- Any feature that requires unvalidated regulatory permissions.

## 8. Product success measures

Measure during a lawful, controlled pilot only:
- Request-to-accepted rate.
- Median time to driver acceptance and pickup.
- Completion and cancellation rates, segmented by reason.
- Repeat usage and support contact rate.
- Safety reports and time to acknowledge/resolve them.
- Driver earnings transparency and driver retention.
- App reliability on common lower-end Android devices.

Do not optimize growth at the expense of safety or driver economics.

## 9. Open questions before implementation

- Which exact city/area can be served lawfully and operationally?
- What authorizations, operator status, insurance, driver eligibility, and vehicle requirements apply?
- Which payment and cash-handling model is permitted and practical?
- What local language set is required for the pilot (Arabic, French, and potentially Tamazight)?
- What fare model is understandable and economically sustainable?
- What minimum support coverage and emergency escalation can actually be provided?
