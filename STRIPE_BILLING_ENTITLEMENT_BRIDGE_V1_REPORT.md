# Stripe Billing Entitlement Bridge V1 Report

Date: 2026-08-28 CEST

## Stripe Read-only Audit

The signed-in live Stripe account was inspected without modifying any Product, Price, tax setting, webhook or customer.

- Eleven active products exist in the shared account.
- Two live Pachangas IQ products exist: a monthly base activation at EUR 5.99/month and an annual base activation at EUR 64.99/year.
- Both use the electronically supplied services tax category and tax-inclusive Prices.
- Neither Product has metadata that maps it to `CLUB_ORGANIZER` or `TEAM_ORGANIZER_PRO`.
- The existing Pachangas production webhook targets `/api/stripe/webhook`, is active and listens to six V1 events: Checkout completion, subscription create/update/delete and invoice payment success/failure.
- The existing products and webhook remain untouched.

Conclusion: these are valid base-subscription assets but not evidence authorizing organizer-plan pricing. `live_prices_approved=false` and `live_checkout_enabled=false` remain mandatory.

## Bridge Contract

- Hosted Checkout and Billing Portal are server-created intents; the browser cannot select Stripe mode, Product or Price.
- A Checkout success redirect never grants access.
- Signed webhooks are normalized into a private idempotent event ledger and then projected transactionally.
- Canonical organizer entitlements, not Stripe objects, authorize competition capabilities.
- Duplicate events replay one stored receipt. Stale projections fail closed against revision/sequence.
- Expiration and reconciliation run under service authority and server time.
- Reconciliation processes expiration before claiming drift work.
- Full Stripe customer, subscription, Price and invoice identifiers stay private and are redacted from owner and ordinary platform read models.

## Webhook Coverage

The Wave 7B endpoint supports the organizer projection lifecycle while preserving the V1 endpoint. A separate destination can be installed after deployment without enabling Checkout. Test and live secrets remain server-only; no `service_role` or Stripe secret enters the browser bundle.

## Status

Foundation and sandbox contracts: READY.

Live organizer pricing: `AWAITING_PRICE_APPROVAL`.

Arbitrary live charge created: no.
