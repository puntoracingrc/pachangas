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
- Resolution: connectivity and cache hydration now use deterministic first
  snapshots and cancellable microtasks, avoiding synchronous effect updates.
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

### W9B-052 - Local visual runner uses a different development origin

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: start Next on `http://localhost:3100` and open the same
  process through `http://127.0.0.1:3100/demo` in the isolated browser.
- Impact: Next 16 blocks cross-origin development chunks, so the server-rendered
  Demo shell remains on its loading state even though the application build is
  healthy.
- Required correction: repeat visual QA on the exact advertised `localhost`
  origin and confirm that all chunks load; do not weaken `allowedDevOrigins` or
  change production configuration for this local-host mismatch.
- Resolution: browser QA now uses the exact advertised `localhost` origin; no
  application or Next configuration changed.
- Regression evidence: Demo V3.5 hydrates beyond its loading shell, renders
  2,472 visible text characters, has zero framework overlays, zero page errors
  and zero root overflow.

### W9B-053 - Demo section menu is rendered beneath the active surface

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open Demo V3.5 as Platform reviewer, expand `Secciones`
  and press `Campos` at desktop width.
- Impact: the section button has a visible layout box, but the active Home
  statistics layer covers its click point; Demo V3.5 cannot be reached through
  normal pointer interaction.
- Required correction: keep the existing navigation structure and raise only
  the section popover above the Demo content, then verify pointer navigation at
  desktop, portrait and landscape widths.
- Resolution: no product correction was required. The first automation tried
  to locate the hidden option before opening its native `details` parent; the
  real sequence opens `Secciones` first and its panel is already above Home.
- Regression evidence: `elementFromPoint` at the visible `Campos` center
  resolves to the button itself, and a real pointer click reaches
  `Season Field Allocation` with zero root overflow.

### W9B-054 - Demo section popover remains open after navigation

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open `Secciones`, click `Campos` and inspect the newly
  selected Season Field Allocation surface.
- Impact: navigation succeeds, but the native `details` panel remains open and
  obscures the planner header and controls until the user closes it manually.
- Required correction: close only the originating `details` after invoking the
  existing tab navigation callback, and add a focused structural plus pointer
  regression.
- Resolution: each domain option invokes the unchanged tab callback and then
  removes `open` from its closest native `details` element.
- Regression evidence: Demo tests pass `5/5`, focal ESLint/typecheck pass, and
  the pointer flow ends on `Season Field Allocation` with `open=false` and
  zero root overflow.

### W9B-055 - Connectivity initializer causes product hydration mismatch

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open the server-rendered Season Venue Planner in a
  browser and inspect React hydration. The server and first client render can
  disagree between `Servidor conectado` and `Solo lectura offline`.
- Impact: React discards and regenerates the product shell, violates the zero
  hydration-warning gate and can briefly present the wrong write state.
- Required correction: use one deterministic SSR/first-client snapshot and
  update actual browser connectivity only from an asynchronous mounted
  subscription; retain offline write denial and zero synchronous state updates
  in effects.
- Resolution: both SSR and first client render start connected; a cancellable
  microtask reads `navigator.onLine`, and subsequent browser events remain the
  only connectivity transitions.
- Regression evidence: fresh-browser hydration reports zero page errors, zero
  console errors, `Estado: Servidor conectado`, zero root overflow; focal lint
  and typecheck both pass.

### W9B-056 - Product route reports a client-rendered script warning

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: open the local Season Venue Planner in Next development
  mode and inspect console output after hydration.
- Impact: React reports that a script tag encountered inside a rendered
  component will not execute on the client. The source and ownership are not
  yet established, so it cannot be classified as Wave 9B product behavior.
- Required correction: identify the exact script owner and reproduce on an
  unchanged base route; fix only if Wave 9B introduced or exposed a reachable
  regression.
- Resolution: the warning was retained by the development browser after a hot
  refresh of the root layout; it does not reproduce in a fresh context on the
  Season Venue Planner or on the unchanged Mercado route.
- Regression evidence: a clean browser context reports no page errors and only
  the expected development HMR/React DevTools informational messages.

### W9B-057 - Next development server generates untracked agent files

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: start Next 16 development mode in the isolated Wave 9B
  worktree and inspect `git status`.
