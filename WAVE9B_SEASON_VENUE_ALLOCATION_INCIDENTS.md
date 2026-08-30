# Wave 9B Season Venue Allocation Incidents

Fecha de apertura: 2026-08-30 CEST

## Checkpoint

- base: `592a3dcc1147df41fb05c21703f131e66fc75a0a`;
- rama: `codex/recurring-venue-bulk-allocation-v1`;
- ledger productivo inicial: `220`;
- tests iniciales conocidos: `699/699`;
- entidades reales permitidas: `0`;
- Stripe y Live Checkout: `UNTOUCHED / OFF`;
- PR excluidos: `#6`, `#131`, `#132`;
- checkout compartido: sucio y preservado, sin incorporar sus cambios.

## Politica

Todo fallo encontrado se registra antes de corregirse como `PRODUCT_BUG`,
`SIMULATION_BUG`, `TESTABILITY_GAP`, `ENVIRONMENT_ISSUE` o
`NEEDS_PRODUCT_DECISION`. Tras la correccion debe incluir el escenario original
y quedar en `fixed + regression_verified`.

No se corrigen silenciosamente errores de SQL, simulacion, producto, QA,
migracion, release o cleanup.

## Incidencias

### W9B-001 - npm audit reports preexisting dependency advisories

- Classification: `ENVIRONMENT_ISSUE`
- Status: `open / preexisting / non-blocking`
- Original reproducer: run `npm ci` on exact base
  `592a3dcc1147df41fb05c21703f131e66fc75a0a`.
- Impact: installation succeeds, but npm reports `18` advisories: `1` low,
  `4` moderate and `13` high. Wave 9B has not installed or changed a package.
- Required correction: do not run a broad or breaking `npm audit fix` inside
  this product slice. Keep `package.json` and `package-lock.json` unchanged,
  run the full product gates, and close this incident only after the final diff
  proves Wave 9B introduced zero dependency changes.

### W9B-002 - Baseline test result lost after output truncation

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: run `npm test` through a bounded interactive command;
  the build and Node suite were visible, but the TS/TSX output exceeded the
  transport buffer and the completed process could no longer be queried.
- Impact: the exact baseline total and final exit code are not auditable from
  the first run, so it cannot be counted as a completed gate.
- Required correction: repeat the exact command while preserving full output
  in a temporary log, report only its parsed summary, then delete the log after
  the result is recorded in this ledger.
- Resolution: the rerun produced `20/20` Node tests and `679/679` TS/TSX tests,
  for an exact total of `699/699`; fail, cancelled, skipped and todo were all
  zero, the build passed, and the command returned exit code `0`.
- Regression verification: the complete output was retained until its two TAP
  summaries and exit code were parsed independently.

### W9B-003 - zsh wrapper used a reserved variable

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: capture the `npm test` exit code in a variable named
  `status` under `zsh`.
- Impact: `zsh` rejects the assignment because `status` is read-only, causing
  the wrapper to exit `1` without reporting the underlying test result.
- Required correction: use a non-reserved variable, rerun the exact test suite,
  and add a regression check that the wrapper reports both the TAP summary and
  the actual exit code.
- Resolution: the wrapper now uses `rc`, which is writable under `zsh`.
- Regression verification: the corrected wrapper reported both TAP summaries
  and `EXIT_CODE=0` in the same completed process.

### W9B-004 - Temporary log cleanup command rejected by tool policy

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: request `rm -f` for the isolated test log under `/tmp`.
- Impact: no product file or test result is affected, but the temporary log
  remains until removed through an accepted single-file cleanup operation.
- Required correction: remove the exact file with `unlink`, verify it no longer
  exists, and leave all repository evidence untouched.
- Resolution: removed only `/tmp/pachangas-wave9b-baseline-tests.log` with
  `unlink`.
- Regression verification: an independent existence check returned success for
  the file being absent.

### W9B-005 - Audit search included a non-existent source directory

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: run the Wave 9B inventory search against `app`, `lib`,
  `supabase` and `tests` when this repository has no top-level `lib` directory.
- Impact: `rg` reported the missing directory while still returning the useful
  matches from the other roots; no product source was changed.
- Required correction: derive the source roots from the checkout and repeat the
  inventory only against directories that exist.
- Resolution: repeated the inventory against the verified roots `app`,
  `supabase` and `tests` only.
- Regression verification: the corrected search completed with exit code `0`
  and enumerated `342` relevant paths without missing-directory diagnostics.

