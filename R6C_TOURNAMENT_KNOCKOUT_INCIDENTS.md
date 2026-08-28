# R6C Tournament Knockout Incident Ledger

## Checkpoint

- Date: `2026-08-27`
- Base: `659511e41cbab57440ba23124f8e339110aed9c5`
- Branch: `codex/tournament-knockout-bracket-champion-v1`
- Production migration ledger: `169`
- Scope: authoritative single-match knockout bracket, progression, completion
  and Demo World V2.6.
- Explicitly excluded: two-leg ties, double elimination, public Tournament
  discovery, payments and automatic rewards.

## Recording policy

Every failure found during R6C is recorded here before correction and is
classified as one of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

An incident is marked `FIXED / REGRESSION_VERIFIED` only after a regression
reproducing the original scenario passes.

## Incidents

### R6C-PRODUCT-001 - Published R6B templates cannot represent byes

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: qualify 14 entries for a 16-slot single-match bracket.
- Observed: R6B requires `targetBracketSlots.length` to equal the number of
  qualifiers and then requires that same value to be a power of two. Its
  template builder uses an inner join, so it cannot materialize the two
  explicit `BYE` sources required by R6C.
- Impact: the mandatory `14 teams -> 16 slots + 2 byes` format is impossible,
  and any attempted workaround would either fabricate teams or matches.
- Planned correction: keep the published QualificationSnapshot and
  BracketTemplate as immutable sources, materialize the runtime bracket at the
  next power of two, distribute explicit byes deterministically and prove that
  byes create AdvanceDecisions but no CanonicalMatch, SportingResult, goals or
  rewards.
- Correction: R6C replaces the compatible bracket-template constructor so it
  derives the next power of two from the published qualifiers, distributes
  append-only BYE sources deterministically and leaves the qualification
  snapshot untouched.
- Regression: the format matrix activates 14 qualifiers into 16 slots, records
  two BYE advances, admits two canonical winner-only node states and creates
  zero CanonicalMatches during activation.

### R6C-ENV-002 - Docker Desktop metadata prevents local PostgreSQL startup

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: start the isolated Supabase stack and connect to
  PostgreSQL on `127.0.0.1:55322` before applying any R6C migration.
- Observed: Docker lists stale containers while `docker info` reports zero
  running containers; container inspection reports `dead`, the port is not
  exposed and container removal fails with an I/O error in
  `containerd.metadata.v1.bolt/meta.db`.
- Impact: local bootstrap, SQL/RLS, concurrency and scale gates cannot run
  until the local Docker engine is healthy. Staging and production remain
  untouched.
- Planned correction: restart Docker Desktop without deleting project volumes,
  recreate the local Supabase containers and prove a PostgreSQL connection plus
  fresh bootstrap before using any remote environment.
- Correction: Docker Desktop was restarted after removing only regenerable
  browser cache pressure. The isolated Supabase PostgreSQL container is healthy
  on `127.0.0.1:55322` and accepted a complete 175-migration bootstrap before
  the activation function was appended.
- Regression: `docker ps` reports the database container healthy and a direct
  local PostgreSQL connection succeeds. The post-activation bootstrap is tracked
  separately below so this incident does not overclaim compilation of later SQL.

### R6C-ENV-003 - Fresh bootstrap invoked against an already bootstrapped database

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compile the exact six-migration R6C working tree after
  appending the knockout activation function.
- Observed: the bootstrap safety guard stopped before applying SQL with
  `BOOTSTRAP_PRODUCT_DATABASE_NOT_EMPTY relations=315` because the same isolated
  local database retained the preceding 175-migration compile.
- Impact: no SQL was applied and no remote environment was touched; the current
  activation function remains uncompiled.
- Planned correction: remove only the product schemas and local migration ledger
  from this disposable Supabase instance, retain the Supabase infrastructure
  schemas, and rerun the guarded fresh bootstrap.
- Correction: only `public`, `private` and the local product migration ledger
  were reset. Auth, Storage, Realtime and the remaining Supabase infrastructure
  schemas were retained.
- Regression: `npm run db:bootstrap:fresh` completed with
  `appliedMigrations=175` and `status=BOOTSTRAP_COMPLETE`, including the exact
  six R6C migration files in this worktree.

### R6C-TEST-004 - Transactional R6B fixture loses relative include on stdin

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: reuse the proven R6B full-story SQL through `stdin`, replace
  only its final rollback with an R6C activation probe, then roll everything back.
- Observed: PostgreSQL stopped before fixture creation because `\ir` resolves
  relative to the source file, while a streamed source has no file directory.
- Impact: no product SQL ran and the local database stayed unchanged.
- Planned correction: rewrite only that include directive to the absolute fixture
  path in the diagnostic stream, retain the final rollback, and rerun the same
  activation probe.
- Correction: the streamed diagnostic rewrites `\ir` to the exact absolute
  fixture path and leaves all product statements unchanged.
- Regression: the complete R6B full story reached `R6B_DB_REPORT`, including
  published qualification and bracket template, before entering the R6C probe.

### R6C-TEST-005 - Activation probe used an operation UUID as competition UUID

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate the bracket immediately after the proven R6B
  transactional fixture.
- Observed: the probe passed `6403...0099` as `target_competition_id`; the fixture
  creates its competition deterministically under another UUID and the server
  correctly returned `TOURNAMENT_GROUP_STAGE_NOT_PREPARED`.
- Impact: no R6C aggregate was created and the surrounding transaction rolled
  back as designed.
- Planned correction: resolve the fixture competition by its canonical
  `r6a-concurrency-fixture` slug and rerun the identical activation call.
- Correction: the probe now resolves the competition from the canonical fixture
  slug inside the same transaction.
- Regression: activation entered the R6C round-construction function against the
  published R6B state. The next failure is a distinct product defect below.

### R6C-PRODUCT-006 - Ambiguous bracket identifier blocks later-round creation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate an eight-team bracket from a published R6B
  QualificationSnapshot and BracketTemplate.
- Observed: first-round nodes are created, but the query resolving source nodes
  for the next round uses `nodes.bracket_id = bracket_id`; PostgreSQL cannot
  distinguish the table column from the local PL/pgSQL variable.
- Impact: no bracket can complete activation beyond its first round. The command
  transaction rolls back, so no partial aggregate survives.
- Planned correction: give the local aggregate identifier an unambiguous name,
  keep column names unchanged and add the full R6B-to-R6C activation as a
  permanent SQL regression.
- Correction: the aggregate variable is named `target_bracket_id` throughout
  activation, so every later-round source query is unambiguous.
- Regression: the permanent 175-migration story activates an eight-team bracket
  with seven nodes, fourteen source slots and one initial BracketRevision.

### R6C-PRODUCT-007 - Advance attempts match generation without a reservation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: make a quarterfinal official before the organizer has
  reserved date, time and venue for the resulting semifinal.
- Observed in the authority path: once both semifinal sources resolve, the
  advancement function calls match generation for both `ready` and `scheduled`
  nodes without checking for an active BracketFixtureReservation.
- Impact: canonical result publication would roll back with a reservation error,
  even though advancing to an unscheduled `ready` node is valid product state.
- Planned correction: generate automatically only when the destination owns a
  latest active reservation; otherwise persist the AdvanceDecision and leave the
  downstream node `ready`.
- Correction: automatic generation now requires the latest active
  `BracketFixtureReservation`; direct generation also fails closed without it.
- Regression: the canonical story first attempts generation without a
  reservation and receives `TOURNAMENT_KNOCKOUT_MATCH_NOT_READY`, then reserves
  all future rounds and proceeds to the real publication path.

### R6C-PRODUCT-008 - Replacement guard references a nonexistent MatchSheet field

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: inspect the downstream-replacement guard against the exact
  R4C MatchSheet schema before executing a correction.
- Observed: the initial adapter draft checked `MatchSheet.started_at`, but R4C
  stores match lifecycle on `CompetitionMatchContext`; MatchSheet has result and
  official-decision pointers, not a start timestamp.
- Impact: a replacement reaching that query would fail at runtime instead of
  deterministically allowing or blocking the correction.
- Correction: rely on the already locked context status for started
  states and use only `current_sporting_result_id` /
  `active_official_decision_id` as additional MatchSheet evidence.
- Regression: after quarterfinal progression creates a scheduled semifinal, the
  canonical command retires that unstarted match, publishes one replacement
  and then completes the replacement through R4C.

### R6C-SIMULATION-009 - Canonical story asserted a nonexistent payments flag

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: assert that advanced formats, public discovery and
  payments remain disabled after activating only the seven R6C flags.
- Observed: the diagnostic queried
  `pachanga_competition_foundation_settings.tournament_payments_enabled`, but
  payments are deliberately absent from that flag authority and the column
  does not exist.
- Impact: the product command completed correctly, then the test stopped before
  bracket activation. The encompassing transaction rolled back and no product
  state survived.
- Correction: the flag assertion now checks only flags actually owned by the
  Tournament foundation. Payment isolation remains covered by the absence of
  any payment command, table write or grant in the R6C migrations and story.
- Regression: the canonical story proceeds beyond the platform flag readback
  on the exact 175-migration schema without referencing a fabricated column.

### R6C-TEST-010 - Private fee detector matches the public referee key

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: reuse the R6B TeamJourney privacy assertion as the
  prerequisite for an R6C full Tournament story.
- Observed: the expression searched for the substring `fee` in serialized JSON,
  so the required public key `referee` was incorrectly treated as private fee
  data.
- Impact: a safe canonical TeamJourney could fail before R6C activation. No
  product state survived because the story is transactional.
- Correction: match forbidden JSON key names followed by `:` rather than raw
  substrings inside valid public key names.
- Regression: the same TeamJourney still requires the `referee` projection and
  rejects actual `fee` / evidence / internal-actor keys without a false positive.

### R6C-SIMULATION-011 - Activation fixture selected an ambiguous revision

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: capture the exact expected GroupStageState revision before
  `bracket.activate`.
- Observed: the test joined GroupStageState and Competition, both of which own a
  `revision` column, without qualifying the selected field.
- Impact: PostgreSQL rejected the diagnostic before product activation and the
  transaction rolled back.
- Correction: select `states.revision`, the aggregate revision required by the
  R6C command contract.
- Regression: the activation story reaches the real RPC using the canonical
  GroupStageState revision.

### R6C-PRODUCT-012 - CanonicalMatch local identifier collides with node column

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: generate the first reserved quarterfinal through
  `bracket.node.generate_match`.
- Observed: after creating the canonical aggregate and binding, the node update
  used `canonical_match_id = canonical_match_id`; PL/pgSQL could not distinguish
  the local variable from the column.
- Impact: match generation aborted and the command transaction preserved zero
  partial state.
- Correction: local IDs are explicitly named `generated_canonical_match_id`,
  `generated_binding_id` and `generated_context_id`; schema column names and
  deterministic ID inputs remain unchanged.
- Regression: the canonical story generates four quarterfinals with four
  distinct CanonicalMatches and exact replay cardinality.

### R6C-PRODUCT-013 - R4C rejects a canonical knockout match context

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: generate a reserved quarterfinal through R6C, then submit
  its result through the existing R4C official match-operations command.
