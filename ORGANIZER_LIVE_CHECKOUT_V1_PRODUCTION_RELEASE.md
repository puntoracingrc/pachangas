# Organizer Live Checkout V1 Production Release

Date: 2026-08-29 CEST

## Release identity

- Starting `main`: `0040f750dc935ccb43a0f2ccfcf65a243bcb40ef`.
- Pull request: [#219](https://github.com/puntoracingrc/pachangas/pull/219), Draft.
- Functional SHA: `c087d2f93a4d9f7124315fcd26b3a4db485db6b1`.
- Least-privilege fix SHA: `4108fc1630fd5f3cb3510c92335b55a6ba432799`.
- Current evidence SHA: `62c9c4d748bf37cfa22e4981abec7f8cd528d7a9`.
- Production merge SHA: pending.
- Immutable Preview: `dpl_F5782xZibbsPqSGdLNtiXPP2VGNJ`, `READY`.
- Preview URL: [Wave 7C exact SHA](https://pachangas-2zs7cs213-persianas-almar-web-s-projects.vercel.app).
- Production URL: [https://pachangasiq.com](https://pachangasiq.com).

## Forward-only database change

Wave 7C contains exactly six new migrations:

1. `20260828205310_organizer_commercial_decisions_v1.sql`
2. `20260828205311_organizer_commercial_commands_v1.sql`
3. `20260828205313_organizer_stripe_catalog_authority_v1.sql`
4. `20260828205314_organizer_checkout_portal_activation_gates_v1.sql`
5. `20260828205316_organizer_commercial_read_models_v1.sql`
6. `20260828205317_organizer_commercial_hardening_flags_v1.sql`

Local fresh bootstrap reaches ledger 196. The ephemeral staging branch also
reaches 196, but its connector-generated versions differ from the six exact
repository versions; exact production migration parity remains a release gate.
No historical migration is rewritten.

## Validation gates

| Gate | Result |
| --- | --- |
| Focused Wave 7B/7C tests | PASS, 22/22 |
| SQL/RLS/idempotency | PASS, ledger 196 |
| Nine concurrency races | PASS |
| Wave 7B compatibility | PASS |
| Representative scale | PASS |
| Typecheck | PASS |
| Focused lint | PASS |
| Full tests | PASS, 615/615; 0 skipped/todo/cancelled |
| Build | PASS, 56 static pages |
| Global lint | Existing debt only: 22 errors / 18 warnings outside Wave 7C |
| Responsive/PWA QA | PASS at 1440x900, 390x844, 844x390 and standalone simulation |
| `git diff --check` | PASS |

The exact Preview renders the three canonical plans with both paid plans
disabled, four pending-price labels and zero runtime warnings/errors. TEST
Stripe readback confirms two active Organizer Products, four active recurring
Prices and zero active subscriptions.

## Activation boundary

All new flags are born OFF. This release may activate the commercial workflow,
Organizer pricing UI, Stripe TEST health, TEST Checkout, TEST Portal and Demo
V2.9 only after their canonical health gates pass. Activation uses platform
RPCs with revision and idempotency; direct settings updates are forbidden.

LIVE remains OFF unless a later explicit commercial and tax approval exists:

- `live_prices_approved=false`
- `live_checkout_enabled=false`
- `portal_enabled=false`
- no Organizer LIVE Product or Price mapping
- no real charge

## Integrity

Stripe V1, Rating V2, rewards, player cosmetics, team cosmetics, sporting
results and existing billing evidence remain intact. A redirect, browser cache
or Stripe Dashboard state never grants Pachangas IQ access.

Final migration, flag, deployment, smoke, Service Worker and cleanup evidence
will replace the pending fields after controlled production release.