- Impact: framework-generated `AGENTS.md` and `CLAUDE.md` appear as untracked
  files and could be included accidentally in a product commit.
- Required correction: verify their Next-generated marker, remove only those
  two untracked artifacts and confirm the Wave 9B diff contains neither path.
- Resolution: both files contained the documented Next agent-rule marker and
  were removed individually without touching repository-owned instructions.
- Regression evidence: independent absence checks pass and `git status` lists
  only the intentional incident-ledger update.

### W9B-058 - Supabase branch-health poll reads the wrong JSON field

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: create the isolated Supabase branch and poll
  `branches get --output json` using only top-level `preview_project_status` or
  `status` fields.
- Impact: the poll reports an empty state for 30 bounded attempts even though
  branch creation returned successfully; no migration is attempted, but the
  staging gate cannot advance.
- Required correction: inspect the current CLI response shape, read its actual
  health field and retain a bounded wait before any schema operation.
- Resolution: health is now read from the credential-free `branches list`
  response, whose `preview_project_status` is the authoritative branch field.
- Regression evidence: the replacement branch reports `ACTIVE_HEALTHY`,
  `FUNCTIONS_DEPLOYED`, `with_data=false` and the exact Wave 9B Git branch.

### W9B-059 - Branch credential response was emitted by the CLI diagnostic

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: print `supabase branches get --output json` while
  diagnosing W9B-058 on the newly created, empty preview branch.
- Impact: the tool transcript receives ephemeral database and API credentials.
  They were not committed, copied into product files or exposed to a browser,
  but the branch must be treated as compromised and cannot be reused.
- Required correction: delete the empty branch, verify its absence, create a
  replacement with fresh credentials and suppress every later credential
  response; retain only redacted presence/type evidence.
- Resolution: the compromised empty branch was deleted before migration or
  data load; its replacement has new credentials and later retrievals suppress
  all secret-bearing output.
- Regression evidence: the old name is absent and the replacement is a healthy
  no-data branch linked only to Wave 9B.

### W9B-060 - Branch-create output includes a non-JSON prefix

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: pipe `supabase branches create --output json` directly
  into `jq` with CLI 2.107.0.
- Impact: branch creation completes, but the CLI prepends a human-readable
  `Created preview branch:` line and the evidence parser exits non-zero.
- Required correction: discover the created branch through the credential-free
  `branches list` response and use that endpoint for bounded health polling.
- Resolution: creation evidence is obtained only from the filtered branch list,
  so no parser depends on the CLI prefix.
- Regression evidence: the filtered response identifies exactly one healthy
  branch with the expected name, project reference, no-data state and Git link.

### W9B-061 - Direct preview database hostname is not resolvable locally

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: connect with the replacement branch's non-pooling URL
  immediately after it reports `ACTIVE_HEALTHY`.
- Impact: local DNS cannot resolve the direct `db.<preview-ref>` hostname, so
  the readback stops before any migration or data operation.
- Required correction: use the same branch's supplied Supavisor pooler URL,
  verify its embedded branch tenant before connecting, and continue only if a
  read-only ledger query succeeds.
- Resolution: later database access uses only the branch-specific Supavisor
  URL after validating its embedded preview-project reference; the direct host
  is not retried or treated as staging evidence.
- Regression evidence: the verified pooler accepts a read-only PostgreSQL
  query and reports the isolated branch ledger without exposing credentials.

### W9B-062 - Supabase Git branch stops at migration 10

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: read the healthy no-data branch through its verified
  pooler and compare migration history with the canonical repository.
- Impact: the branch reports `MIGRATIONS_FAILED`, ledger `10` and maximum
  `20260728191429` instead of baseline `220`; Wave 9B cannot be validated on a
  partial schema and no new migration has been applied manually.
- Required correction: capture the first exact migration diagnostic using the
  CLI against this disposable branch, determine whether it is a preexisting
  fresh-bootstrap incompatibility or a Wave 9B defect, and rebuild staging to
  the canonical 228-version schema before any synthetic E2E.
- Resolution: rollback-only replay located the exact preexisting failure in
  migration `20260728191804`: it references `pachanga_admin_invites`, which no
  earlier migration creates. Staging now uses the repository's signed baseline
  path on an isolated replacement branch.