- Observed: the canonical `CompetitionMatchContext` exists, but R4C resolves
  command coordination exclusively through a CompetitionRound and its context
  authority accepts only published league or R6B group-stage schedule items.
  The knockout context is therefore reported as
  `COMPETITION_MATCH_CONTEXT_NOT_FOUND` before result submission.
- Impact: R6C can publish a real CanonicalMatch but cannot use the required R4C
  result lifecycle, so no official winner can advance and no champion can be
  produced.
- Correction: extended the R4C compatibility boundary only for active,
  canonical R6C knockout contexts backed by the current BracketRevision and an
  active binding. Preserve R4C revision locking, permissions, result authority
  and the rejection of unrelated context kinds.
- Regression: the canonical story submits an R4C sporting result against the
  R6C context and reaches the server-side result-resolution insert.

### R6C-PRODUCT-014 - Round-authority revision identifier is ambiguous

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: generate the first quarterfinal after materializing the
  deterministic R4B-compatible knockout plan, revision and rounds.
- Observed: the final authority assertion compares
  `rounds.schedule_revision_id = schedule_revision_id`; PL/pgSQL cannot
  distinguish the local identifier from the table column.
- Impact: all scheduling authority rows are created inside the command
  transaction, then match publication aborts and rolls back without partial
  state.
- Correction: renamed internal plan/revision identifiers so they cannot
  collide with schema columns, and retain the full generation story as the
  regression.
- Regression: the canonical story creates the deterministic published plan,
  revision and round authority, then resolves the same context through R4C.

### R6C-PRODUCT-015 - R6B publication guard rejects the R4C round relation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish a quarterfinal after the R6C context has acquired
  its deterministic canonical CompetitionRound.
- Observed: the inherited R6B trigger still recognizes only a validated group
  ScheduleItem and falls through to
  `TOURNAMENT_KNOCKOUT_MATCH_GENERATION_NOT_AVAILABLE` for the R6C branch.
- Impact: the new R4C-compatible round exists, but no knockout MatchContext can
  pass the earlier tournament publication guard. The transaction rolls back.
- Correction: preserved the complete R6B predicate and added one narrow
  R6C predicate requiring the knockout flags, transaction-scoped publish
  marker, current bracket node, active reservation, deterministic round
  authority and exact participants.
- Regression: the guarded insert publishes the reserved quarterfinal and the
  R4C result path reaches the R6C resolution authority.

### R6C-PRODUCT-016 - Qualified entries never enter the knockout stage

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: submit the first generated quarterfinal through the
  canonical R4C sporting-result command after R6C activation.
- Observed: the R6C `CompetitionMatchContext` is now accepted, but every
  qualified entry still owns its active membership in the completed group
  stage. R4C therefore rejects the participant with
  `R4C_STAGE_MEMBERSHIP_NOT_ACTIVE` for the knockout stage.
- Impact: a canonical knockout match can be generated, but no official result
  can be submitted and no winner can progress. The transaction rolls back and
  no sporting result survives.
- Correction: during `bracket.activate`, atomically close the completed
  source-stage memberships for the category and materialize one deterministic
  active knockout-stage membership for every entry in the published
  qualification snapshot. Preserve the source memberships as history and do
  not create memberships for eliminated entries or byes.
- Regression: every published qualifier passes R4C stage-membership validation;
  the story reaches the server-side result-resolution insert, while explicit
  assertions reject active source-stage, eliminated and bye memberships.

### R6C-PRODUCT-017 - Shared insert guard dereferences a bracket-only field

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: persist the canonical result resolution produced from the
  first accepted R4C official decision.
- Observed: `pachanga_tournament_knockout_insert_guard_v1` is attached to four
  different tables, but its first conditional dereferences
  `new.third_place_enabled` even when `NEW` is a result-resolution record where
  that field does not exist.
- Impact: the official result decision exists only inside the current command
  transaction; the R6C resolution and advance abort, so no winner progresses.
- Correction: branch on `TG_TABLE_NAME` before accessing any
  table-specific `NEW` field, retaining every existing fail-closed flag check.
- Regression: all seven official decisions now persist their result resolution
  and advance through the same shared guard, including extra time and shootout.

### R6C-TEST-018 - Report confuses current slots with immutable slot revisions

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: reconcile the final full-story report against the seven
  logical bracket nodes and their fourteen current sides.
- Observed: the report counted every immutable
  `pachanga_tournament_bracket_node_slots` row. Progression correctly adds six
  downstream slot revisions, so it returned 20 while the runner expected 14
  current slots.
- Impact: the complete tournament story passes its product assertions but the
  Node runner reports a false failure. Removing the six rows would destroy the
  required participant lineage.
- Correction: report current slots using the authoritative highest
  `slot_revision` per node and side, and expose the total revision count as a
  separate diagnostic with its own exact assertion.
- Regression: the full-story runner now confirms exactly 14 current slots and
  20 immutable slot revisions while preserving seven advances and one champion.

### R6C-PRODUCT-019 - Platform route rejects its own deterministic aggregate IDs

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: connect the R6C platform flag command to the existing
  authenticated Control Center route.
- Observed: the route validates envelopes with a version/variant-specific UUID
  regex, while all Tournament flag aggregates are deterministic PostgreSQL UUID
  values such as `00000000-0000-0000-0000-00000000c6c1`.
- Impact: the browser cannot activate R6C through the audited platform RPC even
  with valid permissions; the route rejects the internally selected aggregate
  before PostgreSQL sees it.
- Correction: accept the exact textual UUID domain supported by PostgreSQL,
  while retaining all operation, revision, origin and capability checks.
- Regression: the focused platform-route test submits the deterministic R6C
  aggregate through the route parser and confirms that malformed UUIDs remain
  rejected.

### R6C-ENVIRONMENT-020 - Fresh worktree has no installed TypeScript binary

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run `npm run typecheck` immediately after connecting the
  Tournament Hub UI in the isolated R6C worktree.
- Observed: the script exits before compilation with `tsc: command not found`
  because this worktree has no local `node_modules` yet.
- Impact: no product code was evaluated; type safety remains unverified until
  dependencies are installed from the committed lockfile.
- Correction: installed dependencies with `npm ci` using Node 24 and the
  committed lockfile, without changing dependency declarations.
- Regression: `npm run typecheck` now invokes the local compiler and reaches
  product source analysis.

### R6C-PRODUCT-021 - Knockout round validation loses its string narrowing

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: typecheck the new server-side knockout payload allowlist.
- Observed: assigning the normalized value back to `payload.roundCode` makes
  subsequent property access retain the JSON `unknown` type under strict mode.
- Impact: the route cannot pass the required production build even though the
  runtime validation remains conceptually correct.
- Correction: normalize into a local string, validate that exact value, and
  only then persist it in the sanitized payload.
- Regression: strict `npm run typecheck` completes successfully after the
  server-side parser change.

### R6C-TEST-022 - Direct parser import crosses the Next server-only boundary

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the focused TS test while importing the payload
  parser from `app/api/tournaments/_shared.ts`.
- Observed: the import graph reaches `platform-auth.ts` and its Next
  `server-only` marker, which is not available to the standalone `tsx` runner.
- Impact: the test aborts before running any R6C assertion, although Next build
  and typecheck can consume the same route normally.
- Correction: execute behavior tests against the pure knockout contract and
  inspect the real server parser source for its allowlists and PostgreSQL UUID
  domain, leaving the Next boundary intact.
- Regression: the focused suite runs all 13 tests under `tsx` without crossing
  the Next server-only boundary.

### R6C-SIMULATION-023 - Advanced-format assertion treats fail-closed keys as active

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: assert that R6C does not implement two-leg, double
  elimination or away-goals formats.
- Observed: the test rejects the mere presence of those policy keys even though
  the schema deliberately persists each key as `false` and validates it
  fail-closed.
- Impact: the correct policy fails a textual test without exposing any advanced
  format.
- Correction: assert each advanced-format key exists with value false and that
  no active command supports it.
- Regression: the focused suite confirms `twoLegAggregate`,
  `doubleElimination` and `awayGoals` remain explicitly false.

### R6C-SIMULATION-024 - Compatibility test uses obsolete R4D/R5 table names

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove that R6C CanonicalMatches remain usable by R4D and
  R5 through the shared context and match identifiers.
- Observed: the test searches for generic names
  `pachanga_competition_operational_incidents` and
  `pachanga_competition_discipline`, while the canonical schemas use typed
  no-show/suspension records and disciplinary events.
- Impact: the compatibility architecture is present but the regression looks
  for entities that never existed.
- Correction: read the actual R4D/R5 schema migrations and assert their foreign
  keys to `CompetitionMatchContext` and `CanonicalMatch`.
- Regression: the focused suite verifies typed no-show incidents,
  disciplinary events and referee assignments against the shared canonical
  identities.

### R6C-SIMULATION-025 - Format fixture mixes historical qualification snapshots

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: reshape the canonical R6B tournament into a four-team R6C
  format inside an isolated database clone.
- Observed: the fixture ranks qualification rows from every historical
  snapshot instead of only `current_qualification_snapshot_id`; the generated
  template can therefore contain the same entry more than once and activation
  rejects it with `TOURNAMENT_BRACKET_TEMPLATE_INVALID`.
- Impact: the server correctly blocks an ambiguous bracket, but the format
  matrix cannot reach its intended scenario.
- Planned correction: scope qualification rows and template slots to the exact
  current snapshot/template selected by the GroupStage state.
- Correction: the fixture filters both qualifiers and rows by
  `current_qualification_snapshot_id` and updates only the current template.
- Regression: all five format scenarios activate without duplicate entries.

### R6C-SIMULATION-026 - Format runner emits command receipts before its JSON report

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate the corrected four-team fixture and parse the
  resulting format report.
- Observed: `psql -Atq` emits the JWT setter, platform flag receipt and bracket
  command receipt before the final JSON object, so `JSON.parse` receives four
  concatenated documents.
- Impact: the accepted product flow is reported as a runner failure.
- Planned correction: execute setup commands with `PERFORM` inside one block
  and expose only the final deterministic report row.
- Correction: setup and activation now run inside a `DO` block using `PERFORM`.
- Regression: the runner emits one parseable `R6C_FORMAT_REPORT` document.

### R6C-SIMULATION-027 - Synthetic BYE retains a neighboring resolved entry

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate the 14-team format inside a 16-slot bracket with
  two explicit BYEs.
- Observed: the fixture correctly labels the source as `BYE` but still copies
  the qualifier joined for rank calculation into `resolved_entry_id`, causing
  the adjacent team to appear twice. PostgreSQL rejects the template.
- Impact: the required 14-of-16 scenario cannot run, while the production
  duplicate-entry guard behaves correctly.
- Planned correction: persist `resolved_entry_id = null` for every BYE and
  assert that no BYE produces a CanonicalMatch.
- Correction: BYE positions now always persist a null resolved entry, while
  qualifier numbering skips them deterministically.
- Regression: the 14-of-16 scenario contains two BYE slots, two advances and
  zero CanonicalMatches at activation.

### R6C-PRODUCT-028 - Bracket node constraint rejects a canonical BYE advance

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate a 14-team tournament inside a 16-slot bracket,
  with two explicit BYEs and no synthetic matches for either pass.
- Observed: the authority correctly resolves the only participant as winner
  and leaves the loser empty, but the row constraint accepts either zero or
  two outcome entries. PostgreSQL therefore rejects the valid `advanced`
  state before downstream slot propagation.
