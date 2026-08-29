# Stripe Organizer Restricted TEST Key Manifest

Date: 2026-08-29 CEST

## Purpose and scope

This redacted manifest defines the maximum permissions allowed for the
temporary Wave 7C Stripe credential. The credential must be a restricted TEST
key (`rk_test`), exclusive to Pachangas IQ, stored only as the sensitive
server-side Vercel Preview variable `STRIPE_TEST_SECRET_KEY` for branch
`codex/organizer-live-pricing-checkout-v1`.

No credential value, Stripe object identifier, customer identity or payment
data belongs in this file, Git, logs, screenshots, Demo World or client code.

## Permission allowlist

| Stripe resource | Permission | Wave 7C call that requires it |
| --- | --- | --- |
| Balance | Read | `stripe.balance.retrieve()` verifies that the TEST API is reachable in `organizerStripeResources()` |
| Products | Read | `products.list()` and `products.retrieve()` select and read back exact Organizer catalog resources |
| Products | Write | `products.create()` provisions an approved TEST catalog intent idempotently |
| Prices | Read | `prices.list()` and `prices.retrieve()` select and read back exact monthly/annual prices |
| Prices | Write | `prices.create()` provisions an approved TEST price intent idempotently |
| Checkout Sessions | Write | `checkout.sessions.create()` creates the four allowlisted TEST subscription checkouts |
| Customers | Write | `customers.create()` creates the canonical Stripe customer only when the billing account has none |
| Customer Portal configurations | Read | `billingPortal.configurations.list()` detects the dedicated Organizer TEST configuration |
| Customer Portal configurations | Write | `billingPortal.configurations.create/update()` creates or reconciles only the Organizer TEST configuration |
| Customer Portal sessions | Write | `billingPortal.sessions.create()` creates an owner-authorized TEST Portal session |
| Webhook endpoints | Read | `webhookEndpoints.list()` verifies that a dedicated enabled Organizer TEST destination exists |

Write permission is not granted to webhook endpoints: the destination is
created once through the authenticated Stripe Dashboard and its signing secret
is stored separately as `STRIPE_TEST_WEBHOOK_SECRET`.

The Organizer webhook verifies signatures locally and writes canonical events
to PostgreSQL; it does not use this API key to fetch Stripe Events,
subscriptions, invoices, refunds or disputes.

## Explicit denials

The restricted key must have no permission for:

- LIVE mode resources or credentials;
- Payouts, Transfers, Connect or Application Fees;
- Refunds, Disputes or charge reversals;
- bank accounts or external accounts;
- tax settings, tax registrations or live tax configuration;
- Payment Links, Issuing, Treasury, Capital or Financial Connections;
- webhook endpoint creation/update/delete;
- Stripe V1 resources or Pachangas production resources.

If Stripe requires an unlisted permission during TEST QA, the request must fail
closed. The failure is recorded before considering one narrowly justified
manifest amendment; broadening the key preemptively is forbidden.

## Environment decision

Preferred target: a Stripe Sandbox exclusive to Pachangas IQ.

Selected target: dedicated blank Sandbox `Pachangas IQ Wave 7C`. It was created
without copying the active account, so no shared Product, Price, Customer,
webhook, Portal or tax setting enters the Wave 7C environment.

Compatibility gate: the existing Wave 7C staging read model, TEST product
metadata, price mappings, webhook mode and Portal health must be reproducible in
that Sandbox without changing application code or mixing account identifiers.
The existing adapter is account-agnostic and its TEST mappings have not yet been
published in staging, so the E2E can provision this Sandbox without application
code changes. The fallback to the shared TEST account is therefore not used.
Stripe LIVE remains untouched.

## Credential implementation readback

- One active replacement restricted TEST credential exists in the dedicated
  Pachangas IQ Sandbox.
- Its seven canonical permission identifiers and the Stripe permission table
  both match this manifest exactly.
- The first created credential was treated as compromised after its one-time
  value appeared in diagnostic accessibility output; it was never installed and
  was immediately expired.
- The replacement was transferred directly through process standard input to
  the sensitive Vercel Preview variable `STRIPE_TEST_SECRET_KEY`.
- Vercel readback shows branch
  `codex/organizer-live-pricing-checkout-v1`, Preview only, sensitive type and
  zero Production matches.
- Source, tracked HEAD, diff, client bundle and worktree-temporary scans contain
  zero Stripe credential values. No public secret variable exists.
- The Organizer TEST runtime accepts the required `rk_test` server credential;
  LIVE validation remains unchanged and no live credential is configured.

## Storage and lifecycle

- Vercel environment: Preview only.
- Git branch: `codex/organizer-live-pricing-checkout-v1` only.
- Visibility: sensitive/secret and server-only.
- Public variable: forbidden; no `NEXT_PUBLIC` alias.
- Production environment: absent.
- Webhook signing secret: separate branch-scoped sensitive variable.
- After Wave 7C QA: remove Preview variables, revoke the temporary restricted
  key, delete temporary Preview resources and retain only redacted textual
  evidence.

## Standard TEST key incident

The standard TEST secret observed during diagnosis is not authorized for Wave
7C. Its usage must be inventoried without PII, its dependent projects migrated
through a coordinated plan, and the credential rotated only after those
dependencies can be updated safely. Wave 7C must not authenticate with it.
