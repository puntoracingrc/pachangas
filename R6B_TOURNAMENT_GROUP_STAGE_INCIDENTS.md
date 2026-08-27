# R6B Tournament Group Stage Incident Ledger

## Checkpoint

- Date: `2026-08-27`
- Base: `7f46951fd4144985b05c8029606574b82c655b73`
- Branch: `codex/tournament-group-stage-match-tracking-v1`
- Production migration ledger: `163` (pending fresh linked readback)
- Scope: Tournament Group Stage, canonical group matches, tracking,
  qualification, bracket template and Demo World V2.5.
- Explicitly excluded: knockout match generation, bracket progression,
  champion resolution, public discovery and payments.

## Recording policy

Every failure found during R6B must be recorded here before correction and
classified as one of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

After correction, the entry must include its regression and may only be marked
`FIXED / REGRESSION_VERIFIED` after the original scenario passes.

## Incidents

### R6B-ENV-001 - Linked migration readback lacks project reference

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run `supabase migration list --linked` from the isolated
  R6B worktree before changing schema.
- Observed: Supabase CLI exits `1` with `Cannot find project ref. Have you run
  supabase link?`.
- Impact: the remote ledger cannot yet be reconciled from this worktree.
- Planned correction: recover and verify only the Pachangas IQ project link
  from the existing local checkout, without guessing a ref or touching another
  Supabase project; then rerun the exact command.
- Correction: verified the existing linked project metadata identifies
  `Pachangas`, linked this isolated worktree to that exact project ref, and did
  not alter the shared checkout or any other project.
- Regression: `supabase migration list --linked` exits `0`; all local and
  remote versions match through `20260826195040` with no one-sided row.

### R6B-PRODUCT-001 - Qualification health query drops healthy snapshots

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rebuild qualification with every group holding a current
  R4C `StandingSnapshot`.
- Observed: the draft query filters the joined rows to unhealthy groups before
  aggregating `source_standing_snapshot_ids`; a completely healthy tournament
  therefore produces an empty source array and is rejected as incomplete.
- Impact: qualification cannot be rebuilt from valid standings.
- Planned correction: aggregate all canonical current snapshots and count
  unhealthy groups with `FILTER`, then add a SQL regression proving that all
  group snapshots remain in authoritative group order.

### R6B-PRODUCT-002 - Tournament discipline adapter reads non-canonical policy keys

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create the canonical R5 discipline catalog on the first
  group-stage disciplinary event.
- Observed: the initial adapter draft reads `cardTypes` and an embedded
  `checksum`, while R5 publishes `cardTypeCatalog` and derives the checksum
  from the complete policy document.
- Impact: Tournament could create an invalid or incomplete R5 catalog instead
  of reusing the League authority.
- Planned correction: retain the original R5 key names and checksum algorithm,
  then cover Tournament catalog creation and League non-regression in SQL.

### R6B-TEST-003 - Tournament Hub references a deferred nonexistent shield helper

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compile migrations 1-4 without invoking the Tournament Hub
  snapshot.
- Observed: PostgreSQL accepts the PL/pgSQL body even though it references
  `private.pachanga_team_shield_snapshot_v1(uuid)`, which does not exist; the
  only product RPC is user-contextual and requires group membership.
- Impact: the migration compiles but the first real Hub read would fail at
  runtime, and an organizer is not necessarily a member of every participating
  team.
- Planned correction: build a deliberately small public shield projection from
  the canonical loadout/state tables inside the authorized Tournament read
  model, then add a runtime SQL regression for an organizer who is not a team
  member.

### R6B-PRODUCT-004 - R6A phase boundary blocks narrow group match activation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate all seven R6B flags through the audited platform
  RPC after a published Tournament draw.
- Observed: the legacy
  `pachanga_comp_foundation_tournament_phase1_off_check` constraint rejects the
  row because it requires the generic Tournament match-generation flag to stay
  `false` unconditionally.
- Impact: the intended R6B group-only match gate cannot be activated even though
  knockout generation and bracket progression remain disabled.
- Planned correction: replace only the obsolete R6A phase-boundary constraint
  in migration 6 with an R6B boundary that permits the generic flag exactly
  when the narrower group-stage flag is active, while continuing to force
  public discovery, knockout generation and progression off; rerun the original
  platform command as regression.

### R6B-PRODUCT-005 - Group-stage runtime cannot resolve deterministic ID helper

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run `group_stage.prepare` after a published draw, valid
  participant freeze, locked rosters and active R6B flags.
- Observed: the PL/pgSQL variable initializer fails at runtime with
  `function private.pachanga_tournament_operation_entity_id_v1(uuid, unknown)
  does not exist`, although migration compilation succeeds.
- Impact: no GroupStage aggregate can be prepared.
- Diagnosis: the current PostgreSQL schema contains the hardened R6A command,
  which uses transactionally protected random entity IDs, but does not contain
  the older `private.pachanga_tournament_operation_entity_id_v1` helper still
  present in the repository migration source.
- Correction applied: R6B now owns a private, deterministic
  `pachanga_tournament_group_operation_entity_id_v1(uuid,text)` helper and all
  R6B entity derivation uses it. Client roles cannot execute it directly.
- Regression pending: rerun the original `group_stage.prepare` command on the
  effective 163-migration base and on a fresh schema.

### R6B-PRODUCT-006 - Preparation reads a nonexistent freeze checksum column

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: continue the same `group_stage.prepare` call after the
  deterministic R6B entity IDs have been resolved.
- Observed: the adapter reads `freeze_row.participant_checksum`, but the
  canonical R6A `ParticipantFreeze` stores its evidence digest in `checksum`;
  `participant_checksum` belongs to a DrawRevision, not a freeze.
- Impact: every otherwise valid GroupStage preparation fails before persisting
  its immutable preparation evidence.
- Planned correction: use `freeze_row.checksum` for the preparation input and
  snapshot while retaining `revision_row.result_checksum` as the published draw
  evidence; rerun the original preparation flow.

### R6B-SIMULATION-007 - Four-team group schedule is reported unsatisfiable

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after a valid GroupStage preparation, create six dated
  slots for each four-team group and invoke the canonical R4B generator.
- Observed: R4B raises `SCHEDULE_UNSATISFIABLE` with
  `bounded_repair_exhausted` while generating the first group plan.
- Impact: the full-story regression cannot yet prove the 24 canonical group
  fixtures or progress to tracking, standings and qualification.
- Planned diagnosis: inspect the Tournament-to-R4B participant mappings and the
  effective R4B slot/rest constraints. Correct the synthetic fixture if its
  dates are invalid; correct the adapter only if it leaks participants across
  groups.
- Diagnosis: the adapter correctly scopes four entries per
  `competition_group_id`; the fixture supplied 60-minute slots while the frozen
  rule requires 60 minutes of play plus a 15-minute buffer.
- Correction applied: each synthetic slot now lasts 90 minutes, preserving the
  same group/date/resource topology while satisfying the canonical R4B policy.
- Regression pending: rerun generation and assert six scheduled fixtures for
  each of the four groups.

### R6B-PRODUCT-008 - Group schedule publication loses the closed-registration precondition

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish all four group schedules after successful R4B
  generation and validation.
- Observed: `private.pachanga_league_schedule_publish_v1` rejects the operation
  with `REGISTRATION_MUST_BE_CLOSED`.
- Impact: generated group fixtures cannot become official CanonicalMatches.
- Planned diagnosis: trace the edition status from R6A fixture creation through
  R6B prepare, validate and publish; preserve R4B's canonical precondition
  without inventing a parallel Tournament status transition.
- Diagnosis: R4B assumes one SchedulePlan per edition and changes the edition
  from `registration_closed` to `scheduled` after publishing that plan. R6B
  intentionally owns one R4B plan per group, so the second plan sees the first
  plan's intermediate transition inside the same all-groups transaction.
- Correction applied: the private R6B publisher restores only the internal
  `registration_closed` precondition before each subsequent R4B publication;
  all group publications remain atomic and the final R4B call leaves the
  edition canonically `scheduled`.
- Regression pending: publish four plans, assert 24 exact 1:1 matches/contexts
  and assert the final edition status remains `scheduled`.

### R6B-PRODUCT-009 - R4C standings tie-lot lookup has an ambiguous identifier

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish an official group result that triggers the
  canonical R4C standings rebuild.
- Observed: `private.pachanga_league_standings_rebuild_v1` fails with
  `column reference "tie_group_key" is ambiguous` while reading persisted draw
  lots; the same identifier names both a PL/pgSQL variable and a table column.
- Impact: an official result can roll back instead of updating the canonical
  standing snapshot whenever that tie path is evaluated.
- Planned correction: preserve the R4C algorithm and rename or explicitly
  qualify only the local tie variables in a forward R6B migration; rerun the
  official-result scenario and the existing R4C regression suite.

### R6B-SIMULATION-010 - Generated function patch lost one dollar delimiter

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compile migration 3 after copying the unchanged R4C
  standings function with an explicit variable-conflict directive.
- Observed: the generated patch wrote the opening body delimiter as `$` while
  preserving the closing `$$`, causing a SQL syntax error before any runtime
  state was changed.
- Impact: the R6B migration batch cannot compile.
- Planned correction: restore the exact `$$` opening delimiter, run the full
  migration batch again and keep `git diff --check` in the release gate.

### R6B-SIMULATION-011 - Official-result fixture omits persisted tie decisions

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: officialize group results sequentially and let canonical
  R4C rebuild standings after each match.
- Observed: after resolving the SQL ambiguity, R4C correctly raises
  `TIE_REQUIRES_DECISION` for teams still level in a partially played group.
- Impact: the synthetic season stops before all group standings and R6B
  qualification can be built.
- Planned correction: exercise the real `standings.draw_lot` command whenever
  R4C requests a persisted tie decision, then retry the same idempotent
  official-result intent; do not fabricate rows or weaken the tie policy.
- Reassessment: the fixture exposed a product-level contradiction rather than
  merely omitting data. With more than two teams, provisional standings
  naturally contain unplayed teams tied on zero; requiring a final draw lot
  after every partial result makes normal group operation impossible. The
  product correction is tracked separately in `R6B-PRODUCT-013`.

### R6B-ENV-012 - Diagnostic search used an unmatched zsh glob

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: search existing R4C tests for the persisted draw-lot flow.
- Observed: zsh rejected the unmatched `tests/*r4c*` argument before `rg` ran.
- Impact: diagnostic only; no repository or database state changed.
- Planned correction: search the concrete `tests` directory without shell
  globs and confirm the intended R4C contract is found.

### R6B-PRODUCT-013 - R4C applies final tie resolution to provisional standings

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: officialize the first result in a four-team group while
  the remaining fixtures are still pending.
- Observed: the standings rebuild requires `PERSISTED_DRAW_LOT` for teams tied
  provisionally, rolling back the official result. That contradicts the R6B
  contract: provisional standings must exist during the group stage and final
  qualification is only confirmed after every required match is official.
- Impact: any league or group with more than two entries can be blocked by a
  harmless provisional tie.
- Planned correction: make the canonical R4C rebuild distinguish provisional
  from complete scope. Provisional ties receive shared positions and an
  unresolved explanation; once every scoped match is official, the frozen
  rule's final tie policy remains mandatory. Add regressions for both states.

### R6B-TEST-014 - Group-stage command masks an internal constraint failure as stale state

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after all 24 group matches reach an official R4C result
  and current StandingSnapshot, invoke `qualification.rebuild` with the
  revision read immediately from the locked GroupStage state.