- Regression evidence: the failed branch was deleted; the replacement reports
  exact version parity, ledger 228 and canonical schema hash `89ae...`.

### W9B-063 - Non-Git Supabase branch starts without product schema or ledger

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: create a healthy no-data Supabase branch without a Git
  association and query `supabase_migrations.schema_migrations` through its
  branch-verified Supavisor URL.
- Impact: the branch is isolated and healthy, but it contains neither the
  product schema nor the migration ledger, so Wave 9B cannot run until the
  repository's signed baseline and forward migrations are installed.
- Required correction: bootstrap only this verified ephemeral project from the
  hash-checked product baseline, record absorbed migration versions, apply the
  repository's incremental migrations in order and prove exact ledger `228`
  plus schema equivalence before loading any synthetic identity or fixture.
- Resolution: branch reads are delayed until deployment reaches a terminal
  state, then the settled prefix is reconciled through the signed baseline and
  exact repository migrations.
- Regression evidence: final staging reaches `228|20260830223014`, hash
  `89ae...`, and no synthetic fixture is loaded before that proof.

### W9B-064 - zsh reserves the diagnostic variable name `status`

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: wrap the transactional migration diagnostic in zsh and
  assign the command exit code to the shell variable named `status`.
- Impact: zsh rejects the read-only variable assignment after PostgreSQL has
  closed the rollback-only diagnostic connection, so no error text is retained
  and the Git-branch failure remains unexplained.
- Required correction: retain the same verified branch and rollback-only SQL,
  but capture the process code in a non-reserved variable and prove the target
  migration leaves its schema unchanged.
- Resolution: the wrapper now captures `exit_code`; PostgreSQL reports the
  first exact failure at migration `20260728191804`, where
  `public.pachanga_admin_invites` is absent.
- Regression evidence: the diagnostic exits non-zero while `pg_policy` remains
  unchanged at seven rows before and after the rollback-only connection.

### W9B-065 - Supabase CLI migration runner collides through branch pooler

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: after applying the signed baseline and repairing its 36
  absorbed versions on the verified non-Git branch, run `supabase migration up
  --include-all` through the branch's supplied Supavisor URL.
- Impact: the CLI stops before establishing the incremental migration stream
  with SQLSTATE `42P05` because prepared statement `lrupsc_1_0` already exists;
  the direct branch hostname remains unavailable from this environment.
- Required correction: prove the ledger stayed at 36, then apply every
  incremental file through `psql` in its own transaction and insert the exact
  migration version/name in that same transaction; stop on the first failure
  and require final ledger 228 plus repository/remote version equality.
- Resolution: staging uses credential-free `psql` connections, one transaction
  per migration plus ledger row, instead of the incompatible CLI runner.
- Regression evidence: all 192 incrementals apply in order and remote versions
  equal all 228 repository versions byte-for-byte as a sorted set.

### W9B-066 - psql variables are not interpolated inside `-c`

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: execute the first incremental migration and append its
  ledger row with `:'migration_version'` and `:'migration_name'` inside a
  separate `psql -c` argument.
- Impact: the migration body runs inside the intended transaction, but the
  ledger statement reaches PostgreSQL with the literal colon syntax and fails;
  connection teardown rolls back the entire first incremental migration.
- Required correction: verify ledger 36 and absence of the first incremental
  schema, constrain filename-derived values to the repository naming grammar,
  then use those validated literals in the same transaction and require exact
  ledger/schema parity after all 192 files.
- Resolution: version and migration name are first constrained to numeric and
  lowercase repository grammars, then inserted as validated literals.
- Regression evidence: the failed first attempt leaves ledger 36 and no first
  table; the corrected sequence ends at ledger 228 with exact schema parity.

### W9B-067 - Schema-hash command loses its resumable session identifier

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: start the remote normalized-schema hash with a 30-second
  yield, but return only stdout from the orchestration wrapper and omit the
  `exec_command` session identifier.
- Impact: the long-running `pg_dump` continues without a resumable handle, so a
  second comparison cannot safely start until the original process is located
  and terminated or observed to completion.
- Required correction: terminate the exact orphaned command tree, prove no
  schema writer was involved, and propagate every later long-running session
  identifier before waiting.