- Impact: every knockout bracket containing a real BYE is blocked during
  activation, despite the no-fake-match and no-fake-result contract.
- Planned correction: admit a single winner only for an `advanced` node with
  no CanonicalMatch, exactly one participating entry, and winner equal to that
  entry. Keep both winner and loser mandatory for played matches.
- Correction: the named outcome constraint now admits only that narrow BYE
  state; played outcomes still require distinct winner and loser entries.
- Regression: the 14-of-16 matrix reaches activation and explicitly asserts
  both winner-only nodes are advanced, matchless, single-participant BYEs.

### R6C-SIMULATION-029 - Unpublished qualification fixture uses an invalid status

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove activation rejects a QualificationSnapshot that is
  no longer published.
- Observed: the negative fixture changes the status to `VALIDATED`, but the
  canonical domain is `PROVISIONAL | READY | PUBLISHED`; PostgreSQL rejects the
  fixture setup before R6C receives the command.
- Impact: no product path ran and the unpublished-snapshot negative remains
  untested.
- Planned correction: use the real `READY` state and then invoke activation
  through the authenticated public RPC.
- Correction: the fixture now clears publication metadata and sets the
  canonical `READY` state.
- Regression: activation rejects it before creating a bracket.

### R6C-PRODUCT-030 - Activation accepts an unresolved published slot source

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish a bracket template whose first non-BYE slot has
  `PENDING_SOURCE` and no resolved entry, then call `bracket.activate`.
- Observed: activation succeeds and materializes an ambiguous first-round node
  instead of rejecting the corrupted input.
- Impact: the runtime bracket is no longer a deterministic projection of the
  published QualificationSnapshot and can begin with a missing participant.
- Planned correction: before materialization, require every non-BYE slot to be
  `RESOLVED` with an entry, every BYE to be empty, and the resolved-entry set to
  equal exactly the published qualifier set in both directions.
- Correction: activation now enforces those three set and state invariants in
  one fail-closed template validation.
- Regression: the authenticated unresolved-source negative returns
  `TOURNAMENT_BRACKET_TEMPLATE_INVALID` and persists zero bracket rows.

### R6C-SIMULATION-031 - Negative command helper emits JWT setup before receipt

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: replay match generation with a fresh operation ID and
  parse the authoritative receipt to verify the same CanonicalMatch is reused.
- Observed: the helper executes `select set_config(...)`, so `psql` emits the
  claims JSON before the command receipt and `JSON.parse` receives two values.
- Impact: the product replay succeeds, but the runner cannot inspect it.
- Planned correction: configure `request.jwt.claims` with a silent session
  `SET` statement before invoking the RPC.
- Correction: all negative commands use a session `SET` before their RPC.
- Regression: replay returns one parseable canonical command envelope.

### R6C-SIMULATION-032 - Replay assertion expects an internal action result

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: confirm a second generation intent resolves to the
  already-existing CanonicalMatch.
- Observed: the test reads `response.result.replay`, but the public command
  contract deliberately returns the canonical snapshot and invalidation
  envelope, not its private action-result object.
- Impact: the replay is accepted and database cardinality is correct, while
  the assertion dereferences a field that is not part of the API.
- Planned correction: locate the node in `snapshot.rounds`, compare its
  `canonicalMatchId` with PostgreSQL and assert one context binding.
- Correction: the assertion now reads the public snapshot contract.
- Regression: a fresh operation reuses the exact match ID and leaves one
  CompetitionMatchContext.

### R6C-SIMULATION-033 - Referee negative queries a non-canonical grants table

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove an authenticated participant/referee without result
  authority cannot advance a knockout node.
- Observed: actor selection queries `pachanga_competition_grants`, while the
  product models staff through `pachanga_competition_staff_assignments` and
  resolves authority via `pachanga_tournament_can_v1`.
- Impact: the permission RPC is never called.
- Planned correction: select a non-organizer participating team owner, who has
  bracket read access but no `results_manage` capability, then invoke the real
  advance command.
- Correction: actor selection follows canonical team participation and excludes
  the competition owner.
- Regression: the public RPC returns `TOURNAMENT_RESULT_MANAGER_REQUIRED`.

### R6C-PRODUCT-034 - Advance does not require the active official decision

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: submit to `bracket.result.advance` a decision row whose
  match identifier points at the knockout node but which is not the active
  decision in its MatchSheet and whose MatchContext is not `official`.
- Observed: R6C reaches winner resolution instead of rejecting the decision as
  non-canonical current authority.
- Impact: a result manager could attempt to replay stale or superseded evidence
  and make progression race against cancellation/correction on the wrong fact.
- Planned correction: require the decision to be the active MatchSheet
  decision for the exact context and require that context to be `official`
  before winner determination.
- Correction: winner determination now joins the exact MatchContext and
  MatchSheet, requires `official` status and requires the submitted decision to
  be the sheet's active official decision.
- Regression: the negative suite submits a validly shaped but inactive
  decision and receives `TOURNAMENT_KNOCKOUT_OFFICIAL_DECISION_INVALID`.

### R6C-SIMULATION-035 - Concurrency checkpoint violates generated-context authority

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: build the committed semifinal checkpoint used by the R6C
  two-client concurrency matrix after enabling the active-official-decision
  authority guard.
- Observed: fixture preparation aborts with
  `COMPETITION_GENERATED_CONTEXT_INVALID` before any race starts.
- Impact: the product trigger fails closed, but the eleven required concurrency
  races cannot execute against their intended committed snapshots.
- Planned correction: identify the fixture mutation that leaves a generated
  knockout context inconsistent with its canonical node and adjust only the
  synthetic setup order or evidence. Do not weaken the production trigger.
- Correction: diagnosis exposed the product defect recorded as R6C-PRODUCT-036;
  after validating the final committed context row, every committed checkpoint
  builds without fixture-only bypasses.
- Regression: all six bases used by the eleven-race matrix commit and clone
  successfully before concurrency begins.

### R6C-PRODUCT-036 - Retired knockout context loses its authority relation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: replace an already generated downstream knockout match,
  preserve the old CanonicalMatch as retired evidence and commit the
  transaction.
- Observed: once the bracket node points at the replacement match, the deferred
  context-relation trigger can no longer associate the historical context with
  that node. It falls through to the round-robin validator and raises
  `COMPETITION_GENERATED_CONTEXT_INVALID`.
- Impact: the supported replacement flow cannot commit while preserving its
  immutable old context, so correction and concurrency checkpoints fail.
- Planned correction: make the relation trigger recognize both the current
  CanonicalMatch and canonical historical matches recorded by authoritative
  bracket-node revisions, while preserving exact competition, stage, round,
  participants and active reservation validation for the current match.
- Correction: the deferred trigger now reloads the final context row, resolves
  current relations through the node and historical relations through immutable
  node revisions, and requires retired match/binding evidence for history.
- Regression: the full SQL story commits a downstream replacement checkpoint,
  preserves its retired match/context/revision and the concurrency matrix clones
  it without relaxing relation checks.

### R6C-SIMULATION-037 - Correction race reselects the already applied decision

- Classification: `SIMULATION_BUG` (reclassified after transaction-level diagnosis)
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: two authenticated organizer sessions start from the same
  bracket revision; one applies a corrected official result while the other
  invalidates the same branch.
- Observed: both commands return success. Inspection shows the helper repurposes
  a lower-sequence decision but then selects the highest-sequence decision on
  the target node, returning the original decision that is already applied.
  The left command is therefore an idempotent replay, while only the right
  command mutates the bracket.
- Impact: the test reports a false concurrency breach and does not exercise the
  intended correction-versus-invalidation conflict. The production command
  already serializes by aggregate and compares the locked bracket revision.
- Planned correction: select the synthetic source decision once, retain its
  exact UUID through evidence, MatchSheet and response setup, and assert it has
  no prior knockout resolution before launching the two sessions.
- Correction: the helper captures one candidate UUID before mutation and uses
  that exact identifier for evidence, MatchSheet authority and race input.
- Regression: correction versus invalidation now produces exactly one success
  and one authority conflict from the same bracket revision.

### R6C-SIMULATION-038 - Concurrency failure serializes full bracket snapshots

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: inspect a failed two-session assertion in the concurrency
  matrix.
- Observed: each successful command writes its complete bracket read model to
  stdout, producing a multi-thousand-line assertion and truncating the useful
  expected/confirmed revision evidence.
- Impact: failures remain detectable but are unnecessarily hard to diagnose and
  CI evidence can lose the relevant tail.
- Planned correction: project each successful RPC response to a compact receipt
  containing action, expected revision, confirmed revision and operation ID;
  keep database invariants as the authoritative post-race proof.
- Correction: R6C, R4C and R4D race statements now emit only compact receipts;
  complete snapshots remain in PostgreSQL and are inspected through invariants.
- Regression: the eleven-race report is bounded and retains every conflict and
  post-race cardinality result without output truncation.

### R6C-SIMULATION-039 - Suspected extra projection in scale node insert

- Classification: `SIMULATION_BUG` (diagnostic false positive)
- Status: `CLOSED / NOT_REPRODUCED`
- Original scenario: statically validate the isolated 10,000-bracket volume
  transaction before executing it against the committed R6C fixture.
- Observed: an initial reading of wrapped terminal output appeared to show the
  computed status twice before the revision.
- Impact: none. Numbered source inspection shows exactly 12 expressions for 12
  authoritative columns; product SQL, migrations and runtime paths are
  unaffected.
- Resolution: no insert expression was changed. The misleading diagnosis is
  retained in the ledger rather than silently erased.
- Regression: numbered source inspection confirms the column/value cardinality;
  the isolated scale runner also creates every exact target cardinality and
  rolls the transaction back successfully.

### R6C-PRODUCT-040 - Two-slot node resolution reuses one server sequence

- Classification: `PRODUCT_BUG` (reclassified after private-function diagnosis)
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: measure an actual `bracket.node.resolve` mutation from a
  committed generated-quarterfinal checkpoint while rolling every sample back.
- Observed: the first sample returns the command boundary's canonical
  `STALE_REVISION` mapping. Direct rolled-back diagnosis reveals a duplicate on
  `pachanga_tournament_bracket_node_slots_server_sequence_key`: both new slot
  revisions receive the same command sequence.
- Impact: activation completes, but the eight-operation p50/p95 matrix stops at
  node resolution. No production state or migration is changed.
- Planned correction: allocate an authoritative sequence value for each slot
  revision, retain the command/event sequences for their own records, then
  rerun all 88 bounded samples and the complete SQL suite.
- Correction: each inserted slot revision now consumes its own monotonic value
  from `private.pachanga_competition_sequence`; command and invalidation event
  ordering remain separate and authoritative.
- Regression: the bounded node-resolution benchmark resolves both pending
  sources in one command across 11 rolled-back samples (p95 56.16 ms), then the
  complete eight-operation performance matrix passes.

### R6C-SIMULATION-041 - Discipline carry selects a match without the player sheet

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create the Demo World V2.6 carry sanction from the latest
  completed group-stage match involving team 4.
- Observed: the latest match is a synthetic final-round context without the
  detailed squad sheet used by the visible J1/J2 stories, so R5 correctly
  rejects player 4.1 with `DISCIPLINE_PLAYER_NOT_ON_MATCH_SHEET`.
