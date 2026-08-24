# League Scheduling Foundation V1 Production Release

## Release Decision

The product owner authorized the coordinated R4B release with the scheduling
foundation installed but inactive. This release did not authorize production
schedule plans, rounds, fixtures, canonical matches, a canonical backfill, or
activation of any R4B feature flag.

Final product state:

- Official UI V2.1: `LIVE / ACTIVE`;
- R4A League Participation: `DEPLOYED / INACTIVE`;
- R4B League Scheduling: `DEPLOYED / INACTIVE`;
- R4B laboratory: `LIVE / NOINDEX / LOCAL FIXTURES`;
- R4B flags: `OFF`;
- R4B production rows: `0`;
- canonical match: `NOT_INITIALIZED`;
- R4C: `NOT STARTED`.

## Source And Merge

| Item | Value |
| --- | --- |
| Initial `main` | `382f919e522af43feda7dc393253d3231ec3c44c` |
| PR | `#172` |
| Functional HEAD | `264a3911b51a69d50224f55efe80d5e60eed8df5` |
| Branch | `codex/league-scheduling-canonical-fixtures-v1` |
| Merge method | Squash |
| Merge SHA / resulting functional `main` | `3e9845673fe963b8813df247695d818713fdd313` |
| Merged at | `2026-08-24T01:47:30Z` |
| Performance follow-up | `#173 R4B LARGE SCHEDULE EXECUTION` |

`main` had not diverged from the reviewed base before merge. The branch was
clean and GitHub reported the PR mergeable with the Vercel check successful.
The four migration files remained byte-identical throughout release.

## Migration Ledger

Production project: `Pachangas` (`qonbngfrnrqgmxbdfbea`), region `eu-west-1`,
PostgreSQL `17.6`.

The production ledger advanced from 119 to 123. Each migration was applied in
its own transaction and followed by an authoritative readback. The final
remote versions match the 123 local migration versions exactly.

| Version | Migration | SHA-256 |
| --- | --- | --- |
| `20260823224156` | `league_scheduling_schema_v1` | `58992bba1d5c0f63a93a783572101471019aedaa154a3bfef457a2e4a25700aa` |
| `20260823224218` | `league_scheduling_commands_v1` | `0eb0eaeaa6dbe5f79817223a5b0d8d39ccc2f10bc3f4b102987d98ec0bc26067` |
| `20260823224235` | `league_scheduling_access_v1` | `fda93a6de7a32157766de0edb63c08a3d11332aff7238e86b2f916379d268367` |
| `20260823224236` | `league_scheduling_hardening_v1` | `17ccc51407b08e0422617c34500f042747ef5cfaf10f52767c4cd4a270ded86e` |

The linked CLI profile could not render the ledger because of its inherited
`Unsupported Config Type ""` configuration. The release therefore used the
Supabase management connection plus direct ledger readback; it did not edit
the global CLI profile or repair migration history speculatively.

## Backup And Baselines

Before SQL execution, the Supabase dashboard showed a recoverable physical
backup from `2026-08-24T00:16:08Z` with Restore available. The dashboard did
not expose that backup's internal ID in the accessible view, so no ID was
invented or committed. The previous verified backup ID was retained only in
private release evidence.

The protected pre-release baseline covered 205 public/private tables and 1,064
rows. After migration, 204 of 205 existing table snapshots were byte-equivalent.
The only expected difference was
`private.pachanga_canonical_match_health_state`: its JSON snapshot gained the
zero-valued `competitionGenerated` source/binding fields and
`competitionGeneratedMatches: 0`. Existing matches, bindings, contexts,
reviews and source counts were unchanged.

Platform capabilities, R1/R2/R3/R4A flags and the five active Team Cosmetic
Reward mappings were unchanged. Premium Ball remains inactive.

## Inactive Production State

The final authoritative SQL readback at
`2026-08-24T01:55:35.546592Z` confirmed all six R4B flags are false:

- `league_scheduling_foundation_enabled`;
- `league_schedule_generation_enabled`;
- `league_schedule_editing_enabled`;
- `league_schedule_publication_enabled`;
- `league_public_calendar_enabled`;
- `league_canonical_fixture_creation_enabled`.

All R4B authorities contain zero rows: schedule plans, revisions, slots,
rounds, byes, schedule items, validations, conflicts, quality snapshots,
R4B receipts, R4B events and R4B invalidations.

Canonical readback remains `NOT_INITIALIZED`: zero canonical matches, zero
competition-generated bindings, zero R4B competition contexts and zero
backfills. The seven pre-existing unbound sources are unchanged.

R1, all six R4A flags and all six R4B flags remain off. No production League,
schedule plan or QA fixture was created.

## Security And Authority

- every exposed R4B table has RLS enabled;
- anonymous and authenticated clients have no direct table-write grant;
- anonymous users cannot execute the scheduling command RPC;
- authenticated writes pass through the versioned, idempotent command RPC;
- actor identity, authorization, canonical IDs, constraints and pairings are
  resolved server-side;
