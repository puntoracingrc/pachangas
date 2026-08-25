# League Private Beta V1 - Production Release

## Release checkpoint

- Initial `origin/main`: `161c152fb0423a87304b1549c15e33184cb0de4d`
- Initial release PR: `#186`, merged as `cdd11e2790f5f961101234dac9682c7913958744`
- Closeout branch: `codex/league-private-beta-v1-release-closeout`
- Closeout PR: `#187`, merged as `90378797c26feb7ebdbd3cee83a53eb194a71a03`
- Final evidence branch: `codex/league-private-beta-v1-final-report`
- Status: `ACTIVE / INVITE-ONLY`; LPB-017, LPB-018, and LPB-019 fixed and
  regression verified
- Production modified: yes, by PRs `#186`/`#187` and the five forward-only
  productization migrations
- Supabase production modified: yes; the canonical ledger contains 141 entries
  and ends at `20260825115500`

## Productization migrations

1. `20260825074304_league_private_beta_schema_v1.sql`
2. `20260825074353_league_private_beta_commands_v1.sql`
3. `20260825074358_league_private_beta_access_v1.sql`
4. `20260825102400_league_private_beta_fk_indexes_v1.sql`
5. `20260825115500_league_private_beta_draft_edition_fix.sql`

They are forward-only units installed after the existing 136-entry ledger in
both staging and production (136 -> 141). The
schema reuses canonical Competition entitlements and R1/R4A-R4D entities; it
does not create a parallel League engine or initialize legacy backfill.

## Local release gates

- Node: `v24.19.0` (repository contract `>=22.13.0`).
- Production build: PASS, 49 static pages generated and `/ligas` present.
- Full suite: PASS, 461/461; skipped/todo/cancelled 0/0/0.
- Wave 2 contract: PASS, 18/18.
- Typecheck: PASS.
- Focused lint for every Wave 2 TypeScript/JavaScript route: PASS.
- Global lint: pre-existing debt remains at 22 errors and 18 warnings in
  `app/legal-data.tsx`, `app/mercado/page.tsx`, and `app/page.tsx`; no Wave 2
  focal finding.
- SQL/RLS/idempotency/adversarial: PASS on a temporary local PostgreSQL 17
  database.
- Bootstrap and upgrade: PASS; exact 136 -> 141 ledger and fresh/upgraded
  schemas are equivalent.
- Concurrency: PASS for replay, competing creates, competing step writes, and
  competing revocations.
- Scale: PASS with 120 active bundles, bounded 100-row read models, stable
  ordering, and isolated temporary-database cleanup.
- `git diff --check`: PASS.

## Authority and privacy

- Every mutation uses authenticated RPC/API intent with `operationId` and
  `expectedRevision`; PostgreSQL resolves actor, sequence, time, grants, rules,
  capacity, and canonical materialization.
- The PWA stores a derived read cache only. Offline writes are never queued or
  shown as confirmed.
- Realtime carries scoped invalidations and clients refetch canonical models;
  WAL payloads are not applied as authority.
- Private League pages and APIs are `noindex`, `nofollow`, and `no-store`.
- Public registration, calendars, standings, exception status, referee
  assignments, discipline, payments, and tournaments remain unavailable.

## Authorized scope

Productize the existing R1 and R4A-R4D foundations as a private,
invite-only League beta. League creation requires both the global product gate
and an explicit, unexpired organizer entitlement.

The release must keep public registration, public calendars, public standings,
public exception status, referee assignments, competition discipline, payments,
tournaments, and the canonical legacy backfill disabled.

## Evidence

Authenticated staging E2E: PASS against Supabase project
`iozcjirlfytryzrcmrnq` and the exact protected Vercel Preview. The composed
story produced 6 entries, 5 rounds, 15 canonical fixtures, 15 official results,
6 standing rows and the complete R4D exception matrix. Idempotent replay,
competing writes, stale-revision rejection, and Realtime invalidation followed
by canonical refetch all converged. Cleanup archived/cancelled the synthetic
competition, revoked the exact entitlement bundle, restored every mutable flag
to OFF, and left 0 active QA bundles.

Direct staging readback: 141 migration ledger entries ending at canonical version
`20260825115500`; 0 active beta bundles, 0 active beta wizards, 0 active QA
competitions, 0 active QA plans, and 0 active QA match contexts. Every R1,
R4A, R4B, R4C, R4D and private-beta mutable switch was OFF after cleanup;
`inviteOnly=true` remained the structural invariant.

