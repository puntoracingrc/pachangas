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
| Valid/invalid/tampered signature | Covered locally; remote TEST pending final QA |
| Duplicate/out-of-order event | PASS locally |
| Unknown Price / V1 Product at V2 endpoint | PASS locally |
| Four TEST Checkout combinations | Pending controlled remote TEST QA |
| Success redirect without entitlement | PASS by contract and tests |
| Portal owner / transfer / role rejection | PASS locally; remote TEST pending |
| Payment failure / grace / recovery | PASS locally and Demo V2.9 |
| LIVE Checkout and Portal | OFF / not exercised |

Credential gate: PASS for one least-privilege `rk_test` credential stored as a
sensitive branch-scoped Preview variable; Production and public client bundles
contain no matching secret. The dedicated Organizer TEST webhook signing secret
and Supabase staging service authority remain pending before remote QA.

This report is updated with the final remote TEST result before release closure.
The remaining remote gates require branch-scoped server credentials and a
dedicated TEST webhook/Portal; no LIVE credential or resource is authorized.
