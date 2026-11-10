# MITHAQ — Initial Data Model (Draft 0.1)

This is a conceptual schema, not a migration or deployed database. Use UUID primary keys, UTC timestamps, foreign keys, constraints, and indexes. Store only data needed for a defined purpose.

## Core entities

### users
- `id` UUID primary key
- `phone_e164` nullable/unique after verification; avoid exposing it to other users
- `email` nullable
- `display_name`
- `role_flags` or, preferably, linked role assignments
- `account_status` (pending, active, restricted, closed)
- `created_at`, `updated_at`

Authentication secrets belong to a trusted identity provider or securely hashed credential store, never plaintext.

### user_roles
- `user_id`, `role` (passenger, driver, support, admin)
- unique pair; privileged role grants must be auditable.

### driver_profiles
- `id`, `user_id` unique
- `onboarding_status`
- `verification_status`
- `availability_status`
- `approved_at`, `created_at`, `updated_at`

### vehicles
- `id`, `driver_id`
- `make`, `model`, `year`, `color`
- `registration_reference` (restricted; avoid unnecessary document copies)
- `seat_capacity`
- `eligibility_status`

### driver_documents
- `id`, `driver_id`, `document_type`
- secure object reference, verification status, expiry date
- retention/deletion metadata
- access must be restricted and audited; do not store document bytes in ordinary database rows or Git.

### service_areas
- `id`, `name`, `boundary` (PostGIS geometry)
- `status`, `operating_hours`

### fare_policies
- `id`, `service_area_id`, `version`, `currency_code`
- `base_amount_minor`, `distance_rate_minor`, `time_rate_minor`, `minimum_amount_minor`
- effective dates and active status
- Store a policy snapshot on each quote/ride so historic fares remain explainable.

### ride_quotes
- `id`, `passenger_id`, pickup/dropoff geospatial points
- route estimate, distance and duration estimates
- `fare_policy_version`, `estimated_amount_minor`, `currency_code`
- `expires_at`, `created_at`

### rides
- `id`, `passenger_id`, `driver_id` nullable until assigned
- pickup/dropoff points and user-facing place labels
- `status`, `fare_amount_minor`, `currency_code`
- `quote_snapshot`, `requested_at`, `accepted_at`, `started_at`, `completed_at`
- cancellation reason and actor where relevant

### ride_offers
- `id`, `ride_id`, `driver_id`
- `status` (sent, accepted, declined, expired, withdrawn)
- `offered_at`, `expires_at`, `responded_at`
- Enforce one accepted driver per ride at the database/domain level.

### ride_events
- `id`, `ride_id`, `actor_user_id` nullable for system events
- `event_type`, `from_status`, `to_status`, `reason_code`
- minimal structured metadata, `created_at`
- Append-only for normal application roles.

### active_ride_locations
- `id`, `ride_id`, `driver_id`, `position`, `recorded_at`
- short retention; collect only during a justified active service window.

### safety_reports
- `id`, `ride_id` nullable, `reporter_user_id`
- `category`, `severity`, `description`, `status`
- restricted assignment and access log; avoid storing unnecessary sensitive narrative.

### support_tickets
- `id`, `user_id`, `ride_id` nullable, `category`, `status`
- `assigned_to`, timestamps, resolution code.

### audit_logs
- `id`, `actor_user_id`, `action`, `target_type`, `target_id`
- timestamp, reason, minimal metadata
- protect from ordinary modification and review access regularly.

## Important constraints and indexes

- Unique verified phone number where present.
- Foreign keys for all relationships.
- Geospatial indexes (GiST) for service areas and active driver positions.
- Index rides by status and request time; offers by ride/driver/status/expiry.
- Enforce valid state transitions in the domain layer and transaction boundary.
- Use check constraints for non-negative monetary values and valid capacities.
- Use integer minor currency units and explicit currency code.
- Separate personally identifying information from operational analytics where feasible.

## Deliberately deferred

No biometric templates, face embeddings, passenger identity scans, wallet balances, card details, or government ID image storage in the first development schema. These require a separate necessity, legality, security, retention, and vendor assessment.