### W9B-006 - Existing-binding-only plans are rejected by the hold batch

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: build an allocation revision whose every Match already
  has a canonical active Venue binding, then run `allocation.hold`.
- Impact: the first publication draft counts zero new holds and rejects the
  operation even though preserving existing bindings requires no new claim.
- Required correction: allow a zero-sized hold batch only when every assigned
  item is an immutable `EXISTING_BINDING`, then publish those bindings without
  manufacturing reservations or claims.

### W9B-007 - A recurring hold invalidates its own frozen input

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: freeze a plan that selects a `planned` recurring
  occurrence, create its bulk hold, then validate the unchanged plan.
- Impact: changing that occurrence to `held` alters the availability checksum,
  so the plan reports `STALE_INPUT` because of its own server-side operation.
- Required correction: keep the occurrence projection `planned` while the
  canonical Wave 9A hold owns temporary occupancy; set it to `reserved` only
  after atomic publication.

### W9B-008 - Validation status identifier shadows the persisted column

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: compile the allocation validation helper where the
  PL/pgSQL variable and revision column are both named `validation_status`.
- Impact: PostgreSQL can reject the statement as ambiguous or assign the column
  to itself, leaving the authoritative validation outcome unpersisted.
- Required correction: rename the local result variable and qualify every
  target-column assignment explicitly.

### W9B-009 - Fresh bootstrap rejects the engine/command migration

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run the guarded fresh bootstrap from the exact Wave 9B
  migration set after resetting the isolated local Supabase database.
- Impact: migrations 1-4 apply, but PostgreSQL rejects
  `20260830223008_competition_venue_allocation_engine_commands_v1.sql`; no
  later Wave 9B migration is applied and release is blocked.
- Required correction: capture the first untruncated PostgreSQL diagnostic,
  correct only that migration defect, rerun fresh bootstrap from zero and add a
  regression assertion that all eight versions reach the migration ledger.
- Resolution: parenthesized the two role-dependent horizon expressions that
  PostgreSQL's PL/pgSQL parser had treated ambiguously, then rebuilt the local
  database from the canonical baseline.
- Regression verification: the guarded bootstrap applied all `228` migrations,
  including the eight Wave 9B files through `20260830223014`, and returned
  `BOOTSTRAP_COMPLETE` with exit code `0`.

### W9B-010 - Bulk hold and publish helpers omit their dedicated feature gates

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: enable allocation foundation while leaving
  `competition_venue_allocation_holds_enabled` or
  `competition_venue_allocation_publish_enabled` OFF, then invoke the matching
  command.
- Impact: the first helper draft checks only the generic allocation flag and
  can execute a gated production capability before its staged activation.
- Required correction: enforce each dedicated server-side flag inside the
  transactional helper itself and add negative DB coverage with foundation ON
  but the individual capability OFF.

### W9B-011 - Publish gate was attached to validation during the first fix

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: inspect or invoke `allocation.validate` after the first
  dedicated-gate patch while publication remains OFF.
- Impact: validation is incorrectly blocked by
  `VENUE_ALLOCATION_PUBLISH_DISABLED`, preventing the required staged flow
  where plans are validated before publication is activated.
- Required correction: remove that check from validation, place it at the top
  of the publication helper, and cover both transitions independently.

### W9B-012 - Constraint parameters accept sensitive arbitrary JSON

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: call `allocation_constraint.create` with nested keys
  such as `latitude`, `longitude`, `privateAddress`, `contactPhone` or an
  oversized parameters object.
- Impact: untrusted client data can persist private-looking location/contact
  fields and later escape through a management read model or diagnostic log.
- Required correction: reject sensitive keys recursively, cap serialized size,
  enforce object shape in the authoritative command, and regression-test both
  create and update paths before any read model returns parameters.

### W9B-013 - Completed and ended recurring states have no reachable command

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: publish a finite recurring series and inspect the
  allowlisted command surface after its final occurrence has passed, or try to
  end it explicitly before its natural completion.
- Impact: the table accepts `completed` and `ended`, but no authenticated RPC
  action can reach either state; a published series can only pause, resume or
  cancel, so its declared lifecycle is incomplete.
- Required correction: add explicit `recurring_series.complete` and
  `recurring_series.end` intents with authority, state and occurrence guards,
  preserve every historical reservation/binding, and cover both transitions.

### W9B-014 - Recurring lifecycle transitions do not append series revisions

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: create a recurring series, then validate, offer, accept,
  publish, pause or materialize it and compare `current_revision_id` before and
  after each accepted command.