- Resolution: the read-only parent and children were stopped by exact PID and
  all later dump/bootstrap sessions propagate their session identifier.
- Regression evidence: process readback confirms the orphan absent; subsequent
  long operations are resumed to a terminal result rather than duplicated.

### W9B-068 - Branch database password appears in local process arguments

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: pass the credential-bearing branch URL directly as the
  final `pg_dump` argument, then inspect the local process table while the dump
  is still running.
- Impact: the ephemeral branch password appears in diagnostic process output.
  The branch contains schema and platform defaults only, with no synthetic
  identities or product data, but its credentials can no longer be trusted.
- Required correction: stop the dump, delete the affected no-data branch and
  the earlier failed Git branch, verify both absent, then create a fresh branch
  whose database tools receive the password only through `PGPASSWORD` and a
  credential-free connection URI; secret-bearing branch responses remain
  suppressed and no process/log/evidence may contain the new value.
- Resolution: both affected no-data branches were deleted; the active branch
  passes credentials through environment only and every process URI omits its
  password.
- Regression evidence: branch inventory reports the two old names absent and
  all later dumps/migrations complete without a secret-bearing argument.

### W9B-069 - zsh arithmetic cannot format a command-status expression

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: terminate the orphaned schema-hash parent and try to
  print its absence by embedding a command substitution and logical negation
  directly in a zsh arithmetic expansion.
- Impact: `TERM` is delivered before the formatting error, but the wrapper exits
  without durable confirmation that the parent and its dump children stopped.
- Required correction: use ordinary conditional control flow, verify the exact
  PIDs are absent from the process table and only then continue with branch
  retirement.
- Resolution: ordinary `if kill -0` control flow replaced arithmetic status
  formatting.
- Regression evidence: the parent reports `parent_alive=false` and no listed
  child PID remains.

### W9B-070 - Healthy branch still runs repository migrations in background

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: create a no-data branch without `--git-branch`, wait only
  for `preview_project_status=ACTIVE_HEALTHY` while its deployment status is
  still `CREATING_PROJECT`, and begin the baseline bootstrap.
- Impact: Supabase concurrently creates the ten pre-failure migration rows, so
  the baseline succeeds but the explicit absorbed-ledger insert collides on
  `20260728051437`; staging cannot claim a deterministic bootstrap while a
  platform migration job is still active.
- Required correction: delete the no-data branch, recreate it, wait for both
  database health and a terminal deployment status, verify the expected failed
  prefix exactly, and only then apply the baseline plus missing absorbed and
  incremental versions with no concurrent platform writer.
- Resolution: the final branch is not touched at `CREATING_PROJECT`; bootstrap
  begins only after `ACTIVE_HEALTHY/FUNCTIONS_DEPLOYED` and exact ten-version
  prefix readback.
- Regression evidence: no duplicate ledger insertion or concurrent schema
  change occurs during the final 228-version bootstrap.

### W9B-071 - PostgreSQL resolves an absent ledger relation inside `CASE`

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: query `to_regclass` in a `CASE` arm while the alternate
  arm contains a static subquery against
  `supabase_migrations.schema_migrations` on a fresh branch.
- Impact: PostgreSQL resolves the absent relation while planning the statement,
  so the read-only probe fails instead of returning `ABSENT`.
- Required correction: query relation existence first and only issue the ledger
  query when that independent result is present; preserve the branch unchanged.
- Resolution: relation existence and ledger contents are now separate queries.
- Regression evidence: fresh-branch probes return an explicit prefix without a
  planner error and perform no write.

### W9B-072 - Remote `pg_dump` returns an empty schema stream

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: export `public` and `private` through the branch's
  credential-free Supavisor URI and hash the normalized stdout.
- Impact: migration-version parity, flags and all 12 RLS markers pass, but the
  dump stream hashes to SHA-256 `e3b0...`, proving that schema equivalence has
  not actually been established even though `pg_dump` exits successfully.
- Required correction: capture byte count and redacted diagnostics without
  exposing credentials, determine whether Supavisor filtering or dump options
  caused the empty stream, remove all temporary dump files, and establish
  equivalence through a non-empty canonical schema export before staging E2E.
- Resolution: the dump contained 6,553,848 bytes; Node had split on the literal
  `\\n`, causing the leading comment filter to discard the whole stream. It now
  uses a real newline regular expression and rejects empty input explicitly.