LPB-017 focal staging story: PASS. A real authenticated organizer completed all
ten wizard steps; finalization returned and persisted an Edition in `draft`
with no registration opening timestamp. The separate revisioned
`registration.open` command then moved it to `registration_open`. Cleanup
cancelled the Competition before fixtures, revoked its exact bundle, restored
all competition/Club flags to OFF, and left 0 active QA bundles, wizards and
competitions.

Preview visual gate: PASS on the feature commit
`dfe317995d8612ec4c9b8ce95e1490602d4e705a` and repeated on the LPB-017 fix
commit `de647ea5189ad09cd661f6f0420c2372b1f7cb5a`. `/ligas`, Control Center,
registration, calendar, match, results, standings, and operational-exception
surfaces were checked at 1440x900, 390x844, and 844x390. Across the 24 route
and viewport combinations there were 0 horizontal overflows, 0 controls outside
the viewport, 0 broken images, and 0 console errors or warnings. Every private
surface returned `noindex, nofollow`.

PWA Preview gate: PASS for manifest, controlled Service Worker, and emulated
standalone presentation. The manifest declares fullscreen with a standalone
fallback, the Service Worker was active and versioned, its script response was
`no-store`, and `/ligas` remained free of overflow and broken images in the
standalone shell. Physical Android, physical iPhone, and a physically installed
PWA remain unclaimed and were not represented as PASS.

Staging diagnostics: API logs contained no 5xx. The observed 400/409 responses
were the expected negative, stale-revision, and competing-write assertions.
Security advisors reported only the intentional authenticated
`SECURITY DEFINER` command/read surfaces guarded by canonical actor and RBAC
validation. Performance advisors reported only pre-traffic `unused_index`
information for the new foreign-key indexes; no Wave 2 foreign key remained
without its covering index.

## Production activation and readback

- Before activation, every new beta setting was OFF by default, R1/R4A-R4D
  product gates and Club Competition Organizer were OFF, public League surfaces
  were OFF, and no productive Competition existed. Existing Club and Referee
  beta data was preserved.
- Recoverability checkpoint: the scheduled physical backup dated
  `2026-08-25 00:16:37 UTC` was available before activation. Point-in-time
  recovery is not enabled on the current plan; no destructive or down migration
  was used.
- Code release: Vercel deployment `dpl_6kNEWx9H1YjzU7Y8XgcPKUMkHhAJ` is
  `READY` for `90378797c26feb7ebdbd3cee83a53eb194a71a03` and serves
  `https://pachangasiq.com`.
- Migration history: staging and production both list the five canonical
  versions above. A temporary MCP-generated ledger version was repaired before
  activation; production now has exactly 141 entries and no divergent version.
- Activation order was respected: beta read gate with creation OFF, R1,
  Club organizer, private R4A, private R4B, private R4C, private R4D, and only
  then beta creation ON. Every step received a direct PostgreSQL readback.
- Final Competition settings are revision `8`, server sequence `17`:
  R1 and the required R4A-R4D private capabilities are ON; beta and beta
  creation are ON; maximum active Editions is `1`; default cap is `12`.
- Public discovery, public registration, public calendar, public standings,
  and public exception status are OFF.
- Club foundation, self-service creation, public profiles, Team relationships,
  and Club Competition Organizer remain ON. Referee foundation/marketplace and
  Club relationships remain ON, while Referee Assignments remains OFF.
- Canonical legacy backfill remains uninitialized and was not executed.

## Grants, wizard, and canonical flow

- The product reuses `pachanga_competition_entitlement_grants`; it does not add
  a second entitlement authority. TEAM and CLUB organizers require an active,
  unexpired `LEAGUE_PRIVATE_BETA_V1` bundle in addition to their canonical
  owner/Club role.
- Each bundle contains 11 existing capabilities: `competition_create`,
  `competition_manage`, `competition_staff`, `competition_rules`,
  `competition_categories_manage`, `competition_entries_manage`,
  `competition_rosters_review`, `competition_schedule`,
  `competition_results`, `competition_standings`, and
  `competition_operations`.
- Grants use `platform_grant`, retain actor/reason/time/revision/sequence,
  support expiry and exact bundle revocation, and never include discipline,
  billing, payments, referee assignment, or platform flag authority.
- Standard capacity is 4-12 Teams; 13-20 requires an explicit platform
  override; more than 20 returns `BETA_CAPACITY_LIMIT`.