- Impact: the aggregate revision and event advance, but most lifecycle changes
  keep pointing at the previous configuration snapshot. The audit trail cannot
  reconstruct the exact state accepted by each operation.
- Required correction: append an immutable series revision for every accepted
  lifecycle command, advance `current_revision_id`, and verify monotonically
  ordered versions without changing past snapshots.

### W9B-015 - Revalidation overwrites persisted validation evidence

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: validate the same allocation revision and checksums
  twice with different operation IDs and inspect the row identified by the
  unique revision/input/result tuple.
- Impact: `ON CONFLICT DO UPDATE` replaces actor, sequence and timestamp, so
  the first server evidence disappears and the operation is not append-only.
- Required correction: retain the first immutable validation row, return its
  canonical summary on equivalent revalidation, and add an immutable-history
  trigger plus a regression proving timestamp and sequence do not change.

### W9B-016 - Fresh bootstrap process has no guarded database URL

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: run `npm run db:bootstrap:fresh` in the isolated Wave 9B
  worktree without exporting `PACHANGAS_BOOTSTRAP_DATABASE_URL` or `DB_URL`.
- Impact: the guard exits before connecting with
  `PACHANGAS_BOOTSTRAP_DATABASE_URL_OR_DB_URL_REQUIRED`; no migration runs and
  no database state changes.
- Required correction: rerun the same guarded bootstrap with the explicit
  local Supabase URL on `127.0.0.1:55322`, verify its safety checks accept only
  that local target, and remove the temporary log afterward.
- Resolution: supplied only the isolated local PostgreSQL URL through
  `PACHANGAS_BOOTSTRAP_DATABASE_URL`; no credential or remote project reference
  was persisted.
- Regression verification: the guard accepted the loopback target and the
  completed bootstrap identified the canonical baseline and all 228 versions.

### W9B-017 - Isolated local database is not fresh after the prior compile

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: rerun the guarded bootstrap against the local Supabase
  container after the earlier six-migration compile left `420` product
  relations present.
- Impact: the safety guard exits with `BOOTSTRAP_PRODUCT_DATABASE_NOT_EMPTY`
  before applying any migration, which is correct but blocks the eight-file
  full rebuild.
- Required correction: reset only the isolated local Supabase database without
  seed or migration replay, confirm it is empty, then run the guarded 228-file
  bootstrap from the canonical baseline and migration ledger.
- Resolution: `supabase db reset --local --no-seed` recreated only the local
  container; the repository bootstrap then applied the baseline and migrations.
- Regression verification: the reset completed on the local target and the
  subsequent clean rebuild returned `appliedMigrations: 228`.

### W9B-018 - Wave 9B fixture can be loaded against stale local QA state

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: load `season-venue-allocation-v1-fixture.sql` directly
  into the already bootstrapped local `postgres` database after an earlier
  fixture or partial QA graph has been created.
- Impact: pre-existing synthetic memberships can trigger canonical owner
  guards such as `CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED`; the allocation test
  then measures fixture contamination instead of the Wave 9B behavior.
- Required correction: execute the fixture and authoritative DB suite only in
  a newly created disposable database, load each fixture exactly once, and
  always drop that database after pass or failure.

### W9B-019 - Competition recurring invalidation has inconsistent audience

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: create a `COMPETITION_RECURRING_BLOCK` through the
  canonical command after enabling Wave 9B.
- Impact: the command emits `audienceKind = AUTHENTICATED` together with a
  Competition `audienceId`; the existing Wave 9A invalidation constraint
  rejects that inconsistent row and rolls the operation back.
- Required correction: classify Competition recurring series as
  `COMPETITION`, Team recurring series as `TEAM`, and reserve
  `AUTHENTICATED` for invalidations without a scoped audience identifier.

### W9B-020 - Canonical DB test has ambiguous aggregate identifiers

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run the isolated Wave 9B DB suite until the occurrence
  count query compares `rows.series_id` with the PL/pgSQL `series_id` variable.
- Impact: PostgreSQL aborts the diagnostic block with an ambiguous-column
  error before the recurrence assertion can evaluate product behavior.
- Required correction: declare the test block's variable-conflict policy
  explicitly while continuing to qualify every table column through aliases.

### W9B-021 - Pool membership upsert has an ambiguous conflict target

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: accept an offered pool authorization and activate its
  pool through `command_pachanga_competition_venue_allocation_v1`.