- Regression evidence: the corrected remote export is non-empty and hashes
  exactly to the fresh canonical `89ae...` value.

### W9B-073 - Diagnostic cleanup command is rejected before execution

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: prepare two `mktemp` paths and register a trap containing
  `rm -f` before running the redacted `pg_dump` diagnostic.
- Impact: the command sandbox rejects the process at creation time; no
  temporary file or database command is created, but W9B-072 remains open.
- Required correction: use verified individual `unlink` operations, prove both
  temporary paths absent and retain only byte counts plus redacted stderr.
- Resolution: diagnostics use individually verified `unlink` calls and no
  prohibited recursive/force deletion.
- Regression evidence: final comparison reports temporary files removed and a
  follow-up namespace scan returns zero Wave 9B dump paths.

### W9B-074 - macOS `unlink` accepts only one temporary path

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after a successful 6,553,848-byte schema export, invoke
  one macOS `unlink` command with both temporary paths.
- Impact: `unlink` prints its usage and the diagnostic exits before proving
  cleanup; the files contain schema only and no rows or branch credentials, but
  they must not remain on disk.
- Required correction: locate only the freshly created `w9b-pgdump-*` paths,
  unlink each one separately, prove the namespace is empty, and recalculate the
  normalized hash with a real newline separator rather than the over-escaped
  literal that caused W9B-072.
- Resolution: cleanup iterates one exact temporary path per `unlink` call.
- Regression evidence: no `w9b-pgdump-*` file remains and later dump comparison
  also removes all five of its temporary files.

### W9B-075 - zsh loop variable `path` overwrites executable search paths

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: iterate temporary files with `read -r path` in zsh and
  call `unlink` inside the loop.
- Impact: zsh binds lowercase `path` to `PATH`; after the first unlink, later
  `find`, `wc` and `tr` commands are no longer resolvable, so cleanup evidence
  stops with at most one schema file remaining.
- Required correction: start a fresh shell, use a non-special variable name,
  unlink every exact Wave 9B dump path and prove zero remain.
- Resolution: cleanup loops use `file_path`, never zsh's special `path` array.
- Regression evidence: executable lookup remains available and zero targeted
  temporary files remain.

### W9B-076 - Remote non-empty schema hash differs from local certification

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: normalize the 6.55 MB remote `public`/`private` dump with
  the same line filter as the local Wave 9B migration runner and compare its
  SHA-256 to the certified local hash.
- Impact: remote hash `34cc...` differs from local `89ae...`; ledger 228, exact
  version parity, flags and RLS counts are insufficient to prove full schema
  equivalence, so authenticated staging remains blocked.
- Required correction: compare canonical schema contracts object-by-object,
  distinguish harmless server/dump-version serialization from actual DDL drift,
  and proceed only after either exact contract equality or a corrected remote
  schema followed by a regression hash.
- Resolution: fresh-local versus remote diff isolated a partial-prefix bootstrap
  defect; staging was rebuilt from canonical tables instead of waiving it.
- Regression evidence: remote and freshly certified schemas now share exact
  SHA-256 `89ae7c302759827bcb58d747eec4ff538422548c3792b105d8d4ccf454141c26`.

### W9B-077 - Long-lived local database ledger masks stale function bodies

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: compare the remote 228-schema dump against the default
  local Supabase database, which also reports ledger 228.
- Impact: the 698-line diff shows the local database retains older Wave 9B
  function bodies and signatures while the remote branch reflects current
  migration source; migration count alone falsely suggests schema parity and
  the previously quoted hash cannot be reused as a live-instance contract.
- Required correction: run the canonical fresh/upgrade database runner from the
  current committed migration set, use its newly generated schema hash as the
  authoritative expected value, and compare the remote branch to that fresh
  result rather than to the long-lived local service database.
- Resolution: the canonical runner rebuilt two disposable local databases from
  current source and independently regenerated `89ae...`.
- Regression evidence: runner reports schema equivalence, flags born OFF,
  canonical lifecycle PASS and cleanup PASS; long-lived local state is excluded
  from staging authority.

### W9B-078 - Baseline over partial prefix omits canonical team-code uniqueness

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: apply the signed baseline over the settled ten-migration
  branch prefix and compare it to a database built from a genuinely empty
  product schema.
