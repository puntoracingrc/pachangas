# League Match Results And Standings V1 Production Release

## Release Decision

The product owner authorized the coordinated R4C release after the local,
staging, Preview, database and production gates passed. R4C is installed as a
server-authoritative but inactive League Engine capability. This release did
not authorize a real League, fixture, squad, Attendance response, sporting
result, official decision, standings row, canonical backfill, referee
assignment, reward or disciplinary action.

Final product state:

- Official UI V2.1: `LIVE / ACTIVE`;
- Clubs and Referees Beta: `STABLE / ACTIVE`;
- R4A League Participation: `DEPLOYED / INACTIVE`;
- R4B League Scheduling: `DEPLOYED / INACTIVE`;
- R4C Match Operations, Results and Standings: `DEPLOYED / INACTIVE`;
- R4C laboratory: `LIVE / NOINDEX / LOCAL FIXTURES`;
- R4C flags: `OFF`;
- R4C production rows: `0`;
- canonical legacy backfill: `NOT_INITIALIZED`;
- R5 Discipline: `NOT STARTED`;
- Tournament Engine: `NOT IMPLEMENTED`.

## Source And Merge

| Item | Value |
| --- | --- |
| Initial `main` | `57fe285daf4eb57f400c313f20841cff2dff4962` |
| Functional PR | `#182` |
| Functional branch | `codex/league-match-results-standings-v1` |
| Functional HEAD | `1ddf50c520f7afc2ac3d87e6b5f4d908998a8c05` |
| Merge method | Squash |
| Merge SHA / resulting functional `main` | `d175d78c6eb8f6e2ca9f16ead7e5970fd2115524` |
| Merged at | `2026-08-24T21:21:56Z` |

GitHub reported the functional PR clean and mergeable, with the final Vercel
Preview successful. The immutable Preview was
`pachangas-fm2x87zqw-persianas-almar-web-s-projects.vercel.app`, deployment
`dpl_9upUCEh4eYmFWefZynKN7wW22NUv`, built from the exact functional HEAD.
Branch-scoped environment readback confirmed the Preview used Supabase staging
`iozcjirlfytryzrcmrnq`; the production project ref and service-role material
were absent from the loaded client bundles.

## Migration Ledger

Production project: `Pachangas` (`qonbngfrnrqgmxbdfbea`), region `eu-west-1`,
PostgreSQL `17.6`.

The production ledger advanced from 127 to 131. Each migration was dry-run,
applied separately and followed by an authoritative SQL readback. Final
`supabase migration list --linked` showed matching local and remote versions.

| Version | Migration | SHA-256 |
| --- | --- | --- |
| `20260824165759` | `league_match_operations_schema_v1` | `b579fff07aafbc97d56ab5fca7b737563c73d33834e67baf3557072a249d313c` |
| `20260824165804` | `league_match_operations_commands_v1` | `e8cea1ad591b037a25a2c5fc91c6ea2f82c147aa22062e93ff9e13413edce6b6` |
| `20260824165810` | `league_match_operations_access_v1` | `a46fd5ced21bea13459692a7e0ef9d51c868897b857a7f5b533041e6086df7c8` |
| `20260824165815` | `league_match_operations_hardening_v1` | `4bde27ec08f10c9c496bc455ccc04973a7f5bed080d8e56b280cbf1436ec585a` |

The inherited `~/.supabase/profile` triggers the known CLI
`Unsupported Config Type ""` error. Release commands temporarily hid that
20-byte selector with an exit trap, used the existing native credential and
restored the file after every command. A temporary project copy enabled normal
migration push without changing repository configuration. The CLI emitted a
post-apply pg-delta certificate-cache warning, but every transaction completed,
the four exact ledger versions were present and all schema/readback gates
passed. No migration history was repaired or rewritten.

## Backup And Protected Baselines

Before the first production SQL statement, physical backup `1460747472` was
`COMPLETED`, dated `2026-08-24T00:16:08.916Z`, in `eu-west-1`. WAL-G was
enabled; PITR was not enabled. Production was still on `main`
`57fe285daf4eb57f400c313f20841cff2dff4962`, deployment
`pachangas-cdfo9w4ce-persianas-almar-web-s-projects.vercel.app`, with ledger
127.

The protected baseline captured row counts and deterministic checksums for 51
relations covering Rating, assessments, matches, scorers, Attendance,
participants, Rewards, Player and Team Cosmetics, Conduct, Billing, Ranking,
Clubs, Referees, R1, R4A, R4B and canonical health.