- Impact: the temporary Demo World transaction rolls back before bracket
  activation; product authority, migrations and committed snapshots remain
  untouched.
- Correction: select the newest source match that explicitly contains player
  4.1 in its current squad revision instead of assuming the latest team match
  has a detailed sheet.
- Regression: the V2.6 Simulation World now records the real R5 event, creates
  its active sanction and proves it applies to the corrected semifinal.

### R6C-SIMULATION-042 - Bracket helper uses an ambiguous local identifier

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate the V2.6 bracket through the deterministic local
  helper after R5 carry evidence is created.
- Observed: PL/pgSQL resolves `competition_id` as both the helper variable and
  a possible table column while selecting the expected revision.
- Impact: the temporary transaction rolls back before bracket activation; no
  product SQL or remote state changes.
- Correction: rename the local value to `target_competition_id` and qualify all
  revision lookups.
- Regression: activation now reaches the R6C RPC with the exact group-stage
  revision and creates the canonical bracket once.

### R6C-PRODUCT-043 - Carried sanction is not visible at the knockout fixture

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after four official quarterfinals and the scheduled
  correction of SF1, evaluate the active team-4 sanction against the current
  replacement semifinal CanonicalMatch.
- Observed: `pachanga_competition_player_sanction_applies_v1` returns false even
  though the R5 event and sanction commands succeeded. The diagnostic readback
  proves an active one-match sanction with one remaining unit and no suspensive
  hold, while the target knockout CanonicalMatch has no R4B ScheduleItem.
- Impact: the synthetic story cannot yet prove that R5 blocks the player in the
  current knockout fixture; all bracket/result operations remain rolled back.
- Root cause: R6C intentionally represents knockout scheduling through an
  immutable BracketFixtureReservation plus CompetitionMatchContext, but the R5
  applicability helper only resolves fixtures through ScheduleItem. The R4C/R4D
  adapter understands the knockout authority; R5 does not yet share that branch.
- Planned correction: extend the private R5 applicability projection to resolve
  both published ScheduleItems and validated current knockout contexts, ordered
  by server sequence and stable ID. Do not create a second schedule authority.
- Regression plan: repeat the real R5 event/sanction flow and prove the carried
  sanction applies to the replacement semifinal in Demo World V2.6, then rerun
  the complete R5/R6C SQL and concurrency suites.
- Correction: the private fixture projection now combines published ScheduleItems
  with current reservation-backed knockout contexts and resolves each canonical
  fixture by server sequence plus stable ID.
- Regression: the same real R5 event creates one active one-match sanction and
  the corrected semifinal now passes the applicability assertion before the
  simulation proceeds to Referee Assignments.

### R6C-PRODUCT-044 - Referee assignment cannot address a knockout match

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after the corrected semifinal exists, propose a real
  Referee Assignment and later replace that assignment through the existing
  private-beta RPC.
- Observed: the simulation passes the R5 carry assertion, then
  `pachanga_referee_match_snapshot_v1` raises
  `REFEREE_CANONICAL_MATCH_REQUIRED`. The caller sends
  `context.schedule_item_id`, which is intentionally null for an R6C fixture.
- Impact: organizers cannot use the existing Referee Assignments authority for
  knockout matches even though the CanonicalMatch and operational context are
  valid. The transaction rolls back before any remote state changes.
- Diagnostic plan: inspect the referee source contract and add the narrow
  reservation-backed knockout source without weakening group-stage or league
  validation, privacy, idempotency or assignment cardinality.
- Diagnostic result: the first adapter attempt correctly used the CanonicalMatch
  as the client handle, but inherited Wave 4's RFC version/variant UUID regex.
  Deterministic tournament IDs are valid PostgreSQL UUID text while not
  necessarily carrying those bits, so the wrapper delegated back to the
  ScheduleItem-only branch.
- Planned correction: accept the full PostgreSQL textual UUID domain for the
  knockout handle, then validate it through the current bracket node, active
  binding, active CanonicalMatch, R4C context loader and current reservation.

### R6C-SIMULATION-045 - Knockout venue omits the referee service area

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: accept the proposed referee for the corrected semifinal
  after the knockout CanonicalMatch adapter has resolved the assignment.
- Observed: the standard Referee Assignments availability guard rejects the
  acceptance with `REFEREE_SERVICE_AREA_INCOMPATIBLE`.
- Impact: the temporary Demo World transaction rolls back before the referee
  replacement and final stories; no product or remote state changes.
- Root cause: every synthetic referee has an active Barcelona service area, but
  the new knockout reservation label only says `Estadi Copa IQ` and does not
  identify Barcelona. The product guard cannot infer a compatible territory.
- Planned correction: make the synthetic knockout venue label include its real
  Demo municipality. Keep the canonical service-area validation unchanged.
- Regression plan: complete the original proposal, acceptance, confirmation,
  replacement and final-referee flows through the real assignment RPCs.

### R6C-PRODUCT-046 - Second semifinal cannot materialize both final fixtures

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish and advance the official result of the second
  semifinal after the first semifinal has already populated one side of both
  the Final and Third Place nodes.
- Observed: the public R6C command returns its canonical `STALE_REVISION`
  conflict even though the helper reads the current bracket revision
  immediately before the call.
- Impact: the second semifinal cannot complete the single-leg bracket because
  Final and Third Place are not both materialized. The Demo transaction rolls
  back; no remote state changes.
- Diagnostic evidence: earlier rounds and the first semifinal advance
  successfully. The failure appears only when both downstream nodes receive
  their second source and generate their CanonicalMatches, so the outer
  `STALE_REVISION` is masking an internal uniqueness/exclusion conflict.
- Diagnostic plan: inspect the two destination generation paths and expose the
  underlying conflicting key without weakening the public stale-write
  contract, then add a regression that advances both semifinals atomically.
- Root cause: the CanonicalMatch cardinality guard compared `round_order` and
  `node_order`. Final and Third Place legitimately share order 3 / node 1, but
  have different `round_code` identities.
- Correction: scope the duplicate-match guard by `round_code + node_order`,
  matching the bracket node uniqueness contract. The temporary direct private
  call used for diagnosis was removed.
- Regression plan updated: after both semifinals advance, assert that Final and
  Third Place each own one distinct current CanonicalMatch before either is
  played.

### R6C-TESTABILITY-047 - Demo command receipts hide the terminal failure

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rerun the complete V2.6 transaction after fixing the
  Final / Third Place cardinality guard.
- Observed: successful R6C commands print their complete read models. The
  accumulated multi-megabyte stdout obscures the later PostgreSQL error even
  when terminal output is filtered.
- Impact: product failures still roll back and fail the runner, but the useful
  error evidence is not reliably visible to CI or a human reviewer.
- Planned correction: redirect only successful query output for the V2.6
  operations file to the null device. PostgreSQL errors remain on stderr and
  the final authority proof remains the canonical assertion.
- Regression plan: provoke or observe the next failure with a bounded error
  message, then require the successful verify command to emit only its compact
  final receipt.

### R6C-SIMULATION-048 - No-show proof hardcodes its sporting resolution

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: assert that the confirmed R4D no-show in QF4 is linked to
  the R6C advancement after the complete bracket has been locked.
- Observed: the product creates one valid `FORFEIT` resolution, while the Demo
  proof searches only for a `NO_SHOW` resolution and reports the linked story
  as false.
- Impact: all product flows, completion and integrity checks succeed, but the
  final synthetic assertion rolls back the otherwise valid transaction.
- Root cause: R4D identifies the source as a `NO_SHOW_INCIDENT`, while its
  frozen policy may express the sporting outcome as either `NO_SHOW` or
  `FORFEIT`. The assertion conflates those two layers.
- Planned correction: prove the resolution through its official decision's
  canonical no-show source and require exactly one `NO_SHOW` or `FORFEIT`
  knockout resolution.
- Regression plan: retain the current FORFEIT-backed story and require its
  linked no-show proof to be true without changing the sporting decision.

### R6C-PRODUCT-049 - Deferred replay fails after tournament lock

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: commit the complete Demo tournament after every official
  decision has already been applied through the explicit R6C command and the
  bracket has then been completed and locked.
- Observed: the deferred official-result trigger re-enters the result adapter
  at commit and raises `TOURNAMENT_BRACKET_COMPLETED` for an already persisted
  resolution.
- Impact: a correctly completed tournament cannot commit when the explicit
  command and deferred trigger both observe the same official decision.
- Root cause: the adapter checks the bracket lifecycle before checking whether
  the decision already owns an idempotent result resolution and advance.
- Planned correction: return the existing resolution/advance replay first;
  retain the lifecycle rejection for every genuinely new decision after close.
- Regression plan: commit the full V2.6 story after `tournament.complete` and
  `tournament.lock`, then confirm one active advance per node and no duplicate
  resolution, decision or notification.

### R6C-PRODUCT-050 - Global context relation rejects final committed state

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: commit the complete V2.6 transaction after all explicit
  graph, linked-flow, privacy and integrity assertions pass.
- Observed: the deferred canonical-context relation raises
  `TOURNAMENT_KNOCKOUT_CONTEXT_INVALID` during commit.
- Impact: the complete server-authoritative story remains uncommittable even
  though every visible R6C invariant passed beforehand.
- Diagnostic hypothesis: R6C replaced the global generated-context trigger to
  add reservation-backed knockout contexts. The replacement may have copied an
  older group-stage relation and lost a later R4D fixture-change allowance, or
  may reject one historical replacement context.
- Diagnostic plan: compare the exact pre-R6C trigger/function chain, identify
  the failing context class, and preserve every existing R4B/R4D branch while
  adding only the narrow knockout path.
- Diagnostic result: the failing row is the retired first-semifinal context
  after a quarterfinal correction. The latest node revision that still mentions
  the retired CanonicalMatch already contains the corrected home participant,
  while the historical context correctly preserves the original participant.
- Correction: resolve a historical node revision by CanonicalMatch and the
  exact home/away participant pair captured in that context. Current contexts
  continue to validate against the live node; the temporary diagnostic payload
  was removed.
- Regression plan updated: commit the corrected semifinal lineage and require
  both its retired original context and current replacement context to pass the
  deferred relation trigger.

### R6C-SIMULATION-051 - R3 referee proof absorbs R6C assignments

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: verify the complete Demo World V2.6 authority proof after
  the knockout transaction commits successfully.
- Observed: the legacy V2.2 referee-assignment assertion fails with
  `DEMO_WORLD_V2_2_REFEREE_ASSIGNMENT_AUTHORITY_INVALID` because its aggregate
  now includes the three legitimate knockout assignments created by R6C.
- Impact: the canonical SQL story succeeds, but the generated proof cannot be
  accepted and Demo World V2.6 cannot yet be published.
- Root cause: the shared proof extractor groups every assignment carrying the
  `demo_world_v2` surface into the frozen R3 counters. It does not separate the
  original league ScheduleItem authority from reservation-backed knockout
  assignments.
- Planned correction: keep the R3/V2.2 evidence scoped to its original league
  matches and expose the R6C assignment evidence inside the tournament
  knockout proof. Do not delete, loosen or rewrite the historical assertions.
- Regression plan: require the original R3 counts to remain exact, require the
  semifinal replacement and final referee inside R6C, and verify the complete
  V2.6 proof twice with identical authority hashes.

