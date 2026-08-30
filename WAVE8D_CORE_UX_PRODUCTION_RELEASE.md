# Wave 8D Core UX Production Release

## Release checkpoint

- Initial `main`: `a3e5abe7ab37d21f4b3f10edcb6de7d5504979bd`.
- Functional branch: `codex/core-ux-product-convergence-v1`.
- Functional PR: #232.
- Final `main`: pending functional merge.
- Vercel production deployment: pending functional merge.
- Production URL: `https://pachangasiq.com`.
- Supabase migrations created/applied: 0 / 0.
- Supabase ledger expected: 212, unchanged.

## Pre-release gates

| Gate | Result |
| --- | --- |
| `npm ci` | PASS |
| Node tests | 20/20 |
| TS/TSX tests | 662/662 |
| Total | 682/682 |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Typecheck | PASS |
| Build | PASS, 62 static pages |
| Global lint | 0 errors / 0 warnings |
| `git diff --check` | PASS |
| Local visual QA | PASS |
| Axe | 0 violations on seven representative surfaces |

## Release invariants

- Rating, rewards, cosmetics, conduct, billing, standings, brackets,
  discipline, referee statistics, and Team Operational State are unchanged.
- V3.2 authority hash remains
  `763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1`.
- Real entities, external notifications, Demo remote writes, Stripe operations,
  and live checkout activation: 0.
- Rollback required before merge: no.

## Production completion

This section must be updated after the exact merged SHA reaches Vercel READY.
It will record final SHA, deployment ID/URL, production route smoke, manifest,
Service Worker, logs, asset checks, and cleanup. Until then the release status
is `PRE_RELEASE_GATES_PASSED`, not `PRODUCTION_VERIFIED`.

Physical Android, iPhone, and installed-PWA QA remain `PENDING` and do not block
this web release under the Wave 8D contract.
