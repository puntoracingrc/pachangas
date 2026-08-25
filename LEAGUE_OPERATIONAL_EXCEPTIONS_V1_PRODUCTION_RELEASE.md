# League Operational Exceptions V1 Production Release

## Release Decision

R4D has been installed in production as a server-authoritative but inactive
League capability. The release adds the schema, commands, read models,
responsive surfaces and operational laboratory needed to handle published
fixture exceptions without activating a real League or creating sporting data.

Final product state:

- R4D Operational Exceptions: `DEPLOYED / INACTIVE`;
- all nine R4D flags: `OFF`;
- R4D production rows, events and receipts: `0`;
- Clubs and Referees Beta: `ACTIVE / UNCHANGED`;
- Club Competition Organizer: `OFF`;
- Referee Assignments: `OFF`;
- R1, R4A, R4B and R4C: `DEPLOYED / INACTIVE`;
- canonical legacy backfill: `NOT_INITIALIZED`;
- R5 Discipline: `NOT STARTED`;
- League Private Beta: `NOT ACTIVATED`;
- Tournament Engine: `NOT IMPLEMENTED`.

No tournament, disciplinary card, player or team sanction, fine, charge,
Stripe operation, reward, cosmetic grant, automatic venue booking or referee
payment was introduced or executed.

## Source And Merge

| Item | Value |
| --- | --- |
| Initial `main` | `c6efeb72c7bf30456a75873e8e9ff93d7d7c6609` |
| Functional PR | `#184` |
| Functional branch | `codex/league-operational-exceptions-v1` |
| Functional HEAD | `91d2e4291b6765f66b5511e2539c9bd5e103869e` |
| Merge method | Squash |
| Merge SHA / resulting functional `main` | `63f361928d662c73289bb138e963d6510cefaa7a` |
| Merged at | `2026-08-25T03:05:37Z` |

GitHub reported the PR clean and mergeable. Its required Vercel checks passed
before merge. No conflicting `main` change appeared between final validation
and release.

## Migration Ledger

Production project: `Pachangas` (`qonbngfrnrqgmxbdfbea`), region `eu-west-1`,
PostgreSQL `17.6`.

The production ledger advanced from 131 to 136. `supabase migration list
--linked` first confirmed that local and remote histories matched through
`20260824165815` and that exactly the five expected R4D versions were pending.
The five forward-only migrations were then applied without repairing,
rewriting or deleting migration history. Final local and remote ledgers match.

| Version | Migration | SHA-256 |
| --- | --- | --- |
| `20260824230726` | `league_operational_exceptions_schema_v1` | `b732cc56edc735450163f0d5f6be9a28fdc5a5fd1dc26c2c2a38a705ec9b8d66` |
| `20260824230732` | `league_operational_exceptions_commands_v1` | `ca01621f3036e9af162140ade4b06e5cb4a4da5f55d3674a53350a5eaa62090c` |
| `20260824230733` | `league_operational_exceptions_access_v1` | `da0524ed2196c752ac18953b1c9f429d33251a101dee63b7042837b48eb898eb` |
| `20260824230734` | `league_operational_exceptions_hardening_v1` | `f9dae027259fb8346207d0092a1404791c062cd839249863909b779ad215f4a0` |
| `20260825021800` | `league_operational_exceptions_venue_status_fix_v1` | `b729558e555c0c1a844022d4434e790248b6c1aa9f9a23ea043da66c26c1a7fa` |

The fifth migration is an additive correction for R4B fixtures that use an
authorized venue label while their saved venue remains `TBD`. It does not
rewrite the four earlier R4D migrations.

The inherited `~/.supabase/profile` is a stale 20-byte selector that makes the
CLI return `Unsupported Config Type`. Release commands temporarily moved that
file with an exit trap, used the existing native credential, and restored it
after every operation. Repository configuration and credentials were not
changed or committed.

## Backup And Preflight

Before applying production DDL, physical backup `1470476739` was
`COMPLETED`, inserted at `2026-08-25T00:16:37.824Z`. Eight completed daily
physical backups were visible; WAL-G was enabled and PITR was not enabled.

The authoritative preflight captured:

- ledger 131, latest version `20260824165815`;
- zero Competition rows, CanonicalMatch rows and CompetitionMatchContext rows;
- R1, R4A, R4B and R4C flags `OFF`;
- Club foundation, self-service, team relationships and public profiles `ON`;
- Club Competition Organizer `OFF`;
- Referee foundation, self-service, public profiles, marketplace and Club
  relationships `ON`;
