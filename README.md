# MITHAQ

**Smart mobility platform concept for Algeria.**

## Current software status

This repository contains the first runnable web MVP shell:
- Arabic, RTL, responsive interface.
- Passenger booking flow with editable pickup/destination and illustrative fare estimate.
- Driver availability and simulated offer acceptance.
- Basic operations dashboard placeholder.
- Simulated ride lifecycle.
- PWA manifest for install-to-home-screen support.

**Important:** This is a local demonstration only. It does not connect passengers to real drivers, use live GPS/maps, authenticate users, store trips, process payments, or provide emergency response. All ride transitions and prices shown in the interface are simulated.

## Run locally

Requirements: Node.js LTS and npm.

```bash
npm install
npm run dev
```

Open the local URL printed by Vite. To create a production bundle:

```bash
npm run build
npm run preview
```

## Backend setup status

The backend is not connected yet. The next integration is Supabase (PostgreSQL, Auth, Realtime, and Row Level Security). Create a Supabase project, apply the migration in `supabase/migrations`, then add the project URL and publishable/anon key to a local `.env` file based on `.env.example`. Never expose a service-role key in the browser.

## Project areas

- `src/`: web prototype.
- `supabase/migrations/`: database schema and security policies.
- `docs/`: product, architecture, data model, safety, and roadmap.

## Legal and operational boundary

MITHAQ is software under development, not an operating transport company. Before a real pilot, validate Algerian transport permissions, operator/driver eligibility, insurance, consumer terms, privacy requirements, support coverage, and emergency escalation with qualified local sources.

## Development principles

- Synthetic data only until security and privacy controls are reviewed.
- Server-side authorization and pricing; never trust the client for ride state or fare.
- No biometric recognition in the MVP.
- No real payments until legal, accounting, and security reviews are complete.