- Observed: the public command returns `STALE_REVISION` even though its explicit
  revision guard has current input. Its blanket exception handler maps every
  `unique_violation` raised by downstream canonical engines to stale state,
  hiding the failing invariant and preventing a truthful recovery path.
- Impact: clients may be instructed to reload a revision that was never stale,
  while operators lose the database evidence needed to distinguish concurrency
  from a deterministic product defect.
- Planned correction: reproduce the qualification rebuild through the private
  authority function to identify the original constraint, then narrow the
  public error mapping so only genuine revision/concurrency conflicts become
  `STALE_REVISION`. Add a regression for the original public command.

### R6B-PRODUCT-015 - Bulk qualification and bracket rows reuse one unique sequence

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rebuild qualification for four completed groups and
  persist all sixteen QualificationRows in one authoritative operation.
- Observed: every row receives the command's single `target_server_sequence`,
  while QualificationRows require a unique sequence per row. PostgreSQL rejects
  the second insert. Static review found the same defect in published
  qualification copies and draft/published BracketSlots.
- Impact: qualification and the non-progressing bracket template cannot be
  persisted even though their canonical inputs are valid.
- Planned correction: retain the operation sequence on aggregate snapshots and
  state, but allocate a monotonic database sequence to every child row, as the
  existing R6A/R4C child-row models do. Regress all four bulk insert paths.

### R6B-PRODUCT-016 - Eliminated qualification rows collide on a nullable slot

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: static invariant review of the same sixteen-row
  qualification snapshot after exposing the first constraint failure.
- Observed: `unique nulls not distinct (qualification_snapshot_id,
  target_bracket_slot)` permits only one eliminated row because all eliminated
  entries correctly have no target bracket slot.
- Impact: a valid group stage with more than one eliminated team cannot persist
  its complete qualification evidence.
- Planned correction: replace that constraint with a partial unique index that
  enforces uniqueness only for non-null target slots, then assert that all eight
  eliminated entries and all eight unique qualifier slots coexist.

### R6B-SIMULATION-017 - Discipline assertion references a nonexistent document column

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after qualification and bracket publication succeed,
  verify that the Tournament adapter materializes the exact canonical R5
  discipline policy and checksum.
- Observed: the test reads `policy_document` from
  `pachanga_competition_discipline_rule_catalogs`, but R5 canonically stores the
  document in typed JSON components and never defined that column.
- Impact: the full-story test fails after the product flow has completed and
  could wrongly suggest that the R5 adapter changed.
- Planned correction: compare every relevant catalog projection and its digest
  against `private.pachanga_competition_discipline_default_policy_v1()`, without
  changing R5 storage or authority.

### R6B-PRODUCT-018 - Tournament TeamJourney omits canonical match operations context

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: read the canonical Tournament Hub for a participant whose
  next group match is already published through R4B/R4C and inspect that team's
  `TournamentTeamJourney` projection.
- Observed: the journey exposes group, standing, recent results, next matches
  and provisional qualification, but its next-match projection omits the R4C
  attendance/squad context, applicable R5 sanctions, confirmed referee and
  public R4D incident state required by the R6B contract.
- Impact: a participant cannot use one authoritative journey snapshot to know
  the operational state of the next match; a client would have to assemble
  private tables independently or silently show incomplete information.
- Planned correction: enrich only the sanitized TeamJourney projection from
  the existing canonical R4C, R4D, R5 and Referee Assignment authorities. Add
  a SQL regression proving the fields are present without exposing evidence,
  private restrictions or referee fees.

### R6B-SIMULATION-019 - TeamJourney sanction lookup used a nonexistent roster status

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compile the TeamJourney enrichment that resolves active
  player sanctions through the canonical competition roster.
- Observed: the draft query checked `roster_members.status = 'active'`, but R4A
  models member eligibility and effective dates on immutable roster revisions;
  that generic column does not exist.
- Impact: migration 4 would fail to compile before changing any persistent
  data.
- Planned correction: bind members to the roster's current revision, require
  `eligibility_status in ('eligible', 'waived')` and respect `effective_until`.
  Re-run the original Hub snapshot regression.

### R6B-ENV-020 - Supabase local reset records migrations without the baseline schema

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run `supabase db reset --local` and then execute the R6B
  full-story SQL fixture against the documented local database.
- Observed: the CLI reports a successful reset and migration ledger entries
  through R6B, but the resulting database does not contain the baseline table
  `public.pachanga_groups`; the fixture stops at its first group insert.
- Impact: a CLI-success message alone cannot certify fresh bootstrap or execute
  the R6B regression in this repository's local environment.
- Planned correction: identify and run the repository's canonical baseline
  bootstrap before the ordered migrations, then verify both schema presence and
  the complete R6B story. Do not alter linked or production databases.

### R6B-ENV-021 - Failed pre-bootstrap fixture leaves authentication rows behind

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after the pre-baseline fixture fails on the missing product
  schema, run the guarded product bootstrap and then retry the same fixture.
- Observed: the failed psql invocation had already committed its fixed QA users;
  the product bootstrap correctly checks product relations but does not purge
  Auth data, so the retry collides with `auth.users_pkey` before R6B starts.
- Impact: the full-story regression cannot be judged from that contaminated
  local database.
- Planned correction: reset the local Supabase instance again, run the guarded
  bootstrap first, and execute the fixture exactly once. Keep all hosted
  environments untouched.

### R6B-PRODUCT-022 - Recursive null stripping removes stable TeamJourney fields

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the new TeamJourney contract regression for a
  published match that does not yet have a submitted squad or referee.
- Observed: the Hub's final recursive `jsonb_strip_nulls` removes the `squad`
  and `referee` keys entirely even though the inner match projection declares
  them, so the client receives a shape that varies with operational state.
- Impact: PWA cache consumers and responsive clients cannot distinguish “not
  assigned yet” from an older/incomplete snapshot without shape inference.
- Planned correction: return explicit sanitized sentinel objects with statuses
  `NOT_SUBMITTED` and `UNASSIGNED`, then rerun the exact TeamJourney regression.

### R6B-TEST-023 - Direct-write negative executes with superuser privileges

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove that an authenticated Tournament actor cannot insert
  a QualificationSnapshot directly and must use the command authority.
- Observed: the test's DO block runs as the local `postgres` superuser, which
  bypasses grants and RLS; the fabricated row reaches a foreign-key check
  instead of raising the expected permission error.
- Impact: the negative test can fail for the wrong reason and does not certify
  the real authenticated-client boundary.
- Planned correction: run the attempted insert under `set role authenticated`
  with the existing JWT claims, reset the role afterwards, and
  assert SQLSTATE `42501` plus zero inserted rows.

### R6B-ENV-024 - Isolated worktree has no installed TypeScript toolchain

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the first focal `npm run typecheck` after wiring the
  R6B Tournament Hub, API and Control Center.
- Observed: the script exits `127` with `sh: tsc: command not found` because
  this isolated worktree has no installed `node_modules` yet.
- Impact: the new TypeScript surface cannot be validated until the immutable
  lockfile dependencies are installed in this worktree.
- Planned correction: run `npm ci`, repeat the exact typecheck and only mark
  this incident fixed after it succeeds.
- Regression evidence: `npm ci` installed the lockfile toolchain and the exact
  rerun of `npm run typecheck` completed with exit code `0`.

### R6B-PRODUCT-025 - Tournament Hub omits per-group schedule readiness

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: open Organizer Desk after preparing the group stage and
  decide whether every group has the required slots and generated fixtures.
- Observed: each group projection exposes identity and members but not its R4B
  schedule status, revision, slot count or fixture count. The client cannot
  distinguish a group awaiting slots from one ready to validate without
  reading canonical scheduling tables independently.
- Impact: the Hub cannot drive a truthful group-by-group scheduling workflow
  from one canonical read model.
- Correction applied: extend the sanitized group projection with the mapped
  R4B plan status/revision/server sequence and authoritative slot/fixture
  counts. Keep the API and PWA cache dependent only on the Hub snapshot.
- Regression required: rerun the original four-group SQL story and prove every
  published group reports exactly six slots and six fixtures.
- Regression evidence: the guarded 169-migration bootstrap and exact SQL story
  pass with all four Hub groups reporting `published`, six slots and six
  fixtures.

### R6B-TEST-026 - Static adapter assertion uses a nonexistent R4B wrapper name

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run `npm run test:tournament-group-stage` after wiring the
  Tournament Hub and assert that R6B delegates schedule generation to R4B.
- Observed: the test searches for `pachanga_league_schedule_generate_v1`, while
  the canonical R4B authority actually invoked by the adapter is
  `private.pachanga_league_schedule_generate_revision_v1`.
- Impact: the focal test fails despite the adapter using the correct existing
  authority.
- Planned correction: assert the exact invoked R4B symbol and retain the
  negative assertion against a duplicate Tournament scheduling engine.
- Regression evidence: the focal suite now resolves the exact
  `pachanga_league_schedule_generate_revision_v1` delegation and this scenario
  passes.

### R6B-TEST-027 - Publication assertion does not match the implemented 1:1 invariant

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: statically certify atomic publication and one
  CanonicalMatch plus one MatchContext for every published fixture.
- Observed: the test searches for nonexistent variables
  `fixture_count_value` and `canonical_count_value` and an error label that is
  not used by publication. The implementation compares
  `published_fixture_total`, `canonical_total` and `context_total` with
  `expected_fixture_total`, then checks each binding/context cardinality and
  raises `TOURNAMENT_CANONICAL_MATCH_CARDINALITY_VIOLATION`.
- Impact: a correct stronger invariant is reported as a focal test failure.
- Planned correction: bind the regression to the real count and cardinality
  predicates and the exact public error label.
- Regression evidence: the focal suite now asserts all three authoritative
  totals, the one-binding/one-context predicate and the exact cardinality
  violation label; this scenario passes.

### R6B-TEST-028 - Full-story marker expects an English word absent from SQL evidence

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: statically verify that the SQL full story exercises
  provisional group standings before final qualification.
- Observed: the TypeScript harness searches for `classification`, while the
  durable SQL assertion says `provisional standings with shared positions`.
- Impact: the harness rejects the correct regression scenario because of a
  wording mismatch unrelated to product behavior.
- Planned correction: assert the exact durable standings scenario marker.
- Regression evidence: the focal suite now finds the durable `provisional
  standings` scenario and advances beyond this assertion.

### R6B-TEST-029 - Full-story SQL is not transactionally reversible

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the focal TypeScript contract after aligning its
  static markers, then inspect the full-story SQL hygiene gate.
- Observed: `tests/tournament-group-stage-v1-db.sql` creates fixed Auth and
  product fixtures but contains no outer `BEGIN`/`ROLLBACK`; the final harness
  assertion correctly rejects it.
- Impact: a successful local run leaves R6B fixture rows behind and makes
  retries dependent on a database reset instead of being self-cleaning.
- Planned correction: wrap the included R6A fixture and complete R6B story in
  one transaction, emit the report before rollback, then prove both the full
  scenario and post-run absence of the fixed fixture.
- Regression evidence: the full story emits 4 groups, 24 canonical matches, 4
  standings snapshots, published qualification, 8 bracket slots and zero
  knockout matches, then rolls back. Direct readback reports zero fixture
  competitions, zero fixture users, ledger 169 and every R6B flag still false.

