# League Participation Foundation V1 Production Release

## Release Decision

The product owner authorized the coordinated production release after Official
UI V2.1, with R4A installed but inactive. This release did not authorize a
canonical backfill, production fixtures, R4B, or activation of any R4A flag.

Final product state:

- Official UI V2.1: `LIVE / ACTIVE`;
- R4A League Participation: `DEPLOYED / INACTIVE`;
- R4A laboratory: `LIVE / NOINDEX / READ-ONLY VISUAL`;
- R4A flags: `OFF`;
- R4A production rows: `0`;
- canonical match: `NOT INITIALIZED`;
- R4B: `NOT STARTED`.

## Source, Normalization And Merge

| Item | Value |
| --- | --- |
| `main` after Official UI V2.1 report | `59b601ba0998382faf4473a87548d4cf51ed3282` |
| PR | `#162` |
| Original R4A HEAD | `a419f30d1ab10025ff0365300cf39dc047da7e51` |
| Safety branch | `codex/safety-r4a-pre-official-ui-v2-1-20260823` |
| Normalized R4A HEAD | `ce8c1fe222f227a91fb3b89f4f929e7765772cbc` |
| Merge method | Squash |
| Merge SHA / resulting functional `main` | `f2a3d55f8b540da3b3931a172ed886822c21c387` |
| Merged at | `2026-08-23T17:54:29Z` |
| Functional diff | 43 paths; 11,178 insertions; 17 deletions |

The branch was rebased onto the final Official UI V2.1 `main`. Range and file
inspection kept the six migrations byte-identical. A final three-file visual
adaptation brought the participation surfaces into the Official UI V2.1 shell
without changing SQL authority:

- `app/_components/league-participation-client.tsx`;
- `app/_components/league-participation-client.module.css`;
- `tests/league-participation-v1.test.ts`.

## Migration Ledger

Production project: `Pachangas` (`qonbngfrnrqgmxbdfbea`), region `eu-west-1`,
PostgreSQL `17.6.1.147`.

The production ledger advanced from 113 to 119. Each migration was dry-run,
applied separately in order, and followed by an authoritative SQL readback.
No existing migration was edited or repaired.

| Version | Migration | SHA-256 |
| --- | --- | --- |
| `20260822192929` | `league_participation_schema_v1` | `860f118d3dc1751e59c36ccc422bd7d27c60a9ed15d858a53ab973ce77a7de80` |
| `20260822192935` | `league_participation_commands_v1` | `f6a1ccea6cde474724a340e52edd0f16134c69192170459c6dee21b514567ca8` |
| `20260822192941` | `league_participation_access_v1` | `d3dff6e89d1c8180aefe5f9e7be642bfb45f124700d59ce75736a379f2604a12` |
| `20260822193624` | `club_competition_rule_entitlement_bridge_v1` | `dd3fa1226a46a4a1e2cd19d37754cd40fb9da73c296b34ccea4084b1fd5ad41c` |
| `20260822194325` | `club_competition_manage_entitlement_bridge_v1` | `1ccccacc5c2dc104a9303930bc1ba10d0c92636237d0626325dc6b052cb74172` |
| `20260822195054` | `league_team_owner_scope_precedence_v1` | `e2db366b7e9fe9921eabc55232c6100025f8d3a69e88b4aa4b52dc5d3db7fe44` |

`supabase migration list --linked` confirmed the same six local and remote
versions after the release.

## Backup And Baseline

The latest Supabase physical backup was verified before the first migration:

| Item | Value |
| --- | --- |
| Backup ID | `1451157308` |
| Inserted at | `2026-08-23T00:17:32.931Z` |
| Status | `COMPLETED` |
| WAL-G | enabled |
| PITR | disabled |

The pre-release baseline had zero canonical matches, competition match
contexts, competitions, clubs, referee profiles and assignments. R1, R2 and R3
settings were all off. The post-release readback matched every protected
baseline count exactly, including groups, members, Rating evidence and
snapshots, reward grants, player and team cosmetics, Conduct, Billing and
Ranking publication data.

## Inactive Production State

The final SQL readback confirmed all six R4A flags are false:

- `league_participation_foundation_enabled`;
- `league_registration_enabled`;
- `league_public_registration_enabled`;
- `league_delegates_enabled`;
- `league_rosters_enabled`;
- `league_schedule_preferences_enabled`.

All R4A authorities contain zero production rows: categories, entries, entry
invitations, delegates, stage memberships, rosters, roster revisions, roster
members, credentials and evidence, eligibility waivers, kits, jersey numbers,
constraints, preferences, events, receipts and invalidations.

No league fixture was created. No staging fixture was copied. No canonical
backfill ran. R4B tables, routes and workflows were not introduced.

## Security And Authority

- all 14 public R4A tables have RLS enabled;
- direct client table grants are zero;
- private credential evidence remains fully revoked;
- anonymous write execution is not granted;
- authenticated writes are only available through the versioned and
  idempotent RPC contract;