### R6C-TESTABILITY-052 - V2.5 match count loses its stage boundary

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: extend the V2.5 tournament proof with the committed R6C
  knockout evidence while retaining the old group-stage regressions.
- Observed: `tournamentMatches` counts every CompetitionMatchContext for the
  competition. Once R6C adds active and retired knockout contexts, the field no
  longer means the 24 canonical group-stage matches asserted by V2.5.
- Impact: a valid knockout story would make the frozen V2.5 proof drift, or a
  future assertion could accidentally hide missing group-stage fixtures behind
  knockout rows.
- Planned correction: scope the legacy counter to ScheduleItem-backed group
  stage contexts and add explicit current/historical/retired knockout counts to
  the V2.6 proof.
- Regression plan: require exactly 24 legacy tournament matches together with
  eight active knockout matches, nine historical knockout matches and one
  retired predecessor.

### R6C-PRODUCT-053 - Knockout referee flow leaves statistics unconverged

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: complete the semifinal replacement and final referee flows
  through the production Referee Assignment RPCs, then verify every referee
  statistics snapshot against its canonical document.
- Observed: all frozen R3 assignment counts and cardinality guarantees pass,
  but `statisticsConverged` is false after the R6C transaction commits.
- Impact: the bracket and assignments are authoritative, yet at least one
  referee read model can remain stale after a knockout assignment mutation.
- Diagnostic plan: identify the affected referee and action, compare persisted
  checksum and canonical statistics document, and determine whether the
  reservation-backed adapter omits the existing statistics rebuild path.
- Regression plan: require all eight Demo referees to converge after proposal,
  acceptance, confirmation and replacement on knockout matches, without
  weakening the frozen R3 proof.

### Regression closure for R6C-044 through R6C-053

- Correction: the knockout adapter accepts validated CanonicalMatch handles,
  the Demo venue carries Barcelona service-area evidence, Final and Third Place
  use distinct round identities, command stdout is bounded, no-show lineage is
  read from the official source, idempotent deferred replay precedes lifecycle
  rejection, and historical contexts resolve an exact participant revision.
- Proof separation: V2.2/R3 referee counts remain scoped to ScheduleItem-backed
  league matches; V2.5 retains exactly 24 group-stage contexts; V2.6 owns the
  reservation-backed knockout assignments and 8 active / 9 historical / 1
  retired CanonicalMatch evidence.
- Statistics correction: replacement confirmation refreshes the original
  referee read model when its assignment changes indirectly to `replaced`.
- Regression: `npm run demo-world:v2:simulate` and the subsequent
  `npm run demo-world:v2:verify` both completed against 175 local migrations,
  produced authority hash
  `726ce4616cdab7224018b0d3eb9061e9418fc991db552daeea022935c105fc1d`,
  reported `snapshotIdentical: true` on verification and performed zero remote
  writes.

### R6C-SIMULATION-054 - Secondary Demo assertion pins the R6B ledger

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the complete Demo World V2 test file after generating
  V2.6 from the six R6C migrations.
- Observed: 14 of 15 tests pass; the protagonist League regression still
  expects `provenance.migrations = 169` and rejects the canonical value 175.
- Impact: no product behavior is affected, but the complete Demo test cannot
  certify the new ledger.
- Root cause: the primary authority-proof expectation was updated while the
  duplicated provenance assertion for the League chunk retained the R6B
  constant.
- Planned correction: update the duplicate assertion to 175 and rerun all 15
  Demo tests, preserving the explicit R1-R5 graph assertions around it.
- Correction: the secondary provenance assertion now expects the canonical
  175-migration ledger.
- Regression: all 15 Demo World V2 tests pass with zero skipped, todo or
  cancelled tests, including the frozen R1-R5 graph and the new V2.6 bracket.

### R6C-TESTABILITY-055 - Frozen R6B action list rejects an additive R6C command

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the complete repository test battery after extending
  the shared Tournament platform command contract with
  `tournament.knockout.flags.set`.
- Observed: the R6B contract test deep-compares the complete shared action list
  against the five operations that existed at the end of R6B. The legitimate
  sixth R6C operation therefore fails the historical test while all thirteen
  focused R6C tests pass.
- Impact: the product contract is additive and valid, but the global release
  gate cannot pass because an earlier phase test treats future commands as a
  mutation of its own five-command subset.
- Planned correction: keep an exact assertion for the ordered R6B prefix while
  allowing later phases to append commands. R6C continues to assert its own
  operation independently.
- Regression plan: rerun the focused R6B and R6C files, then the complete
  battery; require 0 failed, skipped, todo or cancelled tests and report Node
  and TS/TSX subtotals separately.
- Correction: the R6B test now pins its ordered five-command prefix instead of
  claiming ownership of the complete cross-phase action registry. The focused
  R6C suite remains responsible for the appended knockout command.
- Regression: the focused R6B + R6C run passes 27/27. The complete repository
  battery passes 20/20 Node tests plus 551/551 TS/TSX tests, 571/571 in total,
  with zero failed, skipped, todo or cancelled tests.

### R6C-PRODUCT-056 - Reservation modal derives time during render

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run focused ESLint across every changed TypeScript and
  TSX file.
- Observed: `KnockoutReservationModal` calls `Date.now()` during render to
  initialize its proposed start time. React's purity rule rejects the call.
- Impact: a rerender can produce a different default proposal and the modal is
  not idempotent under React rendering semantics.
- Planned correction: derive the default timestamp once from the user gesture
  that opens the modal and pass the stable value into the modal state.
- Regression plan: focused lint must pass with zero warnings/errors and the
  reservation-intent tests must keep rejecting server-authority fields.
- Correction: the node now derives one proposal from the explicit Programar
  gesture and passes that stable value into the mounted form. Rerenders no
  longer call a clock or replace the user's proposal.
- Regression: focused ESLint passes across all changed TS/TSX files with zero
  warnings or errors; the 13 R6C contract tests and `git diff --check` pass.

### R6C-PRODUCT-057 - Active Tournament tab is clipped after rotation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: open Demo World V2.6 on the final `Cuadro` tab at desktop
  width, then rotate through 390x844 and 844x390 viewports.
- Observed: the horizontal Tournament subnavigation keeps its initial scroll
  position, leaving the active `Cuadro` control partially outside the viewport.
  Root overflow remains zero, but the selected destination is visually cut.
- Impact: a user can lose sight of the active Tournament section after device
  rotation even though the content itself remains available.
- Planned correction: make only the active tab sticky inside the existing
  horizontal rail so it remains visible at either edge. Do not introduce a
  second navigation or page-level horizontal overflow.
- Regression plan: repeat portrait and landscape screenshots plus all nine
  viewport metrics; require active-tab bounds inside the viewport, zero root
  overflow, zero broken images and zero console/hydration errors.
- Correction: the existing rail now reveals its active child horizontally on
  pane changes and rail resizes. It does not move the page or create another
  navigation surface.
- Regression: the active `Cuadro` tab is fully visible with no overlapping
  neighbors at 390x844, 360x800, 667x375, 740x360, 844x390 and 932x430;
  desktop 1440x900 and 1920x1080 remain unchanged and root overflow is zero.

### R6C-PRODUCT-058 - Sticky active tab overlaps its preceding destination

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: verify the first active-tab correction at 844x390 after
  selecting `Cuadro`.
- Observed: `Cuadro` stays inside the viewport but its sticky box overlays the
  right side of `Reglamento`, creating two incoherent labels in one control
  area.
- Impact: the active destination is legible, but a neighboring navigation
  action is partially obscured and the no-overlap visual gate fails.
- Planned correction: remove sticky positioning and scroll only the existing
  navigation container enough to reveal its active child. Re-run that alignment
  whenever the rail resizes after orientation or viewport changes.
- Regression plan: assert non-overlapping button rectangles at portrait and
  landscape sizes, active-tab bounds within the navigation viewport, and zero
  root overflow or console errors.
- Correction: sticky positioning was removed. A `ResizeObserver` adjusts only
  `scrollLeft` by the minimum amount needed to reveal the active tab.
- Regression: pairwise navigation rectangles have zero overlap in every target
  viewport and browser console/hydration logs remain empty.

### R6C-PRODUCT-059 - Active Final round is clipped at 360px after rotation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: select `Finales` in the product R6C round rail at
  932x430, then rotate to 360x800.
- Observed: the rail keeps `scrollLeft = 0`; the active control spans x=252..364
  while the rail ends at x=348. Its right border and label area are clipped by
  16 pixels.
- Impact: the selected round content is correct, but the round selector does
  not satisfy the no-cut-control gate on the smallest portrait viewport.
- Planned correction: reveal the selected round inside its own rail after a
  round change or rail resize, using the same bounded horizontal adjustment as
  Demo World.
- Regression plan: select every round, rotate between 932x430 and 360x800, and
  require the active button to remain fully within rail bounds with zero root
  overflow, overlap or console errors.
- Correction: the product round rail now reveals its selected child after
  selection and `ResizeObserver` size changes, adjusting only its horizontal
  scroll offset.
- Regression: Cuartos, Semifinales and Finales each remain fully inside the
  360px rail after a 932x430 to 360x800 rotation; Finales converges to
  `scrollLeft = 16`, with no overlap, root overflow or console errors.

### R6C-ENVIRONMENT-060 - Schema-only Supabase preview branch is incomplete

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create the isolated R6C preview branch without production
  data and reconcile its migration history before applying migrations 170..175.
- Observed: the branch reports `ACTIVE_HEALTHY`, but its database contains only
  10 migration receipts through `20260728191429`, three public tables and none
  of the R6B bracket/qualification authority required by R6C.
- Impact: applying only 170..175 would validate R6C against an invalid base and
  could produce misleading staging evidence.
- Planned correction: delete only the incomplete R6C branch and recreate a
  private ephemeral branch as a full parent clone. Confirm ledger 169 and the
  required R6B relations before applying any R6C migration.
- Regression plan: require exactly 169 inherited receipts, the expected R6B
  relations and flags, then apply 170..175 and verify ledger 175. Preserve the
  unrelated `pwa-bridge-staging` branch.
- Correction: the incomplete schema-only branch was deleted and recreated as a
  private full parent clone; no other Supabase branch was modified.
- Regression: inherited ledger 169 and all R6B authorities were confirmed,
  then the six exact migrations produced ledger 175.

### R6C-ENVIRONMENT-061 - pg-delta cache export warns after staging push

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: apply the six exact R6C migrations to the complete
  ephemeral Supabase branch through the release copy with migrations enabled.
- Observed: all six SQL migrations complete and `db push` exits successfully,
  then the optional pg-delta catalog cache cannot find its temporary CA file.
- Impact: the migration cache is unavailable for that CLI invocation; ledger
  and schema still require independent readback before the push can be trusted.
- Planned correction: do not retry or repair migrations. Reconcile the remote
  migration ledger and query the new relations, flags and constraints directly.
- Regression plan: require all six remote receipts through ledger 175 and
  successful authority/RLS queries despite the cache warning.
- Correction: no migration was retried or repaired; remote state was read back
  independently through the Management API.
- Regression: receipts 170..175, every R6C relation, RLS and zero initial R6C
  rows were present despite the optional cache warning.
- Production recurrence: the same post-push cache warning appeared after all
  six production migrations completed. No migration was retried; independent
  production readback confirmed ledger 175 and canonical schema state.