### R6B-SIMULATION-030 - Demo draw plan target diverges from its RuleRevision

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: continue the published Copa Barrios IQ 2027 draw through
  Group Stage, final qualification and bracket-template publication.
- Observed: all three V2.5 authoring payloads declare
  `GROUPS_THEN_KNOCKOUT`, but the persisted DrawPlan creation payload still
  declares `GROUP_ASSIGNMENT`.
- Impact: the real R6B bracket authority must reject the final template with
  `TOURNAMENT_BRACKET_TEMPLATE_NOT_REQUIRED`, even though the frozen
  RuleRevision says that an eight-slot bracket follows the groups.
- Planned correction: align only the Demo DrawPlan target with the already
  authored RuleRevision, preserve the historical public V2.4 snapshot, then
  rerun the complete V2.5 simulation through published qualification and a
  published template with zero knockout matches.
- Regression evidence: the isolated 169-migration simulation consumed the
  published `GROUPS_THEN_KNOCKOUT` lineage, published eight bracket sources and
  retained zero knockout matches and disabled progression.

### R6B-SIMULATION-031 - Demo V2.5 asks for discipline while the rule disables it

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: record canonical R5 cards and sanctions in the Copa
  Barrios IQ 2027 group-stage story and expose their public-safe projection.
- Observed: every Tournament authoring payload persists
  `discipline.enabled=false`, contradicting the V2.5 scenario that is meant to
  exercise cards and sanctions through R5.
- Impact: a Demo could display discipline data that its own frozen rules say
  is disabled, making the public snapshot internally inconsistent.
- Planned correction: enable discipline in the V2.5 Tournament RuleRevision,
  keep public discipline projection sanitized, and prove the card/sanction
  rows are created only through the canonical R5 command authority.
- Regression evidence: V2.5 exported four public card events and at least one
  effective public sanction after canonical R5 commands, while private reasons
  and evidence references remained absent from the generated read model.

### R6B-SIMULATION-032 - Demo group-stage helper has an ambiguous competition identifier

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prepare the Copa Barrios IQ 2027 group stage through the
  real R6B command authority after enabling the private-beta flags.
- Observed: PostgreSQL rejects the helper before `group_stage.prepare` because
  its local `competition_id` variable collides with the identically named
  table column in the revision lookup.
- Impact: the disposable Demo World cannot reach any R6B operation even though
  platform activation succeeds through the audited RPC.
- Planned correction: rename the local variable unambiguously, keep every
  command input and authority boundary unchanged, then rerun the exact complete
  V2.5 simulation from a fresh disposable database.
- Regression evidence: the fresh rerun passed platform activation and entered
  `group_stage.prepare`; PostgreSQL no longer reported an ambiguous identifier.

### R6B-SIMULATION-033 - V2.5 Tournament is authored before the R6B rule compiler exists

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prepare the published Copa Barrios IQ 2027 group stage
  with the RuleRevision referenced by its R6A DrawPlan.
- Observed: the simulator creates and publishes the current Tournament before
  applying R6B. Its immutable RuleRevision therefore uses the historical R6A
  schema, which intentionally contains no executable scheduling, match or
  qualification policy, and R6B raises `TOURNAMENT_GROUP_STAGE_RULES_REQUIRED`.
- Impact: the V2.5 story cannot legitimately schedule group matches from the
  frozen rules; patching the row after publication would violate the product
  contract and hide the migration-order defect.
- Planned correction: retain the copied V2.4 public artifact as immutable
  history, apply the additive R6B migrations first, then create the current
  V2.5 Tournament through the same R6A commands so its initial RuleRevision is
  compiled by the R6B schema before the draw is published.
- Regression evidence: the fresh rerun resolved the group-stage schedule,
  match and qualification policy from the published DrawPlan and advanced to
  the independent locked-roster validation.

### R6B-SIMULATION-034 - Demo rosters retain a superseded authoring revision

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prepare R6B from sixteen accepted entries, each backed by
  a seven-player locked roster with no pending eligibility.
- Observed: the Demo creates rosters from each entry's invitation-time
  RuleRevision, while the later hybrid authoring revision becomes the frozen
  RuleRevision of the published DrawPlan. R6B correctly rejects those rosters
  with `TOURNAMENT_GROUP_STAGE_ROSTERS_REQUIRED`.
- Impact: all player rows are valid, but their roster evidence is bound to an
  obsolete ruleset and cannot authorize the published group stage.
- Planned correction: bind each synthetic roster and roster revision to the
  current published DrawPlan RuleRevision, preserving the immutable entry and
  draw history, then repeat the complete fresh-database scenario.
- Regression evidence: the rerun passed the locked-roster gate for all sixteen
  entries and reached R4B's canonical schedule-input construction.

### R6B-PRODUCT-035 - Accepted Tournament entries can remain bound to a pre-publication rule

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: author a hybrid Tournament revision after teams accepted,
  refreeze and publish the draw, then prepare its R6B group schedules.
- Observed: R6A correctly updates the edition, stage, category, DrawPlan and
  memberships to the final RuleRevision, but accepted entries retain their
  acceptance-time RuleRevision. R4B's shared input authority filters them out
  and raises `SCHEDULE_REQUIRES_AT_LEAST_TWO_ENTRIES`.
- Impact: a valid pre-publication authoring workflow can publish a draw that
  R6B cannot schedule, despite current memberships, frozen participants and
  locked rosters all being valid.
- Planned correction: during the transactional `group_stage.prepare` phase,
  promote only frozen accepted/active entries to the published DrawPlan
  RuleRevision with a monotonic entry revision and server sequence. Preserve
  the participant freeze as the draw-time evidence and add a regression that
  starts with one deliberately stale accepted entry.
- Regression evidence: a fresh V2.5 run reconciled the stale accepted entries,
  generated and published all four R4B group schedules and atomically created
  exactly 24 CanonicalMatches plus 24 MatchContexts. The focal SQL regression
  retains an explicit stale-entry assertion for the final battery.

### R6B-SIMULATION-036 - Demo match sheets submit only one of seven required starters

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: operate the first two Tournament matchdays through the
  canonical R4C squad, attendance, lifecycle and result commands.
- Observed: V2.5's FUTBOL_7 rule requires seven starters, but the Demo helper
  adds only the single player later used for cards and attendance before
  submitting each squad. R4C correctly raises `R4C_SQUAD_POLICY_VIOLATION`.
- Impact: the public story cannot reach match readiness or any downstream
  result, incident, discipline or referee evidence.
- Planned correction: add all seven eligible roster members through individual
  `squad.member.add` intentions for both teams, nominate one captain, and keep
  the existing focal player references for attendance and discipline.
- Regression evidence: the rerun submitted, validated and locked both seven-
  starter squads, closed attendance, marked the matches ready and reached the
  downstream R5 sanction decision.

### R6B-SIMULATION-037 - Demo sanction decision omits required review evidence

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: convert the provisional sanction created from a direct
  red card into a one-match fixed sanction through the R5 committee command.
- Observed: the Demo sends the public outcome and units but omits the mandatory
  private review reason and evidence-reference array. R5 correctly raises
  `DISCIPLINE_DECISION_PAYLOAD_INVALID`.
- Impact: the red-card story cannot demonstrate an auditable committee
  decision even though event recording and the provisional proposal succeed.
- Planned correction: add a synthetic private decision rationale and one
  non-public evidence reference to the command payload; neither field will be
  copied into the public Demo snapshot.
- Regression evidence: R5 accepted the committee decision, activated the
  one-match sanction and R4C subsequently enforced it on the player's next
  squad submission.

### R6B-SIMULATION-038 - Demo reselects a player serving a real R5 suspension

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: operate the sanctioned player's next group match after a
  direct-red committee decision.
- Observed: the fixed seven-player Demo roster has no replacement and blindly
  reuses all seven members. R4C correctly raises
  `R4C_SQUAD_CONTAINS_DISCIPLINARY_INELIGIBLE_PLAYER`.
- Impact: the season cannot continue while preserving the intended proof that
  R5 eligibility is consumed by R4C.
- Planned correction: use eight eligible roster members per team and select
  seven starters for each match by calling the canonical sanction-applicability
  function. The suspended player remains out and the eighth player replaces
  them; the sanction itself is not altered or bypassed.
- Regression evidence: the rerun omitted the suspended player, selected the
  eighth eligible member, and R4C accepted the resulting seven-starter squad.

### R6B-SIMULATION-039 - Later Demo cards target a fixed player absent from the sheet

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: record sparse yellow-card evidence after the replacement
  logic has changed a team's seven-player match sheet.
- Observed: card payloads still target the hard-coded number-seven profile.
  When that player is serving the real suspension, R5 correctly raises
  `DISCIPLINE_PLAYER_NOT_ON_MATCH_SHEET`.
- Impact: the simulation cannot complete later discipline stories and its
  attendance reference may describe a roster member who did not play.
- Planned correction: after each squad is locked, resolve the focal roster
  member and profile from that exact canonical squad revision, preferring its
  captain and otherwise the final selected starter. Use those resolved values
  for attendance and card evidence.
- Regression evidence: the rerun recorded all four sparse cards against players
  present on their exact locked sheets and completed all 24 official results.

### R6B-SIMULATION-040 - Public sanction projection assumes a team-target sanction

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: freeze the public-safe J2 snapshot with the direct-red
  sanction created and decided through R5.
- Observed: the Demo projection joins every sanction through `entry_id`, but R5
  deliberately stores player sanctions with `player_profile_id` and a null
  `entry_id`. The inner join drops the real sanction and the snapshot assertion
  reports an empty list.
- Impact: the public Demo hides a canonical sanction that affected eligibility,
  despite the private R5 row and its service history being correct.
- Planned correction: resolve player-sanction team attribution through the
  universal player's `source_group_id`; retain only public category, summary,
  unit and status fields, with no profile or private evidence identifier.
- Regression evidence: the fresh full simulation exported the active player
  sanction, passed the non-empty public-sanction assertion and generated the
  V2.5 snapshot without an internal player, evidence or private-reason key.

### R6B-SIMULATION-041 - Final Demo scores leave an unresolved persisted-lot tie

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: complete Jornada 3 internally and publish every remaining
  sporting result through the canonical R4C official-result command.
- Observed: once one Group becomes complete, its final sporting table remains
  tied after all configured sporting criteria. R4C correctly rejects the
  transaction with `TIE_REQUIRES_DECISION` because no persisted draw-lot
  decision exists for that exact candidate set.
- Impact: the V2.5 final proof cannot publish qualification or materialize the
  bracket template, even though all 24 canonical fixtures were generated.
- Planned correction: identify the exact Group and adjust only the synthetic
  score matrix so every final Demo Group is separated by its declared sporting
  criteria. Persisted-lot authority remains covered by the dedicated R4C/R6B
  regression rather than being silently invented in the public Demo story.
- Regression evidence: results now derive from stable team numbers instead of
  random draw UUID ordering. All four final Groups contain four unique
  positions after three matches per team and the V2.5 simulator published
  qualification without requesting a synthetic persisted lot.

### R6B-SIMULATION-042 - Authority extractor still enforces the V2.4 zero-match graph

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: extract and validate authority evidence after the V2.5 SQL
  story has completed all Tournament Group Stage operations.
- Observed: the extractor reaches `assertDemoWorldV2AuthorityProof`, but the
  V2.4 assertion still requires `tournamentMatches = 0` and rejects the 24 real
  CanonicalMatches with `DEMO_WORLD_V2_4_TOURNAMENT_GRAPH_INVALID`.