- The ten-step wizard persists every step through idempotent, revisioned server
  commands. Finalization materializes the existing R1/R4 graph atomically and
  now leaves both Competition and Edition in `draft`; only the separate R4A
  `registration.open` command opens registration.
- Identity, modality, Edition/dates, invite-only Teams, rosters, scoring,
  tiebreakers, schedule, results, exceptions, and final consent are represented
  in the immutable RuleRevision/read model. Discipline, referee assignment,
  payments, and tournaments are explicitly unavailable.
- Staging exercised both CLUB and TEAM grant paths, invitations, owner
  acceptance/rejection, delegates, eligibility and roster revisions, schedule
  generation/publication, squads, attendance, sporting and official results,
  standings, postponement, no-show, suspension/resume, and administrative
  decisions through the existing R1/R4 commands.
- `Mis Ligas`, the bounded wizard, and the Control Center expose canonical
  read models only. The existing notification system delivered the expected
  invitation, schedule, result and incident signals; recipient-aware assertions
  prevented duplicate or unbounded fan-out.

## Production smoke and cleanup

The final production smoke used the known non-real Team organizer
`6401ec56-4877-4395-b211-0973b7f227eb` and an ephemeral grant. It verified:

1. Grant replay returned the same canonical response and did not duplicate the
   11 capability rows.
2. Wizard creation and all ten revisioned steps converged at revision `12`.
3. Finalization created Competition
   `53fe4cfa-3e64-4738-96a2-53f6d1b04f41`, Edition
   `1027f81a-ac04-46b4-b9f0-9def69755b93`, and RuleRevision
   `6a57e985-903e-432e-a1b0-57a771e28d40` as private, invite-only canonical
   entities.
4. Before opening, the Edition was `draft`, revision `1`, with
   `registration_opens_at = null`; the independent canonical command moved it
   to `registration_open`, revision `2`.
5. The Competition was cancelled at revision `2` before fixtures and the exact
   bundle `d3669c4c-3aaa-48e6-9191-34cbb89e1fd4` was revoked.

Final independent readback found 0 active QA bundles, 0 draft wizards, 0 active
QA competitions, 0 fixture plans, 0 canonical match contexts, 0 sporting
results, 0 standing snapshots, and 0 operational rows. The retained audit rows
show the completed wizard, cancelled Competition, and 11 revoked grants. The
smoke wrote no Rating, Reward, Conduct, discipline, payment, referee assignment,
or Tournament data.

## Production web, PWA, Realtime, and logs

- `https://pachangasiq.com/ligas` returned 200 at 1440x900, 390x844, and
  844x390 with 0 horizontal overflow, 0 controls outside the viewport, 0 broken
  images, and 0 console errors or warnings. Navigation and private
  `noindex, nofollow` metadata were present.
- Manifest and Service Worker returned 200. The Service Worker is controlled
  and its script is served with `no-cache, no-store, must-revalidate`; offline
  mutations remain blocked and are never shown as confirmed.
- Physical Android, physical iPhone, and a physically installed PWA remain
  `PENDING`; they are not represented as PASS.
- Realtime logs contained 81 recent entries and no error/fatal/failed sample.
  The implementation only treats Realtime as invalidation and refetches the
  canonical snapshot on `SUBSCRIBED` and reconnect.
- Recent PostgreSQL logs contained 94 normal log entries, 6 diagnostic errors,
  and 0 `FATAL`/`PANIC`. All six errors came from deliberate negative or
  temporary release-harness probes and were transactionally rolled back; two
  are permanently recorded as LPB-018 and LPB-019 below.
- Vercel reported no runtime error cluster for the release. Three observed 503
  responses belong exclusively to the pre-existing
  `/api/internal/rankings/refresh` `CRON_SECRET` debt and are unrelated to
  League Private Beta.
