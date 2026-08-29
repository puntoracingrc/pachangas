# Organizer Access and Onboarding V1 Production Release

Opened: 2026-08-29 CEST

## Release checkpoint

- Initial `main`: `e0cbf7bd45f8d38e4edc8bc7dc97fd1272ec355f`.
- Branch: `codex/organizer-access-onboarding-v1`.
- Draft PR: #223.
- Local checkpoint: `dcffb61bfad62cf2d57e9fd893fcb4e539f6eaa5`.
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
| Preview exact SHA | PENDING | - |
| Staging migrations | PENDING | - |
| Staging authenticated E2E | PENDING | - |
| Staging cleanup | PENDING | - |
| Production backup/readback | PENDING | - |
| Production migrations | PENDING | - |
| Merge to `main` | PENDING | - |
| Vercel deployment READY | PENDING | - |
| Inactive smoke | PENDING | - |
| Phased activation | PENDING | - |
| Productive canary + cleanup | PENDING | - |
| Demo World V3.0 LIVE | PENDING | - |
| Service Worker HTTPS | PENDING | - |

## Required final readback

The release cannot close until it records the final `main` SHA, PR merge,
remote migration ledger/hashes, seven flag values, production deployment URL,
runtime logs, ephemeral canary identifiers, cleanup zeros, Demo V3.0 manifest
and Service Worker version.

Physical Android, iPhone and installed-device PWA remain `PENDING`; they do not
block this web release.
