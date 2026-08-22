# Official UI V2.1 Deep Demo Parity Report

## Release State

- Initial main: `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Branch: `codex/official-ui-v2-1-deep-demo-parity`.
- Draft PR: [#163](https://github.com/puntoracingrc/pachangas/pull/163).
- Initial checkpoint commit: `4381563af4149236d79c3adf2faf53f5aa40bcfc`.
- Final branch HEAD: use the exact `headRefOid` shown by PR #163 after the final push.
- Status: `READY FOR HUMAN VISUAL REVIEW` once the exact-head Preview finishes.
- Production modified: NO.
- Supabase modified: NO.
- Migrations: 0.
- Merge: NO.
- R4A started: NO.

## Cause Of The Gap

Official UI V2 successfully unified palette, shell and responsive navigation, but its authenticated content still placed the legacy hero, many peer actions and permanent Team Access metadata before the sporting task. Demo World used the same visual language with a stronger hierarchy: identity, one next action, object, metrics, agenda and activity. V2.1 closes that structural gap without replacing official authority.

## Implemented

### Home

- New real-data `OfficialHomeGameDashboard`.
- Team identity band with the current player card or a stable empty placeholder.
- Exactly one primary action derived from current match and permission state.
- Four compact real metrics: finished matches, upcoming matches, roster and group level.
- Upcoming rail from real open matches.
- Activity rail from real closed matches; no invented events.
- Team Access reduced to selector plus details drawer.
- Profile, team, identity, Market, create, settings, manual and session actions moved to one compact secondary menu.

### Match

- New persistent `OfficialMatchGameHub` with one contextual navigation and one active-match header.
- Próximo prioritizes match facts, attendance and roster.
- Alineación gives the existing interactive pitch the central stage and keeps compact tools.
- Resultado promotes score and scorers.
- Admin groups configuration, Market/guests, privacy and dangerous operations.
- Existing state, guards and callbacks remain in the official page.

### Market And Ranking

- Market uses one subnavigation and a compact context/filter/results workspace.
- The context tied to the active match appears only where it is relevant.
- Player, match, challenge, team and referee panels retain existing data and mutation paths.
- Ranking places the canonical own position and eligibility before the public table.

### Comparison Lab

- New noindex/nofollow `/laboratorio-official-ui-v2-1`.
- Supports Home, Match panes, Market, Ranking, Avisos, Carta, Escudo, Equipo and Perfil arbitral.
- Supports player/admin/owner, no-team, offline, upcoming and explicit light/dark visual states.
- Imports no Demo JSON, Supabase client, RPC, localStorage or IndexedDB.

## Functional State Coverage

| State | Evidence | Result |
| --- | --- | --- |
| Visitor | actual public routes in product regression matrix | PASS |
| User without team | isolated V2.1 no-team state plus actual identity guard route | PASS visual |
| Player | V2.1 player state and source permission branches | PASS visual/source |
| Admin | V2.1 admin state, Match Admin and Market admin composition | PASS visual/source |
| Owner | V2.1 owner state and existing owner guards retained | PASS visual/source |
| No match | Home empty/creation branch | PASS visual/source |
| Upcoming match | Home and Match Próximo | PASS |
| Lineup pending | Match Alineación | PASS |
| Result pending | Match Resultado | PASS |
| No notifications | Avisos empty state | PASS visual |
| Offline | V2.1 offline state, no optimistic success added | PASS visual/source |

Authenticated canonical readback cannot be exercised in the clean local worktree because it has no private environment. It must be repeated on the exact Vercel Preview without destructive writes; this limitation is not replaced by lab fixtures.

## Automated Visual QA

Required viewports:

`1440x900`, `1920x1080`, `390x844`, `360x800`, `667x375`, `740x360`, `844x390`, `932x430`, PWA standalone `390x844`.

| Matrix | Combinations | Navigation errors | Console errors | Warnings | Failed requests | Broken images | Overflow X | Fixed/sticky violations | Game chrome violations | Blank pages |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V2.1 proposal | 144 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Demo/product regression | 135 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Corrections discovered during the first pass were rerun against their original viewport: compact 360px Match tabs, low-landscape tool height and above-fold image priority. The final focused regression has zero violations.

## Orientation

A browser test selected `Retos` in Market, rotated portrait -> landscape -> portrait and retained the selected tab with one Market navigation. A second test selected `Alineación`, repeated the rotation and retained the pane with one Match navigation. The shell and presentation use one functional tree; orientation changes CSS composition rather than route or state ownership.

## Performance

### Added presentation source

| Scope | Files | Raw source | Gzip source |
| --- | ---: | ---: | ---: |
| Production Home/Match/Market presentation modules | 6 | 35,560 bytes | 7,228 bytes |
| Route-isolated comparison lab | 3 | 49,300 bytes | 11,380 bytes |

These are source payload measurements, not a claim that the full values are added to every network route. The lab is isolated behind its own route.

### Cold local dev instrumentation

Home, Match Alineación and Market were loaded with browser cache disabled in desktop, portrait and landscape:

| Metric | Minimum | Median | Maximum |
| --- | ---: | ---: | ---: |
| CLS | 0 | 0 | 0 |
| DOM content loaded | 100 ms | 115 ms | 148 ms |
| First contentful paint | 116 ms | 132 ms | 172 ms |
| Load | 164 ms | 196 ms | 257 ms |

The measured transfer was about 1.27 MB per local development load and is not representative of a minified Vercel Preview. Preview performance remains the release-quality measurement.

## Evidence

Five required contact sheets and their source captures are stored under `docs/official-ui-v2-1`. Machine-readable results and matrices are retained in the same evidence tree.

## Authority And Scope Check

- No `supabase/` path changed.
- No migration, SQL, RPC, RLS or remote flag changed.
- No Demo World source changed.
- No Control Center source changed.
- No Rating V2 formula, assessment, vote or evidence path changed.
- No attendance, lineup, result, Market, ranking or cosmetics contract was replaced.

## Final Engineering Validation

| Gate | Result |
| --- | --- |
| `npm test` | PASS: production build plus 369 tests (20 HTML/bootstrap and 349 functional) |
| `npm run typecheck` | PASS |
| Production build | PASS: 39 static pages generated and the V2.1 lab route included |
| Focused lint | PASS: 0 errors and 0 warnings across every new or extracted TypeScript/JavaScript module and the updated regression tests |
| Existing monolith lint | No new debt: current `app/page.tsx` + `app/mercado/page.tsx` retain 15 inherited errors and 18 warnings; `origin/main` has the same 15 errors and 20 warnings |
| React review | PASS: presentation components own no network/storage authority, add no effects or global listeners, and keep one functional tree across orientation changes |
| `git diff --check` | PASS |
| Supabase/SQL paths in diff | 0 |

The CSS modules are covered by build, visual matrices and browser inspection; the repository ESLint configuration does not lint CSS files. The two removed monolith warnings correspond to presentation code retired by this structural convergence, while the pre-existing hook and purity errors remain explicitly outside this release.

## Human Review Gate

The exact-head Preview must be compared with `/demo` and the authenticated product in desktop, portrait, landscape and PWA. Until Alberto approves that Preview, PR #163 remains draft and no merge or production deployment is authorized.
