# MITHAQ

**A safety-conscious, locally adapted mobility platform concept for Algeria.**

MITHAQ is being designed as a ride-hailing platform with passenger, driver, and operations experiences. The project is starting with product definition and technical foundations before implementation or any real-world pilot.

## Project principles

- Build for Algerian operating realities; validate legal, insurance, payment, and connectivity assumptions before launch.
- Prioritize passenger and driver safety, privacy, and transparent trip handling.
- Start with a tightly scoped MVP in one launch area; expand only after evidence from a controlled pilot.
- Use a modular, maintainable architecture and prefer open standards and cost-conscious infrastructure.
- Learn and document each subsystem rather than generating an opaque application.

## Current status

**Phase:** Foundation and product definition  
**Not yet implemented:** production backend, mobile apps, dispatch, payments, live tracking, or deployment.

## Documentation

- [Product requirements](docs/PRODUCT_REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Data model](docs/DATA_MODEL.md)
- [Roadmap](docs/ROADMAP.md)
- [Security and privacy](docs/SECURITY_PRIVACY.md)
- [Decision log](docs/DECISIONS.md)

## Proposed initial technology direction

The stack is a proposal, not a final lock-in: TypeScript, Expo/React Native for mobile clients, PostgreSQL with PostGIS for geospatial data, and a modular backend. Mapping should use an open-data-friendly approach where practical. Technology choices will be validated against device constraints, operating cost, licensing, and maintainability before implementation.

## Important boundary

MITHAQ is currently a software project. This repository does not authorize or represent an active passenger transport service. No real rides, identity documents, payments, or precise location data should be collected during development. Legal and operational requirements must be reviewed with qualified local sources before any pilot.

## Contributing and ownership

This repository is private and currently maintained by its owner. Do not add secrets, API keys, personal data, identity documents, or production credentials to Git history.