- Referee Assignments `OFF`;
- canonical health `initialized_at = null`;
- protected Rating, Conduct, Ranking and Player Cosmetics settings digest
  `5fae096750b4a41a268927ec0ceff5232eaaa265e163c73e3e412469f0171a2a`.

The final readback reproduced every protected value and digest exactly.

## Authority And Privacy

R4D applies changes to `CanonicalMatch + CompetitionMatchContext`. It never
edits a published R4B ScheduleItem destructively. A post-publication change is
represented by a request or administrative decision, a typed FixtureChange,
an effective context revision and immutable lineage.

- all writes require an idempotent `operationId` and `expectedRevision`;
- PostgreSQL resolves actor, team entry, Delegate, organizer capability,
  RuleRevision, server time and server sequence;
- stale concurrent writes fail instead of using silent last-write-wins;
- the browser never calculates or persists a definitive result;
- offline clients may retain read models but cannot confirm a sporting write;
- private reasons and evidence remain in the private schema;
- authenticated and anonymous roles have zero direct R4D DML grants;
- all 13 R4D tables have RLS enabled;
- raw R4D tables are not in the Realtime publication;
- the existing competition invalidation table is in Realtime, and clients
  refetch the canonical snapshot after invalidation, `SUBSCRIBED` and
  reconnection.

The production security readback found 13/13 R4D tables with RLS, zero direct
INSERT/UPDATE/DELETE/TRUNCATE grants and zero raw R4D tables in Realtime.

## Functional Coverage

The release covers:

- postponement request, response, withdrawal and deadline expiry;
- bilateral approval and organizer intervention by explicit capability;
- rescheduling and time changes without reopening R4B;
- saved venue, authorized venue label and `TBD` handling;
- venue-condition decisions;
- late-arrival reports, grace deadline and escalation;
- confirmed and rejected no-show decisions;
- suspension, resumption, replay and administrative resolution;
- typed administrative effects, including official outcomes only when a
  RuleRevision authorizes them;
- original and effective fixture history in read models;
- notifications, Control Center, Official UI V2.1, Mobile Game Landscape and
  PWA-safe command handling.

No ordinary attendance change from `voy` to `no voy` creates a no-show.
Partial suspended scores are preserved but do not enter standings until an
authorized official decision exists.

## Validation

| Gate | Result |
| --- | --- |
| Canonical suite | 443/443 PASS |
| Focused R4D | 19/19 PASS |
| Focused R4B regression | 23/23 PASS |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Typecheck | PASS |
| Production build | PASS |
| Focused ESLint | PASS |
| Global ESLint | 22 inherited errors and 18 warnings outside R4D |
| `git diff --check` | PASS |
| SQL/RLS/adversarial | PASS |
| Idempotency | PASS for every R4D action |
| Concurrency | PASS; one winner and one stale/conflict in nine races |
| Fresh bootstrap | PASS at 136 migrations |
| Upgrade bootstrap | PASS from 131 to 136 |
| Fresh/upgrade schema equivalence | PASS |
| Realtime | PASS with two authenticated clients and canonical refetch |
| PWA/server-authority contract | PASS |

Scale rollback covered 10,000 FixtureChanges, 10,000 PostponementRequests,
5,000 late arrivals, 2,000 no-shows, 2,000 suspensions and 5,000
administrative decisions. Relevant command timings remained below 43 ms
against a 2,000 ms threshold; measured read models remained below 27 ms.

## Staging And Preview

Staging installed all five migrations at ledger 136. The final authenticated
world used six teams, 15 canonical matches, five rounds and ten operational
stories: postponement approved, denied and expired; venue change; late
arrival; no-show confirmed and rejected; suspension resumed; replay; and
partial-result administrative resolution.

Remote concurrency converged on one winner and one stale writer. Realtime
performed invalidation followed by canonical refetch. Cleanup archived QA
authorities through service authority, restored the nine flags to `OFF`, and
left zero active R4D rows.

The immutable Preview was
`pachangas-x8ql5ciz5-persianas-almar-web-s-projects.vercel.app`, deployment
`dpl_H4ScAW7PWzZqEzfiuasohBghNT9F`, built from functional HEAD
`91d2e4291b6765f66b5511e2539c9bd5e103869e`.

Eight viewports, six laboratory surfaces and PWA standalone produced zero
root overflow, broken image, clipped control, console error, console warning
or failed request.

## Production Deployment