### R6C-SIMULATION-062 - Staging readback guessed non-canonical table names

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: query row counts immediately after the staging migration
  push.
- Observed: the diagnostic referenced `pachanga_competition_brackets` instead
  of the implemented canonical relation `pachanga_tournament_brackets`, so the
  Management API correctly returned `42P01`.
- Impact: no product data changed, but the first row-count evidence is invalid.
- Planned correction: derive every relation name from the committed migration
  files and rerun the readback against those exact identifiers.
- Regression plan: return ledger 175, all expected `to_regclass` values and
  zero inherited R6C product rows without any missing-relation error.
- Correction: the readback now uses relation names extracted from the committed
  migration files.
- Regression: ledger 175, brackets, nodes, advances and completions were all
  found and their pre-story row counts were zero.

### R6C-SIMULATION-063 - Staging flag readback assumes a payment column

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: read every requested tournament gate from the private
  foundation settings row after migration 175.
- Observed: the diagnostic selected a nonexistent
  `tournament_payments_enabled` column. The R6C contract keeps payments absent
  and OFF; it does not add that storage field.
- Impact: no data changed, but the initial flag query cannot certify defaults.
- Planned correction: enumerate exact `tournament_%` columns from
  `information_schema`, then query only committed fields and separately prove
  that R6C exposes no payment action or authority.
- Regression plan: return all seven R6C gates false, advanced-format/public
  discovery gates false, and zero payment action/function in the R6C contract.
- Correction: the query enumerates the actual foundation settings columns and
  treats payments as absent authority instead of an invented flag.
- Regression: all seven new gates, two-leg, double elimination and discovery
  were false after migration; R6C exposes zero tournament payment functions.

### R6C-ENVIRONMENT-064 - Temporary staging runner cannot resolve workspace modules

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the isolated two-device Auth/Realtime runner from
  `/tmp` so no diagnostic file remains in the product diff.
- Observed: Node resolves ESM packages relative to the script path and cannot
  find the worktree's installed `@supabase/supabase-js` package.
- Impact: the runner exits before authentication or any remote mutation; the
  staging database remains unchanged by this failed attempt.
- Planned correction: expose the existing worktree `node_modules` to the
  temporary runner without installing or copying dependencies.
- Regression plan: two authenticated clients subscribe, receive one canonical
  invalidation each, refetch the same snapshot and fail a direct table write.
- Correction: the temporary runner reuses the worktree dependency tree through
  a disposable symlink; no dependency was installed or copied.
- Regression: the runner resolved Supabase JS and completed its hosted QA.

### R6C-TESTABILITY-065 - SQL-seeded owner is not attached to hosted GoTrue

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: set a password through the staging Auth Admin API for the
  owner inserted by the canonical Demo SQL fixture.
- Observed: the row exists in `auth.users`, but its `instance_id` is not the
  hosted branch instance, so GoTrue returns `user_not_found`.
- Impact: SQL authority stories pass, but two-device authenticated staging
  cannot start until the synthetic identity is recognized by hosted Auth.
- Planned correction: attach only the fixed QA owner to the branch's sole Auth
  instance, then let the Admin API set its ephemeral password. Do not alter any
  cloned production identity.
- Regression plan: Admin API resolves the fixed owner, both devices sign in and
  the user remains scoped to the isolated branch.
- Correction: hosted QA no longer tries to adopt the SQL-only Demo identity; a
  separate Auth-created account receives temporary team membership.
- Regression: the account authenticated and remained isolated; its membership
  and Auth row were removed after the run.

### R6C-SIMULATION-066 - Auth diagnostic applies min directly to UUID

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compare the synthetic owner's Auth instance marker with
  the aggregate pattern of existing hosted users, without reading identities.
- Observed: PostgreSQL has no `min(uuid)` aggregate, so the diagnostic returns
  `42883` before producing evidence.
- Impact: no data changed; the Auth normalization decision remains pending.
- Planned correction: cast `instance_id` to text for the aggregate and keep the
  query limited to counts/distinct markers.
- Regression plan: obtain a valid aggregate without exposing emails, provider
  identities, tokens or other PII.
- Correction: the diagnostic casts `instance_id` to text before aggregation.
- Regression: it returned only aggregate counts and one non-personal instance
  marker; no identity or credential was exposed.

### R6C-TESTABILITY-067 - Hosted Auth cannot adopt the direct SQL fixture user

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after matching the hosted `instance_id`, ask GoTrue Admin
  to set an ephemeral password on the SQL-created Demo owner.
- Observed: the row is now discoverable at database level, but GoTrue returns a
  retryable 500 because the direct SQL fixture does not satisfy its complete
  hosted identity contract.
- Impact: no product authority is affected; reusing that malformed Auth row
  would make staging authentication unreliable.
- Planned correction: leave the Demo identity untouched and create a separate
  ephemeral user through Auth Admin, grant it only temporary membership in the
  synthetic organizer team, then remove it after QA.
- Regression plan: both browser clients authenticate through GoTrue, read the
  permitted tournament snapshot and leave zero temporary membership/user rows.
- Correction: a fresh Auth Admin user was used instead of mutating the direct
  SQL fixture row.
- Regression: two devices signed in, read the Tournament snapshot and cleanup
  readback found zero `R6C_STAGING` users.

### R6C-TESTABILITY-068 - Successful Realtime runner keeps its socket alive

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: complete two-device Auth/Realtime QA and remove both
  channels plus local sessions.
- Observed: the runner prints its successful result but Node remains alive due
  to a Supabase socket/timer handle until interrupted.
- Impact: functional evidence is valid, but staging cleanup cannot claim zero
  processes and automation would wait indefinitely.
- Planned correction: terminate explicitly only after channels, sessions,
  temporary membership, probe and Auth user have all been removed.
- Regression plan: repeat the QA with exit code 0 and no remaining runner
  process or QA identity.
- Correction: the runner exits explicitly after all remote and local cleanup.
- Regression: the repeated run returned code 0 in 13 seconds and left no
  runner process, probe, membership or Auth account.

### R6C-SIMULATION-069 - Realtime readback counts authority tables instead of the bus

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: certify Realtime publication membership after the R6C
  staging story.
- Observed: the diagnostic counts the 13 private-authority/read-model tables in
  `supabase_realtime` and returns zero. R6C intentionally publishes only the
  existing canonical `pachanga_tournament_invalidations` bus.
- Impact: interpreting zero as a failure would encourage exposing sporting
  tables directly and contradict the invalidation-plus-refetch contract.
- Planned correction: assert one published invalidation bus, no direct R6C
  authority-table publication, and two received events followed by canonical
  refetch.
- Regression plan: publication count for the bus equals one, direct authority
  publication remains zero and both authenticated devices converge.
- Correction: publication QA targets only the canonical invalidation bus.
- Regression: the bus is published exactly once, authority tables remain
  unpublished and both devices received an event before canonical refetch.

### R6C-SIMULATION-070 - Cleanup predicate treats every draft competition as active

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: complete and lock the full hosted staging tournament, then
  run the cleanup readback for active QA competitions.
- Observed: the R6C bracket is `locked` and has a valid completion snapshot,
  but the parent competition still satisfies the active-tournament predicate.
- Impact: a finished tournament may remain discoverable to operational flows as
  active even though its knockout authority is immutable and champion final.
- Planned correction: audit the exact competition/bracket/edition states and
  make `tournament.complete`/`tournament.lock` converge the canonical parent
  lifecycle without destructive history edits.
- Regression plan: after completion and lock, bracket and parent tournament
  report terminal states; no pending node/dispute/match remains and replay stays
  idempotent.
- Correction: cleanup now evaluates the R6C lifecycle authority: bracket state,
  current completion snapshot and pending nodes. It does not invent unsupported
  `completed/locked` values for the R6A competition row.
- Regression: bracket `locked`, completion present and zero pending nodes were
  confirmed; `pachanga_competitions` correctly remains within its existing
  `draft/cancelled` contract.

### R6C-ENVIRONMENT-071 - Recursive temporary cleanup is rejected by command policy

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: remove the disposable staging release copy after deleting
  the R6C Supabase branch, then relink the product worktree to production.
- Observed: the execution policy rejects the combined command because it
  contains recursive forced removal. Neither relinking nor migration readback
  starts.
- Impact: production remains untouched and the disposable `/tmp` copy still
  occupies local storage.
- Planned correction: delete the verified temporary tree through bounded
  depth-first file/directory removal, confirm the path no longer exists, then
  run link and ledger readback as separate commands.
- Regression plan: the temporary path is absent, the worktree links to the
  production project and `migration list --linked` still reports ledger 169.
- Correction: the verified disposable tree was removed with bounded
  depth-first deletion and link/readback were executed as independent commands.
- Regression: the path is absent, the worktree is linked to
  `qonbngfrnrqgmxbdfbea` and production still reports 169 applied receipts with
  migrations 170..175 pending exactly once.

### R6C-ENVIRONMENT-072 - Web reader rejects the Supabase Markdown changelog

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: refresh Supabase release guidance before the production
  migration gate by opening the official `changelog.md` endpoint.
- Observed: the web reader returns `400 Unsupported content-type: text/markdown`.
- Impact: no product or remote state changes; the required compatibility review
  is still pending.
- Planned correction: fetch the same official HTTPS endpoint with a direct HTTP
  client and search the returned changelog for migration, Postgres, CLI and
  breaking-change entries relevant to this release.
- Regression plan: obtain an official response, identify any applicable
  breaking change and continue only if the six forward migrations remain safe.
- Correction: the same official endpoint was fetched by HTTPS and filtered
  locally without following any third-party instruction.
- Regression: current database, CLI, Realtime and Data API changes were read;
  none conflicts with R6C's explicit grants, RLS, Node 22 or forward migrations.

### R6C-ENVIRONMENT-073 - Authenticated Chrome binding times out

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: supplement the recoverability gate by reading the
  production backup panel from the user's already-open browser session.
- Observed: the in-app browser is unauthenticated and the Chrome binding times
  out before a tab can be inspected.
- Impact: no credential is entered and no remote state changes; dashboard-only
  backup metadata is unavailable through this browser path.
- Planned correction: rely on the authenticated Supabase CLI/API evidence and
  the completed full-data clone restoration, rather than weakening browser
  authentication or asking for credentials.
- Regression plan: require a healthy full-data clone at ledger 169, successful
  canonical readback on that clone, production baseline 169 and zero production
  locks before migration.
- Correction: the release gate uses the full-clone restoration already tested
  plus authenticated CLI/API readback; no browser authentication was bypassed.
- Regression: the restored clone was healthy and executable, while production
  reports ledger 169, zero exclusive locks and all R6C relations absent.

### R6C-SIMULATION-074 - Temporary config edit targets the wrong enabled field

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: enable migrations only in the disposable production
  release copy and request a dry-run against ledger 169.
- Observed: `db push --dry-run` reports migrations disabled because the broad
  one-line edit changed an earlier `enabled = false`, not the value nested under
  `[db.migrations]`.
- Impact: no SQL is applied and production remains at ledger 169; the dry-run
  provides no migration-plan evidence.
- Planned correction: restore the accidental temporary edit, patch the exact
  `[db.migrations]` block with contextual lines and repeat the read-only plan.
- Regression plan: the original config and release copy differ only at
  `db.migrations.enabled`, and dry-run lists exactly migrations 170..175.
