# Wave 8A Organizer Onboarding Incidents

Date opened: 2026-08-29 CEST

## Checkpoint

- Base `origin/main`: `e0cbf7bd45f8d38e4edc8bc7dc97fd1272ec355f`.
- Repository migration ledger: 197 forward-only migrations.
- Organizer plan catalog, billing account, access grant and competition
  entitlement authorities: present.
- Canonical public plans: `CLUB_PARTNER`, `CLUB_ORGANIZER` and
  `TEAM_ORGANIZER_PRO`.
- Canonical internal access sources: `PROMOTION`, `PRIVATE_BETA` and
  `PLATFORM_GRANT`.
- Organizer Access Applications, review queue, guided onboarding and First
  Competition Launcher: not present at the checkpoint.
- `live_prices_approved=false`, `live_checkout_enabled=false` and
  `portal_enabled=false` at the preceding production readback.
- Stripe is outside Wave 8A and must remain untouched.

## Permanent boundaries

An application is not an entitlement. Only an explicit, auditable platform
decision may create an existing `CompetitionEntitlementGrant`. Paid-plan
interest never creates `SUBSCRIPTION` access while canonical billing has no
active subscription.

Authority tables accept no direct `INSERT`, `UPDATE` or `DELETE` from `anon`
or `authenticated`. Every write uses an authenticated actor, an idempotent
operation ID, an expected revision, server time and a monotonic server
sequence.

## Incident taxonomy

Every failure found during Wave 8A is recorded before correction as one of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

Resolved incidents must include `fixed` and `regression_verified`.

## Incidents

No Wave 8A incident was open at the initial checkpoint.
