# Stripe Organizer Checkout and Portal V1 Report

Date: 2026-08-29 CEST

## Runtime contract

- Dedicated Organizer endpoint: `/api/webhooks/stripe`.
- Stripe V1 endpoint remains `/api/stripe/webhook`.
- Signing secrets are server-only and never enter Git, browser bundles,
  responses, logs or Demo World.
- Eleven allowlisted event types cover Checkout, subscription, invoice and
  customer lifecycle changes.
- Signature, endpoint mode, Product family, Price allowlist, ordering and
  duplicate delivery checks all fail closed.

## Checkout authority

The four TEST combinations are `CLUB_ORGANIZER` monthly/annual and
`TEAM_ORGANIZER_PRO` monthly/annual. The browser sends only organizer, plan,
interval, expected revision and `operationId`. The server resolves owner,
billing account, Customer, Price mapping, mode and return URLs.

A successful redirect produces only a `confirming` UI state. It never grants
access. Only a verified webhook processed into the canonical billing ledger
may grant an entitlement. Cancel and expired sessions grant nothing; duplicate
events cannot duplicate access; the Team add-on never mutates the Team base
subscription.

## Portal authority

The TEST Portal supports customer details, payment method, invoice history,
at-period-end cancellation and allowlisted monthly/annual changes. Portal
creation revalidates the current Club or Team owner under the same canonical
row lock used by ownership transfer. Admins and viewers are rejected, stale
owner intents are expired, Customer IDs never reach UI responses and offline
requests fail closed.

## Verification matrix

| Gate | State |
| --- | --- |
| Two TEST Products / four TEST Prices | PASS; metadata exact, zero active subscriptions |
| Valid/invalid/tampered signature | PASS; official Stripe-origin TEST delivery returned 200 and an invalid signature returned 400 |
| Duplicate/out-of-order event | PASS locally and on staging canonical ingestion |
| Unknown Price / V1 Product at V2 endpoint | PASS locally |
| Four TEST Checkout combinations | PASS for TEST page, plan, amount, interval and canonical intent; no hosted payment submitted |
| Success redirect without entitlement | PASS by contract and tests |
| Portal owner / transfer / role rejection | PASS locally and staging; replay is idempotent |
| Payment failure / grace / recovery | PASS locally, staging with two clients and Demo V2.9 |
| Cancellation / resume | PASS; one auditable access grant, monotonic revision and Realtime convergence |
| LIVE Checkout and Portal | OFF / not exercised |

Credential gate: PASS for one least-privilege `rk_test` credential stored as a
sensitive branch-scoped Preview variable; Production and public client bundles
contain no matching secret. The dedicated Organizer TEST webhook uses its own
branch-scoped signing secret and is separate from Stripe V1.

Stripe-origin signature verification and canonical projection tests are kept
separate: lifecycle, duplicate, out-of-order, invoice, cancellation and resume
scenarios were injected through the service-only staging processor after the
signed HTTP boundary had been independently proved. They are not described as
Stripe-origin deliveries.

The hosted Checkout disclosure control could not be completed through the
browser adapter, so QA deliberately stopped before payment submission. This is
tracked as W7C-159 and does not weaken the server, SQL, signature, Portal or
Realtime evidence. No LIVE credential, resource or charge is authorized.