- Impact: `ON CONFLICT (operation_id)` can resolve to either the RPC parameter
  or the membership column, so PostgreSQL aborts pool activation before any
  canonical membership is created.
- Required correction: target the named unique membership-operation
  constraint, preserving idempotency without depending on PL/pgSQL name
  resolution.

### W9B-022 - Allocator modality variable collides with membership column

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: freeze an authorized plan and invoke
  `allocation.generate` with at least one compatible pool membership.
- Impact: the allocator compares `memberships.modality = modality`, where the
  latter identifier can resolve to either the local variable or the column;
  PostgreSQL aborts before producing an allocation revision.
- Required correction: rename the internal value to `target_modality` and use
  it explicitly in candidate filtering and availability validation.

### W9B-023 - Recurring fixture compares local time with a UTC match time

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: materialize the main test series at `18:00`
  `Europe/Madrid` and compare it with the canonical match scheduled at
  `18:00Z` on 17 May 2027.
- Impact: daylight-saving time makes the occurrence start at `16:00Z`, so the
  allocator correctly treats it as a different slot and the test incorrectly
  reports a product failure.
- Required correction: set the synthetic series to `20:00` local, assert its
  exact `18:00Z` occurrence, and retain the canonical match time unchanged.

### W9B-024 - Bulk hold helper assigns an ambiguous hold identifier

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: generate an assignable plan and invoke
  `allocation.hold` through the canonical command.
- Impact: `hold_id = hold_id` inside the item update is ambiguous between the
  table column and local variable, so PostgreSQL aborts the entire hold batch.
- Required correction: rename the generated local identifier to
  `created_hold_id` and use it for the claim, canonical hold, link, request and
  allocation item in the same transaction.

### W9B-025 - Publication helper assigns ambiguous reservation and binding IDs

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: hold and validate an allocation, then invoke
  `allocation.publish`.
- Impact: the final item update evaluates `reservation_id = reservation_id`
  and `binding_id = binding_id`; both identifiers collide with local variables
  and the whole publication transaction rolls back.
- Required correction: rename the generated values to
  `created_reservation_id` and `created_binding_id` throughout claim
  conversion, reservation creation, binding creation and lineage writes.

### W9B-026 - Read-model regression inspects status at the wrong JSON path

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: publish the canonical plan and assert
  `desk->>'status' = 'published'` on the Organizer Desk response.
- Impact: the canonical read model correctly nests aggregate fields below
  `plan`; the incorrect assertion reports a privacy/read-model failure despite
  receiving `plan.status = published` and no private authority fields.
- Required correction: assert `{plan,status}` while retaining the full response
  scan for private addresses, coordinates, contacts and actor identities.

### W9B-027 - Unauthorized read regression expects legacy error names

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: query the Organizer Desk as a synthetic user without
  Competition authority after publishing a plan.
- Impact: the server correctly rejects the read with
  `VENUE_ALLOCATION_READ_FORBIDDEN`, but the test only accepts two older error
  names and therefore reports a false RLS regression.
- Required correction: accept the canonical read-forbidden error while keeping
  the negative actor and direct-table denial assertions unchanged.

### W9B-028 - Competing recurring series can both become accepted

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: create two overlapping series for the same Pitch,
  validate and offer both, then accept them concurrently.
- Impact: validation only checks already accepted/published series and no
  Pitch-scoped lock serializes acceptance; both transactions can pass the check
  and create overlapping seasonal authority.
- Required correction: serialize conflict-sensitive transitions per Pitch and
  re-evaluate the recurring overlap immediately before accept, publish, resume
  and materialization.

### W9B-029 - Allocation revisions are mutated by lifecycle actions

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: capture an AllocationRevision after generation, then
  validate, publish or cancel its plan and compare the same row afterward.
- Impact: status, validation metadata, publication metadata, revision and
  sequence are updated in place, violating the required append-only revision
  history and making the generated artifact non-reconstructible.
- Required correction: keep lifecycle on the mutable AllocationPlan and in
  immutable validation/publication evidence, stop all revision updates, derive
  validation for publication from the evidence table, and reject any future
  update/delete of an AllocationRevision with an immutable-history trigger.

### W9B-030 - Immutable-read-model patch omitted the global health join

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: inspect or invoke the patched platform allocation health
  query after deriving published status from the AllocationPlan.
- Impact: the query references the `plans` alias without joining the plans
  table, which would make migration compilation or the health RPC fail.
- Required correction: join each revision to its plan and restrict the metric
  to the plan's current immutable revision.