- security-definer functions use a fixed `search_path`;
- Realtime carries invalidations and clients refetch canonical snapshots;
- public calendar reads are reduced read models and remain disabled by flag;
- the PWA does not present offline scheduling intents as confirmed.

Supabase advisors returned no R4B security or performance error. Expected
advisories concern deliberately closed direct-table paths, intentional reduced
public readers, authenticated RLS policies and unused indexes on empty R4B
tables. No adjacent advisor finding was changed during this release.

## Validation

| Gate | Result |
| --- | --- |
| `npm ci` | PASS; 21 inherited audit findings, dependency graph unchanged |
| Node runner | 20/20 PASS |
| TSX runner | 377/377 PASS |
| Canonical total | 397/397 PASS |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Focused R4B | 23/23 PASS |
| Typecheck | PASS |
| Production build | PASS; 43 routes |
| `git diff --check` | PASS |
| SQL/RLS/adversarial | PASS |
| Idempotency | PASS |
| Concurrency | PASS; one winner and one stale revision per race |
| Fresh bootstrap | PASS at 123 migrations |
| Upgrade bootstrap | PASS from ledger 119 to 123 |
| Schema equivalence | PASS between fresh and upgraded databases |
| Realtime | PASS in the authenticated staging harness |
| PWA/server-authority contract | PASS |

Concurrency covered generation, publication and canonical fixture creation.
Both clients converged after stale-revision rejection. Scale validation handled
95,000 schedule items/slots, 5,000 constraints and 10,000 preferences in
33.565 seconds with transactional rollback.

Final performance evidence:

| Fixture | Result |
| --- | --- |
| 6 teams / 1 leg | generation `232.485 ms`; publication `647.487 ms` |
| 20 teams / 2 legs | generation `7.175 s` |
| 32 teams / 2 legs | generation `42.560 s` |

R4B remains off, so the 32-team result does not block this inactive release.
Issue `#173` owns the explicit product decision between a 20-team interactive
limit and asynchronous generation for 21-32 teams.

## Production Deployment

| Item | Value |
| --- | --- |
| Deployment ID | `dpl_4Zq2q2Ug1WFuQGfjP2Qv78p8kCTk` |
| Immutable URL | `pachangas-kd6nided4-persianas-almar-web-s-projects.vercel.app` |
| Created | `2026-08-24T01:47:32.581Z` |
| Ready | `2026-08-24T01:48:17.315Z` |
| State | `READY` |
| Git SHA | `3e9845673fe963b8813df247695d818713fdd313` |

Production aliases `pachangasiq.com` and `www.pachangasiq.com` resolve to this
deployment. `/sw.js` returns HTTP 200 with `no-cache, no-store`, version
`2.0.0+sw.3e9845673fe9` and SHA-256
`d299f33a0f4d955f2a4c674e93dcbdb930a0889b773c2c1671113d56c5dc693f`.

## Production QA

Read-only QA confirmed:

- `/`, `/laboratorio-league-scheduling`, `/admin/competitions`,
  `/competiciones/competition-inexistente/calendario` and
  `/mis-competiciones/calendario` return HTTP 200;
- the laboratory is labelled `LABORATORIO R4B`, `NO PRODUCTIVO` and
  `Fixtures locales - flags OFF`;
- the laboratory metadata is `noindex, nofollow` and its scenarios write
  nothing to Supabase;
- the unauthenticated Control Center path is correctly gated;
- the missing-competition probe renders `COMPETITION_NOT_FOUND` and produces
  only its expected HTTP 404 resource response;
- no public League CTA appears while the flags are off;
- desktop `1440x900`, portrait `390x844` and landscape `844x390` have no root
  overflow, broken images, duplicate navigation or framework overlay;
- a real Chromium app-mode run reports `display-mode: standalone`, active
  Service Worker, no overflow, no broken images and no console/page error;
- `/manifest.webmanifest` and `/sw.js` return HTTP 200;
- Vercel reported zero grouped runtime errors for the R4B deployment window.

The production log continues to show the inherited
`/api/internal/rankings/refresh` 503 every five minutes because its secret is
not configured. The identical failure was present on the previous production
deployment and is tracked separately; it is not caused by R4B and did not
alter the R4B release decision.

No destructive product write was made during production QA.

## Protected Systems

Post-release baselines confirm that R4B did not modify Rating V2 formulas,
facets, assessments, votes, profiles or evidence. Results, matches,
participants, scorers, Attendance, Conduct, Rewards, Player Cosmetics, Team
Cosmetics, Billing, Ranking, R1, R2, R3 and R4A remain intact. The local cache
remains a derived read model and never became a second sports authority.

## Rollback Decision And Final State

Rollback: **NO**.

No migration failure, protected-data drift, permission exposure, broken
navigation or accidental R4B activation was observed. The deployed schema is
forward-only and dormant.

- Production modified: **YES**, by the R4B schema and merged application code.
- Supabase modified: **YES**, only the four R4B migrations.
- Productive R4B data created: **0**.
- Canonical backfill executed: **NO**.
- R4B: **DEPLOYED / INACTIVE**.
- R4C started: **NO**.