- Impact: only 49 dump lines differ, but the remote branch preserves earlier
  column order and lacks `pachanga_groups_team_code_key`; `CREATE TABLE IF NOT
  EXISTS` cannot repair that constraint, so the branch is not schema-equivalent
  despite having all 228 ledger rows.
- Required correction: on this verified no-data branch only, recreate the
  product schemas from an empty canonical state, rerun baseline plus all 192
  incrementals and prove exact dump hash, unique constraint, ledger, flags and
  RLS before loading synthetic QA.
- Resolution: the final branch drops only its three prefix tables before the
  baseline creates canonical table definitions.
- Regression evidence: `pachanga_groups_team_code_key` exists as a unique
  constraint, schema hash is exact and all 12 Wave 9B relations have RLS.

### W9B-079 - Full product-schema reset exceeds branch lock capacity

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: drop `private`, `public` and the migration schema in one
  transaction on the fully built 228-version ephemeral branch.
- Impact: cascading through 1,282 dependent objects exceeds
  `max_locks_per_transaction`; PostgreSQL aborts and rolls back the reset before
  any baseline or ledger reconstruction begins.
- Required correction: delete the unchanged no-data branch, recreate its
  settled ten-migration prefix and drop only the three partial product tables
  there, before the later dependency graph exists; then bootstrap canonically
  and require the exact fresh-schema hash.
- Resolution: the aborted 1,282-object reset was not retried; a new no-data
  branch drops exactly three prefix tables before dependency expansion.
- Regression evidence: the small transaction succeeds, final ledger is 228 and
  canonical hash/constraint/RLS/flags all pass.

### W9B-080 - Authenticated staging E2E has an extra closing parenthesis

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run
  `node --check tests/season-venue-allocation-v1-staging-e2e.mjs` immediately
  after adding the authenticated two-device staging harness.
- Impact: Node stops at the synthetic-role setup call, before any staging
  connection, identity, flag or product mutation can occur.
- Required correction: remove only the unmatched parenthesis, rerun the exact
  syntax check and retain this incident as a permanent regression record.
- Resolution: the five direct `runSql` calls now close only their own call;
  nested `JSON.parse` and `Number` expressions retain their second parenthesis.
- Regression evidence: the exact `node --check` reproducer exits zero under
  Node `24.16.0`, before staging credentials are loaded.

### W9B-081 - Canonical Club owner guard rejects the inherited fixture order

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: apply
  `tests/season-venue-allocation-v1-staging-dataset.sql` to the clean 228-ledger
  branch using `psql -v ON_ERROR_STOP=1`.
- Impact: the inherited Wave 9A fixture inserts `pachanga_clubs` before its
  owner membership; the current canonical trigger raises
  `CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED` before any Wave 9B RPC is called.
- Required correction: adapt staging setup without weakening or disabling the
  product guard, then rerun against a newly isolated canonical branch.
- Resolution: the complete inherited fixture and Wave 9B extension now execute
  inside one explicit transaction, so the deferred Club owner membership guard
  observes the canonical membership before commit without ever being disabled.
- Regression evidence: the unchanged guard accepts all three synthetic Clubs
  and the committed topology reports exactly three Clubs and twelve teams.

### W9B-082 - Staging dataset did not enclose inherited fixtures in a transaction

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: inspect the branch after W9B-081 stops `psql` with
  `ON_ERROR_STOP`; earlier inherited fixture statements used normal autocommit.
- Impact: rows preceding the rejected Club insert may remain committed, so the
  branch can no longer provide a clean authenticated staging baseline.
- Required correction: retire the affected branch, recreate the exact 228-ledger
  schema and wrap the complete seed in one transaction so any later failure has
  a mandatory zero-row readback.
- Resolution: `season-venue-allocation-v1-staging-dataset.sql` owns one
  `BEGIN/COMMIT` around every included fixture, platform activation and Wave 9B
  row; `ON_ERROR_STOP` closes the failed connection and PostgreSQL rolls back.
- Regression evidence: three later guard failures each produced zero groups,
  Clubs, profiles, venues, competitions, matches and setup receipts before the
  corrected dataset committed its exact topology.