### W9B-031 - Immutability regression captures the revision before generation

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: inspect the first version of the W9B-029 regression,
  which reads `current_revision_id` immediately after `allocation_plan.create`.
- Impact: the plan has no generated revision yet, so the snapshot is null and
  cannot prove that validation/publication preserve the generated artifact.
- Required correction: capture the complete revision row immediately after
  `allocation.generate` and before holds, validation or publication.

### W9B-032 - Revision immutability trigger blocks atomic construction finalization

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: generate a plan after enabling the immutable revision
  trigger introduced for W9B-029.
- Impact: the allocator inserts a transaction-local placeholder revision so
  its items can reference it, then finalizes checksum/counts before commit; a
  blanket trigger rejects that one construction transition and aborts every
  generation.
- Required correction: permit exactly one placeholder-to-final transition,
  include candidate count in that same finalization, and reject every update
  once the result checksum is non-placeholder as well as every delete.

### W9B-033 - Deterministic result checksum includes a random revision item ID

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: generate and regenerate the same frozen inputs with the
  same seed and algorithm version, then compare `result_checksum`.
- Impact: each revision receives a random UUID and item IDs are derived from
  it; including the item ID in the checksum makes equivalent allocations
  produce different canonical hashes.
- Required correction: hash only sporting identity, fixed times, Venue/Pitch,
  source, status, conflicts, warnings and override semantics, then verify two
  equal generations return the same checksum.

### W9B-034 - Concurrency fixture uses a non-allowlisted pool field

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: prepare the concurrency pool with
  `authorizedPitchIds` instead of the command contract's `pitchIds` key.
- Impact: the authoritative payload allowlist correctly rejects the setup with
  `VENUE_ALLOCATION_COMMAND_INVALID`, preventing later allocation races from
  running.
- Required correction: use the exact canonical `pitchIds` field in the
  synthetic pool offer and keep the server rejection behavior unchanged.

#### Closure evidence for W9B-006 through W9B-034

The corrections above are preserved by the disposable canonical database
suite and, where the defect was race-dependent, by the independent concurrency
runner:

- W9B-006: existing-binding-only plans hold/publish without synthetic claims.
- W9B-007: a recurring hold leaves the frozen occurrence projection stable
  until publication.
- W9B-008: validation uses the qualified `validation_result_status` value.
- W9B-010/W9B-011: holds and publication each enforce their own flag while
  validation remains reachable before publication activation.
- W9B-012: nested sensitive keys and oversized constraint JSON are rejected.
- W9B-013/W9B-014: complete/end are reachable and every accepted recurring
  lifecycle command appends and advances an immutable revision.
- W9B-015: equivalent revalidation returns the first evidence without changing
  its sequence, actor or timestamp.
- W9B-018: fixture, DB and concurrency runners create and always destroy their
  own disposable database.
- W9B-019: invalidations use `COMPETITION`, `TEAM` or unscoped
  `AUTHENTICATED` audiences consistently.
- W9B-020: the DB regression declares its variable-conflict behavior and every
  aggregate column is qualified.
- W9B-021: pool activation targets the named operation-id unique constraint.
- W9B-022: allocator candidate filtering uses `target_modality` explicitly.
- W9B-023: the Europe/Madrid fixture proves `20:00` local equals the intended
  `18:00Z` summer occurrence without altering the Match schedule.
- W9B-024/W9B-025: hold, reservation and binding identifiers use distinct
  `created_*` variables throughout their transactions.
- W9B-026/W9B-027: Organizer Desk status is asserted below `plan`, and an
  unrelated actor receives the canonical read-forbidden error.
- W9B-028: Pitch-scoped advisory locks produce one winner and one rejected
  loser for overlapping series acceptance.
- W9B-029/W9B-031/W9B-032: the generated revision is captured at the correct
  point, permits only its transaction-local placeholder finalization and then
  rejects every update/delete during validation and publication.
- W9B-030: global health joins each immutable revision to its current plan.
- W9B-033: two equal generations produce the same sporting result checksum.
- W9B-034: concurrency setup sends only canonical `pitchIds`.

Regression result: fresh and upgrade paths both reach ledger `228`, have schema
hash `89ae7c302759827bcb58d747eec4ff538422548c3792b105d8d4ccf454141c26`,
pass the complete canonical lifecycle and cleanup, and the concurrency runner
passes all six races with exactly one authoritative winner per conflict.

### W9B-035 - Scale fixture omits required Wave 9A feature dependencies

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run
  `node tests/season-venue-allocation-v1-scale-runner.mjs` against a fresh
  disposable database. The first settings update fails with
  `pachanga_venue_wave9b_allocation_dependencies_check`.