- Impact: the valid SQL graph cannot be exported into the immutable V2.5 read
  model, manifest or visual Demo.
- Planned correction: version the authority proof and public contract to V2.5,
  add exact public-J2 and final-qualification evidence, and preserve V2.1-V2.4
  as immutable historical snapshots.
- Regression evidence: authority proof version 6 accepted 24 Tournament
  CanonicalMatches, exact J2 tracking, 24 final official results, 16
  qualification rows, eight bracket sources and zero progression, then wrote a
  deterministic V2.5 manifest while V2.1-V2.4 remained separate.

### R6B-SIMULATION-043 - Export payload retains the previous authority version literal

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: validate the newly typed V2.5 authority payload after its
  SQL evidence has been extracted successfully.
- Observed: the exported object still sends `version: 5` while the canonical
  authority contract now requires version 6, producing
  `DEMO_WORLD_V2_AUTHORITY_VERSION_INVALID`.
- Impact: valid V2.5 evidence is rejected before snapshot generation.
- Planned correction: emit authority version 6 from the simulator and retain
  the exact-version assertion as the regression gate.
- Regression evidence: the simulator emitted version 6, passed the strict
  authority-version assertion and produced authority hash
  `817cdd67f59ef2b6b12ea121cc84237866ad184f2d0c282fda08126a9b123985`.

### R6B-ENV-044 - Ad hoc proof-summary command contains an unmatched object brace

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: print a concise subset of the committed V2.5 authority
  proof before updating its deterministic tests.
- Observed: the inline Node diagnostic contains one unmatched closing brace and
  terminates with `SyntaxError` before reading the JSON file.
- Impact: no product, database or generated snapshot changed, but the intended
  evidence summary was not produced.
- Planned correction: repeat the read using a short, separately assigned summary
  object and retain the resulting exact counts as test inputs.
- Regression evidence: the corrected diagnostic read authority version 6,
  ledger 169, 24 public fixtures, 16/8 official/scheduled matches, 24 final
  official results, 8 qualifiers and 8 bracket sources without mutation.

### R6B-TEST-045 - Historical League assertion pins the pre-R6B migration count

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the complete Demo World V2 test after exporting the
  V2.5 authority proof and public snapshot.
- Observed: the protagonist League regression still requires provenance
  migration count 163 even though the shared proof and generated read models
  correctly report the additive ledger at 169.
- Impact: 13 of 14 Demo tests pass, but a stale metadata assertion rejects the
  unchanged R1-R5 League graph.
- Planned correction: update only the expected provenance count to 169 and
  rerun the exact 14-test suite with zero skipped/todo/cancelled tests.
- Regression evidence: the focal Demo suite now passes 14/14 with the unchanged
  15-match League graph, additive provenance count 169 and zero
  skipped/todo/cancelled tests.

### R6B-SIMULATION-046 - Current Tournament operations retain V2.4 client metadata

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: audit current Demo V2.5 operation metadata after preserving
  V2.4 as a separate immutable snapshot.
- Observed: the active Tournament creation script still labels its reasons,
  client version and Service Worker version as V2.4.
- Impact: product state is correct, but receipts would describe the current
  V2.5 creation run as its predecessor and weaken audit clarity.
- Planned correction: update only the active SQL script's V2.4 labels to V2.5,
  leave `public/demo-world/v2-4` untouched, then rerun the deterministic
  simulator and proof verification.
- Regression evidence: every active Tournament reason, client version and
  Service Worker version now identifies V2.5, the historical V2.4 directory is
  unchanged, and the fresh `--verify` run matched the committed V2.5 snapshot.

### R6B-SIMULATION-047 - Fresh V2.5 rebuild diverges from the committed Tournament proof

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run `npm run demo-world:v2:verify` after updating only the
  active Tournament operation reasons and client metadata from V2.4 to V2.5.
- Observed: the fresh isolated database produced a different authority hash,
  draw input checksum, Group placement graph, derived scores and qualification
  checksum than the committed V2.5 proof, so verification stopped with
  `DEMO_WORLD_V2_AUTHORITY_PROOF_DRIFT`.
- Impact: Demo World cannot be certified as reproducible until a second fresh
  build selects the same canonical teams, fixtures, standings and qualification
  graph from the same public seeds and immutable operation identifiers.
- Planned correction: distinguish stale committed evidence from a genuinely
  unstable ordering, identify the first divergent authoritative row, correct
  only that source, regenerate once and require a subsequent fresh `--verify`
  run to match exactly before marking this incident fixed.
- Regression evidence: after correcting the two semantic identity defects
  recorded below, a full export followed by an independent fresh verification
  produced authority hash `3d51909498c47762ee6256f6a71e5ab642fbd2a2f2fc953178d537ca54dd06af`
  and manifest hash `675d2992138de4253a0e9e09eab77d09682cecc708fc06a4f87ed0e6d15e57f8`
  in both runs with `snapshotIdentical=true`.

### R6B-PRODUCT-048 - Group schedule seed depends on an opaque Group UUID

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compare two consecutive fresh Demo V2.5 databases after
  confirming that both published DrawRevision placement graphs are identical.
- Observed: `private.pachanga_tournament_group_schedule_generate_v1` derives
  each R4B seed from `competition_group_id`; R6A creates that internal Group ID
  independently in each database, so equivalent Group 1 inputs produce a
  different round rotation even though `group_order`, teams and rules match.
- Impact: schedule checksums and canonical home/away pairings are not
  reproducible across equivalent restores or synthetic rebuilds, and every
  result, standing and qualification proof then drifts in cascade.
- Planned correction: bind the per-Group schedule seed to the stable
  `group_order` inside the already versioned preparation instead of the opaque
  storage identifier, retain UUIDs for relational identity only, and add a
  regression that rejects reintroducing `competition_group_id` into the seed.
- Regression evidence: the generator now binds its seed to `group_order`; the
  focused source regression rejects `competition_group_id` in that expression,
  and two fresh databases produced exactly the same 24 home/away pairings.

### R6B-PRODUCT-049 - Qualification checksum hashes evidence pointers instead of sporting content

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rebuild and verify Demo V2.5 twice after the Group schedule
  seed was made semantic and every fixture, score and standing row matched.
- Observed: only `qualificationChecksum` still changed because its input embeds
  random `StandingSnapshot` and `CompetitionGroup` UUIDs.
- Impact: two equivalent qualification snapshots cannot share a stable checksum;
  replay detection is coupled to storage allocation rather than the canonical
  standings and qualification decisions it is meant to protect.
- Planned correction: retain snapshot and Group UUIDs in their relational
  lineage columns, but hash R4C content checksums, stable Group order, sporting
  positions, outcomes, comparison values and target bracket slots. Add a source
  regression proving that opaque IDs are absent from the checksum payload.
- Regression evidence: the checksum payload now contains R4C content checksums
  and semantic qualification rows while the persisted lineage still stores all
  source IDs. The source regression passes and two independent builds emitted
  the same qualification checksum and authority hash.

### R6B-SIMULATION-050 - Legacy acceptance regression selects a nullable revision

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rerun the complete transactional R6B SQL story after the
  deterministic schedule and qualification checksum corrections.
- Observed: the fixture derives an acceptance-time rule from
  `published_rule_revision.supersedes_revision_id`; in the current immutable
  R6A lineage that pointer is nullable, so the diagnostic update violates the
  existing `pachanga_competition_entries.rule_revision_id NOT NULL` contract
  before `group_stage.prepare` is called.
- Impact: the full-story regression cannot reach R6B even though no production
  command attempted an invalid write. The test is not modelling the intended
  stale-but-valid acceptance rule reliably.
- Planned correction: select the entry's actual earlier accepted RuleRevision
  from canonical revision history, assert it is non-null and distinct from the
  published sporting revision, then rerun the original complete SQL story.
- Regression evidence: the regression now creates a genuine second authoring
  revision through R6A, refreezes and regenerates the draw, proves that all
  sixteen accepted entries retain a non-null earlier RuleRevision, and the
  fresh 169-migration story reaches published qualification and bracket.

### R6B-ENV-051 - Local database retained the pre-reconciliation prepare function

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: accept sixteen teams under RuleRevision 1, publish a
  regenerated draw under RuleRevision 2, bind memberships and locked rosters to
  RuleRevision 2, then call `group_stage.prepare`.
- Observed: the first rerun raised `SCHEDULE_REQUIRES_AT_LEAST_TWO_ENTRIES`, but
  a predicate-by-predicate diagnostic passed for all four teams in every Group.
  `pg_get_functiondef` then confirmed that the long-running local database did
  not contain the entry reconciliation already present in migration
  `20260827105018`; the migration source had changed after that database was
  bootstrapped.
- Impact: the stale local function produced a false product failure and cannot
  certify the current six-migration source.
- Planned correction: reload the six unpublished R6B migrations only into the
  disposable local database, verify the function definition, rerun the exact
  sixteen-team story, and retain fresh-bootstrap validation as the release gate.
- Regression evidence: the fresh ephemeral database contains the current
  reconciliation function; `group_stage.prepare` promotes all sixteen entries,
  every R4B Group input contains four eligible teams and all 24 fixtures publish.

### R6B-TEST-052 - Ephemeral psql bootstrap omits the Supabase migration ledger

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: bootstrap a fresh isolated R6B database from the immutable
  baseline plus all incremental migration files, then assert an exact ledger of
  169 versions before running the canonical story.
- Observed: direct `psql -f` execution applies the schema but does not emulate
  the Supabase CLI bookkeeping table, so
  `supabase_migrations.schema_migrations` is absent.
- Impact: the test can validate schema behaviour but cannot prove its own exact
  migration inventory or report the same ledger contract used by release.
- Planned correction: create the standard three-column local ledger in the
  disposable database and populate it from the verified baseline manifest plus
  ordered repository migrations before any R6B scenario runs.
- Regression evidence: the runner records the manifest-backed ordered ledger,
  asserts exactly 169 rows, completes the canonical story and verifies rollback
  left zero fixture users and zero fixture competitions.

### R6B-TEST-053 - Concurrency slot fixture enumerates Groups after assuming the client role

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: build the canonical slots-created checkpoint for the ten
  R6B concurrency races on a fresh 169-migration database.
- Observed: the fixture switched to `authenticated` before enumerating internal
  Competition Groups, so PostgreSQL correctly rejected the setup query with
  `permission denied for table pachanga_competition_groups` before any race ran.
- Impact: no product authority or evidence changed, but the concurrency runner
  cannot reach the command boundary it is intended to certify.
- Planned correction: let the isolated harness enumerate opaque Group IDs as
  test infrastructure, then submit each slot mutation through the real
  authenticated R6B RPC; do not grant extra table access to the client role.
- Regression evidence: the harness enumerated four opaque Group IDs without
  changing grants, then every slot mutation crossed the authenticated R6B RPC.

### R6B-TEST-054 - Ephemeral cleanup masks the first concurrency failure

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: retain the first failing assertion from the ten-race R6B
  runner and remove all of its cloned databases in `finally`.
- Observed: one just-closed `psql` session still appeared under the privileged
  connection role for a fraction of a second. The cleanup immediately called
  `pg_terminate_backend`, received `permission denied to terminate process`,
  and replaced the original race error with the cleanup error.
