# Organizer Live Pricing V1 Report

Date: 2026-08-29 CEST

## Product and Price authority

Stripe Products and Prices are external payment resources, not Pachangas IQ
access authority. PostgreSQL confirms a mapping only after a server-side
allowlisted intent creates or reuses an exact Stripe resource and reads it
back successfully.

Required metadata is exact and mode-separated:

- `product_family=organizer`
- `plan_code`
- `organizer_kind`
- `environment=test|live`
- `catalog_revision`

The adapter rejects arbitrary browser IDs, duplicate exact Products or Prices,
mode mismatches, amount drift, interval drift, metadata drift and tax-behavior
drift. A retry with the same `operationId` is idempotent; a new operation first
reads and reuses the unique exact resource.

## Temporary TEST catalog

The isolated Wave 7C QA catalog contained only:

| Product | Monthly | Annual | Mode |
| --- | ---: | ---: | --- |
| Pachangas IQ - Club Organizer | EUR 29 | EUR 290 | TEST |
| Pachangas IQ - Team Organizer Pro | EUR 9.90 | EUR 99 | TEST |

The Stripe Dashboard readback confirmed both Products, all four recurring
Prices, active state, zero active subscriptions and all five metadata pairs on
2026-08-29. Their opaque Stripe IDs are intentionally excluded from reports
and Demo World.

After authenticated QA, the dedicated `Pachangas IQ Wave 7C` TEST environment
was retired atomically. Its webhook, Products, Prices, standard key and
restricted key are no longer active. PostgreSQL staging catalog mappings and
runtime TEST health were reset, while Production retains zero TEST mappings.

## LIVE boundary

No LIVE Organizer Product or Price is authorized by this wave. LIVE creation
requires a published decision, `LIVE_READY` tax health, current Terms and
Privacy revisions, a healthy LIVE webhook and Portal, and platform-owner
confirmation. Price changes create a new immutable Stripe Price and plan
revision; published amounts are never edited in place.

## Isolation

The Organizer endpoint is `/api/webhooks/stripe`; Stripe V1 remains on
`/api/stripe/webhook`. Wave 7C does not modify V1 Products, Prices, Customers,
subscriptions, mappings, metadata, webhook destination or reconciliation.

## Verification state

Local SQL, static isolation, idempotency, concurrency and representative volume
are PASS on ledger 197. Controlled staging QA verified the dedicated signed TEST
webhook, all four Checkout price/interval combinations without payment,
owner-only Portal, invoice failure/recovery, cancellation/resume and two-client
Realtime convergence. Exact redacted outcomes are recorded in
`STRIPE_ORGANIZER_CHECKOUT_PORTAL_V1_REPORT.md`.

Release readback confirms exact Production ledger 197, all commercial and LIVE
flags OFF, zero LIVE mappings and no real charge. The production adapter and
schema remain available for a later explicitly authorized commercial
activation; this release does not leave Stripe TEST credentials or catalog
resources deployed.