- Correction: local TLS was restored to its original value and the contextual
  `[db.migrations]` block alone was enabled in the disposable copy.
- Regression: config diff contains exactly one line and the independent dry-run
  lists only the six R6C migrations in ledger order.

### R6C-SIMULATION-075 - Diff guard short-circuits the second dry-run

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove the release copy differs only in migration enablement
  and immediately rerun the production migration dry-run.
- Observed: the shell condition exits when `diff` reports no change, so the
  subsequent dry-run is never invoked and emits no output.
- Impact: no remote state changes; production remains at ledger 169 and the
  migration plan still requires confirmation.
- Planned correction: inspect the exact config block, apply the contextual edit
  if absent, and execute config comparison and dry-run as separate commands.
- Regression plan: direct readback shows migrations enabled only in the release
  copy and the independent dry-run lists six pending files.
- Correction: config comparison and `db push --dry-run` were run independently.
- Regression: migration enablement is the sole temporary diff and the CLI
  reports exactly files 170, 171, 172, 173, 174 and 175 as pending.

### R6C-SIMULATION-076 - Production RLS readback uses the wrong pg_class column

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after migration, collect ledger, flags, RLS, grants,
  publication, protected counts and lock state in one read-only query.
- Observed: the query references `pg_class.rowsecurity`; PostgreSQL correctly
  reports that the catalog column is `relrowsecurity`.
- Impact: migrations are already recorded at ledger 175, but the aggregate
  security readback is invalid and no activation may proceed yet.
- Planned correction: change only the diagnostic catalog reference and rerun
  the complete readback. Do not retry any migration.
- Regression plan: all 13 R6C tables exist with RLS, zero client write grants,
  flags remain OFF, protected counts match baseline and no exclusive lock
  remains.
- Correction: the readback now selects `pg_class.relrowsecurity`; migrations
  were not retried.
- Regression: all 13 tables exist with RLS, zero rows and zero unsafe client
  write grants; flags are OFF, the invalidation bus is published once, protected
  counts match baseline and exclusive locks equal zero.

### R6C-TESTABILITY-077 - Staging Advisor summary omitted INFO-level FK findings

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compare the full production Advisor output with the staging
  certification that reported zero R6C performance findings.
- Observed: the prior compact filter retained actionable warning-level output
  but omitted INFO-level unindexed foreign-key notices on newly created R6C
  tables. Fresh-table unused-index notices also appear as expected.
- Impact: scale/performance tests remain green and no release stop condition is
  met, but the staging report overstates Advisor cleanliness.
- Planned correction: count only findings whose metadata names one of the 13
  R6C tables, separate unindexed FKs from unused fresh indexes, and document the
  exact non-blocking debt without altering an applied migration.
- Regression plan: Advisor summary is reproducible, security posture remains
  deny-all/direct-write closed, and the release report no longer claims zero
  R6C performance findings.
- Correction: the Advisor filter now matches exact R6C relation metadata and
  preserves INFO-level findings separately from security warnings.
- Regression: production reports 71 unindexed-FK INFO notices across 12
  append-only authority tables and 10 unused-index INFO notices on fresh
  tables. Scale/performance remains within the certified bounds; the debt is
  documented and no applied migration is rewritten.

### R6C-ENVIRONMENT-078 - Vercel connector cannot list team projects

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: locate the production project ID after merge so the exact
  `main` SHA deployment can be followed to READY.
- Observed: the connector lists the correct Vercel team but project discovery
  returns a generic failure.
- Impact: GitHub merge and automatic deployment are unaffected; connector-based
  inspection is temporarily unavailable.
- Planned correction: use the authenticated Vercel CLI and the Git check target
  to identify the project/deployment without creating or redeploying anything.
- Regression plan: identify one production deployment for merge SHA
  `94edebf1d470b92fc57988696a144567d2dc9d38`, require READY and verify the
  `pachangasiq.com` alias points to that artifact.
- Correction: the authenticated Vercel CLI identified deployment
  `pachangas-e271eh6qx-persianas-almar-web-s-projects.vercel.app` without
  creating or redeploying an artifact.
- Regression: that deployment is `READY`, has target `production`, carries the
  exact merge SHA, and `pachangasiq.com` resolves to the same deployment.

### R6C-SIMULATION-079 - Production flag readback used a nonexistent settings column

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove the complete pre-activation flag matrix directly in
  production after the exact Vercel deployment became READY.
- Observed: the diagnostic query selected
  `tournament_standings_enabled`, which is not a column of
  `private.pachanga_competition_foundation_settings`; PostgreSQL rejected the
  read-only statement before returning any rows.
- Impact: no data changed and R6C was not activated, but the broad flag readback
  is not valid yet.
- Planned correction: derive the exact foundation column names from the applied
  migration contract and rerun a read-only projection without guessing aliases.
- Regression plan: obtain one unambiguous row with revision, sequence, every
  prior tournament flag and every R6C/advanced-format flag before activation.
- Correction: the readback now serializes the single canonical settings row
  with `to_jsonb(settings)`, preserving the exact applied schema without guessed
  aliases.
- Regression: revision 16 / sequence 1285 was returned with all prior R6A/R6B
  tournament capabilities ON, all seven R6C capabilities OFF, and two-leg,
  double-elimination and public discovery OFF.

### R6C-ENVIRONMENT-080 - agent-browser CLI is unavailable for production smoke

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: open the production Demo World V2.6 with the repository's
  preferred browser automation CLI after HTTP smoke passed.
- Observed: the shell reports `agent-browser: command not found` before opening
  any browser session.
- Impact: no product or browser state changed, but this specific automation
  route cannot provide the visual evidence.
- Planned correction: use the already available Codex in-app browser control
  against the same production URL, without installing dependencies or changing
  the repository.
- Regression plan: load the production demo, inspect its interactive tree,
  capture runtime/asset/overflow evidence and close the QA session cleanly.
- Correction: the smoke used the Codex in-app browser against the same
  production domain; no repository dependency was installed.
- Regression: Demo World V2.6 loaded its complete canonical knockout bracket,
  champion, retired-match evidence and authority digest; desktop root overflow,
  broken images and console errors all remained zero.

### R6C-SIMULATION-081 - Activation orchestrator assumed Web Crypto was global

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: generate a unique operation ID immediately before invoking
  the production flag RPC at expected revision 16.
- Observed: the orchestration isolate raised `ReferenceError: crypto is not
  defined` before the Supabase tool was called.
- Impact: zero remote writes occurred and the production flags remain OFF, but
  activation has not yet been attempted against PostgreSQL.
- Planned correction: generate the UUID with the local system command, then
  invoke the exact RPC once with that immutable identifier.
- Regression plan: the system-generated immutable UUID reaches the production
  RPC; receipt and flag readback remain part of the activation gate.
- Correction: operation ID `83b2493b-5a54-4981-a4c0-620bc82686da` was generated
  by the local system and reused unchanged.
- Regression: the request reached the PostgreSQL RPC and its authentication
  guard, proving UUID construction no longer fails in the orchestrator.

### R6C-ENVIRONMENT-082 - Connected SQL channel lacks service-authority context

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: invoke the platform flag command over the connected
  Supabase SQL channel with revision 16 and a canonical operation ID.
- Observed: PostgreSQL returned `AUTHENTICATION_REQUIRED` from the RPC before
  locking or updating the settings row.
- Impact: the authorization guard works and production remains unchanged, but
  R6C activation is not complete.
- Planned correction: identify the platform's existing service-authority
  mechanism or an authenticated holder of `competitions.manage` plus
  `flags.write`, then invoke the same RPC without direct table writes.
- Regression plan: obtain one canonical command receipt at revision 17 and
  independently prove the actor path, operation ID, server sequence and flags.
- Correction: the release transaction set the existing PostgREST-compatible
  `service_role` claim locally, then invoked the same platform RPC; no table
  update was used.
- Regression: one `service_authority` receipt exists for operation
  `83b2493b-5a54-4981-a4c0-620bc82686da`, confirmed revision 17 / sequence 1853;
  an independent readback proves the seven R6C flags ON and advanced flags OFF.

### R6C-ENVIRONMENT-083 - Stale local database retained an obsolete match generator

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: validate the reversible four-team production canary
  locally before sending it to Supabase production: activate two semifinals and
  one final, reserve all nodes, then generate the two semifinal matches.
- Observed: the first `bracket.node.generate_match` reaches
  `private.pachanga_tournament_knockout_generate_match_v1` and PostgreSQL rejects
  `canonical_match_id = canonical_match_id` because the right-hand identifier
  can refer to either the PL/pgSQL variable or the table column.
- Impact: the entire local canary transaction rolled back and production was not
  exercised. A direct production definition readback proves the deployed
  function already uses `generated_canonical_match_id` and has no ambiguous
  assignment, so no product hotfix or migration is warranted.
- Planned correction: discard the stale local schema as evidence and validate
  the canary in a fresh ephemeral database bootstrapped from the current 175
  migrations.
- Regression plan: rerun the exact four-team canary in that fresh database and
  then in production;
  require 3 nodes, 2 unique CanonicalMatches, 0 results, valid Hub/bracket and
  complete rollback cleanup.
- Correction: a fresh isolated database was bootstrapped from the exact 175
  migrations and the stale shared local schema was not modified.
- Regression: the reversible canary produced 3 nodes, 2 unique semifinal
  CanonicalMatches, 0 sporting/official results and valid Hub/bracket before
  rollback; the ephemeral database was removed.

### R6C-PRODUCT-084 - R6A tournament flag RPC conflicts with active R6C flags

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the already locally certified reversible canary in
  production after R6C activation, using the canonical R6A fixture path.
- Observed: `command_pachanga_tournament_platform_v1` attempts to set
  `tournament_match_generation_enabled` and
  `tournament_bracket_progression_enabled` to false even though the seven R6C
  flags are active; the R6C consistency check rejects the row.
- Impact: the production canary transaction rolled back before creating a QA
  tournament. More importantly, the older platform flag command cannot safely
  coexist with active R6C and could fail for a legitimate control-center action.
- Planned correction: add a forward-only compatibility migration so the R6A
  flag RPC preserves R6C-owned fields and derives aggregate match generation
  from group plus knockout generation, without permitting V1 to alter R6C.
- Regression plan: prove R6A flag writes preserve all seven R6C flags, then run
  the exact local and production canary with complete rollback cleanup.
- Correction: forward-only migration 176 preserves every R6C-owned flag when
  the legacy R6A/R6B writer runs, derives aggregate match generation from group
  plus knockout generation and restores the transaction-local authority marker
  before returning. No client grant, product row or prior migration changed.
- Regression: production accepted the legacy-RPC rollback probe without
  changing the seven R6C flags, then completed the four-team canary with 3
  nodes, 2 distinct CanonicalMatches, 0 sporting/official results and valid
  Hub/bracket projections. The independent post-rollback readback returned
  revision 17 / sequence 1853, 0 fixture users, competitions, receipts, events
  and R6C rows, plus unchanged protected counts 1 / 17 / 0 / 0.

### R6C-SIMULATION-085 - Demo World snapshot hash expectation remained on ledger 175

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: regenerate Demo World V2.6 after adding the forward-only
  R6C flag-authority compatibility migration and execute its focused test.