- Impact: databases were almost entirely removed, but the diagnostic that must
  be recorded before a product correction was hidden.
- Planned correction: disable new connections, wait for command sessions to
  close naturally, terminate only non-superuser leftovers and fail with an
  explicit connection inventory if a privileged session remains.
- Regression evidence: cleanup disabled new connections, waited for the command
  sessions and removed every clone while preserving the subsequent product
  assertion as the process error.

### R6B-TEST-055 - Fixed concurrency dates fall outside the Tournament window

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create six valid R4B slots per Group and materialize the
  generated/validated concurrency checkpoint.
- Observed: the first runner used September 2027 as a hard-coded date. That is
  outside the active dates of the reusable R6A fixture, so the real bounded
  repair engine returned `SCHEDULE_UNSATISFIABLE` before concurrency began.
- Impact: R4B is enforcing the intended Tournament constraints; the synthetic
  checkpoint, not the scheduling product, is invalid.
- Planned correction: derive six consecutive slots from the current fixture
  window in the same way as the passing canonical SQL story.
- Regression evidence: all four schedules generated and validated from six
  in-window slots before the runner reached the participant-withdrawal race.

### R6B-PRODUCT-056 - A frozen participant can withdraw after Group generation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: start `group_schedule.generate` for the frozen sixteen-team
  stage, then submit `participant.withdraw` for one accepted Entry 200 ms later.
- Observed: both authenticated commands succeeded. R6B retained four generated
  Groups and 24 planned fixtures while R6A changed the canonical participant to
  `withdrawn`, incrementing the Tournament revision independently.
- Impact: the published Draw/ParticipantFreeze and the canonical Entry set can
  diverge after R6B preparation, violating the immutable sporting input and
  making generated fixtures refer to a participant no longer accepted.
- Planned correction: guard participant identity/status mutations after an
  active R6B state exists, acquire the same competition advisory lock used by
  the R6B command and return a stable PT409 conflict; pre-prepare withdrawals
  remain valid.
- Regression evidence: the delayed original race now gives Group generation as
  its only winner, returns `TOURNAMENT_PARTICIPANT_FREEZE_LOCKED` to withdrawal
  and retains all sixteen accepted Entries with zero duplicate memberships.

### R6B-TEST-057 - Results checkpoint inherits unrelated TeamJourney assertion

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create the all-results-official template required by the
  R4C/R6B concurrency races.
- Observed: the runner sliced the broad canonical SQL story immediately before
  qualification, which also executed a prior TeamJourney presentation
  assertion. One fresh draw produced no visible `nextMatches` for that actor at
  that exact checkpoint, so setup stopped before creating any result race.
- Impact: the dedicated concurrency suite depends on an unrelated read-model
  assertion already covered by the canonical DB runner. The exact canonical
  runner still passes 4 Groups, 24 matches, standings, qualification and bracket.
- Planned correction: derive results from the validated schedule template,
  publish and activate through R6B, then drive only the real R4C submit, accept
  and official-result paths needed for the concurrency checkpoint.
- Regression evidence: the isolated setup published and activated the validated
  schedule, drove 24 submit/accept/publish lifecycles through R4C and persisted
  exactly four current StandingSnapshots before the cross-domain races.

### R6B-PRODUCT-058 - A result can change after final qualification is completed

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute `group_stage.complete`, then submit an authenticated
  `official_result.supersede` 200 ms later for one of the 24 official matches.
- Observed: both commands succeeded. R4C created a corrected official decision
  and a new Group StandingSnapshot while the R6B state remained `complete` and
  its published QualificationSnapshot retained the superseded standings IDs.
- Impact: final qualifiers and bracket sources can disagree with the canonical
  official results after a successful Group completion.
- Planned correction: persist an explicit completion seal, coordinate official
  decisions with the R6B competition lock, invalidate non-published qualification
  evidence when a result changes, and reject result changes after qualification
  publication with a stable PT409 until a future audited reopen operation exists.
- Regression evidence: the complete ten-race suite now gives exactly one winner
  for delayed completion/correction and qualification-publication/correction;
  the losing command returns the canonical stale/domain conflict and all 24
  match contexts retain one unambiguous official lineage.

### R6B-TEST-059 - Schedule-edit winner is asserted as if publish had won

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: race a valid schedule edit against atomic schedule
  publication from the same validated revision.
- Observed: the edit correctly won, publication returned stale and no canonical
  matches were created, but the runner unconditionally expected 24 matches as
  though publication had won.
- Impact: the required one-winner/one-conflict behavior passed while its valid
  losing-publication outcome was misclassified as a match-generation failure.
- Planned correction: bind the invariant to the actual winner: 24 canonical
  matches for publish, zero for edit, with no partial count in either branch.
- Regression evidence: the next run accepted the actual race winner and proved
  the corresponding all-or-nothing count, then continued into the R4C races.

### R6B-TEST-060 - Concurrency correction creates an unrelated unresolved tie

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: supersede one official result immediately before a delayed
  manual standings rebuild, expecting the latter to observe a stale revision.
- Observed: the synthetic `1-1` correction created an exact Group tie, so the
  canonical standings engine correctly raised `TIE_REQUIRES_DECISION` before
  the version race could be measured.
- Impact: one winner and one domain conflict existed, but the runner was testing
  tie policy rather than the required official-result/standings coordination.
- Planned correction: read the current official score and increase only the
  winning side's margin, preserving the sporting order while changing the
  StandingSnapshot revision.
- Regression evidence: the correction now extends the current winner's margin,
  the original delayed official-result/standings race reaches its intended
  authority boundary and finishes with one winner and one stale conflict.

### R6B-PRODUCT-061 - Qualification rebuild reuses non-canonical READY evidence

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish a QualificationSnapshot, create the corresponding
  draft BracketTemplate, then race `qualification.rebuild` against delayed
  `bracket_template.publish` from the same GroupStage revision.
- Observed: both authenticated commands succeeded. The rebuild found an older
  READY QualificationSnapshot with the same semantic checksum and returned it
  as a replay even though the canonical qualification pointer referenced the
  later PUBLISHED snapshot. Because that path did not advance the GroupStage
  revision, the delayed Bracket publication also passed its expected revision.
- Impact: a caller can request qualification supersession without producing a
  canonical revision, while a bracket based on the prior published evidence is
  simultaneously accepted. The receipt says both intents won although only one
  authoritative lineage can remain current.
- Planned correction: treat a same-checksum snapshot as a semantic replay only
  when it is also the current canonical qualification pointer. A rebuild after
  publication must create a new READY snapshot, supersede the published one and
  advance the GroupStage revision so the competing bracket publication is stale.
- Regression evidence: the original delayed qualification/bracket race now has
  exactly one successful command. A non-canonical READY snapshot is not reused,
  the competing operation conflicts, and zero knockout matches are generated.

### R6B-TEST-062 - Qualification/bracket race assumes a deterministic winner

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rerun the delayed qualification rebuild versus bracket
  publication race after preventing reuse of non-canonical READY evidence.
- Observed: exactly one operation succeeded and the other returned a conflict,
  but process scheduling let the nominally delayed bracket publication acquire
  the database lock first. The assertion required the rebuild to win by label.
- Impact: the authority now satisfies the one-winner contract, while the test
  rejects one of the two valid serial orders for concurrent clients.
- Planned correction: assert one success and one stale/domain conflict without
  prescribing which independently scheduled PostgreSQL client wins.
- Regression evidence: the complete ten-race run accepts either serial winner,
  requires exactly one loser and reports `10/10 one winner and one
  stale/conflict` with 24 CanonicalMatches and zero knockout matches.

### R6B-TEST-063 - Unpublished DrawPlan fixture violates its own status invariant

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: make the canonical published DrawPlan unavailable, then
  prove `group_stage.prepare` refuses to consume it.
- Observed: the adversarial setup changed only `status` to `draft` while leaving
  `published_at` populated. PostgreSQL rejected the fixture itself through the
  DrawPlan status/timestamp check before the R6B command was invoked.
- Impact: the product invariant is healthy, but the negative runner cannot yet
  distinguish an invalid test row from a valid non-published DrawPlan.
- Planned correction: set the plan to the valid `validated` state and clear
  `published_at`, then run the authenticated preparation command.
- Regression evidence: the valid non-published DrawPlan reached the RPC and was
  rejected with `TOURNAMENT_PUBLISHED_GROUP_DRAW_REQUIRED` in the complete
  18/18 negative suite.

### R6B-TEST-064 - Unofficial-result fixture changes identity after sequence update

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: move one canonical Group match to `played`, submit a real
  but still unofficial R4C SportingResult and prove standings remain unchanged.
- Observed: the fixture reread “the first match” after advancing that match's
  server sequence. The ordering then selected a different scheduled match, so
  R4C correctly returned `R4C_RESULT_REQUIRES_PLAYED_MATCH`.
- Impact: the product rejects a result for a scheduled match as intended, but
  the test lost the stable CanonicalMatch identity it was meant to exercise.
- Planned correction: retain the selected MatchContext ID and refresh only its
  revision after the transition to `played`.
- Regression evidence: the runner retained the exact MatchContext, submitted a
  real unofficial R4C result and confirmed zero StandingStates were created.

### R6B-TEST-065 - Anonymous discovery expects an error behind a revoked grant

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: call the private-beta Tournament Hub as `anon` and prove
  public discovery remains unavailable.
- Observed: PostgreSQL denied EXECUTE on the RPC before entering its explicit
  `AUTHENTICATION_REQUIRED` branch. The runner accepted only the inner error.
- Impact: anonymous access is correctly closed at a stronger boundary, while
  the test misclassifies the grant-level denial as a failure.
- Planned correction: accept either revoked EXECUTE or the explicit unauthenticated
  domain error, and continue to require `TOURNAMENT_READ_FORBIDDEN` for an
  unrelated authenticated actor.
- Regression evidence: anonymous access was denied at EXECUTE and an unrelated
  authenticated actor was independently rejected with
  `TOURNAMENT_READ_FORBIDDEN` in the passing negative suite.

### R6B-TEST-066 - Negative report declares one case more than it executes

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: reconcile the final adversarial report after reaching the
  anonymous and unrelated-authenticated discovery checks.
- Observed: the runner emits eighteen durable case records but asserted and
  labelled the summary as nineteen.
- Impact: all required scenarios are present, but the documentary total cannot
  be trusted until it is derived from the actual inventory.
- Planned correction: bind the expected total and summary to the eighteen
  concrete cases currently executed.
- Regression evidence: `R6B_NEGATIVE_REPORT` now reports the exact eighteen
  emitted cases and closes with `18/18`, direct writes zero and knockout matches
  zero.

### R6B-TEST-067 - Migration default assertion omits Qualification flag

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compare a fresh 169-migration bootstrap with an exact
  163-to-169 upgrade, then assert every R6B/R6C flag is born disabled and all
  product tables are empty.
- Observed: schema equivalence completed, PostgreSQL returned
  `qualificationOff=true`, but the JavaScript expected object omitted that
  queried key and rejected the otherwise correct default-state evidence.
- Impact: the database contract is safe, while the migration runner cannot
  close because its expected inventory is one field shorter than its query.
- Planned correction: include `qualificationOff: true` in the explicit expected
  object and rerun the complete fresh/upgrade/schema-equivalence scenario.