### W9B-083 - Replacement no-data branch has no migration relation

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: after the replacement branch reports
  `ACTIVE_HEALTHY/FUNCTIONS_DEPLOYED`, query
  `supabase_migrations.schema_migrations` through its verified pooler.
- Impact: PostgreSQL reports that the relation does not exist; no schema or data
  mutation has occurred, but a prefix-based bootstrap cannot be assumed.
- Required correction: treat relation absence as the canonical empty starting
  state, verify the signed baseline hash, install all absorbed ledger versions
  and incrementals in order, then require ledger 228 and schema hash parity
  before retrying the transactional dataset.
- Resolution: the guarded bootstrap waited for the asynchronous ten-version
  prefix, verified all three partial tables were empty, replaced only those
  tables with the signed baseline and installed every remaining migration.
- Regression evidence: staging reports exact ledger `228`, last version
  `20260830223014`, all repository versions in order and no product rows before
  the dataset is loaded.

### W9B-084 - Empty-ledger branch still hashes to the partial-prefix schema

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: install the signed baseline, 36 absorbed versions and
  all 192 incrementals on the replacement branch whose migration relation was
  absent, then normalize `public`/`private` with the canonical dump filter.
- Impact: ledger reaches exact 228 but remote SHA-256 is `34cc...`, not the
  certified fresh-schema `89ae...`; authenticated staging remains blocked and
  no synthetic dataset has been loaded.
- Required correction: inspect whether product prefix tables existed despite
  the absent ledger, rebuild from genuinely canonical table definitions if so,
  and require exact hash parity before any fixture is retried.
- Resolution: delayed branch initialization was treated as an asynchronous
  ten-version prefix rather than an empty schema; only its three zero-row
  product tables were rebuilt before dependency expansion.
- Regression evidence: the remote normalized `public`/`private` dump equals
  canonical SHA-256
  `89ae7c302759827bcb58d747eec4ff538422548c3792b105d8d4ccf454141c26`,
  `pachanga_groups_team_code_key` exists and all 12 Wave 9B public relations
  have RLS enabled.

### W9B-085 - Supabase CLI prepared statements collide on the staging pooler

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: after replacing the delayed ten-version branch prefix
  with the signed baseline and reconciling the 36 absorbed versions, invoke
  `supabase db push --include-all` through the branch pooler.
- Impact: the CLI aborts before the first incremental migration with PostgreSQL
  `42P05` because prepared statement `lrupsc_1_0` already exists. The baseline
  transaction and absorbed ledger are valid, no synthetic rows exist, and the
  branch remains intentionally incomplete at version 36.
- Required correction: keep the guarded non-production target checks, apply
  each repository incremental in an explicit transaction over `psql` without
  prepared statements, append its exact ledger row atomically, then prove all
  228 versions and the canonical schema hash before seeding staging.
- Resolution: the staging bootstrap now uses credential-redacted `psql`
  transactions for every missing migration and atomically appends the matching
  version/name to `supabase_migrations.schema_migrations`; the one historical
  file with its own transaction wrapper is normalized before execution.
- Regression evidence: the exact reproducer resumes safely from ledger 36,
  reaches 228/228 with hash `89ae7c...`, leaves its temporary transport clean
  and passes focal syntax plus ESLint checks.

### W9B-086 - League Private Beta guard blocks the synthetic competition seed

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: execute the fully transactional Wave 9B staging dataset
  against the certified 228-schema while every product flag is correctly born
  OFF.
- Impact: the canonical Club/player/venue seed reaches the first League insert,
  then `private.pachanga_league_private_beta_guard_competition_v1()` raises
  `LEAGUE_PRIVATE_BETA_CREATION_DISABLED`. PostgreSQL aborts the enclosing
  transaction, so no partial synthetic topology is allowed to survive.
- Required correction: establish the minimum synthetic platform/competition
  feature context through the existing server-authoritative flag contract for
  dataset setup, never disable the trigger, rerun the full seed and require both
  exact topology and cleanup/readback evidence.
- Resolution: a dedicated `.test` platform actor is created inside the dataset
  transaction and every dependency transition is confirmed through the
  canonical platform RPCs before Wave 9B adds its Tournament/season objects.
- Regression evidence: the League guard remains installed; the final seed
  commits one private League, one explicitly keyed private Tournament and zero
  public discovery.

