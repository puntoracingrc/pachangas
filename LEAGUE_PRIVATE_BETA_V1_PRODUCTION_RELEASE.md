# League Private Beta V1 - Production Release

## Release checkpoint

- Initial `origin/main`: `161c152fb0423a87304b1549c15e33184cb0de4d`
- Branch: `codex/league-private-beta-v1`
- Status: implementation in progress
- Production modified: no
- Supabase production modified: no

## Productization migrations

1. `20260825074304_league_private_beta_schema_v1.sql`
2. `20260825074353_league_private_beta_commands_v1.sql`
3. `20260825074358_league_private_beta_access_v1.sql`
4. `20260825102400_league_private_beta_fk_indexes_v1.sql`

They are forward-only units installed after the existing 136-entry ledger. The
schema reuses canonical Competition entitlements and R1/R4A-R4D entities; it
does not create a parallel League engine or initialize legacy backfill.

## Local release gates

- Node: `v24.16.0` (repository contract `>=22.13.0`).
- Production build: PASS, 49 static pages generated and `/ligas` present.
- Full suite: PASS, 458/458; skipped/todo/cancelled 0/0/0.
- Wave 2 contract: PASS, 16/16.
- Typecheck: PASS.
- Focused lint for every Wave 2 TypeScript/JavaScript route: PASS.
- Global lint: pre-existing debt remains at 22 errors and 18 warnings in
  `app/legal-data.tsx`, `app/mercado/page.tsx`, and `app/page.tsx`; no Wave 2
  focal finding.
- SQL/RLS/idempotency/adversarial: PASS on a temporary local PostgreSQL 17
  database.
- Bootstrap and upgrade: PASS; exact 136 -> 140 ledger and fresh/upgraded
  schemas are equivalent.
- Concurrency: PASS for replay, competing creates, competing step writes, and
  competing revocations.
- Scale: PASS with 120 active bundles, bounded 100-row read models, stable
  ordering, and isolated temporary-database cleanup.
- `git diff --check`: PASS.

## Authority and privacy

- Every mutation uses authenticated RPC/API intent with `operationId` and
  `expectedRevision`; PostgreSQL resolves actor, sequence, time, grants, rules,
  capacity, and canonical materialization.
- The PWA stores a derived read cache only. Offline writes are never queued or
  shown as confirmed.
- Realtime carries scoped invalidations and clients refetch canonical models;
  WAL payloads are not applied as authority.
- Private League pages and APIs are `noindex`, `nofollow`, and `no-store`.
- Public registration, calendars, standings, exception status, referee
  assignments, discipline, payments, and tournaments remain unavailable.

## Authorized scope

Productize the existing R1 and R4A-R4D foundations as a private,
invite-only League beta. League creation requires both the global product gate
and an explicit, unexpired organizer entitlement.

The release must keep public registration, public calendars, public standings,
public exception status, referee assignments, competition discipline, payments,
tournaments, and the canonical legacy backfill disabled.

## Evidence

This report will be completed with the exact migrations, flags, grants, tests,
staging run, production activation, rollback evidence, and final SHAs before the
release is closed.

## Defect register

| ID | Classification | Original scenario | Status | Regression |
| --- | --- | --- | --- | --- |
| LPB-001 | PRODUCT_BUG | Two platform operators raced to revoke the same active beta bundle. Both calls failed because the RPC variable `bundle_id` was ambiguous with the entitlement column. | fixed + regression_verified | `tests/league-private-beta-v1-concurrency.mjs` repeats the two-client revocation and requires one canonical effect plus one explicit stale conflict. |
| LPB-002 | PRODUCT_BUG | Platform bundles and private organizer/wizard lists were not all bounded, so their read models could grow indefinitely. | fixed + regression_verified | SQL now caps each list at 100 with stable ordering; `tests/league-private-beta-v1-scale.sql` verifies 120 bundles produce a bounded response and accurate global metrics. |
| LPB-003 | TESTABILITY_GAP | Staging advisor readback exposed eight new foreign keys without dedicated covering indexes before the product had representative traffic. | fixed + regression_verified | A forward-only fourth migration adds all eight indexes; static coverage and a repeated staging advisor readback verify the original warnings disappear. |
