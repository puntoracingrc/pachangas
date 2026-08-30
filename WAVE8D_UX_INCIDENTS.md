# Wave 8D UX incidents

Checkpoint: `a3e5abe7ab37d21f4b3f10edcb6de7d5504979bd`

This ledger records every product, security, privacy, authority, PWA, and
accessibility defect found during Wave 8D before it is changed. Environment-only
diagnostic failures are grouped at the end.

| ID | Class | Status | Reproduction and evidence | Expected regression |
| --- | --- | --- | --- | --- |
| W8D-001 | PRODUCT_BUG | fixed + regression_verified | Open `/demo?perspective=referee`, reload, and inspect the perspective. `readInitialDemoWorldSession` accepted only four of the nine published perspective IDs, so several roles fell back to player. | All published perspectives are normalized and survive URL/session restoration. Verified by the eight-tour perspective contract and browser reload/deep-link QA. |
| W8D-002 | PRODUCT_BUG | fixed + regression_verified | Open `/demo?tab=temporada`. `SyntheticSeasonView` loaded the selected checkpoint and then fetched all nine checkpoint files. | The current checkpoint plus adjacent snapshots are the only eager reads. Regression rejects `Promise.all(index.checkpointFiles)` and browser QA confirmed stable week changes. |
| W8D-003 | PRODUCT_BUG | fixed + regression_verified | Desktop and landscape exposed five product tabs plus a second permanent row of twelve technical/domain destinations. | Six canonical desktop/landscape destinations, exactly five portrait destinations, and contextual tools by role. Covered by navigation-contract tests and all target viewports. |
| W8D-004 | PRODUCT_BUG | fixed + regression_verified | With no stored preference and a light OS preference, `/demo` started in light mode despite the default game identity. | An absent explicit preference resolves to dark; explicit theme choice remains available. Verified in dark/light visual QA. |
| W8D-005 | ACCESSIBILITY_BUG | fixed + regression_verified | At `844x390` the Demo domain navigation was a clipped horizontal strip without an accessible contextual grouping. | A bounded native `details/summary` menu replaces the clipped strip, exposes `aria-current`, and keeps its panel scrollable. Verified at every landscape viewport and by Axe with 0 violations. |
| W8D-006 | PRODUCT_BUG | fixed + regression_verified | `ProductFeedback` existed in two shared modules with incompatible tone names and live-region semantics. | One canonical shared feedback implementation remains, with one polite live region and no fake-success behavior. Covered by the product-state regression and full test suite. |
| W8D-007 | ACCESSIBILITY_BUG | fixed + regression_verified | Baseline lint reported 22 errors and 18 warnings in `app/page.tsx`, `app/mercado/page.tsx`, and `app/legal-data.tsx`. | Global lint is 0 errors / 0 warnings with no rule suppression or TypeScript escape hatch. Verified by lint and the stabilization regression. |
| W8D-008 | PRODUCT_BUG | fixed + regression_verified | Referee contextual links pointed to two nonexistent routes. | `Ficha arbitral` resolves to `/perfil/arbitro` and `Asignaciones` to `/mis-asignaciones-arbitrales`. Both routes were browser-verified and are exact regression expectations. |
| W8D-009 | PRODUCT_BUG | fixed + regression_verified | Direct Mercado links such as `?tab=retos` produced a server/client hydration mismatch. | Mercado starts from a deterministic baseline, restores URL state after mount, and handles push/pop navigation. Direct link, click, back and zero-warning browser QA passed. |

## Baseline evidence

- Tests: 20 Node + 650 TS/TSX = 670/670.
- Skipped / todo / cancelled: 0 / 0 / 0.
- Typecheck: pass.
- Build: pass, 62 static pages generated.
- Lint: 22 errors + 18 warnings = 40 findings.
- Visual captures: `/tmp/pachangas-wave8d-before` (temporary, redacted, no real identities).
- Real entities, notifications, payments, and remote Demo writes: 0.

## Environment appendix

- An exploratory wildcard test command included the intentionally heavy
  `synthetic-world.test.ts`, which is outside the contracted `npm test` list. It
  was stopped cleanly; the exact package suite was then rerun to completion.
- The browser wrapper rejected `networkidle`; QA uses `domcontentloaded` plus a
  bounded render wait.
- `next dev` generated untracked `AGENTS.md` and `CLAUDE.md`; both are temporary
  framework artifacts and will be removed after the local server stops.
