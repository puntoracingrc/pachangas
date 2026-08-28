# Organizer Live Checkout V1 Production Release

Date: 2026-08-29 CEST

## Release identity

- Starting `main`: `0040f750dc935ccb43a0f2ccfcf65a243bcb40ef`.
- Pull request: [#219](https://github.com/puntoracingrc/pachangas/pull/219), Draft.
- Functional SHA: pending final commit.
- Production merge SHA: pending.
- Vercel deployment: pending.
- Production URL: [https://pachangasiq.com](https://pachangasiq.com).

## Forward-only database change

Wave 7C contains exactly six new migrations:

1. `20260828205310_organizer_commercial_decisions_v1.sql`
2. `20260828205311_organizer_commercial_commands_v1.sql`
3. `20260828205313_organizer_stripe_catalog_authority_v1.sql`
4. `20260828205314_organizer_checkout_portal_activation_gates_v1.sql`
5. `20260828205316_organizer_commercial_read_models_v1.sql`
6. `20260828205317_organizer_commercial_hardening_flags_v1.sql`

Local fresh bootstrap reaches ledger 196. Linked migration parity and final
production ledger are pending the release gate; no historical migration is
rewritten.

## Validation gates

| Gate | Result |
| --- | --- |
| Focused commercial tests | PASS, 9/9 |
| SQL/RLS/idempotency | PASS, ledger 196 |
| Nine concurrency races | PASS |
| Wave 7B compatibility | PASS |
| Representative scale | PASS |
| Typecheck | PASS |
| Focused lint | PASS |
| Full tests / build / global lint | Pending final run |
| Responsive/PWA QA | Pending final Preview |
| `git diff --check` | PASS |

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