Post-release comparison found all protected business projections identical.
`pachanga_match_participants` intentionally gained the canonical-competition
identity and monotonic metadata required to reuse Attendance V1. Its four
legacy rows received unique IDs, revision 1 and server sequences, while all
competition links remained null. The checksum of its eight pre-existing
sporting fields remained exactly
`f58775eac5a77af8255b8f74bec4a2f8`; no attendance status, seat, payment,
join time or update time changed.

## Inactive Production State

All eight R4C flags are false:

- `league_match_operations_foundation_enabled`;
- `league_match_squads_enabled`;
- `league_match_attendance_enabled`;
- `league_sporting_results_enabled`;
- `league_result_confirmation_enabled`;
- `league_official_results_enabled`;
- `league_standings_enabled`;
- `league_public_standings_enabled`.

All R4C authorities contain zero rows: squads, squad revisions, squad members,
match sheets, sporting results, result revisions, result scorers, result
responses, official decisions, private official evidence, standing states,
standing snapshots, standing rows, tie-break explanations, persisted draw
lots, rebuild receipts, R4C operation receipts and R4C events.

Existing flags remain unchanged:

- R1 foundation: `OFF`;
- R4A participation: `OFF`;
- R4B scheduling: `OFF`;
- Club foundation, self-service, relationships and public profiles: `ON`;
- Club Competition Organizer: `OFF`;
- Referee foundation, self-service, marketplace, relationships and public
  profiles: `ON`;
- Referee Assignments: `OFF`.

Production still has zero Competition rows, zero CanonicalMatch rows and zero
competition-generated matches. Canonical health remains
`initialized_at = null`; `canonical.backfill` was not executed.

## Authority, Privacy And Realtime

- CanonicalMatch plus CompetitionMatchContext is the only League match
  identity; no LeagueMatch copy exists;
- Attendance reuses `pachanga_match_participants` with disjoint legacy and
  competition identities;
- squads, results, official decisions and standings are versioned and
  server-authoritative;
- all writes require an operation ID and expected revision;
- stale concurrent writes fail rather than using silent last-write-wins;
- actor, Entry, Delegate, Roster, RuleRevision, context and permissions are
  resolved by PostgreSQL;
- anonymous and authenticated roles have zero direct INSERT, UPDATE or DELETE
  grant on R4C tables;
- RLS is enabled and direct table paths are closed;
- Realtime emits invalidations and clients refetch canonical snapshots,
  including after `SUBSCRIBED` and reconnection;
- offline clients may read cached models but never show a sports write as
  confirmed;
- public standings are a reduced read model and remain closed by flag.

Production Supabase Security Advisors reported no R4C error. Fourteen
`rls_enabled_no_policy` information notices are intentional closed-table
surfaces, and ten SECURITY DEFINER warnings correspond to the explicitly
granted command/read-model APIs with server-side authorization. Performance
Advisors reported no R4C warning or error; the 59 unindexed-FK and six
unused-index information notices are documented against the empty dormant
schema and the measured query plans. No speculative index was added during
release.

## Validation

| Gate | Result |
| --- | --- |
| `npm ci` | PASS; 21 inherited audit findings, dependency graph unchanged |
| Canonical test suite | 424/424 PASS |
| Focused R4C | 16/16 PASS |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Typecheck | PASS |
| Production build | PASS |
| Focused ESLint | PASS |
| Global ESLint | 40 inherited findings: 22 errors, 18 warnings |
| `git diff --check` | PASS |
| SQL/RLS/adversarial | PASS |
| Idempotency | PASS for every R4C command |
| Concurrency | PASS; one winner and one stale/conflict per race |
| Fresh bootstrap | PASS at 131 migrations |
| Upgrade bootstrap | PASS from ledger 127 to 131 |
| Schema equivalence | PASS between fresh and upgraded databases |
| Realtime | PASS with authenticated staging clients and canonical refetch |
| PWA/server-authority contract | PASS |

The authenticated staging world produced 15 canonical fixtures, 15 contexts,
five rounds, six entries and the eleven required stories. It covered squads,
Attendance, confirmation, change proposal, dispute, administrative decision,
official correction, tie-breaks, three-team mini-table, round completion,
Realtime and incremental/full rebuild equality. Cleanup archived the QA world
through service authority, restored every flag and left zero active R4C rows.

