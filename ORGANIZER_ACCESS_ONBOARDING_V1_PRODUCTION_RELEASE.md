# Organizer Access and Onboarding V1 Production Release

Opened: 2026-08-29 CEST

## Release checkpoint

- Initial `main`: `e0cbf7bd45f8d38e4edc8bc7dc97fd1272ec355f`.
- Branch: `codex/organizer-access-onboarding-v1`.
- Draft PR: #223.
- Implementation checkpoint: `c941294f93ab282aa5dfd23f9c0cce55161258ff`.
- Final branch checkpoint: the exact PR #223 HEAD; its commit and merge SHAs are
  recorded after the controlled release.
- Local migration ledger: 204.
- Stripe touched: NO.
- Real charges: 0.
- Next Wave started: NO.

## Exact migrations

1. `20260829152223_organizer_access_applications_revisions_v1.sql`
2. `20260829152228_organizer_access_review_decisions_messages_v1.sql`
3. `20260829152232_organizer_access_entitlement_bridge_authority_v1.sql`
4. `20260829152237_organizer_guided_onboarding_workspace_v1.sql`
5. `20260829152241_organizer_access_read_models_control_center_v1.sql`
6. `20260829152246_organizer_access_rls_realtime_notifications_v1.sql`
7. `20260829152250_organizer_access_hardening_indexes_flags_v1.sql`

All seven are forward-only. The previous 197 migrations remain unchanged.

## Local gates

| Gate | Result |
| --- | --- |
| Organizer access TS/source | 16/16 PASS |
| SQL/RLS/idempotency | PASS |
| Concurrency | 13/13 PASS |
| Fresh bootstrap | 204 migrations PASS |
| Global tests | 615/615 PASS |
| Typecheck | PASS |
| Build | PASS |
| Focused lint | PASS |
| Global lint | 40 pre-existing findings; no Wave 8A regression |
| Security Advisor | 0 findings |
| `git diff --check` | PASS |
| Responsive matrix | 8 viewports x 4 surfaces; 0 root overflow, broken images or console findings |

## Flag policy

All Wave 8A flags are born OFF:

- `organizer_access_applications_enabled`
- `organizer_access_submission_enabled`
- `organizer_access_review_enabled`
- `organizer_partnership_approval_enabled`
- `organizer_onboarding_enabled`
- `organizer_first_competition_launcher_enabled`
- `demo_world_v30_enabled`

`live_prices_approved`, live Checkout and customer portal remain OFF.
Activation must use the audited platform settings RPC, never direct table
updates.

## Remote release ledger

This section must be completed from real readback; no local result is promoted
to remote evidence.

| Step | Status | Evidence |
| --- | --- | --- |
| Preview exact SHA | SUPERSEDED | Implementation commit `c941294f93ab282aa5dfd23f9c0cce55161258ff` reached Vercel `READY`; a fresh Preview is required after the Realtime/RLS hotfix commit. |
| Staging migrations | PASS | Branch `pwa-bridge-staging` (`iozcjirlfytryzrcmrnq`) reconciled to the canonical 197 baseline and then applied exactly migrations `20260829152223` through `20260829152250`; ledger readback 204. |
| Staging authenticated E2E | PASS | Six application lifecycles, owner transfer, private-note isolation, paid-interest without grant, one-winner concurrency, launcher/cancel, grant revocation, mandatory notification deduplication and two-device Realtime invalidation followed by canonical refetch. |
| Staging cleanup | PENDING | All launcher drafts are cancelled and active grants/entitlements are zero. The ten ephemeral users and remaining QA evidence are isolated to the disposable staging branch and will be removed by retiring that branch after production verification. |
| Production backup/readback | PENDING | - |
| Production migrations | PENDING | - |
| Merge to `main` | PENDING | - |
| Vercel deployment READY | PENDING | - |
| Inactive smoke | PENDING | - |
| Phased activation | PENDING | - |
| Productive canary + cleanup | PENDING | - |
| Demo World V3.0 LIVE | PENDING | - |
| Service Worker HTTPS | PENDING | - |

## Staging security and consistency readback

- All seven Wave 8A flags were born `OFF`; phased staging activation used the
  platform settings RPC, never direct `UPDATE`.
- Existing League/Tournament dependency flags were restored to their previous
  values after the E2E.
- `anon` cannot execute the private invalidation predicate.
- `authenticated` receives only `EXECUTE` on the boolean RLS predicate and
  `SELECT` on the invalidation table; it has no direct write privilege.
- An organizer owner reads the relevant invalidation; an unrelated user reads
  zero rows.
- Realtime is invalidation-only. Both clients refetched the same canonical
  revision instead of treating the WAL payload as state.
- The first staging attempt exposed W8A-018: the RLS policy could not call its
  private predicate because `EXECUTE` had been revoked from `authenticated`.
  The migration and staging schema now carry the minimum targeted grant, with
  SQL and source regressions.
- Billing live flags, Stripe Checkout, prices and portal remained `OFF`; Stripe
  was not touched.

## Required final readback

The release cannot close until it records the final `main` SHA, PR merge,
remote migration ledger/hashes, seven flag values, production deployment URL,
runtime logs, ephemeral canary identifiers, cleanup zeros, Demo V3.0 manifest
and Service Worker version.

Physical Android, iPhone and installed-device PWA remain `PENDING`; they do not
block this web release.
