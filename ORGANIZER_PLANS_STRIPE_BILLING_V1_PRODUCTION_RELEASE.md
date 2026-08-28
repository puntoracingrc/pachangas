# Organizer Plans and Stripe Billing V1 Production Release

Date: 2026-08-28 CEST

## Candidate

- Base `main`: `42e697e294ba2849b1cb5116f2aec24b29f010f9`
- Candidate HEAD: `da85b8af8fe2472db567edce676887255dd33936`
- Pull request: #217, draft and mergeable at this checkpoint.
- Vercel Preview deployment: `dpl_FvRGUnVJmJunGiwnnTDcz98F6zsj`, READY for the exact candidate HEAD.
- Production ledger before Wave 7B: 183.
- Wave 7B migrations: seven, ending at local ledger 190.

## Gates

| Gate | Result |
| --- | --- |
| Full tests | PASS, 606/606 |
| Typecheck | PASS |
| Production build | PASS |
| Focused TS/TSX lint | PASS |
| Global lint | PRE-EXISTING DEBT, 22 errors and 18 warnings |
| SQL/RLS/idempotency | PASS |
| Concurrency | PASS |
| Representative scale | PASS |
| `git diff --check` | PASS |
| Local desktop/portrait/landscape | PASS |
| Installed physical PWA | PENDING; not claimed from emulation |

The global lint findings are confined to pre-existing `app/legal-data.tsx`, `app/mercado/page.tsx` and `app/page.tsx`. All Wave 7B-owned TS/TSX files pass focused lint.

## Commercial Decision

Stripe has valid live monthly and annual Pachangas IQ base-subscription assets, but no approved organizer-specific mapping. Therefore:

- `live_prices_approved=false`;
- `live_checkout_enabled=false`;
- no organizer Price is seeded;
- no live charge is permitted;
- existing base billing remains intact.

## Deployment Checkpoint

This report records the release candidate before remote migration, merge and production activation. Final production SHA, migration ledger, flags, deployment and smoke readback must be appended after those steps; this checkpoint must not be misread as a completed production release.