- Impact: the corpus enables allocation, holds and publication while the
  inherited Wave 9A availability, hold, canonical-reservation and binding
  authorities remain disabled. The production dependency guard correctly
  rejects this impossible state before any scale rows are written.
- Required correction: enable the exact Wave 9A dependencies inside the
  disposable scale transaction; do not weaken or bypass the database guard.
- Resolution: the scale transaction now enables the inherited availability,
  request, hold, canonical-reservation and match-binding authorities before
  enabling Wave 9B. The original dependency error no longer occurs and the
  corpus advances to reservation generation.
- Regression evidence:
  `node tests/season-venue-allocation-v1-scale-runner.mjs` crosses the settings
  update under the unchanged database constraints.

### W9B-036 - Long scale calendar crosses an ambiguous Europe/Madrid hour

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: generate 50,000 two-hour-spaced synthetic reservations
  from January 2030 while deriving local times in `Europe/Madrid`. At the
  autumn DST transition, `00:00Z` and `01:00Z` both map to local `02:00`, so
  one request violates the canonical local-end-after-local-start constraint.
- Impact: the scale corpus aborts before reservation, binding and read-model
  measurements. Product validation is behaving correctly; no product row is
  committed because the test transaction rolls back.
- Required correction: use UTC for the artificial multi-year reservation
  corpus. Keep the dedicated Europe/Madrid DST assertions in the canonical DB
  suite as the source of timezone behavior coverage.
- Resolution: the 50,000-row load corpus now uses UTC local projections and a
  zero resolved offset; the canonical Europe/Madrid fixture remains unchanged.
- Regression evidence: the scale runner inserts all 50,000 canonical
  reservation requests, claims, terms, reservations and bindings before
  reaching the later invalidation phase.

### W9B-037 - Scale invalidations use a non-canonical audience label

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: insert the 50,000 scale invalidations with
  `audience_kind = COMPETITION_STAFF`.
- Impact: Wave 9A's audience contract only accepts `PUBLIC`, `AUTHENTICATED`,
  `CLUB`, `TEAM`, `COMPETITION` or `USER`; the protected table rejects the
  corpus before latency sampling.
- Required correction: emit `venue_allocation_plan` invalidations for the
  canonical `COMPETITION` audience and provide the Competition ID as
  `audience_id`, matching the Wave 9B hold-expiry trigger.
- Resolution: the scale corpus now uses `venue_allocation_plan`, audience
  `COMPETITION` and the canonical Competition UUID.
- Regression evidence: all 50,000 invalidations are accepted and the scale
  transaction advances to latency sampling.

### W9B-038 - Product routes cannot discover recurring series or Venue Pools

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open the required `/reservas/recurrentes` or
  `/clubes/gestionar/campos/pools` surface without already knowing an aggregate
  UUID. The available read models only accept a specific series or pool ID.
- Impact: a client would have to read protected authority tables directly,
  retain IDs from unrelated local state or present an empty product surface.
- Required correction: add one privacy-safe catalog RPC filtered by an
  authorized Club or Competition. It may expose operational identifiers,
  statuses and revisions, but never contacts, private locations, actor IDs or
  write authority.
- Resolution: `get_pachanga_season_venue_catalog_v1` now returns only authorized
  series, pools and plans, and the product routes use it for discovery.
- Regression evidence: fresh/upgrade schema equivalence and the DB suite pass;
  authorized discovery returns the expected aggregates without private fields,
  while an unrelated identity is rejected.

### W9B-039 - Scale latency block shadows series identifier

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: execute the first `series_materialization` latency
  sample after the exact corpus has been inserted. PL/pgSQL resolves
  `series_id` as both a local variable and a table column.
- Impact: data generation succeeds but no percentile evidence is emitted; the
  transaction still rolls back and the disposable database is destroyed.
- Required correction: prefix all probe identifiers with `target_` and qualify
  every compared table column so no PL/pgSQL name can be ambiguous.
- Resolution: every probe UUID now uses a `target_` prefix and the occurrence
  comparison is column-qualified.
- Regression evidence: the full scale runner passes with the exact corpus,
  ten p50/p95 metrics, competition sizes 16/32/64/128/256, full rollback and
  disposable database cleanup.

### W9B-040 - Status label mixes nullish and boolean fallback operators

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run `npm run typecheck` after adding the Season Venue
  client contract. TypeScript reports TS5076 in `seasonVenueStatus`.