- Regression evidence: the complete isolated run now bootstraps fresh ledger
  169, upgrades exact ledger 163 through the six ordered R6B migrations,
  produces the same normalized schema hash
  `d26a99f64e7ee56103254ecc7f2d9a5bd06ffdb183b0a417819a8e4a54304063`,
  confirms every R6B/R6C flag OFF and finds zero product rows.

### R6B-TEST-068 - Rebuilt negative checkpoint intermittently loses TeamJourney evidence

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rebuild the canonical activated Group Stage checkpoint as
  the shared base for the eighteen adversarial cases after the DB full story
  had passed independently.
- Observed: the checkpoint stopped at the existing assertion that TeamJourney
  must expose at least one next match with attendance, squad, sanctions,
  referee and incident projections. The same assertion passed in the immediately
  preceding isolated DB runner.
- Impact: the negative suite cannot start, and the difference may indicate
  either a time/order-sensitive fixture or a non-deterministic Hub projection.
- Root cause: the presentation assertion inherited the ambient JWT claims left
  by earlier platform and organizer operations in one long SQL transaction.
  The isolated snapshot proved that the canonical read model contained one
  TeamJourney, three scheduled matches, every stable operations key and no
  private-data match; the product projection itself had not lost data.
- Correction: set the participant JWT claims explicitly immediately before the
  TeamJourney read, so every checkpoint exercises the same authorized actor
  instead of depending on session history.
- Regression evidence: two consecutive executions of the original adversarial
  runner complete all eighteen cases after the deterministic actor setup,
  including TeamJourney shape and privacy checks, with zero direct writes and
  zero knockout matches.

### R6B-TEST-069 - Demo World V2 hash expectations still identify V2.4

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the complete `npm test` battery after generating
  and verifying the committed Demo World V2.5 snapshot and authority proof.
- Observed: the deterministic generator returns manifest hash
  `675d2992138de4253a0e9e09eab77d09682cecc708fc06a4f87ed0e6d15e57f8`
  and authority hash
  `3d51909498c47762ee6256f6a71e5ab642fbd2a2f2fc953178d537ca54dd06af`,
  while two integration assertions still expect the former V2.4 values.
- Impact: the full battery rejects the intended immutable V2.5 fixture even
  though `demo-world:v2:verify` proves the committed snapshot is deterministic.
- Correction: bind the integration assertions to the committed V2.5 manifest
  and authority hashes without altering the generated snapshot.
- Regression evidence: the focused Demo World/R6A/R6B run passes `44/44`; the
  PostgreSQL verifier reports `snapshotIdentical=true`, 169 migrations, zero
  remote writes and the exact two V2.5 hashes recorded above.

### R6B-TEST-070 - R6A action assertion treats the platform command list as closed

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the unchanged R6A contract suite after R6B adds
  the audited `tournament.group_stage.flags.set` action to the shared platform
  command endpoint.
- Observed: R6A expects the complete platform action list to contain exactly
  its four historical actions, so it rejects the additive R6B action although
  all four R6A actions remain byte-identical and reachable.
- Impact: the full battery cannot distinguish an R6A regression from a valid
  later-phase extension of the shared platform command surface.
- Correction: make the R6A assertion verify its owned ordered action prefix and
  add an exact five-action allowlist assertion to the R6B contract suite.
- Regression evidence: the focused R6A and R6B suites pass together inside the
  `44/44` run, proving all four historical actions remain ordered and the only
  permitted additive action is `tournament.group_stage.flags.set`.

### R6B-ENVIRONMENT-071 - Full-suite summary wrapper uses a reserved zsh variable

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run `npm test` while capturing its verbose output and
  preserving the child exit code for a compact final summary.
- Observed: the wrapper assigns the child code to `status`, a read-only special
  parameter in zsh, and exits with `read-only variable: status` after the test
  process finishes.
- Impact: the wrapper result cannot be used as evidence even if the underlying
  suite completed; product code and tests are unaffected.
- Correction: repeat the identical command with a non-reserved
  `test_exit_code` variable and keep the child exit code authoritative.
- Regression evidence: the corrected wrapper exits zero and records `20/20`
  Node tests plus `536/536` TS/TSX tests, with zero failed, skipped, todo or
  cancelled tests in either runner.

### R6B-PRODUCT-072 - Journey selection performs synchronous state repair in an effect

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run focused ESLint across every changed R6B TypeScript,
  TSX and MJS file.
- Observed: `TournamentGroupStageClient` calls `setRound` synchronously from a
  React effect whenever the selected round no longer exists in a refreshed
  canonical snapshot.
- Impact: snapshot refresh can trigger a cascading render and couples canonical
  read invalidation to imperative local-state repair.
- Correction: derive the effective valid round from the canonical rounds plus
  the user's requested round, retaining state changes only for direct user
  selection.
- Regression evidence: the R6B contract suite passes `13/13`, including a new
  source regression that forbids `setRound` inside the effect, and focused
  ESLint passes for both the component and its regression test.

### R6B-TEST-073 - Repository-wide lint remains blocked by pre-existing UI debt

- Classification: `TESTABILITY_GAP`
- Status: `OPEN / PREEXISTING_OUT_OF_SCOPE`
- Original scenario: run the repository-wide `npm run lint` after the complete
  R6B focused lint succeeds.
- Observed: global ESLint reports 40 existing findings (22 errors and 18
  warnings) in `app/legal-data.tsx`, `app/mercado/page.tsx` and `app/page.tsx`.
- Impact: global lint cannot be a green R6B release signal without expanding
  this phase into unrelated legacy UI refactors.
- Scope evidence: all three reported files are byte-unchanged from
  `origin/main`; `git diff --quiet origin/main --` returns zero for them.
- R6B evidence: focused ESLint passes across all 26 changed TS/TSX/MJS files.
- Decision: preserve the existing debt as an explicit separate gate. Do not
  alter unrelated application behavior inside Tournament Group Stage V1.

### R6B-ENVIRONMENT-074 - Staging inventory uses an unmatched shell glob

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: inventory historical staging and release harnesses before
  creating the isolated R6B hosted environment.
- Observed: zsh rejects the empty `scripts/*staging*` pattern before `rg` can
  inspect it.
- Impact: the first inventory command is incomplete; repository contents and
  hosted services are unchanged.
- Correction: use `rg --files` with regex filtering and explicit directories,
  without shell wildcard expansion.
- Regression evidence: the corrected inventory lists the existing staging E2E
  harnesses and confirms no R6B staging script exists yet.

### R6B-TEST-075 - New release reports contain an extra blank line at EOF

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: stage the exact R6B candidate and run
  `git diff --cached --check` before its implementation commit.
- Observed: five newly created Markdown reports end with an additional blank
  line and fail the repository whitespace gate.
- Impact: documentation-only formatting blocks the clean-diff release gate;
  code, migrations and generated Demo data are unaffected.
- Correction: remove only the redundant EOF lines and restage the reports.
- Regression evidence: both `git diff --cached --check` and the unstaged
  `git diff --check` complete with no output.

### R6B-ENVIRONMENT-076 - Supabase preview branch automatic migration reports failure

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create the isolated non-production Supabase branch
  `r6b-group-stage-staging` from the R6B Git branch.
- Observed: the branch reaches `ACTIVE_HEALTHY` but its deployment status is
  `MIGRATIONS_FAILED`.
- Impact: hosted staging cannot be accepted and production migration is
  blocked until the exact ledger/statement mismatch is understood.
- Root cause: the Git-associated Preview bootstrap starts from the historical
  migration chain even though this repository intentionally disables ordinary
  migration replay and uses the immutable product baseline for fresh
  databases. The historical replay stops after ten pre-baseline migrations;
  the R6B files themselves are not the failing frontier.
- Correction: on the empty isolated branch, verify the baseline SHA-256, apply
  it transactionally, apply every post-baseline migration in one transaction,
  and synchronize the exact version/name ledger without touching production.
- Regression evidence: the branch now exposes exactly 169 ordered migration
  version/name pairs through `20260827105036`; all R6B flags are OFF, all R6C
  and public gates are OFF, product-row counts are zero, and the repository and
  hosted ledger streams compare with no diff.

### R6B-ENVIRONMENT-077 - Preview direct database hostname is IPv6-only from this host

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: inspect the ephemeral branch migration ledger and dry-run
  using its generated `POSTGRES_URL_NON_POOLING` connection string.
- Observed: the direct hostname resolves to IPv6 and both read-only connection
  attempts time out before PostgreSQL authentication.
- Impact: no SQL reaches the staging branch, so the attempt neither diagnoses
  nor changes its schema.
- Correction: use the branch-generated Supavisor URL in session mode while
  keeping the credential in a shell variable and out of logs, files and Git.
- Regression evidence: the session-pooler connection read the original ten-row
  ledger, applied and verified the isolated baseline/upgrade, and returned the
  final 169-row readback without exposing a credential.

### R6B-ENVIRONMENT-078 - Staging readback references a non-canonical bracket table name

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the first consolidated hosted-staging readback
  after applying the immutable baseline plus all incremental migrations.
- Observed: the diagnostic query references
  `public.pachanga_competition_bracket_templates`, which is not the canonical
  relation name, and PostgreSQL stops the read-only statement with
  `relation does not exist`.
- Impact: the first consolidated readback produces no evidence; no product row,
  schema object, ledger entry or flag is changed because the failing statement
  is read-only.
- Correction: bind the readback to the committed canonical relation
  `public.pachanga_tournament_bracket_templates`.
- Regression evidence: the corrected consolidated readback resolves the table
  and reports zero bracket-template rows before hosted QA.

### R6B-ENVIRONMENT-079 - Ledger comparison wrapper is rejected before execution

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compare the 169 hosted-staging ledger names with the
  repository migration filenames and remove two temporary comparison files on
  shell exit.
- Observed: the execution guard rejects the wrapper because it contains an
  `rm -f` cleanup command. No shell command or database query starts.
- Impact: no local file, hosted schema, ledger row or product state changes,
  but the intended exact-name comparison has no evidence.
- Correction: compare process-substitution streams directly, creating no
  temporary file and requiring no removal command.
- Regression evidence: the guarded command runs successfully and the final
  strict 169-line comparison emits no diff.

### R6B-ENVIRONMENT-080 - Manual incremental application does not populate the migration ledger

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: apply every post-baseline migration transactionally to
  the empty hosted-staging branch, then compare its migration ledger with the
  repository.
- Observed: all 133 incremental SQL files commit successfully, but direct
  `psql -f` execution does not insert their versions into
  `supabase_migrations.schema_migrations`; the hosted schema is current while
  the ledger remains at the 36 baseline-absorbed versions.
- Impact: staging cannot be certified or used as production-migration evidence
  until its ledger reflects the exact SQL already applied.
- Correction: insert the exact 133 repository version/name pairs into the
  staging ledger, with no SQL migration replay and no production access.
- Regression evidence: hosted staging and the repository expose the same 169
  ordered pairs, ending at `20260827105036`; the schema remains on the already
  committed SQL and every product table is still empty.

### R6B-ENVIRONMENT-081 - Ledger comparison wrapper reports success after a failed diff

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: fail the hosted-staging ledger comparison if any local
  migration version/name pair is absent or different.
- Observed: `diff` correctly emits the 133 missing incremental ledger rows, but
  the shell wrapper continues to a final success marker because strict exit
  handling was not enabled.
- Impact: the marker is invalid evidence; the full diff itself exposes the
  mismatch and no database state is changed by this read-only comparison.
- Correction: enable strict shell exit handling and make the success marker
  reachable only after `diff` returns zero.