| Item | Value |
| --- | --- |
| Deployment ID | `dpl_9sV6bFSvrusUz3Sc9EaxRBpsRZS9` |
| Immutable URL | `pachangas-md3geq9ds-persianas-almar-web-s-projects.vercel.app` |
| Git SHA | `63f361928d662c73289bb138e963d6510cefaa7a` |
| Created | `2026-08-25T03:05:40.139Z` |
| Ready | `2026-08-25T03:06:27.579Z` |
| State | `READY` |

Production aliases `pachangasiq.com` and `www.pachangasiq.com` point to that
deployment. `/sw.js` returns HTTP 200 with `Cache-Control: no-cache, no-store,
must-revalidate`, version `2.0.0+sw.63f361928d66` and SHA-256
`e0c8f6895e3c09cbf4e8fbc3fa0091d9f32baa85dcf520fdb7e4aa39ad728883`.
The manifest keeps `fullscreen` with `standalone`, `minimal-ui` and `browser`
fallbacks, scope `/` and five icons.

## Production QA

Read-only smoke returned HTTP 200 for `/`, `/manifest.webmanifest`, `/sw.js`,
`/laboratorio-league-operational-exceptions`, `/admin/competitions`,
`/mis-competiciones/solicitudes` and all five R4D competition route families.
Authenticated product actions remain unavailable because every R4D flag is
off and production has no Competition or CanonicalMatch data.

Desktop `1440x900`, portrait `390x844`, landscape `844x390` and PWA standalone
`390x844` produced:

- zero horizontal overflow;
- zero broken images;
- zero clipped controls or viewport violations;
- zero console errors and warnings;
- zero failed requests;
- Service Worker controlled in the PWA;
- `display-mode: standalone` in app mode.

The laboratory title is `Laboratorio R4D · Pachangas IQ`, uses only local
fixtures and declares `noindex, nofollow`. It performs no production write.
Physical Android, iPhone and installed-PWA QA remain explicitly pending and
are not reported as PASS.

## Logs And Advisors

For the production deployment window, Vercel reported 102 HTTP 200 responses,
no 4xx, no 5xx and no runtime error cluster. Supabase sampled 100 API rows
with 98 HTTP 200 and two protocol-upgrade 101 responses, with zero 5xx.
Realtime sampled 96 rows with no error, fatal, panic, crash or timeout term.
PostgreSQL sampled 100 rows with no error or timeout term.

Supabase Advisors reported no `ERROR` or `CRITICAL`. R4D security notices are
the intentional fail-closed tables without direct policies and the audited
SECURITY DEFINER RPC surfaces that perform server-side authorization. R4D
performance notices are unindexed-FK or unused-index information for the
empty dormant schema. The only global performance warning is the pre-existing
Rating V2 duplicate-index notice and was not modified.

## Recorded Incidents

All failures found during implementation were recorded before correction in
`LEAGUE_OPERATIONAL_EXCEPTIONS_V1_REPORT.md`:

- `R4D-001` Realtime cold-start ordering;
- `R4D-002` sanitized concurrency diagnostics;
- `R4D-003` R4B venue-label/TBD compatibility;
- `R4D-004` stale branch-scoped staging credential;
- `R4D-005` Vercel sensitive-value export behavior;
- `R4D-006` protected Preview access;
- `R4D-007` inherited test ledger expectation;
- `R4D-008` active authorities left by two failed QA worlds.

Each corrected issue is `fixed + regression_verified`; no failed QA authority
or temporary production row remains.

## Protected Systems

Post-release counts and digest confirm that Rating V2 formulas, facets,
reliability, assessments, votes, profiles and evidence remain unchanged.
Existing matches, participants, attendance, scorers and results remain
unchanged. Rewards, achievements, Player Cosmetics, Team Cosmetics, Conduct,
Billing, Season Score, provincial Ranking, TOPS, Clubs and Referees remain
intact.

Production still contains zero Competition rows and zero CanonicalMatch rows.
No canonical backfill, Club Organizer action, referee assignment, League
fixture, R4D operation, reward, sanction or payment was created.

## Rollback Decision And Final State

Rollback: **NO**.

No migration failure, protected-data drift, unexpected feature activation,
direct-write opening, Realtime authority violation, deployment error or visual
regression was observed. The forward-only schema remains installed and dormant.

- Production modified: **YES**, by the five R4D migrations and merged code.
- Supabase modified: **YES**, only by the five R4D migrations.
- Productive R4D data created: **0**.
- Canonical backfill executed: **NO**.
- R4D: **DEPLOYED / INACTIVE**.
- League Private Beta activated: **NO**.
- R5 Discipline started: **NO**.
- Tournament Engine implemented: **NO**.