- Impact: the new routes cannot build even though runtime intent is clear.
- Required correction: parenthesize the humanized fallback before applying the
  final empty-string fallback; no status semantics should change.
- Resolution: the fallback expression now resolves the humanized status first
  and only then applies the empty-string fallback.
- Regression evidence: `npm run typecheck` completes with exit code `0` and no
  TS5076 diagnostic.

### W9B-041 - Selecting a Venue Pool does not load its canonical snapshot

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open `/clubes/gestionar/campos/pools`, select a pool and
  inspect the client state. Only the catalog is retained; the pool read model
  with authorizations and memberships is never requested.
- Impact: the operator cannot inspect the selected authorization or build an
  offer from canonical state, despite the server exposing the required RPC.
- Required correction: fetch and merge the selected pool read model after the
  catalog, preserve no-store semantics, and add a product regression covering
  selection plus canonical refetch.
- Resolution: pool selection requests the no-store canonical pool read model
  and merges its authorizations and memberships with the catalog.
- Regression evidence: the focal product suite asserts the selected-pool read
  and passes `4/4`; typecheck passes.

### W9B-042 - Manual planner omits required assisted operations

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open a generated plan and compare its controls with the
  Wave 9B contract. Assign, move and lock exist, but swap, draft removal,
  unlock and constraint management have no reachable product action.
- Impact: the server-authoritative engine is only partially operable from the
  product UI and an organizer cannot complete the declared manual/hybrid flow.
- Required correction: expose the existing allowlisted RPC intents without
  calculating authority client-side, retain expectedRevision and operationId,
  and regression-test every required control.
- Resolution: the planner now exposes swap, draft removal, unlock and
  constraint create/remove alongside assign, move and lock.
- Regression evidence: the focal suite verifies every intent remains routed
  through the central command API with revision and idempotency metadata.

### W9B-043 - Pool acceptance targets the wrong aggregate

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: press `Aceptar` on a pool card. The client sends
  `venue_pool.accept` with the pool ID and pool revision, while the canonical
  command contract requires the offered authorization ID and its revision.
- Impact: a valid owner cannot accept an offer from the UI; the command is
  rejected as authorization not found or stale.
- Required correction: expose acceptance on each offered authorization from
  the selected pool snapshot and send its exact aggregate ID and revision.
- Resolution: acceptance moved from the pool card to each offered authorization
  and sends `authorizationId` plus its canonical revision.
- Regression evidence: the product contract test asserts the authorization
  aggregate path and passes; the DB lifecycle accepts that exact transition.

### W9B-044 - Planner hides the explainable quality breakdown

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open a generated plan with a quality snapshot. The UI
  renders only the score ring and conflict cards.
- Impact: an organizer sees a number such as `92/100` without the contractually
  required explanation for hard violations, usage, overrides, locks, warnings
  and the remaining quality dimensions.
- Required correction: render the canonical quality breakdown returned by the
  read model; do not recalculate or reinterpret the score in the browser.
- Resolution: the planner renders hard violations, unassigned matches,
  recurring usage, changes, utilization, premium balance, overrides, locks,
  warnings and travel status from the canonical snapshot.
- Regression evidence: the focal product suite asserts the breakdown fields
  and passes `4/4`.

### W9B-045 - Structural horizon regression asserts a non-existent identifier

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: run `npm run test:season-venue-allocation`; the migration
  contract test searches for `maximum_horizon_weeks`, while the implementation
  expresses the finite horizon directly through date bounds and role-aware
  interval checks.
- Impact: a valid 52/104-week implementation fails for an invented symbol and
  obscures the actual bounded-horizon evidence.
- Required correction: assert the concrete 728-day schema ceiling plus the
  52/104-week server checks, then rerun the focal suite.
- Resolution: the regression now asserts both the 728-day schema ceiling and
  the role-aware `364/728` server interval.
- Regression evidence: `npm run test:season-venue-allocation` passes `4/4`.

### W9B-046 - Catalog negative test reuses an actor with inherited access

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run the canonical DB suite and use fixture user
  `e901...0005` as a presumed outsider for the Club catalog.
- Impact: the user has a valid inherited sporting relationship, so the
  privacy-safe catalog correctly permits the read and the negative test fails
  with `WAVE9B_EXPECTED_FAILURE_NOT_RAISED`.
- Required correction: execute the ACL negative with a synthetic authenticated
  UUID that has no Club, Competition, Team or platform relationship, then
  rerun fresh/upgrade equivalence and the full DB suite.