- Regression evidence: the strict wrapper reaches
  `R6B_STAGING_LEDGER_169_EXACT` only after an empty 169-line diff.

### R6B-ENVIRONMENT-082 - Staging readback assumes the wrong invalidation relation name

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: complete the consolidated ledger, flags, RLS, direct
  privilege and Realtime readback after repairing the hosted-staging ledger.
- Observed: the diagnostic query references
  `public.pachanga_tournament_group_invalidations`, while the committed access
  migration publishes a differently named canonical relation. PostgreSQL
  aborts the read-only statement before returning the aggregate.
- Impact: no state is changed, but the consolidated RLS/Realtime evidence is
  still pending.
- Correction: use the existing shared Tournament authority relation
  `public.pachanga_tournament_invalidations`, populated by the canonical store
  command and published by R6A.
- Regression evidence: the corrected readback reports RLS enabled, exactly one
  `supabase_realtime` publication entry and no authenticated direct writes on
  any R6B authority table.

### R6B-TEST-083 - Hosted proof joins Groups through a non-existent direct competition column

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after completing the hosted R6A/R6B/R4B-R5/Referee story,
  collect one canonical aggregate with groups, rounds, matches, results,
  incidents, discipline, assignments, standings, qualification and bracket.
- Observed: the staging runner joins `pachanga_competition_groups` through a
  presumed `competition_id`; the canonical model links Group to Stage and
  Edition instead, so the read-only proof query fails after all product
  operations have committed.
- Impact: the hosted product story is preserved, but proof assertions,
  authenticated concurrency and Realtime have not yet run. No product command
  is replayed after this failure.
- Correction: count Groups through
  `Group.stage_id -> Stage.edition_id -> Edition.competition_id`, add a guarded
  resume path for this already-created isolated dataset and execute the
  remaining proof plus two-device checks exactly once.
- Regression evidence: the guarded hosted readback resolves exactly 4 Groups,
  12 rounds and 24 CanonicalMatches without replaying any product command.

### R6B-TEST-084 - Hosted proof assumes the wrong squad context foreign-key name

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: resume the preserved hosted dataset after correcting the
  Group lineage and count locked R4C squads belonging to the 24 Tournament
  MatchContexts.
- Observed: the readback joins squads through `match_context_id`, but the R4C
  schema uses its canonical context foreign-key name. The read-only aggregate
  stops before assertions or Realtime.
- Impact: no command or row is replayed; proof and two-device checks remain
  pending on the preserved isolated dataset.
- Correction: bind the join to the exact R4C schema column and rerun
  only the guarded resume path.
- Regression evidence: the corrected hosted proof resolves exactly 30 locked
  squads through `competition_match_context_id`.

### R6B-TEST-085 - Hosted proof reads attendance closure from MatchContext

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: count both closed attendance sides for every Tournament
  group match after the locked-squad proof has been repaired.
- Observed: the readback expects `home_attendance_closed_at` and
  `away_attendance_closed_at` on `CompetitionMatchContext`; R4C deliberately
  keeps Attendance V1 as its existing authority instead of copying those
  fields into the context.
- Impact: the read-only aggregate fails; the hosted story remains unchanged
  and no operation is replayed.
- Correction: resolve closure evidence through the canonical R4C
  attendance/result authority linked by CanonicalMatch and rerun only the
  resume path.
- Regression evidence: the corrected hosted proof resolves exactly 30 closed
  Attendance sides through the canonical CompetitionMatchSheet relation.

### R6B-TEST-086 - Hosted proof assumes an abbreviated R4D postponement foreign key

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: after resolving Attendance through MatchSheet, count the
  persisted postponement request tied to Tournament MatchContexts.
- Observed: the diagnostic join uses `requests.match_context_id`; R4D keeps the
  full canonical context identifier instead. The read-only query stops before
  the no-show, suspension, discipline and referee assertions.
- Impact: no hosted command or state changes; the preserved dataset remains the
  only source for the guarded resume.
- Correction: audit every remaining readback foreign key directly from
  R4D, R5 and Referee schema definitions, correct them as one focused change,
  then rerun the proof without replaying product operations.
- Regression evidence: the resumed hosted proof reads one postponement, one
  no-show, one suspension/resumption, four disciplinary events and twelve
  confirmed referee assignments from their canonical context relationships.

### R6B-TEST-087 - Hosted proof expects every match side to retain a locked squad

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: assert 48 locked squads for 24 completed Tournament group
  matches after every readback relation resolves successfully.
- Observed: the canonical hosted graph contains 30 squads in `locked` state,
  not 48. The assertion stops before Realtime and concurrency.
- Impact: the runner's cardinality assumption is unproven; product data and
  operations remain unchanged.
- Correction: inspect the exact squad-state distribution together with
  no-show, suspension and result paths, then assert the canonical invariant the
  product actually guarantees rather than forcing two locked squads onto every
  exceptional fixture.
- Regression evidence: the hosted graph proves 30 locked squads and 30 closed
  Attendance sides for the fixtures that pass through MatchSheet operations;
  all 24 matches still own one canonical official result and the J3 proof does
  not fabricate absent MatchSheets.

### R6B-TEST-088 - Both hosted completion intentions are rejected

- Classification: `TESTABILITY_GAP` (provisional until RPC diagnostics are
  captured)
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: submit `group_stage.complete` concurrently from two
  authenticated sessions at the same canonical revision and require one
  winner plus one stale conflict.
- Observed: both RPC calls return errors, so the runner observes zero winners
  and stops before waiting for Realtime. The current assertion does not expose
  the two server diagnostics.
- Impact: sporting proof passes, but hosted concurrency and Realtime remain
  unverified. No successful completion mutation is assumed.
- Correction: capture only code/message diagnostics from both rejected
  calls, determine whether the action state or client payload is invalid, then
  apply the smallest runner or product correction with a regression.
- Regression evidence: after exposing the PostgREST diagnostics and fixing the
  omitted revision, two authenticated sessions now produce exactly one success
  and one `PT409` stale-revision conflict.

### R6B-TEST-089 - Hosted concurrency omits expectedRevision from the RPC call

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: expose the exact diagnostics for both rejected
  `group_stage.complete` calls.
- Observed: PostgREST reports a five-argument signature lookup that omits
  `expected_revision`. The runner reads `beforeA.revision`, but the canonical
  Hub nests the aggregate revision under its Group Stage projection; the
  resulting `undefined` property is omitted by `supabase-js`.
- Impact: both requests fail at schema-cache overload resolution before any
  server command, receipt, event or invalidation is created.
- Correction: resolve the revision from the typed canonical Hub path,
  assert it is an integer before issuing either RPC and retain the diagnostic
  assertion for future drift.
- Regression evidence: the runner resolves `groupStage.revision`, increments it
  exactly once, receives one invalidation on each authenticated device,
  refetches the same completed snapshot and replays the winning operation with
  the byte-equivalent canonical receipt. The hosted runner exits zero.

### R6B-ENVIRONMENT-090 - Branch creation output is not parseable as requested JSON

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create a second, non-Git-associated Supabase branch for a
  one-shot clean hosted regression and parse the CLI response requested with
  `--output json`.
- Observed: Supabase creates the branch successfully, but the returned stream
  contains a non-JSON prefix and `jq` exits before exposing the sanitized branch
  identity.
- Impact: no duplicate branch is created and no product or production data is
  touched; the test cannot use the creation response as machine evidence.
- Correction: reconcile creation through `supabase branches list`,
  retrieve the unique branch by ID with `supabase branches get` and never retry
  creation when the branch already exists.
- Regression evidence: the inventory contains exactly one branch named
  `r6b-group-stage-staging-clean`; `branches get` resolves its isolated ref
  `ukpxcbgnpjlqbttrftpd` and confirms both database and API credentials are
  available without printing either credential.

### R6B-TEST-091 - Clean hosted bootstrap emits an empty migration ledger value list

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: install the immutable baseline, all 133 incrementals and
  the exact 169-row migration ledger in one transaction on a fresh hosted
  branch.
- Observed: the inline Node ledger generator overescapes its migration filename
  regular expression, selects zero files and emits `VALUES ON CONFLICT`, so
  PostgreSQL rejects the final statement.
- Impact: `ON_ERROR_STOP` and `--single-transaction` roll back the baseline and
  every migration; no partial schema or ledger can survive. Production is not
  targeted or modified.
- Correction: use the exact filename pattern, assert 169 selected files
  inside the generator and verify the branch remains at its original 10-row
  ledger before retrying the entire atomic bootstrap.
- Regression evidence: the failed transaction left the branch at exactly 10
  ledger rows with the R6B state table absent; the corrected atomic retry
  installed the immutable baseline plus 133 incrementals and produced an exact
  169/169 version-and-name diff ending at `20260827105036`, with all R6B flags
  OFF and zero product rows.

### R6B-ENVIRONMENT-092 - Fresh hosted branch misses one Realtime invalidation delivery

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the complete R6B hosted story in one shot on a newly
  bootstrapped non-Git branch, subscribe two authenticated devices and complete
  Group Stage concurrently.
- Observed: the sporting story and concurrent writes reach the event wait, but
  device A receives no `postgres_changes` invalidation within 20 seconds and
  the runner exits on `R6B_STAGING_REALTIME_TIMEOUT:device-a`.
- Impact: the clean one-shot run cannot yet certify two-device Realtime
  convergence. No success is inferred from the missing client event and no
  production system is involved.
- Correction: confirm the single persisted receipt and invalidation first, then
  require a two-device Realtime readiness probe with its own server sequence
  before issuing the one-shot sporting completion command. The sporting event
  remains a separate required delivery and is never substituted by the probe.
- Regression evidence: the isolated probe reaches both authenticated devices;
  a subsequent completely fresh branch then runs the 17-story hosted scenario
  in one pass, delivers the real Tournament invalidation to both devices,
  refetches the same revision and exits zero.

### R6B-TEST-093 - Realtime diagnostic assumes a generic invalidation ID column

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: reconcile the latest persisted invalidation after the
  fresh-branch Realtime timeout using an authoritative sequence plus a stable
  tie-breaker.
- Observed: the read-only diagnostic orders by a presumed `id` column that the
  canonical invalidation relation does not expose, so PostgreSQL rejects the
  statement before returning evidence.
- Impact: no data changes; server persistence evidence remains pending until
  the diagnostic binds to the exact schema.
- Correction: inspect the relation columns first, use
  `server_sequence` plus the actual stable key and retain the exact-order check
  as a regression against timestamp-only reads.
- Regression evidence: schema inspection proves `server_sequence` is the
  relation primary key; the corrected readback orders by it and confirms one
  `group_stage.complete` receipt, one latest revision-14 Tournament
  invalidation and no timestamp-only selection.

### R6B-ENVIRONMENT-094 - zsh reserves the branch polling variable name

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: poll the final ephemeral Supabase branch until its API and
  Functions are ready, without printing credentials.
- Observed: the shell wrapper assigns to `status`, a read-only special variable
  in zsh, and exits before its first poll decision.
- Impact: branch creation continues independently; no duplicate branch, schema
  or product operation is issued.
- Correction: rename the local value to `branch_status`, keep the same
  bounded polling contract and stop on any explicit failed state.
- Regression evidence: the corrected wrapper performs its first poll and stops
  on the explicit `MIGRATIONS_FAILED` state caused by the already documented
  pre-baseline replay frontier; direct readback confirms the isolated database
  remains clean at 10 ledger rows, zero users and no R6B state relation.

