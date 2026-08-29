# Organizer Live Checkout V1 Production Release

Date: 2026-08-29 CEST

## Release identity

- Starting `main`: `0040f750dc935ccb43a0f2ccfcf65a243bcb40ef`.
- Pull request: [#219](https://github.com/puntoracingrc/pachangas/pull/219), merged.
- Functional SHA: `c087d2f93a4d9f7124315fcd26b3a4db485db6b1`.
- Least-privilege fix SHA: `4108fc1630fd5f3cb3510c92335b55a6ba432799`.
- Final PR HEAD: `5d3629fc0bb67d0ff5c87ce68141e0276c6d4230`.
- Production merge SHA: `a97f69cebf083d1eb2132133f6c40ec02eba8bd3`.
- Production deployment: `dpl_7uP3PNtLPvtMDDjbyB3SF7Bixqji`, `READY`.
- Exact deployment URL: [Wave 7C production](https://pachangas-kzi0gvkpa-persianas-almar-web-s-projects.vercel.app).
- Production URL: [https://pachangasiq.com](https://pachangasiq.com).
- Wave 7C Previews: retired after QA; four exact deployments removed.

## Forward-only database change

Wave 7C contains six planned commercial migrations:

1. `20260828205310_organizer_commercial_decisions_v1.sql`
2. `20260828205311_organizer_commercial_commands_v1.sql`
3. `20260828205313_organizer_stripe_catalog_authority_v1.sql`
4. `20260828205314_organizer_checkout_portal_activation_gates_v1.sql`
5. `20260828205316_organizer_commercial_read_models_v1.sql`
6. `20260828205317_organizer_commercial_hardening_flags_v1.sql`

Authenticated staging QA discovered that the existing Realtime RLS policy could
not execute its private predicate. The minimal forward-only correction is a
seventh release migration:

7. `20260829080812_organizer_billing_invalidation_rls_execute_v1.sql`

Local fresh bootstrap reaches ledger 197. Staging contains the same seven names
and SQL effects, under connector-generated versions for the six commercial
migrations and the QA hotfix. Production applied the seven exact repository
versions in order and now also reports ledger 197 with no local/remote mismatch.
No historical migration was rewritten or manually repaired.

## Validation gates

| Gate | Result |
| --- | --- |
| Focused Wave 7B/7C tests | PASS, 24/24 |
| SQL/RLS/idempotency | PASS, ledger 197 |
| Concurrency | PASS, five billing races plus nine commercial races |
| Wave 7B compatibility | PASS |
| Representative scale | PASS |
| Typecheck | PASS |
| Focused lint | PASS |
| Full tests | PASS, 618/618; 20 Node + 598 TS/TSX; 0 skipped/todo/cancelled |
| Build | PASS, 56 static pages |
| Global lint | Existing debt only: 22 errors / 18 warnings outside Wave 7C |
| Responsive/PWA QA | PASS at 1440x900, 390x844, 844x390 and standalone simulation |
| `git diff --check` | PASS |

The exact Preview renders the three canonical plans and TEST pricing. Stripe
readback confirms two active Organizer Products, four active recurring Prices
and zero real paid subscriptions. All four hosted Checkout combinations were
validated without submitting a payment; the signed endpoint, Portal,
failure/recovery, cancellation/resume and two-client Realtime paths passed.

Production smoke passed for `/`, `/planes-organizador`, Demo World V2.9,
manifest, Service Worker and both generated Demo assets. Desktop, portrait,
landscape and standalone simulation reported zero runtime console errors,
broken images or layout overflow on the checked surfaces.

Post-migration Production readback confirms that every new Wave 7C flag is OFF,
there are zero LIVE mappings and the pre-existing Wave 7B settings retain their
prior values. The CLI's post-push pg-delta cache warning was independently
cleared by exact linked-history and settings readbacks; it did not alter the
successful migration transactions.

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

## Post-release cleanup

- Production Supabase remains canonical at ledger 197 with exact local/remote
  version and name parity. All Wave 7C and LIVE flags remain OFF and there are
  zero TEST or LIVE production mappings.
- Staging billing settings were restored through platform RPC at revision 31;
  base, V2, TEST, LIVE and Demo flags are OFF. TEST runtime health is reset and
  all QA accounts, subscriptions, invoices, deliveries, mappings, catalog
  intents, active entitlements and billing notifications are zero.
- Three immutable commercial decisions remain as non-active `draft` evidence.
  The QA Club is archived and the temporary platform actor is inactive at
  revision 3; the permanent owner remains active at revision 1.
- All eight Wave 7C branch variables were removed from Vercel. Production has no
  Stripe TEST variable. The historical OAuth alias points back to its preserved
  V2.1 deployment.
- Stripe's dedicated Organizer webhook and `Pachangas IQ Wave 7C` TEST
  environment were deleted. Its standard and restricted TEST keys are revoked;
  no LIVE Stripe resource was created, changed or charged.
- The sole exposed Vercel automation bypass was revoked without replacement.
  Project readback reports zero bypass entries, and all four Wave 7C Preview
  deployments are absent.
- Secret scans over the worktree, built assets, current diff, Wave 7C commit
  range and relevant temporaries returned zero key or bypass matches. Preview
  runtime logs returned zero bypass-query hits.

## Residual QA boundaries

- Hosted Stripe Checkout payment submission was intentionally not automated.
  The custom agent-disclosure interaction remains a physical QA boundary; no
  payment, entitlement or signed paid webhook is claimed from that surface.
- Android, iPhone and installed-PWA physical-device QA remain pending. Browser
  responsive and standalone simulations pass, but are not presented as physical
  device evidence.

## Integrity

Stripe V1, Rating V2, rewards, player cosmetics, team cosmetics, sporting
results and existing billing evidence remain intact. A redirect, browser cache
or Stripe Dashboard state never grants Pachangas IQ access.

Release code, migrations, deployment, production smoke and remote cleanup are
closed. Only the explicit physical Checkout/PWA boundaries above remain; they do
not enable LIVE billing or change the server-authoritative production state.
