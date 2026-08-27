# Tournament Group Stage V1 Production Release

## Release identity

- Initial `origin/main`: `7f46951fd4144985b05c8029606574b82c655b73`
- Functional branch: `codex/tournament-group-stage-match-tracking-v1`
- Functional pull request: #206, merged
- Certified functional HEAD: `03f4e570c49b3c63faf11284f3732c739f368821`
- Functional merge: `ed6063ec4a327b9921410c950b7229a48c697ea1`
- PWA hotfix pull request: #207, merged
- PWA hotfix merge / production code SHA:
  `4c9d04379ebe0f9ba0e69aa023e5badba2ea8637`
- Exact Preview: `https://pachangas-hlbklq6fn-persianas-almar-web-s-projects.vercel.app`
- Production deployment: `dpl_CQH7sBktL2ESVaKw9yX3fiAhTcow`
- Production URL:
  `https://pachangas-npfx9wl4c-persianas-almar-web-s-projects.vercel.app`
- Public aliases: `https://pachangasiq.com` and
  `https://www.pachangasiq.com`
- Diff from `origin/main`: 76 paths
- Local ledger: 163 base migrations plus 6 R6B migrations = 169

## Ordered migrations

| Version | Purpose | SHA-256 |
| --- | --- | --- |
| 20260827105014 | Group-stage schema and qualification | `a8673226c5a6c8a4b585965826861d74b7ac5f872797642814fba7d64b926d2a` |
| 20260827105018 | R4B schedule adapter | `15d806d70830437c51baaf34bddd0e7cd6ba796dd510022a62a87c046b63c14c` |
| 20260827105022 | Canonical publication, qualification and bracket | `3ce16f0daf420b54686f62c4b8fdab7152b9a989bd402bd11967fbd2f0e09623` |
| 20260827105027 | Tournament Hub read model | `1ec49db2416371f0a64ca51f24b9962e0ca84029f14bbf3e2a2402e78c1b6eba` |
| 20260827105033 | Access, RLS and Realtime | `7ce2ba2df4f463f24619a3f7fabb71a0929005583918052c577f05bc3db9324a` |
| 20260827105036 | Hardening, indexes and flags | `d01f0fb571358fa42f34df83b18f0905f845eaddc89cf8ba355684605eb41ab9` |

Fresh 169-migration bootstrap and exact 163 to 169 upgrade produce normalized
schema hash
`d26a99f64e7ee56103254ecc7f2d9a5bd06ffdb183b0a417819a8e4a54304063`.
All R6B and R6C flags are OFF immediately after migration and no product rows
are created.

## Gates completed locally

- Canonical DB story: PASS.
- Adversarial matrix: 18/18 PASS.
- Concurrency: 10/10 PASS.
- Scale and representative volume: PASS.
- Performance bounds: PASS.
- Fresh/upgrade schema equivalence: PASS.
- Demo World V2.5 deterministic verification: PASS.
- Typecheck: PASS.
- Build: PASS.
- Tests after the production PWA hotfix: 20/20 Node and 538/538 TS/TSX,
  558/558 total; 0 skipped, todo or cancelled.
- Focused lint: PASS (27 changed code/test files).
- `git diff --check`: PASS.

Global lint remains blocked by 40 findings in three files unchanged from main;
see `R6B-TEST-073`.

## Hosted staging certification

The final one-shot run used the isolated, non-production Supabase branch
`krljxecwvxbrijmrwbsn`, bootstrapped from the immutable baseline with an exact
169/169 version-and-name ledger comparison. Before fixture creation it proved
zero users, zero competitions, all R6B/R6C flags OFF, RLS enabled, one Realtime
publication and no authenticated direct inserts.

The authenticated 17-story regression then proved:

- 16 entries, 4 Groups, 12 Group rounds and 24 CanonicalMatches;
- 24 official results, 4 current standings snapshots, 30 locked squads and 30
  closed Attendance sides;
- one postponement, one no-show, one suspension/resumption, four disciplinary
  events and twelve confirmed referee assignments;
- published QualificationSnapshot and published eight-slot BracketTemplate;
- exactly zero knockout matches and public discovery still OFF;
- two authenticated devices at the same revision, one successful completion,
  one `PT409` stale conflict and one persisted completion receipt;
- a real PostgreSQL invalidation delivered to both devices, followed by a
  canonical refetch to the same completed revision 14;
- byte-equivalent idempotent replay of the winning operation.

The branch control plane still labels ordinary migration replay as
`MIGRATIONS_FAILED` because it starts with the historical pre-baseline chain.
`R6B-ENVIRONMENT-076` records that environment limitation. Direct PostgreSQL
readback, not the label, proves the exact 169 migration schema used above.

## Preview and authenticated visual QA

The exact `03f4e57` Preview traversed all ten Demo World V2.5 Tournament tabs
at `1440x900`, `1920x1080`, `390x844`, `360x800`, `667x375`, `740x360`,
`844x390` and `932x430`. Every tab became the active control at every size;
root overflow, broken images, framework overlays, console errors and hydration
warnings remained zero.

The real production `TournamentGroupStageClient` was then exercised locally
against the authenticated canonical hosted staging snapshot. It rendered four
groups, 24 official CanonicalMatches, current standings, published
qualification, the eight-slot bracket template, Organizer Desk and the scoped
Team Journey. The same eight-viewport/tab matrix passed, including the
landscape rail regression. Control Center displayed the R6B health and gates at
desktop, portrait and landscape with no root overflow, broken images, console
errors or private evidence leakage.

