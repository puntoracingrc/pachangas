# Organizer Plans V1 Report

Date: 2026-08-28 CEST

## Scope

Wave 7B adds one server-owned organizer catalog without replacing the existing Team subscription:

| Plan | Organizer | Access model | Stripe required | V1 release state |
| --- | --- | --- | ---: | --- |
| `CLUB_PARTNER` | Club | Audited partnership | No | Technically activatable |
| `CLUB_ORGANIZER` | Club | Subscription | Yes | Catalog only, price approval pending |
| `TEAM_ORGANIZER_PRO` | Team | Subscription add-on | Yes | Catalog only, price approval pending |
| `PROMOTION` | Any | Internal promotion | No | Internal only |
| `PRIVATE_BETA` | Any | Private beta | No | Internal only |
| `PLATFORM_GRANT` | Any | Platform grant | No | Internal only |

`TEAM_ORGANIZER_PRO` is an add-on. It never cancels, replaces, upgrades or becomes the authority for the base Team subscription.

## Authority

- PostgreSQL owns the catalog, immutable plan revisions, features, limits, accounts, subscriptions, grants, continuity and final entitlements.
- Every write uses an authenticated actor, idempotent `operationId`, expected revision, server clock and monotonic server sequence.
- Clients send semantic intent only. Realtime invalidates a scoped read model and the client refetches the canonical snapshot.
- Local storage caches only derived catalog or owner read models. There is no offline billing or sporting write queue.
- Limits are enforced only when an approved persisted limit exists. The browser cannot invent a commercial limit.

## Product Surfaces

- `/planes-organizador`: public canonical catalog with explicit unavailable and price-pending states.
- `/ajustes/facturacion`: owner-only account, entitlement, continuity, usage, invoices, Checkout and Portal intents.
- `/admin/billing`: platform control for flags, approved Price mappings, grants, reconciliation and redacted operational health.
- Profile navigation exposes Plans to all users and Billing only to the Team owner.

## Verification

- Focused Organizer Billing and Demo suites: 29/29.
- Full repository: Node 20/20 plus TS/TSX 586/586, total 606/606; zero fail, skip, todo or cancelled.
- Typecheck and production build: PASS, 56 static pages.
- SQL/RLS/idempotency/continuity: PASS, local ledger 190.
- Concurrency: replay, stale revision, duplicate Stripe event, expiration race and reconciliation race PASS.
- Scale: 2,000 accounts, 2,000 subscriptions, 4,000 invoices, 10,000 events, 10,000 deliveries, 10,000 reconciliations and 37,660 entitlements; zero ungranted locks and all thresholds met.
- Responsive browser QA: 1440x900, 390x844 and 844x390; zero horizontal overflow and zero console warnings/errors.

## Release Boundary

The foundation is releasable with all flags born OFF. Catalog and non-commercial access may be enabled independently. Live Checkout remains blocked until an organizer-specific Product/Price mapping and tax posture are explicitly approved.