- every R4A security-definer function has a fixed `search_path=pg_catalog`;
- owner-scope precedence is installed and tested;
- PWA writes use the existing client-version bridge and offline state is never
  shown as confirmed;
- R4A Realtime invalidations are emitted from canonical server receipts.

Supabase security advisors returned only expected `INFO` entries for
`rls_enabled_no_policy`: these tables are intentionally closed to direct
clients and exposed through RPC. Performance advisors returned only `INFO`
entries for unused indexes and candidate foreign-key indexes. No production
`WARN` or `ERROR` was introduced by R4A.

## Validation

| Gate | Result |
| --- | --- |
| `npm ci` | PASS; 21 inherited audit findings, dependency graph unchanged |
| Focused R4A tests | 20/20 PASS |
| Focused Official UI/R3 integration | 27/27 PASS |
| Node runner | 20/20 PASS |
| TSX runner | 374/374 PASS |
| Canonical total | 394/394 PASS |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Typecheck | PASS |
| Production build | PASS; 41/41 routes |
| Focused ESLint | PASS |
| Global ESLint | inherited debt only: 22 errors and 18 warnings; none in R4A files |
| `git diff --check` | PASS |
| SQL/RLS/adversarial | PASS |
| Idempotency | PASS |
| Concurrency | PASS; nine scenarios, one canonical winner and client convergence |
| Fresh bootstrap | PASS at 119 migrations |
| Upgrade bootstrap | PASS from ledger 113 to 119 |
| Schema equivalence | PASS between fresh and upgraded databases |
| Scale | PASS; representative fixtures, p95 maximum 43.935 ms, R4A indexes 99 MB |
| Realtime | PASS in the authenticated staging harness |
| PWA/server-authority contract | PASS |

Scale validation included 150,000 users/profiles, 20,000 entries and 100,000
roster members. It produced no lock timeout, statement timeout or failed
migration. The isolated test database was rolled back and did not use the
production project.

## Preview And Production Deployment

| Item | Preview | Production |
| --- | --- | --- |
| Deployment | `dpl_8SQaP49wfGeUztCpb6UZcZkVNHCF` | `dpl_9wMb85FrSFaTHLgoSf6zuSkrzXLi` |
| Immutable URL | `pachangas-crmt8o6y8-persianas-almar-web-s-projects.vercel.app` | `pachangas-g6jkvsi06-persianas-almar-web-s-projects.vercel.app` |
| State | `READY` | `READY` |
| Production created at | n/a | `2026-08-23T17:54:31Z` |

Production aliases `pachangasiq.com` and `www.pachangasiq.com` resolve to the
R4A functional deployment. The production Service Worker responds HTTP 200 and
has SHA-256
`3c93459c895cbc5e1522cb8b1ea3a44d7a6e876393f0b70228734050db406d71`.

## Production QA

Read-only QA confirmed:

- `/` returns HTTP 200 with no R4A public CTA while the flags are off;
- `/laboratorio-league-participation` returns HTTP 200;
- the laboratory is labelled `Laboratorio R4A`, `NO PRODUCTIVO` and
  `Fixtures aislados - flags OFF`;
- its metadata is `noindex, nofollow`;
- it uses local visual fixtures and exposes no production write flow;
- desktop `1440x900`, portrait `390x844` and landscape `844x390` have no root
  horizontal overflow or broken images;
- browser console warnings and runtime errors on the tested production
  surfaces: 0;
- `/manifest.webmanifest` and `/sw.js` return HTTP 200;
- the manifest remains installable with `fullscreen` plus standalone fallbacks;
- Control Center retains the platform-admin-only R4A status and command path;
- final SQL readback still reports all flags off and all R4A row counts at zero.

No destructive product write was made during production QA.

## Known Debt

The release opened separate issues rather than changing adjacent systems:

1. `#165` Rating V2 onboarding circular blocker;
2. `#166` Google Places selection in Preview;
3. `#167` physical Android QA;
4. `#168` physical iPhone QA;
5. `#169` installed PWA/update QA;
6. `#170` Ranking `CRON_SECRET` verification.

These issues do not activate R4A and do not alter the release result.

## Protected Systems

Post-release baselines confirm that R4A did not modify Rating V2 formulas,
facets, assessments, votes, profiles or evidence. Rewards, Player Cosmetics,
Team Cosmetics, Conduct, Billing, Ranking, R1, R2 and R3 remain intact. The six
R4A migrations add only the inactive participation foundation and its explicit
bridges; no business payload or local cache became a source of truth.

## Rollback Decision And Final State

Rollback: **NO**.

No migration failure, data drift, permission exposure, generalized runtime
error, broken navigation or public R4A activation was observed. The deployed
schema remains dormant and forward-only.

- Production modified: **YES**, by the R4A schema and merged application code.
- Supabase modified: **YES**, only the six R4A migrations.
- Productive R4A data created: **0**.
- Canonical backfill executed: **NO**.
- R4B started: **NO**.