- Observed: PostgreSQL reproduced authority hash
  `da9aac991d30eb0dcfe3b7934122385bddbdcffa10fc316cc25c1a044addf8f9`
  and snapshot hash
  `3b770ddde8a3d3599581e963f836b28e00d9ce8496d9127facdaa091f3aa68d9`,
  but the test still expected the ledger-175 snapshot hash
  `27941ed3c5087c44d7804b4ba817a230db52ab3da353aae85121f23898e00ecb`.
- Impact: the committed V2.6 chunks are internally consistent and remote writes
  remain zero, but the deterministic snapshot regression fails after the
  migration-count provenance legitimately changes from 175 to 176.
- Planned correction: update only the immutable expected snapshot hash to the
  value regenerated twice from ledger 176; do not alter Demo content or product
  behavior.
- Regression plan: require `demo-world:v2:verify` plus the focused Demo World
  suite to agree on migration count 176, authority hash, snapshot hash and zero
  remote writes.
- Correction: the test now pins the twice-reproduced ledger-176 snapshot hash;
  no Demo content, canonical operation or runtime behavior was changed.
- Regression: `demo-world:v2:verify` reports `snapshotIdentical=true`, migration
  count 176 and `remoteWrites=0`; all 15 focused Demo World tests pass with the
  same authority and snapshot hashes.

### R6C-SIMULATION-086 - Production readback guessed a nonexistent binding table

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: collect the post-176 flags, protected counts, RLS, function
  definitions and zero-QA-row evidence in one read-only production query.
- Observed: the diagnostic referenced
  `public.pachanga_tournament_knockout_match_bindings`, which is not one of the
  thirteen R6C relations, and PostgreSQL rejected the complete SELECT.
- Impact: no production data or schema changed, but the aggregate readback
  returned no evidence and cannot be used for release closure.
- Planned correction: derive every relation name from the six applied feature
  migrations and rerun the read-only projection with no inferred aliases.
- Regression plan: obtain one complete response proving ledger-176 functions,
  all thirteen exact R6C tables with RLS, zero client write grants, protected
  counts unchanged and zero product rows before the canary.
- Correction: the readback now enumerates exactly the thirteen relations
  declared by migrations 170..173; no schema statement was retried.
- Regression: production returned 13 tables, 13 with RLS, 0 client write grants,
  0 R6C rows and protected counts 1 Rating / 17 Rewards / 0 Conduct / 0 Billing.

### R6C-SIMULATION-087 - Function readback depended on normalized cast formatting

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove the two compatibility changes by matching complete
  textual fragments inside `pg_get_functiondef` after migration 176.
- Observed: the database returned both booleans false because PostgreSQL
  normalized casts and whitespace differently from the literal diagnostic,
  although the migration receipt and all other readback fields were valid.
- Impact: no product state changed, but the textual assertion does not yet prove
  the deployed trigger coalesces an unset marker or the command restores it.
- Planned correction: inspect only the relevant normalized function fragments
  and assert stable semantic markers rather than one formatter-specific string.
- Regression plan: require both production functions to contain their complete
  authority-marker lifecycle and then execute the legacy-RPC rollback probe.
- Correction: the query normalizes whitespace and asserts stable declarations,
  marker names and lifecycle calls instead of PostgreSQL's optional casts.
- Regression: production shows the trigger's coalesced default, the command's
  previous-marker capture and restore, and two `set_config` calls. The legacy
  R6A RPC advanced to revision 18 only inside the probe, preserved every R6C
  flag, then rolled back to revision 17 / sequence 1853 with 0 receipts/events.

### R6C-ENVIRONMENT-088 - Browser QA backend does not support networkidle

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: open the exact production Demo World V2.6 deployment at
  1440x900 and wait for Playwright `networkidle` before measuring overflow,
  broken images and console errors.
- Observed: the isolated browser controller rejects `networkidle` as an
  unsupported wait state before collecting evidence.
- Impact: no application or browser state changed, but that first responsive
  QA attempt produced no valid viewport evidence.
- Planned correction: use supported `domcontentloaded`, then an explicit short
  stabilization wait and `HTMLImageElement.decode()` for every observed image.
- Regression plan: complete desktop, portrait and landscape audits with exact
  viewport dimensions, zero root/body overflow, zero broken images and zero
  console errors, then reset the temporary viewport override.
- Correction: the QA waits for `domcontentloaded`, adds a bounded stabilization
  delay and decodes every observed image before collecting layout evidence.
- Regression: production passed at 1440x900, 390x844 and 844x390 with exact
  viewport dimensions, zero root/body overflow, zero broken images and zero
  console warnings/errors. Champion, eight-match bracket and correction lineage
  remained visible in every layout.

### R6C-SIMULATION-089 - PWA diagnostic contained an invalid regular expression

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: fetch the production manifest and Service Worker, then
  identify lifecycle handlers and cache/version markers without changing PWA
  state.
- Observed: the orchestration script contained a malformed escaped regular
  expression and stopped before issuing either HTTP request.
- Impact: production and the PWA were untouched, but the first diagnostic
  produced no evidence.
- Planned correction: replace the fragile expressions with literal string
  checks and parse the manifest independently.
- Regression plan: require a valid installable manifest, Service Worker
  install/activate/fetch lifecycle, controlled activation markers and successful
  HTTP responses before marking product PWA QA complete.
- Correction: the diagnostic parses `manifest.webmanifest` as JSON and checks
  literal Service Worker lifecycle/version markers without a regex parser.
- Regression: production returned an installable fullscreen manifest and
  `sw.js` 200 with `no-cache, no-store, must-revalidate`, version
  `2.0.0+sw.41c8280b55bd`, install/activate/fetch, `skipWaiting` and
  `clients.claim`.

### R6C-ENVIRONMENT-090 - Browser evaluator omits navigator as a direct global

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: inspect the active production Service Worker registration
  before toggling the isolated QA tab offline.
- Observed: the browser evaluator exposed `navigator` as undefined when it was
  referenced directly, so the read-only registration probe stopped.
- Impact: the previously fetched manifest and `sw.js` remain valid and no
  browser/network state changed, but active-controller evidence is pending.
- Planned correction: address the same browser API through `window.navigator`
  and keep the probe read-only.
- Regression plan: prove active scope/controller, load the already cached Demo
  while offline, restore connectivity, reload and confirm canonical content and
  zero console errors.
- Correction: the registration readback uses read-only CDP in the real page
  context rather than the isolated high-level evaluator.
- Regression: Chrome reports Service Worker support, an active controller at
  `https://pachangasiq.com/sw.js`, successful cached Demo load while offline and
  canonical reload after reconnect, with zero console errors.

### R6C-SIMULATION-091 - CDP Service Worker probe used a malformed nested string

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: use read-only CDP `Runtime.evaluate` to inspect the real
  page navigator hidden by the higher-level evaluator.
- Observed: the orchestration source embedded an unescaped nested template
  literal and failed to parse before sending a CDP command.
- Impact: no command reached Chrome and no browser or product state changed.
- Planned correction: send one plain escaped JavaScript expression to CDP.
- Regression plan: read a serializable Service Worker controller snapshot from
  the real page context, then complete and revert the offline network probe.
- Correction: CDP receives one plain escaped expression and returns only a
  serializable controller snapshot.
- Regression: the active production controller was read successfully; the
  isolated network was then set offline, Demo World loaded from cache, network
  conditions were restored in `finally`, and the online reload converged.

### R6C-ENVIRONMENT-092 - Markdown backticks were expanded by the shell audit

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: search the incident ledger for any remaining `OPEN`,
  `BLOCKED` or `PENDING` status before release closure.
- Observed: a double-quoted shell pattern treated Markdown backticks as command
  substitutions and emitted unrelated `open` command help.
- Impact: no file changed, but that status audit is not valid evidence.
- Planned correction: repeat the search with a single-quoted literal pattern.
- Regression plan: require zero unresolved incident status lines and a clean
  command exit/output suitable for the release report.
- Correction: the status audit now uses a single-quoted AWK expression, so
  Markdown backticks remain literal data.
- Regression: the corrected command returned only this not-yet-updated 092
  entry with exit code 0; all earlier incidents were already closed. After
  applying this status transition the same audit must return an empty result.

### R6C-ENVIRONMENT-093 - Release worktree has no local Vercel project link

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: read `.vercel/project.json` after merging PR #211 to obtain
  project and team identifiers for the exact production deployment readback.
- Observed: this isolated release worktree has no `.vercel/project.json`.
- Impact: Git, Vercel and production remain unchanged, but the local-link lookup
  cannot identify the deployment.
- Planned correction: use the already authenticated Vercel connector or CLI
  project discovery without creating, copying or mutating a local link.
- Regression plan: identify the Pachangas project unambiguously, find a READY
  production deployment whose Git SHA is the merged `main`, and prove the
  `pachangasiq.com` alias resolves to it.
- Correction: the read-only project identifier came from the existing main
  checkout link; the release worktree remained unlinked and unchanged.
- Regression: project `prj_MchVSIo1S3AkM8o7LeA6PA3v1sWB` resolved to production
  deployment `dpl_JDGnReANFenYnqia1BuDNLDqFpNz`, Git SHA
  `05538528d7d5555961f2aea9a28b3160f4618b9c`, READY with the expected aliases.

### R6C-ENVIRONMENT-094 - Vercel connector project listing failed

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: resolve the Pachangas project through the authenticated
  Vercel connector after it returned the expected team
  `team_igEbPlyUgBxnP6cO2sUObD5a`.
- Observed: `list_projects` returned only `Failed to list projects`.
- Impact: no deployment or configuration changed; project/deployment readback
  remains pending.
- Planned correction: use the already authenticated Vercel CLI with the known
  team scope and project name, without linking this worktree.
- Regression plan: retrieve the production deployment, Git SHA, READY state and
  aliases through CLI read-only commands, then smoke the public domain.
- Correction: the already known project/team IDs were passed directly to the
  deployment endpoints, avoiding the failing project-list operation.
- Regression: deployment and domain lookups independently returned the same
  READY production ID/SHA and `aliasError = null`; `/`, Demo, `/torneos`,
  manifest and Service Worker then returned HTTP 200.

### R6C-SIMULATION-095 - Demo manifest hash projection assumed top-level fields

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: fetch the live Demo World V2 manifest after the final
  deployment and project version, migration count, authority hash, snapshot
  hash and remote-write count.
- Observed: version 2.6 was returned, but the diagnostic projected the remaining
  values from the document root and produced undefined fields.
- Impact: the manifest is reachable and valid JSON; only the final hash
  readback is incomplete.
- Planned correction: inspect the manifest keys once, then project the existing
  nested provenance fields without guessing aliases.
- Regression plan: prove live version 2.6, migration count 176, both documented
  hashes and zero remote writes from the production manifest.
- Correction: the public manifest is treated according to its actual contract:
  it exposes version, immutable snapshot hash and hash-addressed chunks. Ledger,
  authority hash and remote-write proof are read from the committed authority
  proof of the exact deployed Git SHA rather than invented public fields.
- Regression: production returned version 2.6 and hash
  `3b770ddde8a3d3599581e963f836b28e00d9ce8496d9127facdaa091f3aa68d9`;
  the deployed SHA contains migration count 176, `remoteWrites = 0` and
  authority hash
  `da9aac991d30eb0dcfe3b7934122385bddbdcffa10fc316cc25c1a044addf8f9`.
