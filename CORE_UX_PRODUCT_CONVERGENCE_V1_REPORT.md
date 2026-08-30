# Core UX Product Convergence V1

## Checkpoint and scope

- Baseline: `a3e5abe7ab37d21f4b3f10edcb6de7d5504979bd`.
- Branch: `codex/core-ux-product-convergence-v1`.
- Product engines, RPCs, RLS, Rating V2, results, standings, discipline,
  rewards, cosmetics, conduct, billing, and Team Operational State: unchanged.
- Supabase migrations created: 0.
- Real users, teams, Clubs, referees, organizers, payments, sporting data, and
  external notifications used by QA: 0.

## Product contract

The official experience now has one information architecture:

`Inicio -> Partido -> Competir -> Mercado -> Equipo -> Perfil`

Desktop and game landscape expose those six destinations. Portrait exposes
exactly five and moves `Equipo` into the active context. Administrative,
organizer, referee, and platform tools are contextual; their server-side
capability checks remain the only authority.

The shared context selector carries type, identity, role, status, and next
action. It does not persist private snapshots or perform mutations. Home uses
one role-aware primary action and keeps secondary actions subordinate.

## Converged surfaces

| Family | Result |
| --- | --- |
| Home and team identity | One protagonist, active context, role, state, and primary action |
| Match | Existing next match, lineup, result, and admin authority preserved |
| Competition | League, Tournament, public competition, scheduling, results, discipline, and exceptions identify `Competir` as their product domain |
| Market | Stable Players, Matches, Challenges, and Teams tabs with shareable URL state |
| Club and referee | Existing public/private read models retained; tools shown only for the relevant perspective |
| Platform review | Control Center remains capability-gated and contextual |
| Demo | Same product vocabulary and navigation, with presentation-only guided review |

## Shared state and feedback

`ProductState` covers `LOADING`, `EMPTY`, `NO_ACCESS`, `FEATURE_DISABLED`,
`NOT_READY`, `STALE`, `OFFLINE`, `ERROR`, `SUCCESS`, `ACTION_REQUIRED`,
`UNDER_REVIEW`, `SUSPENDED`, and `ARCHIVED`. The shared feedback path emits one
polite live announcement and does not manufacture success. Offline sporting
writes remain blocked by the existing PWA bridge.

## Conservative refactors

- `app/page.tsx`: render purity, stable initialization, keys, dependency
  boundaries, role-aware home/context wiring, and image handling were corrected
  without changing APIs or sporting callbacks.
- `app/mercado/page.tsx`: deterministic hydration, URL restoration,
  `pushState`/`popstate`, stable tab context, and responsive market shell.
- `app/legal-data.tsx`: structural rendering cleanup only. Legal copy, dates,
  links, consent meaning, and versions were not rewritten.
- Competition clients: primary product domain and role perspective normalized;
  command and read contracts unchanged.

## Performance and continuity

- Synthetic season review loads the selected checkpoint and only adjacent
  snapshots; it no longer eagerly fetches all nine checkpoints.
- Heavy official surfaces retain their existing component and route boundaries.
- Rotation changes layout mode without replacing the canonical data source.
- No refetch loop, duplicate operation feedback, hydration warning, or root
  overflow was observed in the local browser matrix.
- No invented byte target is claimed. The release gate is structural: bounded
  checkpoint reads, existing route chunks, and no new authority fetch loop.

## Verification

- `npm ci`: pass. The audit reports 18 dependency advisories already present in
  the lock graph; no unrelated forced upgrade was applied.
- Tests: 20 Node + 662 TS/TSX = 682/682.
- Skipped / todo / cancelled: 0 / 0 / 0.
- Typecheck: pass.
- Build: pass, 62 static pages generated.
- Global lint: 0 errors / 0 warnings.
- `git diff --check`: pass.
- Axe on seven representative surfaces: 0 violations.
- Visual QA: all required desktop, portrait, and landscape viewports; 0 root
  overflow, 0 broken images, and 0 fresh console errors.

Physical Android, iPhone, and installed-PWA QA remain `PENDING` and are not
represented as passed.
