# Organizer Plans and Stripe Billing V1 Production Release

Date: 2026-08-28 CEST

## Release identity

- Starting `main`: `42e697e294ba2849b1cb5116f2aec24b29f010f9`.
- Functional branch HEAD: `fbcf1ac42db1233753040e1f6a1502b544c01753`.
- Pull request: [#217](https://github.com/puntoracingrc/pachangas/pull/217), merged at `2026-08-28T19:50:58Z`.
- Production merge SHA: `9b7b66b8a12f6b38c2c4a54e5fd2349f938f3fb4`.
- Vercel deployment: `dpl_GFNzvqeC44WTzwRzgnax3nTzKn2j`, `READY`, target `production`, Node `24.x`.
- Production URL: [https://pachangasiq.com](https://pachangasiq.com).

## Validation gates

| Gate | Result |
| --- | --- |
| Full tests | PASS, Node 20/20 + TS/TSX 586/586 = 606/606 |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Typecheck | PASS |
| Production build | PASS, 56 static pages |
| Focused Wave 7B TS/TSX lint | PASS, 0 findings |
| Global lint | PRE-EXISTING DEBT, 22 errors and 18 warnings |
| SQL/RLS/idempotency | PASS |
| Concurrency | PASS |
| Representative scale | PASS |
| `git diff --check` | PASS |
| Production desktop/portrait/landscape | PASS |
| Installed physical PWA | PENDING; not claimed from browser emulation |

The global lint findings remain confined to pre-existing debt in `app/legal-data.tsx`, `app/mercado/page.tsx` and `app/page.tsx`. Every Wave 7B-owned TS/TSX file is clean.

## Database deployment

The seven forward-only migrations were applied in order to the linked Pachangas IQ Supabase project:

1. `20260828163750_organizer_billing_accounts_plan_catalog_v1.sql`
2. `20260828163751_stripe_event_ledger_projections_v1.sql`
3. `20260828163752_organizer_billing_entitlement_continuity_v1.sql`
4. `20260828163753_organizer_billing_commands_manual_grants_v1.sql`
5. `20260828163754_organizer_billing_read_models_control_center_v2.sql`
6. `20260828163755_organizer_billing_access_realtime_v1.sql`
7. `20260828163756_organizer_billing_hardening_flags_v1.sql`

`supabase migration list --linked` shows exact local/remote parity through `20260828163756`; the production migration ledger contains 190 rows. Existing migrations were not rewritten.

## Controlled activation

All activation writes used `command_pachanga_organizer_billing_platform_v1` with authenticated actor, stable `operationId`, expected revision, server time and audit metadata. No direct settings `UPDATE` was used.

| Setting | Final value |
| --- | --- |
| `foundation_enabled` | `true` |
| `plan_catalog_enabled` | `true` |
| `partner_grants_enabled` | `true` |
| `billing_accounts_enabled` | `true` |
| `organizer_ui_enabled` | `true` |
| `webhook_ingest_enabled` | `true` |
| `reconciliation_enabled` | `true` |
| `stripe_sandbox_enabled` | `true` |
| `demo_world_v28_enabled` | `true` |
| `portal_enabled` | `false` |
| `live_checkout_enabled` | `false` |
| `live_prices_approved` | `false` |
| `tax_health` | `UNCONFIGURED` |
| Revision / server sequence | `10` / `32` |

The nine activation commands produced nine operation receipts and nine immutable billing events. The first scheduled billing run later added the expected two no-op audit pairs for `billing.expire` and `reconciliation.claim`, bringing both audit totals to 11 without creating a billing account, Stripe event, reconciliation row, grant or entitlement.

## Production readback

The final authoritative readback returned:

- 6 plan catalog rows and 6 immutable revisions;
- 0 Stripe Price mappings;
- 0 organizer billing accounts;
- 0 organizer access grants;
- 0 billing-derived competition entitlements;
- 0 Stripe V2 webhook events;
- 0 Checkout intents;
- 0 Portal intents.

The anonymous catalog returns the three intended public offerings: `Club Organizer`, `Club colaborador` and `Team Organizer Pro`. Prices are empty and every paid card reports `checkoutAvailable=false`.

## Stripe boundary

The integrated Stripe account was audited read-only in live mode. Its existing Pachangas IQ monthly and annual products are base-subscription products, not Organizer products; they have no Organizer metadata and were left untouched.

The existing V1 destination `https://pachangasiq.com/api/stripe/webhook` remains active and unchanged. Wave 7B exposes the separate signed route `/api/webhooks/stripe`, but no Organizer destination or signing secret was created in Stripe during this release. That destination is unnecessary while live Organizer Checkout is disabled and must be configured deliberately before a future commercial activation.

No live Product, Price, Customer, subscription, invoice or charge was created.

## Canonical smoke and rollback

A platform-owner smoke called the real `manual.grant` command for an existing Team organizer inside a nested PostgreSQL subtransaction. It verified the canonical `PLATFORM_GRANT` response, revision `1` and entitlement projection, then intentionally raised and caught a rollback exception.

Immediate readback confirmed:

- platform grants: `0`;
- billing-derived entitlements: `0`;
- smoke operation receipts: `0`;
- smoke billing events: `0`.

PostgreSQL sequence values may advance across rollback by design; no business row persisted.

## Product and browser smoke

Production checks covered:

- `/planes-organizador` at desktop, `390x844` and `844x390`;
- `/ajustes/facturacion` without a session;
- `/admin/billing` without a session;
- `/demo?tab=planes` with all five Demo World V2.8 lifecycle scenarios;
- public catalog API, manifest and Service Worker;
- unauthenticated access to `/api/internal/billing/reconcile` returning the required `403`.

Observed result: zero horizontal page overflow, zero broken images, zero browser console errors and no private billing data exposed to anonymous visitors. The public plans rail has intentional touch-scroll overflow. Demo V2.8 remains GET-only and contains no real Stripe IDs, prices or PII.

The production manifest is valid. `/sw.js` returns `200`, `Cache-Control: no-cache, no-store` and `Service-Worker-Allowed: /`. The worker may cache public Organizer Plans, but does not cache owner billing pages and never queues billing or sporting writes as confirmed operations.

Physical Android, iPhone and installed-PWA validation remain explicitly pending.

## Scheduled processing and logs

The deployed Vercel schedule contains `/api/internal/billing/reconcile` at `17 * * * *`. The first platform-originated invocation after activation ran at `2026-08-28T20:17:40Z` on deployment `dpl_GFNzvqeC44WTzwRzgnax3nTzKn2j` and returned `200`.

Its canonical audit receipts report `billing.expire` and `reconciliation.claim`, each with confirmed revision `0`. Post-run readback remains at 0 reconciliation rows, 0 billing accounts, 0 Stripe events and 0 access grants. The production log window contains no `5xx`.

## Commercial decision and deferred activation

Wave 7B is live as an authoritative foundation, catalog, owner UI, platform Control Center, sandbox bridge and read-only Demo World. Commercial Organizer billing remains deliberately unavailable:

- `live_prices_approved=false`;
- `live_checkout_enabled=false`;
- `portal_enabled=false`;
- no organizer-specific Price mapping exists;
- no live tax decision has been invented;
- no live charge is possible from the Organizer surfaces.

Future live activation requires explicit approval of Organizer prices and tax treatment, creation and verification of a separate signed Organizer webhook destination, authenticated Checkout/Portal QA, then flag activation through the platform RPC. Existing V1 billing must remain isolated throughout that later phase.

## Integrity statement

This release did not alter Rating V2 formulas, player facets, assessments, votes, rewards, player cosmetics, team cosmetics, sporting results or Stripe V1 products. PostgreSQL remains the authority for Organizer access; redirects, browser cache and Stripe UI are never entitlement authority.
