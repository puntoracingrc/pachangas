# Organizer Commercial Decision V1 Report

Date: 2026-08-29 CEST

## Scope

Wave 7C adds one PostgreSQL-owned commercial approval workflow on top of the
existing Organizer Billing foundation. It does not replace the Wave 7B plan
catalog, billing account, subscription projection, entitlement or continuity
models.

The only initial proposals are:

| Plan | Monthly proposal | Annual proposal | Authority state |
| --- | ---: | ---: | --- |
| `CLUB_PARTNER` | EUR 0 | EUR 0 | Existing non-Stripe partnership |
| `TEAM_ORGANIZER_PRO` | EUR 9.90 | EUR 99 | TEST fixture; LIVE not approved |
| `CLUB_ORGANIZER` | EUR 29 | EUR 290 | TEST fixture; LIVE not approved |

No amount in this report is a live commercial or tax decision.

## Canonical workflow

`draft -> pending_approval -> approved -> published`, with the bounded exits
`approved -> withdrawn` and `published -> superseded`. Published rows are
immutable. Every command includes an authenticated platform actor, stable
`operationId`, expected revision, server time, monotonic sequence and audit
receipt.

Only `platform_owner` may approve, withdraw, publish a Stripe catalog or
activate LIVE Checkout. The browser cannot submit actor identity, Product ID,
Price ID, tax result or calculated entitlement as authority.

## Tax boundary

The canonical states are `UNCONFIGURED`, `COMMERCIAL_DECISION_PENDING`,
`TAX_REVIEW_REQUIRED`, `TEST_READY`, `LIVE_READY` and `BLOCKED`. Wave 7C does
not decide VAT inclusion, VAT rate, reverse charge, exemptions or invoicing
obligations. LIVE publication and Checkout remain blocked unless an explicit
platform decision has reached `LIVE_READY`.

## Verification

- Focused commercial contract tests: 11/11 PASS; combined Wave 7B/7C suite: 24/24 PASS.
- SQL, RLS, RBAC and idempotency: PASS on a fresh 197-migration database.
- Nine requested concurrency races: PASS with one canonical winner and a
  stale, replayed or fail-closed loser.
- Direct authenticated writes to private decisions, protected settings and
  live mappings: rejected.
- Existing Stripe V1 routes, resources and authority remain unchanged.
- The six planned commercial migrations remain unchanged; authenticated
  staging QA added one separate forward-only RLS predicate-execution hotfix.

## Release state

The workflow can be deployed and enabled independently while all LIVE
commercial flags remain OFF. Final production SHA, ledger readback and feature
flag revisions are recorded in `ORGANIZER_LIVE_CHECKOUT_V1_PRODUCTION_RELEASE.md`.