The protected Preview redirects `/sw.js` to Vercel SSO, so it cannot certify a
real installed Service Worker. `R6B-ENVIRONMENT-100` keeps that result open and
requires the public production origin smoke before closure; no PWA success is
inferred from the protected Preview.

## Production migration gate

Production was read before migration at exactly 163 versions with R6A active,
R6B absent, zero Tournament rows, zero CanonicalMatches and zero
CompetitionMatchContexts. Canonical health retained `initializedAt = null`, so
the legacy backfill was not executed.

Recovery evidence exists in two independent forms: a completed Supabase
physical backup from `2026-08-27T00:14:33Z`, plus permission-restricted logical
schema, role and data dumps captured immediately before R6B. Their SHA-256
checksums are respectively
`c148fcb7adf63ed7e544d7b545f50b967567c9d48841e58d0e633182917bc1db`,
`168a95a9c745af5ed4679751f90419ac9dc434240a213b03e32a06d5664c2308`
and
`48f9821ea068a20c6e8270100544ecb4b1204c7de99fe064bbe0a87d61a44549`.

The repository intentionally disables generic `db push`; the documented
existing-database path, `supabase migration up --linked`, applied only the six
immutable R6B files. Linked and Management API readbacks now agree on exactly
169 versions through `20260827105036` with all names in the table above.

The nine new relations contain zero rows after the reversible canary, all have
RLS, authenticated/anonymous
roles have zero direct write grants, no R6B index is invalid and Tournament
invalidations are present in `supabase_realtime`. Advisor warnings for RPC-only
tables/functions are expected from the deliberate no-direct-table-access and
authenticated command architecture; optional foreign-key index notices remain
informational after the certified scale/performance suite.

## Production activation and canary

Activation used only
`command_pachanga_tournament_group_stage_platform_v1`, never a direct settings
update. Five idempotent operations advanced the platform settings monotonically
from revision 11 to 16 and server sequence 1281 to 1285. Replaying the fifth
operation returned the same receipt and created no duplicate event.

Final flag readback at revision 16 is:

| Capability | State |
| --- | --- |
| Tournament Foundation / Private Beta / Draw | ON |
| Group Stage / Scheduling / Group Match Generation | ON |
| Tracking / Group Standings / Qualification | ON |
| Bracket Template | ON |
| Knockout Match Generation | OFF |
| Bracket Progression | OFF |
| Public Tournament Discovery | OFF |
| Payments | OFF |

The production canary ran inside one transaction with four teams, one Group,
one leg, three rounds, six fixtures, six CanonicalMatches and six
CompetitionMatchContexts. Tournament Hub returned one Group projection with
zero standings rows, while SportingResults and persisted StandingStates stayed
at zero. The transaction rolled back. Final readback confirms zero QA users,
roles, grants, tournaments, Group Stage rows, CanonicalMatches, contexts,
results or standings.

## Demo, visual and PWA production proof

Demo World V2.5 is live with Copa Barrios IQ 2027, 16 teams, four Groups, three
rounds per Group and 24 deterministic Group fixtures. Its manifest and
authority hashes are respectively
`675d2992138de4253a0e9e09eab77d09682cecc708fc06a4f87ed0e6d15e57f8`
and
`3d51909498c47762ee6256f6a71e5ab642fbd2a2f2fc953178d537ca54dd06af`.
Remote Demo writes remain zero.

All ten Tournament tabs passed the required eight-view matrix, 80/80
combinations, with zero root overflow, clipped active control, broken image,
pending image, console error or hydration warning. Installed physical Android,
iPhone and standalone PWA remain truthfully pending; CDP display-mode emulation
is not presented as physical QA.

PR #207 corrected two Service Worker defects found during the production gate:
the generated competition-route regex was invalid, and immutable hashed Demo
JSON was recognized but excluded from runtime caching. Worker
`2.0.0+sw.4c9d04379ebe` compiled, activated through the existing controlled
update flow and replaced the previous worker/cache namespace.

The online-to-offline regression warmed the manifest plus all eight V2.5
chunks, blocked the network, proved an uncached API request failed, and reloaded
the same Tournament URL. Copa Barrios, Jornada 2 and the bracket message still
rendered without an error panel, overflow or broken image. Connectivity was
then restored and canonical online rendering converged again. No offline write,
queue or fake success exists.

## Operational readback

- `supabase migration list --linked`: 169 local and 169 remote versions aligned
  through `20260827105036`.
- PostgreSQL settings: revision 16, server sequence 1285.
- R6B product/canary rows after rollback: zero.
- R6B staging branches removed: two; unrelated `pwa-bridge-staging` preserved.
- Vercel deployment: READY and served by `pachangasiq.com` with exact deployment
  ID `dpl_CQH7sBktL2ESVaKw9yX3fiAhTcow`.
- Deployment errors: zero `error`-level entries and zero R6B 5xx.
- Known unrelated debt: `/api/internal/rankings/refresh` remains fail-closed at
  503 while server-only `CRON_SECRET` is absent; it predates R6B and is recorded
  as `R6B-ENVIRONMENT-128`.

## Final matrix

| Result | State |
| --- | --- |
| Tournament Group Stage active | YES / PRIVATE BETA |
| R4B journeys active | YES |
| Canonical Group matches active | YES |
| R4C results active | YES |
| Group standings active | YES |
| Qualification active | YES |
| Bracket template active | YES |
| Knockout matches created | 0 |
| Bracket progression active | NO |
| Tournament champion available | NO |
| Demo World V2.5 live | YES |
| Simulation World verified | YES |
| Remote Demo writes | 0 |
| Functional and PWA PRs merged | YES |
| Production deployment | READY |
| Production rollback required | NO |
| R6C started | NO |
