# Frontend Stabilization and Global Lint Zero

## Baseline

- Scope: full repository lint, not a focused subset.
- Findings: 22 errors + 18 warnings = 40.
- Principal files: `app/page.tsx`, `app/mercado/page.tsx`, and
  `app/legal-data.tsx`.
- Baseline behavior and screenshots were captured before editing.

## Remediation

| Area | Resolution |
| --- | --- |
| Render purity | Removed render-time mutation and unstable browser-derived initial values |
| Effects | Replaced synchronous effect-state patterns with deterministic initialization or bounded post-mount restoration |
| Dependencies | Stabilized callbacks/values and removed stale dependency drift |
| Lists | Added stable keys where React required identity |
| Images | Replaced the affected dynamic avatar image with `next/image` using `unoptimized`, preserving transparency and source behavior |
| Legal content | Reorganized rendering only; legal semantics and text were preserved |
| Mercado | Removed server/client URL divergence and retained back/forward behavior |
| Dead state | Removed unused `remoteInviteToken`; group invitation still derives from the canonical team token |

No `eslint-disable`, `eslint-disable-file`, `@ts-ignore`, `@ts-nocheck`, broad
`any`, or global rule weakening was added.

## Regression reconciliation

Five historical string-based assertions expected the old static shell or an
unused state variable. They now assert the canonical navigation contract and
the active invitation URL flow. Product permissions and mutation behavior were
not relaxed.

## Final gates

- `npm run lint`: 0 errors / 0 warnings.
- `npm run typecheck`: pass.
- `npm run build`: pass.
- `npm test`: 682/682.
- `git diff --check`: pass.
- Stabilization regression confirms the three target files contain no rule or
  TypeScript suppressions.

`npm ci` reported 18 package advisories (1 low, 4 moderate, 13 high). They are
dependency-audit debt, not lint findings; no breaking `npm audit fix --force`
was applied inside this UX release.