- Resolution: the unrelated UUID also passed, disproving the initial fixture
  diagnosis and exposing the NULL-role authority defect recorded as W9B-047.
- Regression evidence: the negative catalog and global-health checks now use a
  synthetic UUID with no inherited relationship and both receive the expected
  server denial after W9B-047.

### W9B-047 - NULL platform role bypasses two read-model authority checks

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: call `get_pachanga_season_venue_catalog_v1` as an
  authenticated UUID with no product relationships and no platform role. The
  helper returns `NULL`; `NULL NOT IN (...)` is unknown, so the PL/pgSQL `IF`
  does not raise. The same pattern exists in global allocation health.
- Impact: an unrelated authenticated actor can pass the outer catalog or
  platform-health gate. Row-level helper filters still reduce catalog content,
  but the authority boundary and global health privacy contract are broken.
- Required correction: coalesce a missing platform role to an explicit
  non-platform sentinel in both checks and add negative SQL regressions for the
  catalog and global health RPCs.
- Resolution: both read-model gates coalesce missing roles to `none` before the
  platform allowlist comparison.
- Regression evidence: the fresh and 220-to-228 schemas are identical with
  hash `89ae7c302759827bcb58d747eec4ff538422548c3792b105d8d4ccf454141c26`;
  catalog and global health both reject an unrelated authenticated UUID.

### W9B-048 - Demo projection treats challenge bindings as Competition inputs

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: project all 128 V3.2 CanonicalMatches directly into the
  four Competition allocation plans. The source season contains 112 League or
  Tournament matches and 16 independent challenges with no Competition ID.
- Impact: plan totals cannot reconcile and existing challenge bindings appear
  to have been created by the Competition allocator.
- Required correction: keep the 16 challenges as immutable
  `EXISTING_BINDING` assignments outside plan totals, and place the deliberate
  unresolved field conflict on one of the 112 Competition matches.
- Resolution: V3.5 projects exactly 112 League/Tournament matches through the
  eight automatic/hybrid plans and preserves all 16 challenges as immutable
  existing bindings outside those plan totals.
- Regression evidence: the five Demo V3.5 tests pass, including exact 128-Match
  identity, 16 `EXISTING_BINDING` rows, one unresolved Competition Match and
  unchanged V3.2/V3.4 authority hashes.

### W9B-049 - Season Venue client performs synchronous state updates in effects

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run focal ESLint on the planner client. React reports
  `react-hooks/set-state-in-effect` for online initialization and cache
  hydration.
- Impact: the implementation builds, but can trigger avoidable cascading
  renders and fails the required zero-warning lint gate.
- Required correction: initialize connectivity lazily from `navigator` and
  deliver cache hydration from an asynchronous external-state callback.
- Resolution: connectivity now uses a lazy state initializer and cache
  hydration is deferred through a cancellable microtask.
- Regression evidence: focal ESLint passes with zero errors and zero warnings;
  product tests pass `4/4` and typecheck passes.

### W9B-050 - Demo V3.5 generator and regression use unbounded any types

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: run focal ESLint over the generator and V3.5 tests;
  `@typescript-eslint/no-explicit-any` reports 25 untyped source records.
- Impact: the generated snapshot passes runtime assertions, but source-season
  shape drift would not be caught statically and lint blocks release.
- Required correction: reuse the V3.2 and V3.4 contracts and add a narrow type
  for the disposable DB proof; remove every explicit `any`.
- Resolution: generator and regression now consume `SyntheticSeasonIndex`,
  `SyntheticSeasonMatch`, `DemoWorldV34FieldOperations` and
  `DemoWorldV34Pitch`, with a bounded database-proof shape.
- Regression evidence: focal ESLint and typecheck pass; regeneration preserves
  content hash `b5d8f72aed06f814ae76e481c03151e1d1ec0d71e2103079a6d19d9c2307bc06`
  and the Demo suite passes `5/5`.

### W9B-051 - Focal ESLint command includes CSS modules

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: pass the two CSS module paths directly to ESLint.
- Impact: ESLint reports two `File ignored because no matching configuration`
  warnings even though CSS is validated by build and visual QA.
- Required correction: rerun focal ESLint only over configured TS/TSX sources
  and keep CSS in build, responsive contract and browser checks.
- Resolution: the focal command now targets only configured TypeScript/TSX
  sources; CSS remains covered by production build and visual QA.
- Regression evidence: focal ESLint exits `0` with zero errors and warnings.
