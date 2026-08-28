# Wave 7C Commercial Activation Incidents

Date opened: 2026-08-28 CEST

## Checkpoint

- Base `origin/main`: `0040f750dc935ccb43a0f2ccfcf65a243bcb40ef`.
- Supabase production ledger: 190 migrations at the preceding Wave 7B readback.
- Organizer Billing Foundation, plan catalog, partnership grants, sandbox, webhook ingest and reconciliation: active.
- Organizer live Price mappings, billing accounts and Stripe V2 events: 0.
- `live_prices_approved=false`.
- `live_checkout_enabled=false`.
- `portal_enabled=false`.
- `tax_health=UNCONFIGURED`.
- Stripe V1: protected invariant.

## Permanent commercial boundary

The proposed Organizer amounts are non-authoritative test fixtures until a
`platform_owner` records a complete commercial decision through the canonical
approval workflow. Wave 7C must not create live Prices, enable live Checkout or
create a real charge without that decision and `tax_health=LIVE_READY`.

## Incident taxonomy

Every failure found during this wave is recorded here before correction as one
of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

Resolved incidents must include `fixed` and `regression_verified`.