Concurrency covered squad create/submit, lock versus edit, result submit,
accept versus dispute, official decision, officialize versus scorer correction,
standings rebuild and round lock versus correction. Every race converged on one
canonical winner and one stale/conflict response.

Scale rollback fixtures covered 20 teams/380 official results, 32 teams/992
official results, 10,000 result revisions, 10,000 official decisions and 1,000
historical rebuilds. Relevant p95 values were: match view `2.674 ms`, result
desk `19.033 ms`, standings `4.494 ms`, public standings `3.722 ms`, full
rebuild `19.310 ms` and incremental rebuild `19.554 ms`. Full and incremental
checksums were equal.

## Production Deployment

| Item | Value |
| --- | --- |
| Deployment ID | `dpl_7gELBdugGp4t1a3BrAYGkycQg2b5` |
| Immutable URL | `pachangas-abnpx3dmh-persianas-almar-web-s-projects.vercel.app` |
| Created | `2026-08-24T21:21:59.446Z` |
| Ready | `2026-08-24T21:22:50.823Z` |
| State | `READY` |
| Git SHA | `d175d78c6eb8f6e2ca9f16ead7e5970fd2115524` |

Production aliases `pachangasiq.com` and `www.pachangasiq.com` resolve to this
deployment. `/sw.js` returns HTTP 200 with version
`2.0.0+sw.d175d78c6eb8` and SHA-256
`ba67dc5db6a234ff60bad4f2f60cd8b705e5177abc540ef242b5a585904c210f`.
The manifest keeps `fullscreen` with `standalone`, `minimal-ui` and `browser`
fallbacks, scope `/`, five icons and the controlled Service Worker update path.

## Production QA

Read-only QA confirmed HTTP 200 for `/`, `/clubes`,
`/mercado?tab=arbitros`, `/laboratorio-league-match-operations`,
`/admin/competitions`,
`/competiciones/competition-inexistente/clasificacion`,
`/mis-competiciones/partidos`, `/manifest.webmanifest` and `/sw.js`.

The laboratory document title is `Laboratorio R4C · Pachangas IQ`, the visible
surface identifies `League Engine R4C`, `Laboratorio local` and the isolated
visual scenario, and metadata is `noindex, nofollow`. Partido, Resultado, Mesa
and Clasificación use local fixtures and perform no Supabase write.

Desktop `1440x900`, portrait `390x844` and landscape `844x390` covered 27
route/viewport combinations plus 12 laboratory scenario combinations. They
produced zero root overflow, broken images, clipped controls, duplicate
navigation, console error, console warning or hydration warning. The final
Preview additionally covered the eight required viewports and all four
laboratory scenarios. Horizontally scrollable Result Desk cards were verified
as intentional carousel content rather than root overflow.

Vercel runtime logs for the release window contain no 4xx, 5xx, error or fatal
entry for the deployment; observed responses were HTTP 200/304. Physical
Android, iPhone and installed-PWA QA remain explicitly pending and were not
reported as PASS.

No destructive or sporting write was made during production QA.

## Protected Systems

Post-release baselines confirm no change to Rating V2 formulas, facets,
reliability, assessments, votes, profiles or evidence. Existing results,
matches, scorers and Attendance business fields are unchanged. Rewards,
achievement grants, Player Cosmetics, Team Cosmetics, Conduct, Billing,
Season Score, provincial Ranking, TOPS, Clubs and Referees remain intact.

R4C created zero reward box, reward point, cosmetic grant, card, sanction,
appeal, Conduct case, restriction, product, price, subscription, charge or
referee assignment. Premium Ball remains inactive. League standings are a
separate domain from provincial Ranking.

## Rollback Decision And Final State

Rollback: **NO**.

No migration failure, data leak, canonical-authority loss, protected-data
drift, nondeterministic standings, partial publication, RLS opening, accidental
Club/Referee deactivation or CanonicalMatch duplication was observed. The
forward-only schema is installed and dormant.

- Production modified: **YES**, by the four R4C migrations and merged code.
- Supabase modified: **YES**, only the four R4C migrations.
- Productive R4C data created: **0**.
- Canonical backfill executed: **NO**.
- R4C: **DEPLOYED / INACTIVE**.
- R5 Discipline started: **NO**.
- Tournament Engine implemented: **NO**.