- Supabase security advisors retain six intentional authenticated
  `SECURITY DEFINER` RPC warnings. Each RPC revokes `PUBLIC`/`anon`, resolves
  `auth.uid()` internally, and validates canonical role/entitlement before
  access. The invalidation-table anonymous-sign-in advisory is also bounded by
  target-user, Team owner, Club role, or Competition-read predicates; it does
  not grant an anonymous user League access. See the
  [Supabase SECURITY DEFINER advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- Performance advisors contain only 10 `INFO` notices for newly introduced,
  pre-traffic indexes. They are retained because they cover canonical actor,
  organizer, Competition, receipt, and invalidation access paths. See the
  [unused index advisor](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Rollback and remaining debt

No rollback was required. The tested emergency path is forward-only: disable
creation first, disable the beta read/write gate only if needed, retain schema,
grants, events and sporting history, and then selectively disable R4D-R4A and
Club organizer. It never promotes a browser cache or legacy payload into a
source of truth and never runs down migrations.

Deliberately deferred: R5 Competition Discipline, cards/sanctions, Referee
Assignments, organizer billing/Stripe, Tournament Engine, public League
registration/discovery/calendar/standings/exception status, physical Android,
physical iPhone, physically installed PWA, and the Ranking `CRON_SECRET` repair.
R5 and Tournament Engine were not started.

## Final state

| Capability | Production state |
| --- | --- |
| Official UI V2.1 | LIVE / ACTIVE |
| Clubs & Referees | STABLE / ACTIVE |
| League Private Beta | ACTIVE / INVITE-ONLY |
| League creation | GRANT REQUIRED |
| R1 | ACTIVE only for authorized beta flows |
| R4A Participation | ACTIVE / PRIVATE BETA |
| R4B Scheduling | ACTIVE / PRIVATE BETA |
| R4C Match Operations | ACTIVE / PRIVATE BETA |
| R4D Operational Exceptions | ACTIVE / PRIVATE BETA |
| Public registration/calendar/standings/exception status | OFF |
| Referee Assignments | OFF |
| Competition Discipline | NOT IMPLEMENTED |
| Payments | NOT IMPLEMENTED |
| Tournament Engine | NOT IMPLEMENTED |
| Canonical legacy backfill | NOT EXECUTED |

## Defect register

| ID | Classification | Original scenario | Status | Regression |
| --- | --- | --- | --- | --- |
| LPB-001 | PRODUCT_BUG | Two platform operators raced to revoke the same active beta bundle. Both calls failed because the RPC variable `bundle_id` was ambiguous with the entitlement column. | fixed + regression_verified | `tests/league-private-beta-v1-concurrency.mjs` repeats the two-client revocation and requires one canonical effect plus one explicit stale conflict. |
| LPB-002 | PRODUCT_BUG | Platform bundles and private organizer/wizard lists were not all bounded, so their read models could grow indefinitely. | fixed + regression_verified | SQL now caps each list at 100 with stable ordering; `tests/league-private-beta-v1-scale.sql` verifies 120 bundles produce a bounded response and accurate global metrics. |
| LPB-003 | TESTABILITY_GAP | Staging advisor readback exposed eight new foreign keys without dedicated covering indexes before the product had representative traffic. | fixed + regression_verified | A forward-only fourth migration adds all eight indexes; static coverage and a repeated staging advisor readback verify the original warnings disappear. |
| LPB-004 | SIMULATION_BUG | The first authenticated staging run requested `creationEnabled=true` before the R4B, R4C and R4D dependency gates were enabled. PostgreSQL correctly rejected the illegal activation through `pachanga_comp_foundation_private_beta_creation_check`. | fixed + regression_verified | The staging runner follows the production activation order, proves creation remains blocked before dependencies, and completes the full story once every dependency is active. |
| LPB-005 | TESTABILITY_GAP | A repeated staging run rotated all fixture passwords and immediately opened nine concurrent Auth sessions; one returned `invalid_credentials` without identifying the affected role. | fixed + regression_verified | Supplemental users receive deterministic password rotation and bounded role-labelled sequential authentication; the repeated authenticated staging run passes. |
| LPB-006 | SIMULATION_BUG | The expired-grant negative fixture moved only `expires_at` into the past, making it earlier than immutable `valid_from`; the canonical entitlement constraint correctly rejected the impossible interval. | fixed + regression_verified | The fixture now uses `valid_from < expires_at < server now` and proves the expired bundle cannot authorize wizard creation. |
| LPB-007 | SIMULATION_BUG | After finalizing the ten-step wizard, the composed staging story tried to read an R4A category from the R1 foundation snapshot. Categories belong to the participation bounded context and are intentionally absent from that read model. | fixed + regression_verified | The service-only fixture reads `pachanga_competition_categories`; all participation actions continue through canonical R4A RPCs and pass. |
| LPB-008 | SIMULATION_BUG | The private-beta negative test expected the category-level `PUBLIC_REGISTRATION_NOT_AVAILABLE` error, but the global public-registration gate rejects the request earlier with `LEAGUE_PUBLIC_REGISTRATION_DISABLED` (`42501`). | fixed + regression_verified | The regression requires the authoritative fail-closed error and then completes invite-only registration successfully. |
| LPB-009 | SIMULATION_BUG | The delegate invitation assertion expected `userId` in the participant-facing entry snapshot. The canonical R4A read model intentionally exposes display name, role and status but omits the delegate identity key. | fixed + regression_verified | The test asserts role/status and independently proves `userId` remains absent from the participant response. |
| LPB-010 | SIMULATION_BUG | Schedule publication expected six notifications after the private-beta flow had created six owners and six active primary delegates. The canonical fan-out correctly produced twelve recipient notifications. | fixed + regression_verified | Notification assertions are mode-aware: 6 recipients in the base R4B story and 12 in the private-beta story. |
| LPB-011 | TESTABILITY_GAP | The private-beta staging competition used a normal product slug, while the service-only QA archive is deliberately restricted to `r4b-qa-*`/`r4c-qa-*`; failure cleanup therefore could not retire its generated fixtures. | fixed + regression_verified | Synthetic competitions use `r4b-qa-private-beta-*`; canonical cleanup leaves the competition cancelled and 0 active QA bundles/fixtures. |
| LPB-012 | SIMULATION_BUG | The combined R4C→R4D story reused fixtures already made official by result QA, so the first postponement was correctly rejected because only `scheduled`/`ready` matches can be postponed. | fixed + regression_verified | Service-only setup restores the selected synthetic fixture to scheduled/ready before exercising the real R4D commands. |
| LPB-013 | SIMULATION_BUG | Suspension scenarios sent hard-coded partial scores after R4C had already persisted canonical sporting-result revisions for those fixtures. R4D correctly rejected a partial score that did not match its evidence snapshot. | fixed + regression_verified | The runner reads the current canonical sporting-result revision and proves suspension, replay and administrative flows preserve its exact score. |
| LPB-014 | SIMULATION_BUG | The combined story attempted `SET_OFFICIAL_RESULT` for a suspension on a match that already had an active R4C official decision. R4D correctly rejected the second authority with `R4D_SUSPENSION_RESULT_CONFLICT`. | fixed + regression_verified | The integrated private-beta story requires the conflict while the standalone R4D suite retains and passes the successful administrative-result path. |
| LPB-015 | TESTABILITY_GAP | Grant cleanup derived an organizer revision from the first bounded Control Center page. Repeated QA history could push the target organizer outside that page, making a valid targeted revocation untestable. | fixed + regression_verified | Cleanup reads the organizer's own canonical revision and checks the exact bundle through service-only status readback; final active QA bundles are 0. |
| LPB-016 | SIMULATION_BUG | Final cleanup treated every boolean in the beta read model as a mutable gate and incorrectly expected the structural invariant `inviteOnly` to become false. | fixed + regression_verified | Final readback requires structural `inviteOnly=true` while every mutable beta/dependency gate is restored to false. |
| LPB-017 | PRODUCT_BUG | The first production smoke finalized the wizard with the Competition in `draft` but the Edition already in `registration_open`, contrary to the release contract that requires both aggregates to remain drafts until a later canonical registration command. | fixed + regression_verified | A fifth forward-only migration enforces `draft` with no `registration_opens_at`, returns `open_registration`, and the repeated SQL plus authenticated staging story proves only the separate revisioned `registration.open` command opens it. Both QA competitions were cancelled before fixtures and both exact beta bundles were revoked. |
| LPB-018 | SIMULATION_BUG | The first LPB-017 production re-smoke completed its product actions but the temporary result projection used an ambiguous `competition_id` reference, so PostgreSQL aborted the entire diagnostic transaction before returning evidence. | fixed + regression_verified | Immediate readback proved full rollback. The projection was qualified and the final binding-aware production smoke returned the complete canonical evidence with 0 active QA rows after cleanup. |
| LPB-019 | SIMULATION_BUG | The corrected result projection assumed `pachanga_canonical_matches` stored `competition_id` directly instead of resolving the canonical Competition binding, so its final evidence query failed after the product actions. | fixed + regression_verified | Immediate readback again proved full rollback. The final projection resolves the Competition through the canonical binding/context and the repeated production smoke passed with the expected 0 fixtures/results/standings/incidences. |