### W9B-087 - League beta creation cannot bypass prerequisite product layers

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: enable Foundation through its canonical platform RPC,
  then request only `league_private_beta_enabled` and
  `league_private_beta_creation_enabled` through the League beta flag RPC.
- Impact: the authoritative settings update is rejected by
  `pachanga_comp_foundation_private_beta_creation_check` because participation,
  scheduling and operational prerequisites remain OFF. The enclosing dataset
  transaction rolls back flags, receipts and every synthetic row to zero.
- Required correction: invoke the existing private-beta activation/bundle
  command that enables the full supported dependency set in server-defined
  order, retain public discovery OFF, and prove the fixture can no longer
  manufacture an invalid partial activation.
- Resolution: staging follows the established product activation sequence:
  Foundation, R4A participation, R4B scheduling, R4C match operations and R4D
  exceptions are confirmed in order before League creation is enabled.
- Regression evidence: all authoritative RPCs accept monotonic revisions, the
  private-beta creation constraint passes, and public registration/calendar,
  standings and exception status remain OFF.

### W9B-088 - Early beta activation retroactively changes legacy fixture rules

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: enable the complete R4A/R4B/R4C/R4D dependency stack and
  League beta before including the inherited canonical League fixture.
- Impact: a pre-beta competition with its historical visibility is evaluated
  under the new global private-beta guard and fails with
  `LEAGUE_PRIVATE_BETA_VISIBILITY_REQUIRED`. The transaction rolls back the
  synthetic authority, all flag receipts and every inherited row.
- Required correction: load the immutable legacy graph under its original
  feature state, then perform the server-authoritative dependency activation
  before adding Wave 9B-specific competition objects; do not rewrite historical
  fixture semantics merely to satisfy a later global gate.
- Resolution: the inherited R4/R5/Wave 9A fixture loads first under its original
  gates; the dedicated synthetic actor and Wave 9B activation follow without
  modifying any historical competition visibility or schedule time.
- Regression evidence: the public legacy League remains intact, the new
  Tournament is private and the staging topology reaches 50 CanonicalMatches.

### W9B-089 - Referee Assignments must pause before a League beta flag command

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: load the inherited Wave 9A/R4D/referee graph, which ends
  with the referee assignment private beta active, then invoke the League beta
  flag RPC even when retaining `enabled=true` and `creationEnabled=false`.
- Impact: the server rejects the command with
  `REFEREE_ASSIGNMENTS_NOT_AVAILABLE_IN_LEAGUE_BETA`; transaction rollback again
  leaves the branch at zero product rows.
- Required correction: avoid the redundant first League beta mutation and use
  the Referee Assignment platform RPC to pause assignments before enabling
  League creation; the authenticated E2E may reactivate assignments later when
  it tests the explicit referee flow.
- Resolution: the redundant beta mutation was removed; after R4 dependencies
  are confirmed, `command_pachanga_referee_assignment_beta_admin_v1` pauses both
  assignment gates before the final League creation command, then reactivates
  both gates through that same authority for the explicit referee E2E.
- Regression evidence: the seed commits with League creation ON, public
  discovery OFF and Referee Assignments/private beta ON at revision 4; no direct
  settings update performs either transition.

### W9B-090 - Deterministic staging dataset gives a low-level duplicate on replay

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: rerun the one-shot deterministic staging dataset after
  its first successful commit in the same disposable branch.
- Impact: the first inherited Auth identity collides with `users_pkey`, which is
  technically correct but obscures that this seed requires a zero-row branch;
  the retry transaction aborts without altering the already valid topology.
- Required correction: add an early canonical zero-topology preflight with a
  stable Wave 9B error, retain fixed deterministic IDs, and validate any
  post-seed flag adjustment through its RPC rather than replaying fixture rows.
- Resolution: the dataset now checks the core product topology before including
  any fixture and raises `WAVE9B_STAGING_DATASET_REQUIRES_EMPTY_BRANCH`; the
  pending referee transition was confirmed separately through its canonical
  admin command.
- Regression evidence: a replay against the committed dataset is rejected at
  the preflight with the stable Wave 9B error, leaves every count unchanged and
  reports Referee Assignments/private beta both ON at revision 4.