### R6B-ENVIRONMENT-095 - Markdown backtick breaks the open-incident shell search

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: confirm that the incident ledger contains no unresolved
  R6B finding other than explicitly accepted pre-existing debt.
- Observed: a double-quoted zsh pattern contains the Markdown backtick from
  ``Status: `OPEN`` and terminates with `unmatched "` before `rg` runs.
- Impact: no file, database or remote state changes; only the auxiliary ledger
  search lacks evidence.
- Correction: use a single-quoted fixed-string pattern and repeat the
  inventory before commit.
- Regression evidence: the corrected search executes successfully and reports
  only `R6B-TEST-073`, explicitly classified as pre-existing global lint debt
  outside the R6B change surface.

### R6B-ENVIRONMENT-096 - Vercel agent-browser CLI is unavailable

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the required responsive Preview matrix with the
  Vercel `agent-browser` CLI after deployment `9a472e1` reaches READY.
- Observed: zsh returns `command not found: agent-browser` before launching a
  browser.
- Impact: no Preview or product state changes; visual QA still requires an
  available browser-control surface.
- Planned correction: use Codex's bundled in-app browser runtime and its
  Playwright viewport/console APIs against the same immutable deployment,
  without installing an unpinned package.
- Regression evidence: Codex's in-app browser completed the immutable Preview
  matrix at all eight required viewport sizes with zero root overflow, broken
  images, overlays, console errors or hydration warnings.

### R6B-ENVIRONMENT-097 - In-app Playwright rejects documented networkidle wait

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: open the immutable Vercel Preview at 1440x900 and wait for
  `networkidle` before the first visual assertion.
- Observed: the bundled browser runtime reports that
  `playwright_wait_for_load_state` does not support `networkidle`, despite that
  value appearing in its local API documentation.
- Impact: the tab is created, but readiness and visual assertions have not yet
  been inferred; no page or remote state is mutated.
- Planned correction: wait for `domcontentloaded`, then verify meaningful DOM,
  pending resources, framework overlays and console errors explicitly before
  accepting each viewport.
- Regression evidence: `domcontentloaded` plus meaningful body text, framework
  overlay, broken-image, root-overflow and browser log checks passed on every
  Tournament tab and viewport.

### R6B-ENVIRONMENT-098 - Browser evaluation scope omits navigator

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: collect desktop DOM, overflow, images, manifest,
  Service Worker control, resources and framework-overlay evidence in one
  read-only evaluation.
- Observed: the browser evaluation sandbox throws while resolving
  `navigator.serviceWorker`; no combined metrics object is returned.
- Impact: no state changes and no partial visual result is accepted.
- Planned correction: keep DOM/resource assertions in the supported evaluation
  scope and inspect the Service Worker independently through the rendered
  endpoint/manifest plus a dedicated capability-safe expression.
- Regression evidence: DOM assertions completed in the supported scope;
  manifest and Service Worker endpoints were inspected separately without
  treating `SUBSCRIBED`, WAL payloads or unsupported globals as authority.

### R6B-ENVIRONMENT-099 - Browser evaluation scope also omits performance

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: repeat the desktop audit without `navigator` while
  retaining a pending-resource inventory through `performance`.
- Observed: the evaluation sandbox also omits `performance` and throws before
  returning the DOM metrics object.
- Impact: no state changes; the attempted metrics are discarded.
- Planned correction: limit page evaluation to supported DOM invariants and
  verify HTTP resources, logs and Service Worker endpoints separately.
- Regression evidence: the reduced DOM audit plus HTTP resource checks and
  console collection completed across the exact Preview without a resource
  timing dependency.

### R6B-ENVIRONMENT-100 - Protected Preview redirects the Service Worker

- Classification: `ENVIRONMENT_ISSUE`
- Status: `OPEN`
- Original scenario: verify the installed/PWA update path on the immutable
  Vercel Preview while traversing the responsive Tournament Hub.
- Observed: the page renders normally through the authenticated Preview
  session, but a direct read of `/sw.js` returns HTTP 302 to Vercel SSO with
  `cache-control: no-store`; the runtime therefore shows
  `No se pudo comprobar la actualización automática.`
- Impact: the protected Preview cannot certify Service Worker installation or
  update. Tournament UI, navigation and canonical reads remain available, and
  no success is inferred for PWA until the public production origin is tested.
- Planned correction: complete visual assertions in Preview, then verify
  manifest, Service Worker response, controlled update and offline shell on
  `pachangasiq.com`, where the SSO barrier does not apply.
- Regression evidence: pending.

### R6B-PRODUCT-101 - Landscape Tournament subnav collapses to one pixel

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: open Demo World V2.5 Tournament Hub at `844x390` and
  select `Clasificación` from the Tournament subnavigation.
- Observed: the sticky `tournamentSubnav` has a computed height of `1px` while
  its buttons remain `36px` high and begin above the rail. They are visually
  clipped, `elementFromPoint` resolves to the parent rail instead of the
  button, and the active Tournament view remains `Resumen`.
- Impact: Mobile Game Landscape cannot navigate reliably between jornadas,
  partidos, standings, Team Journey, discipline, referees, incidents, rules
  and bracket even though the underlying content exists.
- Planned correction: give the Tournament subnavigation an explicit stable
  track in the landscape grid and preserve its horizontal overflow without
  collapsing the row.
- Regression evidence: the corrected Preview computes a `36px` rail, its
  button is the `elementFromPoint` hit target, all ten tabs become current in
  turn, and `667x375`, `740x360`, `844x390` and `932x430` remain free of root
  overflow, broken images, overlays and console warnings/errors.

### R6B-TEST-103 - Hosted QA account readback aggregates UUID directly

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: assign a temporary password to the already disposable
  staging owner and read back a redacted account proof before browser QA of
  Team Journey and Organizer Desk.
- Observed: the diagnostic uses `min(id)` on a UUID column; PostgreSQL rejects
  the statement with `42883 function min(uuid) does not exist`.
- Impact: the staging request is rejected and no account change is accepted as
  applied. Production is not targeted.
- Planned correction: aggregate `id::text`, repeat the guarded staging-only
  request and require one confirmed disposable account before sign-in.
- Regression evidence: the corrected staging-only statement updates exactly
  one disposable account and reads back the expected user ID with confirmed
  email, without targeting production.

### R6B-ENVIRONMENT-104 - Browser evaluation scope omits localStorage

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: apply a successful staging-only Supabase password session
  to the local Tournament Hub before authenticated visual QA.
- Observed: the in-app browser evaluation sandbox reports
  `Cannot read properties of undefined (reading 'setItem')` because
  `localStorage` is omitted from that restricted scope.
- Impact: the authenticated response exists only in the ephemeral Node browser
  controller; no session is accepted as installed and no product assertion is
  made from it.
- Planned correction: use the documented origin-scoped CDP capability to set
  the single ephemeral Supabase session without printing tokens, reload, and
  require the canonical Tournament Hub before visual assertions.
- Regression evidence: origin-scoped CDP installs the ephemeral session without
  emitting its tokens; the browser subsequently loads the authenticated
  canonical Hub and all read models.

### R6B-PRODUCT-105 - API rejects canonical PostgreSQL UUID fixture IDs

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: load the authenticated Tournament Hub through the real
  Next.js API for the canonical hosted staging competition after direct RPC
  access has succeeded for the same actor and aggregate.
- Observed: the route returns `404 TOURNAMENT_NOT_FOUND` before PostgreSQL is
  called because `tournamentUuidPattern` accepts only UUID version nibbles
  `1-8`; the deterministic canonical fixture ID is a valid PostgreSQL UUID
  whose third segment begins with `e`.
- Impact: valid UUID aggregates accepted and stored by PostgreSQL can be
  unreachable through Tournament APIs, and the staging browser path cannot
  exercise Team Journey or Organizer Desk despite correct RLS.
- Planned correction: validate the exact PostgreSQL textual UUID shape
  (`8-4-4-4-12` hexadecimal) without imposing an unrelated version/variant
  restriction, and add a regression for the previously rejected ID.
- Regression evidence: focused tests accept the previously rejected exact
  PostgreSQL UUID, the local API returns HTTP 200 `TournamentGroupStageHub`,
  and the authenticated browser renders its four groups, Team Journey and
  Organizer Desk.

### R6B-PRODUCT-106 - Canonical Hub tabs ignore landscape interaction

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: traverse all ten tabs of the authenticated production
  `TournamentGroupStageClient` at `667x375`, `740x360`, `844x390` and
  `932x430` against the canonical hosted staging snapshot.
- Observed: desktop and portrait change the active `aria-pressed` tab, while
  every landscape click leaves `Resumen` active. Root overflow, broken images,
  framework overlays and console errors remain zero.
- Impact: the real Mobile Game Landscape Hub cannot open rounds, matches,
  standings, Team Journey, discipline, referees, incidents, rules or bracket.
- Planned correction: inspect the rail's computed track and hit target, then
  assign a stable landscape dimension/stacking contract without changing the
  canonical data flow.
- Regression evidence: the real Hub rail computes `32px`, every tab becomes
  the active `aria-pressed` control at all four required landscape sizes, and
  the full canonical matrix reports zero overflow, broken images, framework
  overlays, console errors or warnings.

## Verification closure - 2026-08-27

- `R6B-PRODUCT-005`, `R6B-PRODUCT-006`, `R6B-SIMULATION-010`,
  `R6B-SIMULATION-019`, `R6B-ENV-020` and `R6B-ENV-021`: the guarded fresh
  bootstrap completed from the immutable baseline with exactly 169 ordered
  migrations, including all six R6B migrations.
- `R6B-PRODUCT-001`, `R6B-PRODUCT-002`, `R6B-PRODUCT-004`,
  `R6B-SIMULATION-007`, `R6B-PRODUCT-008`, `R6B-PRODUCT-009`,
  `R6B-SIMULATION-011`, `R6B-PRODUCT-013`, `R6B-TEST-014`,
  `R6B-PRODUCT-015`, `R6B-PRODUCT-016` and `R6B-SIMULATION-017`: the canonical
  full-story regression completed 4 groups, 24 fixtures, 24 CanonicalMatches,
  4 current standings snapshots, published qualification and 8 independently
  sequenced bracket slots while creating zero knockout matches.
- `R6B-TEST-003`, `R6B-PRODUCT-018` and `R6B-PRODUCT-022`: the same regression
  read the organizer Hub and three participant next matches with stable R4C,
  R4D, R5 and referee fields and no evidence, actor, private-reason or fee keys.
- `R6B-TEST-023`: the authenticated direct-insert attempt raised insufficient
  privilege and left zero direct QualificationSnapshot writes.
- `R6B-ENV-012`: the concrete migration/test search completed without an
  unmatched shell glob and located the persisted draw-lot contract used by the
  provisional/final standings regression.
- `R6B-PRODUCT-025`: all four group projections expose published R4B readiness
  with six slots and six fixtures after the exact canonical story.
- `R6B-TEST-026`, `R6B-TEST-027` and `R6B-TEST-028`: the focused TypeScript
  suite now binds to exact canonical symbols and durable scenario markers;
  11/11 tests pass.
- `R6B-TEST-029`: the same SQL story now runs transactionally, emits its report
  before rollback and leaves zero fixture users/competitions while preserving
  all 169 migration ledger rows and OFF defaults.
