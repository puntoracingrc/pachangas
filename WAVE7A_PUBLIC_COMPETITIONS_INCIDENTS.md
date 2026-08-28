# Wave 7A Public Competitions Incident Ledger

Permanent incident log for Public Competition Discovery, Registration Requests,
R6C post-release index hardening and Demo World V2.7.

Every defect discovered during implementation, simulation, staging or release
must be recorded here before correction as one of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

Resolved incidents must include the original scenario, correction and a
regression result marked `FIXED / REGRESSION_VERIFIED`.

## Incidents

### W7A-ENVIRONMENT-001 - Dynamic Next route paths were not quoted

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: inspect the existing registration, calendar, standings and
  tournament pages under `app/competiciones/[competition]`.
- Observed: zsh expanded the square-bracket route segment before `sed` ran and
  returned `no matches found` for all four files.
- Impact: no file, test, database or production state changed; the command
  produced no valid audit evidence.
- Planned correction: pass every dynamic Next route path as a quoted literal.
- Regression plan: read all four source files successfully with exit code zero.
- Correction: every path containing `[competition]` was passed as a
  single-quoted shell literal.
- Regression: registration, calendar, standings and tournament page sources
  were read successfully with exit code zero.

### W7A-PRODUCT-001 - Fixture rebuild reused one server sequence

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: rebuild two or more public fixture read models after one
  canonical Competition event.
- Observed: the first implementation reused the triggering event sequence for
  every fixture while the derived table requires a unique monotonic server
  sequence.
- Impact: a multi-fixture rebuild could fail with a unique violation and leave
  the public calendar stale inside the transaction.
- Planned correction: allocate one authoritative sequence per derived fixture
  row while retaining the source revision inside its canonical payload.
- Regression plan: rebuild at least three fixtures in one transaction and
  assert distinct ordered sequences and a convergent second rebuild.

### W7A-PRODUCT-002 - Bracket projection retained internal lineage identifiers

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish a Tournament whose canonical R6C bracket read
  model contains source slots, reservations and administrative health fields.
- Observed: the first Wave 7A projection removed only top-level health and
  would have retained source-node and reservation identifiers.
- Impact: no PII was exposed, but the public contract would reveal internal
  replacement/dependency structure forbidden by the Wave 7A privacy contract.
- Planned correction: construct a dedicated bracket allowlist from the R6C
  public snapshot and omit sources, reservations IDs, templates, rule revision
  identifiers, health and administrative lineage.
- Regression plan: seed sentinel private/internal keys and assert none survive
  in the public bracket RPC.

### W7A-ENVIRONMENT-002 - Diagnostic command rejected unsafe cleanup syntax

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: clone the local schema into an isolated `wave7a_dev`
  database and apply the first four forward-only migrations.
- Observed: command execution was rejected before launch because the combined
  script contained `rm -f` for temporary diagnostic logs.
- Impact: no command in the script ran and no database or file changed.
- Planned correction: run the isolated database steps without destructive file
  syntax and remove each known temporary artifact with `unlink` after use.
- Regression plan: complete the four-migration apply and verify the product
  database remains unchanged.

### W7A-ENVIRONMENT-003 - Schema clone contained a non-portable role setting

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: restore a schema-only dump of the local Supabase database
  into isolated database `wave7a_dev`.
- Observed: restore stopped at a database-role `log_min_messages` setting that
  the local Supabase `postgres` role is not permitted to set in a cloned DB.
- Impact: only the disposable `wave7a_dev` database was partially populated;
  the source product database and repository were unchanged.
- Planned correction: regenerate a diagnostic-only dump with the non-portable
  environment setting removed, recreate `wave7a_dev`, and restore from zero.
- Regression plan: schema restore and all Wave 7A migrations complete with
  `ON_ERROR_STOP=1` in the isolated database.

### W7A-PRODUCT-003 - Waitlist audit allowed only one row per reorder operation

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: move one waitlisted Team from position four to position
  one while preserving every affected request revision.
- Observed: `operation_id` was globally unique in the request revision table,
  although one reorder operation legitimately changes several requests.
- Impact: complete versioned ordering could not be recorded atomically.
- Planned correction: make idempotency unique per `(operation_id, request_id)`
  while retaining `(request_id, request_revision)` as the canonical history.
- Regression plan: reorder at least four requests, assert one audit row for
  each affected request, stable positions and idempotent replay.

### W7A-PRODUCT-004 - Command variables shadowed the persisted reason code

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute a registration transition such as message update,
  withdraw, waitlist, accept or reject through the new authoritative RPC.
- Observed: the first implementation named the PL/pgSQL variable `reason_code`
  while update statements also addressed the `reason_code` column. PostgreSQL
  can reject the statement as ambiguous at runtime, or make the intended source
  unclear even though function creation succeeds.
- Impact: an otherwise valid registration command could abort before producing
  its canonical receipt and snapshot.
- Planned correction: rename the command-local value to `reason_code_value` and
  reference it explicitly in every write and command receipt.
- Regression plan: execute every affected transition against a disposable
  database and assert the requested reason is persisted and replay remains
  idempotent.

### W7A-PRODUCT-005 - RPC permission closure preceded two RPC declarations

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: review the complete command migration before applying it
  to a clean 176-schema clone.
- Observed: the first append placed the final revoke/grant/comment block after
  an early helper instead of after both public command declarations.
- Impact: PostgreSQL would stop on a missing function signature before the
  migration completed; no database was changed by this draft.
- Planned correction: keep the functions where they are validly declared and
  move the permission closure to the physical end of the migration.
- Regression plan: apply the complete migration with `ON_ERROR_STOP=1` from a
  fresh clone and assert the exact authenticated/anon execute matrix.

### W7A-ENVIRONMENT-004 - Schema-only clone omitted required product seed rows

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the established Competition Configuration Center
  fixture after applying Wave 7A to the disposable schema clone.
- Observed: the legacy private-beta grant RPC reached a `FOREACH` whose source
  catalog was null because `pg_dump --schema-only` intentionally copied tables
  but not the canonical product seed rows installed by migrations.
- Impact: functional command QA cannot use that schema-only clone as if it were
  a full migration bootstrap. The isolated database contains no real data and
  production remains untouched.
- Planned correction: use the repository's migration bootstrap harness, or
  copy only the explicitly required non-user seed catalogs into a new
  disposable database, then rerun the fixture.
- Regression plan: complete the canonical fixture and all Wave 7A command
  transitions with `ON_ERROR_STOP=1` without copying users or product data.

### W7A-SIMULATION-001 - Bootstrap runner conflated ledger versions and files

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: build an isolated database from the consolidated baseline
  plus every migration after it, while certifying the production ledger 176 to
  Wave 7A ledger 183 upgrade.
- Observed: the initial runner expected 175 incremental files after the
  baseline, but 36 historical versions are absorbed by that baseline, leaving
  140 incremental pre-Wave files. It failed before creating a database.
- Impact: no schema, data or repository state outside the new test changed;
  the reported logical ledger and physical bootstrap file count were mixed.
- Planned correction: assert 176 logical pre-Wave migration names separately
  from 140 post-baseline files, then report both values explicitly.
- Regression plan: complete both upgrade and fresh bootstrap paths and prove
  byte-equivalent normalized product schemas.

### W7A-PRODUCT-006 - Flag command operation parameter shadowed ledger column

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: activate the safe Wave 7A flags through the platform RPC
  during the first full functional bootstrap.
- Observed: the receipt lookup compared `ledger.operation_id = operation_id`,
  and PL/pgSQL correctly rejected the unqualified parameter as ambiguous.
- Impact: no flag could be activated; the transaction and disposable database
  were rolled back and removed by the runner.
- Planned correction: copy the public parameter into a distinctly named local
  value and use that value for locks, replay, response and audit writes.
- Regression plan: activate, replay and reject a conflicting flag operation in
  the full fresh/upgrade suite.

### W7A-SIMULATION-002 - Public hub test used a non-existent RPC alias

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: read the newly published Competition as an anonymous user
  during the full functional bootstrap.
- Observed: the regression called
  `get_pachanga_public_competition_hub_v1(text)`, while the implemented and
  granted canonical hub RPC is `get_pachanga_public_competition_v1(text)`.
- Impact: the test stopped before exercising privacy, registration and
  waitlist flows; no product or disposable data survived the runner cleanup.
- Planned correction: call the canonical RPC in both anonymous hub checks
  without adding a redundant public alias.
- Regression plan: complete the anonymous hub and privilege checks in both the
  upgrade and fresh-bootstrap schemas.

### W7A-SIMULATION-003 - Tabular sitemap was assigned directly to JSON

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: verify that a reviewed public Competition appears in the
  anonymous sitemap.
- Observed: the regression assigned the table-returning sitemap RPC directly
  to a `jsonb` variable, causing PostgreSQL to parse a composite row as JSON.
- Impact: the suite stopped at the sitemap assertion before later flows; the
  disposable transaction and database were removed.
- Planned correction: aggregate the returned rows explicitly with `to_jsonb`
  and retain the same slug assertion.
- Regression plan: verify the indexable slug through the actual tabular RPC in
  both bootstrap paths.

### W7A-SIMULATION-004 - Directory test expected private indexing metadata

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove that an approved public Competition is indexable.
- Observed: the test expected an `isIndexable` property inside the safe public
  Competition snapshot, although indexability is an internal read-model column
  enforced by the directory query and sitemap RPC.
- Impact: a valid public projection failed the test despite appearing in both
  discovery and sitemap results; no runtime data survived cleanup.
- Planned correction: assert the authoritative read-model column directly and
  keep the external directory and sitemap assertions independent.
- Regression plan: prove internal indexability and public discoverability
  without leaking internal indexing metadata into the public snapshot.

### W7A-ENVIRONMENT-005 - Cleanup targeted a protected transient backend

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: remove both disposable databases after the complete Wave
  7A suite had already passed.
- Observed: cleanup called `pg_terminate_backend` for every backend attached to
  the temporary database and encountered a transient Supabase-owned protected
  process. The product assertions had passed, but the runner exited non-zero.
- Impact: one empty disposable database remained locally with connections
  disabled; the product database and repository data were not modified.
- Planned correction: terminate only ordinary client backends, let PostgreSQL
  manage its own background processes, and unlink the known dump artifact.
- Regression plan: rerun the complete suite and assert that both generated
  database names and the exact temporary dump are absent after exit.

### W7A-PRODUCT-007 - Official-result refresh ignored active match states

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: publish an `OfficialResultDecision` for a scheduled or
  result-pending Competition match while anonymous clients read its calendar.
- Observed: the source-refresh trigger searched the canonical match only among
  contexts whose status was `lab_bound`. Operational matches normally advance
  through scheduled, ready, played, result_pending and official states.
- Impact: a valid official result could commit without rebuilding the public
  fixture projection, leaving public clients on a stale result until another
  source mutation happened.
- Planned correction: resolve the Competition through the decision's persisted
  `competition_match_context_id`, independent of lifecycle state.
- Regression plan: publish an official decision for a non-lab context while a
  public reader is active, then assert the final public snapshot contains the
  authoritative score and no private evidence.

### W7A-PRODUCT-008 - Result refresh ran before the active decision pointer moved

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: the canonical result command inserts an official decision
  and then points the match sheet to that decision in the same transaction.
- Observed: Wave 7A refreshed only after the decision insert. At that instant
  `active_official_decision_id` still referenced no decision or the superseded
  one, and match-sheet changes did not trigger a second rebuild.
- Impact: public results could remain pending or show a superseded score after
  the authoritative transaction committed.
- Planned correction: treat the match sheet's canonical decision pointer as a
  refresh source and resolve its Competition through the context ID.
- Regression plan: update the active pointer after inserting a decision and
  assert public readers converge to exactly that decision, including the same-
  transaction case.

### W7A-PRODUCT-009 - Archive and registration submit could both commit

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: a Team submits a registration request while the platform
  archives the same published Competition at the same revision.
- Observed: both commands serialized on the publication row but could both
  commit when submission won first, because submission creates a separate
  aggregate and archive did not check active requests.
- Impact: an archived Competition could retain a newly confirmed submitted
  request, producing two successful receipts for an incompatible race.
- Planned correction: make archive fail explicitly while submitted,
  under-review or waitlisted requests exist. If archive wins first, submit is
  rejected by lifecycle/revision; if submit wins first, archive is rejected.
- Regression plan: race both commands repeatedly and require exactly one
  winner plus a final state with no active request on an archived publication.

### W7A-SIMULATION-005 - Result race forged an incomplete generated context

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prepare a minimal canonical match for the public-result
  concurrency test.
- Observed: the fixture labelled its context `COMPETITION_GENERATED` without the
  schedule item and source binding required by that origin contract. The R6C
  relation guard correctly rejected it.
- Impact: the result/read race did not start; no fixture data survived cleanup.
- Planned correction: mark this isolated context as `LEGACY_LAB`, the supported
  source for a deliberately schedule-free diagnostic context.
- Regression plan: run the decision/pointer transaction through the real Wave
  7A refresh triggers and assert final public convergence.

### W7A-SIMULATION-006 - Publish/suspend assertion omitted the specific state code

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: race platform publication against suspension from the
  approved state.
- Observed: suspension correctly lost with
  `PUBLICATION_SUSPEND_STATE_INVALID`, but the assertion allowed only a generic
  moderation-state label or stale revision.
- Impact: a correct one-winner result was reported as a test failure; all
  disposable databases were still removed.
- Planned correction: accept the canonical suspend-state conflict alongside a
  stale revision.
- Regression plan: rerun the complete nondeterministic race matrix.

### W7A-SIMULATION-007 - Representative scale referenced an actor absent from the fixture

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: seed ten registration requests per Competition for the
  100,000-row representative-volume check.
- Observed: request ten referenced `wave7a-team-10`, while the reusable actor
  fixture intentionally creates Teams zero through nine and reserves user ten
  for platform administration.
- Impact: the volume run would stop on a foreign-key violation before measuring
  product queries; no persistent database was affected.
- Planned correction: create Team ten and its owner membership only inside the
  scale transaction, keeping the shared functional fixture unchanged.
- Regression plan: complete the 100,000-request run, verify all thresholds and
  prove the transaction rollback leaves zero scale Competitions behind.

### W7A-SIMULATION-008 - Scale-only actor used obsolete membership columns

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: add the missing tenth Team only inside the representative
  scale transaction.
- Observed: the first draft used obsolete generic names (`version` and
  `status`) instead of the canonical group columns (`payload_revision` and
  `display_name`). Static review caught it before execution.
- Impact: without correction the disposable scale fixture would fail during
  setup and never reach product measurements; no database was changed.
- Planned correction: mirror the exact insert contract used by the shared Wave
  7A actor fixture.
- Regression plan: bootstrap the disposable database and complete the scale
  transaction with the scale-only Team accepted by all canonical constraints.

### W7A-SIMULATION-009 - PL/pgSQL threshold comparison parsed an ungrouped CASE

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: reject a representative-volume result whose p95 exceeds
  the metric-specific objective.
- Observed: PL/pgSQL parsed the ungrouped `CASE` following the comparison as an
  incomplete procedural expression and stopped at the first `WHEN`.
- Impact: all representative rows loaded, but threshold certification and the
  final summary did not run. The disposable database was still deleted.
- Planned correction: parenthesize the scalar `CASE` expression explicitly.
- Regression plan: rerun the complete load and require both threshold checks
  and rollback verification to pass.

### W7A-SIMULATION-010 - Scale writes rebuilt two directly seeded results as pending

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: measure registration acceptance and waitlist reorder after
  directly seeding 100,000 public fixture projections with official scores.
- Observed: those writes correctly rebuilt the affected Competitions from
  canonical sources. Competitions 9,999 and 10,000 had no canonical official
  decision behind their synthetic projections, so twenty fixtures converged to
  pending instead of remaining official.
- Impact: the final count was not 100,000 even though the read path itself was
  coherent; the prior seed violated the server-authoritative test contract.
- Planned correction: seed canonical match sheets and official decisions for
  the two write-measurement Competitions, point each sheet at its decision and
  rebuild through the production read-model function before timing.
- Regression plan: require all 100,000 public results to remain official after
  the measured writes and then prove the entire transaction rolls back.

### W7A-ENVIRONMENT-006 - Isolated worktree had no installed TypeScript binary

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run the focal typecheck immediately after adding the
  public integration layer.
- Observed: the isolated worktree had no `node_modules`, so the package script
  stopped with `tsc: command not found` before analyzing source code.
- Impact: no code verdict was produced and no product state changed.
- Planned correction: run the contract-required `npm ci` in the isolated
  worktree, then repeat the same typecheck.
- Regression plan: require `npm run typecheck` to execute the repository's
  pinned TypeScript compiler successfully.

### W7A-PRODUCT-010 - Public command route imported the JSON normalizer from the wrong module

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compile the new server-authoritative public command API.
- Observed: `publicCompetitionRecord` was imported from the API helper, while
  it is exported by the product contract.
- Impact: the application could not typecheck or build; no runtime or database
  state was affected.
- Planned correction: import the normalizer directly from the canonical public
  competition contract.
- Regression plan: repeat the full TypeScript check and require zero errors.

### W7A-PRODUCT-011 - Category initialization recreated the Realtime subscription

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: open Configuration Center for a Competition whose public
  publication has not been prepared yet.
- Observed: the initial read selected the first category and changed a state
  value captured by the `load` callback. That recreated the callback and the
  effect that owns the Realtime channel, causing an unnecessary unsubscribe,
  subscribe and canonical read.
- Impact: duplicate initial traffic and avoidable subscription churn on the
  publication surface; no authoritative state was changed.
- Planned correction: initialize the category through a functional state
  update so `load` depends only on the Competition identifier.
- Regression plan: typecheck and add a product contract assertion that the
  callback dependency list does not contain mutable form state.

### W7A-PRODUCT-012 - Control Center perimeter errors lost their HTTP semantics

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: call the new public-Competition platform endpoint without
  a valid platform session, capability, same-origin header or admin marker.
- Observed: the route's SQL-code mapper did not yet recognize the typed English
  errors emitted by the shared platform perimeter. Authentication could become
  a generic 500 and an invalid origin could become a 400.
- Impact: access remained denied, but clients received the wrong status and an
  ambiguous failure contract.
- Planned correction: preserve 401 for missing/invalid sessions and 403 for
  platform capability, origin and admin-confirmation failures.
- Regression plan: exercise the endpoint without each perimeter requirement
  and assert the exact status without exposing internal messages.

### W7A-PRODUCT-013 - Structured data did not require the published lifecycle

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: render a Competition snapshot whose visibility is public
  while its lifecycle is not yet `published`.
- Observed: metadata correctly emitted `noindex`, but the JSON-LD condition
  checked only visibility and could still describe the draft as a SportsEvent.
- Impact: a non-published snapshot could expose indexable semantic markup even
  though canonical metadata rejected indexing.
- Planned correction: share the exact `public + published` predicate for
  metadata and structured data.
- Regression plan: assert drafts, unlisted and private publications emit no
  canonical public JSON-LD or sitemap entry.

### W7A-SIMULATION-011 - Public fixture conflicted with the active legacy League beta guard

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: compose the real Wave 7A registration fixture on top of
  the already active Demo World V2.6 League Private Beta state.
- Observed: the shared isolated Wave 7A fixture inserted its category with
  legacy visibility `public`. The older private-beta structure trigger rejected
  that insert because its separate public-discovery flag remains disabled.
- Impact: the disposable simulation stopped before any Demo V2.7 snapshot was
  exported; production and the standalone Wave 7A database suite were not
  modified.
- Planned correction: derive a Demo-only copy of the fixture in memory with a
  private canonical category. Wave 7A still publishes only the reviewed safe
  projection through the real publication RPC, so no legacy discovery flag is
  enabled and V2.6 remains unchanged.
- Regression plan: rerun the complete V2.1-V2.7 simulation from a fresh
  temporary database and require the public directory, lifecycle, requests and
  privacy assertions to pass before exporting the snapshot.
- Correction: the simulation derives a private-category copy in memory while
  retaining the reviewed Wave 7A public projection.
- Regression verified: the fresh 183-migration simulation exported V2.7 with
  the legacy League public-discovery flag still disabled.

### W7A-SIMULATION-012 - Composed League fixture lacked its canonical beta bundle

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the real Wave 7A publication suite after the
  existing Demo World League Private Beta has been activated.
- Observed: the legacy creation guard correctly classified the composed League
  as `LEAGUE_PRIVATE_BETA_V1`, but the fixture organizer had no active beta
  capability bundle. The first `publication.prepare` therefore failed with
  `COMPETITION_MANAGER_REQUIRED`, while the standalone Wave 7A suite passed
  because that older beta gate was not active there.
- Impact: Demo World V2.7 generation stopped in its disposable local database;
  no production or remote data was modified and no permission was widened.
- Planned correction: grant the fixture organizer the exact existing League
  Private Beta bundle through the canonical platform RPC before executing the
  Wave 7A suite. Do not insert grants directly and do not bypass the capability
  check.
- Regression plan: rebuild the complete V2.1-V2.7 world from a fresh database,
  require publication and registration flows to pass, and verify that the
  exported public projection contains no private organizer or grant data.
- Correction: the fixture organizer receives the exact eleven-capability bundle
  through `command_pachanga_league_private_beta_platform_v1`.
- Regression verified: the composed League published successfully and its
  exported projection contains neither grant rows nor private owner data.

### W7A-SIMULATION-013 - Composed registration story reached a closed canonical gate

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: submit the first Team registration request after the
  composed League has completed the real Wave 7A publication lifecycle.
- Observed: the authoritative registration RPC rejected the request with
  `PUBLIC_REGISTRATION_NOT_OPEN`.
- Impact: the disposable Demo World V2.7 build stopped before exporting any
  snapshot; no remote state or product permissions changed.
- Planned correction: make `registration.configure` perform the canonical
  edition transition from `draft` to `registration_open` when the mode becomes
  `REQUEST_APPROVAL`, and to `registration_closed` when it is closed. Keep the
  request-side gate unchanged. Change the isolated fixture to begin in `draft`
  so it cannot hide this transition again.
- Regression plan: rerun all accepted, waitlisted, rejected and withdrawn
  stories through the real RPCs and verify only the accepted request creates a
  canonical Entry.
- Correction: `registration.configure` now opens a draft canonical edition for
  `REQUEST_APPROVAL`; the isolated fixture begins in `draft` and asserts that
  transition explicitly.
- Regression verified: the SQL suite and full simulation passed accepted,
  waitlisted, rejected and withdrawn stories with Entry creation only on accept.

### W7A-SIMULATION-014 - Generated match context failed only in the composed world

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: build the Wave 7A public calendar/result evidence after
  Demo World V2.6 has already created its canonical League and Tournament.
- Observed: R6C hardening rejected a generated match context with
  `COMPETITION_GENERATED_CONTEXT_INVALID`; the same Wave 7A database suite
  passes in isolation.
- Impact: snapshot export stopped in the disposable database. No remote state
  changed.
- Planned correction: add the required canonical SchedulePlan, revision,
  rounds, slots and ScheduleItems to the Wave 7A fixture, then force deferred
  constraints to `IMMEDIATE` inside the isolated SQL suite before its rollback.
  The R6C validator itself is correctly scoped and must remain unchanged.
- Regression plan: execute the same generated-context story with multiple
  coexisting competitions and require deterministic validation plus unchanged
  Tournament lineage.
- Correction: the fixture now includes the canonical plan, revision, rounds,
  slots and items, and forces deferred constraints before rollback.
- Regression verified: both the isolated SQL suite and the multi-competition
  V2.7 simulation passed the R6C relation validator.

### W7A-SIMULATION-015 - Auxiliary Demo competitions reused one beta organizer

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: create the public League fixture plus the unlisted
  Tournament and private League perspectives under the same Demo Team.
- Observed: the existing League Private Beta uniqueness policy rejected the
  second active competition for that organizer through
  `pachanga_beta_active_team_competition_idx`.
- Impact: the safe beta limit remained enforced; only the disposable Demo World
  build stopped.
- Planned correction: assign the auxiliary canonical competitions to distinct
  existing Demo Teams and their real owners. Grant the private League organizer
  its exact beta bundle through the platform RPC; do not alter the uniqueness
  index or its product rule.
- Regression plan: rebuild V2.7 and require four distinct public/unlisted/private
  perspectives while preserving one active beta competition per organizer.
- Correction: the no-listada Tournament and private League use Demo Teams 8 and
  9 respectively, with the latter receiving its bundle through the real RPC.
- Regression verified: the complete world exported all four perspectives while
  the beta uniqueness index remained unchanged and enforced.

### W7A-SIMULATION-016 - Auxiliary Tournament used a non-canonical stage literal

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: seed the no-listada Tournament perspective for Demo World
  V2.7.
- Observed: the fixture used `KNOCKOUT_STAGE`, which is not a value accepted by
  the canonical Competition stage constraint.
- Impact: PostgreSQL rejected the row before any public projection was created;
  only the disposable simulation stopped.
- Planned correction: use the exact knockout stage literal already established
  by R6C, leaving the schema constraint unchanged.
- Regression plan: rebuild V2.7 and verify the no-listada Tournament hub and its
  bracket section render from a valid canonical stage.
- Correction: the fixture now uses the canonical R6C literal `KNOCKOUT`.
- Regression verified: PostgreSQL accepted the stage and the unlisted hub was
  exported without entering the public directory.

### W7A-PRODUCT-014 - Registration close conflated enrolment and sporting lifecycle

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: configure public registration as `CLOSED` for a canonical
  Tournament whose edition is already in progress or completed.
- Observed: the first draft of the Wave 7A transition required every close to
  fit the pre-schedule registration states and attempted to replace the edition
  status with `registration_closed`.
- Impact: a valid published Tournament could not expose its public read model
  with registration closed without corrupting or rejecting its sporting state.
- Planned correction: treat registration mode as an enrolment gate. Preserve
  advanced edition states when closing, and only transition `draft` or
  `registration_open` editions to `registration_closed`.
- Regression plan: close registration on both a draft League and an in-progress
  Tournament, then assert the League closes while the Tournament retains its
  canonical sporting status.
- Correction: `CLOSED` changes the edition lifecycle only while it is still in
  draft/open registration; advanced sporting states are preserved.
- Regression verified: the public Tournament retained its prior sporting status
  after close, while the draft/open League transition remains covered in SQL.

### W7A-SIMULATION-017 - Authority exporter emitted two adjacent JSON documents

- Classification: `SIMULATION_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: extract the complete Demo World V2.7 public Competition
  authority proof after every canonical flow has succeeded.
- Observed: the SQL emitted the product proof and its privacy checks as two rows;
  the Node exporter received adjacent JSON documents and failed parsing them as
  one value.
- Impact: all local database stories had passed, but no V2.7 snapshot was written.
- Planned correction: compose privacy assertions into the single authoritative
  JSON object returned by the extractor.
- Regression plan: require one parseable document, validate its privacy fields,
  and then run the committed snapshot verifier.
- Correction: the JSONB merge is parenthesized before casting the single result
  to text.
- Regression verified: the extractor parsed one complete authority document and
  the V2.7 snapshot exported successfully.

### W7A-SIMULATION-018 - Aggregated Demo authority assertion hid the failing invariant

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: validate the parsed V2.7 authority proof after all database
  operations and privacy projections complete.
- Observed: the validator raised the aggregate code
  `DEMO_WORLD_V2_7_PRIVACY_OR_AUTHORITY_INVALID`, which combines several
  independent conditions and does not identify the failing invariant.
- Impact: the disposable build stopped safely, but diagnosis requires splitting
  the assertion rather than guessing or weakening privacy.
- Planned correction: inspect and name each privacy/authority condition, then
  correct only the mismatched producer or expectation.
- Regression plan: retain distinct assertion codes for public visibility,
  registration outcomes, receipt authority and every PII/private-field guard.
- Correction: remote writes, receipts, privacy diagnostics and private-field
  scanning now have separate failure codes; diagnostic metadata is excluded
  from payload scanning.
- Regression verified: all independent checks passed against the generated
  V2.7 authority proof.

### W7A-SIMULATION-019 - Snapshot contract reported an unspecified private-data leak

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: validate the generated Demo World V2.7 snapshot after the
  authority proof itself has passed its explicit privacy gates.
- Observed: the snapshot contract emitted the generic error
  `public competition payload leaked private data` without naming the matched
  field.
- Impact: export stopped safely and no committed snapshot changed.
- Planned correction: inspect this independent validator, distinguish a real
  leak from diagnostic-key self-matching, and make the regression precise.
- Regression plan: verify the final `public-competitions.json` contains no email,
  phone, private reason, owner identity or registration message while retaining
  explicit false privacy diagnostics.
- Correction: the snapshot validator checks privacy diagnostics separately and
  scans only the product payload, excluding those diagnostic key names.
- Regression verified: V2.7 exported with every privacy diagnostic false and no
  forbidden contact, owner, reason or message field in the product payload.

### W7A-SIMULATION-020 - Demo verifier compared volatile server evidence literally

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: regenerate the same V2.7 world with `--verify` immediately
  after a successful export.
- Observed: UUIDs generated by canonical RPCs and `clock_timestamp()` evidence
  differed between runs, producing `DEMO_WORLD_V2_AUTHORITY_PROOF_DRIFT` even
  though revisions, sequences, sporting outcomes and privacy were equivalent.
- Impact: the verifier reported a false negative and could not certify the
  committed snapshot reproducibly.
- Planned correction: normalize only volatile identifiers and server timestamps
  in the exported proof/read models, while retaining semantic IDs, revisions,
  server sequences, checksums, outcomes and relations in the deterministic hash.
- Regression plan: run simulate followed by verify from separate fresh databases
  and require exact normalized authority and snapshot equality.
- Correction: the verifier now projects UUID-shaped database identifiers to
  stable encounter-order aliases, replaces server-clock timestamps and derived
  digests with typed markers, and leaves revisions, sequences, outcomes and
  repeated identifier relationships untouched.
- Regression verified: `npm run demo-world:v2:verify` rebuilt a fresh 183-
  migration database, returned `snapshotIdentical: true`, performed zero remote
  writes and destroyed the temporary database after comparison.

### W7A-SIMULATION-021 - Public snapshot privacy test matched safe diagnostics

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: add an explicit V2.7 regression that scans the public
  competition chunk for private fields.
- Observed: the broad text matcher treated boolean diagnostics such as
  `containsRoster: false` and `containsFees: false` as leaked roster or fee
  data.
- Impact: the test failed safely despite the public payload containing no
  corresponding private field.
- Planned correction: remove the diagnostics envelope before scanning and
  match forbidden JSON property names exactly.
- Regression plan: the same snapshot must pass while an injected exact
  `privateReason`, `message`, contact, roster, attendance or fee key would fail.
- Correction: the test removes the explicit privacy diagnostics envelope and
  matches only exact forbidden JSON property names in the remaining payload.
- Regression verified: the V2.7 public snapshot privacy regression passes with
  all diagnostics false and no forbidden product field.

### W7A-SIMULATION-022 - Demo renderer regression expected non-existent wrappers

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: prove Demo V2.7 reuses the production directory and public
  hub renderers.
- Observed: the assertion searched for invented names
  `DemoPublicCompetitionDirectory` and `DemoPublicCompetitionHub`; the actual
  product components are `CompetitionDirectoryClient` and
  `PublicCompetitionHub`.
- Impact: the test failed safely even though the production renderers were
  imported and rendered in embedded read-only mode.
- Planned correction: assert the real imports and embedded invocations.
- Regression plan: targeted Demo tests pass only while both production
  renderers remain wired into the Demo public-competition panes.
- Correction: coverage now asserts imports and embedded rendering of
  `CompetitionDirectoryClient` and `PublicCompetitionHub` directly.
- Regression verified: all 16 Demo World V2 tests pass with the V2.7 pane set.

### W7A-PRODUCT-015 - Wave 7A writes were absent from the PWA classifier

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: audit each new publication, registration and platform
  moderation write through the permanent PWA client-version bridge.
- Observed: the clients correctly used `clientWriteFetch`, but their three API
  operation identifiers and four underlying RPC names were not present in
  `pwa-write-classifier.ts`.
- Impact: the bridge could classify the operations as unknown, weakening the
  uniform incompatible-client block and write telemetry contract.
- Planned correction: register only the exact Wave 7A API operation IDs and
  authoritative RPC names.
- Regression plan: static product tests require every new API/RPC write to be
  known while public GET routes remain reads.
- Correction: the three API operations and four authoritative RPCs are now
  registered in the permanent write classifier.
- Regression verified: the focused suite recognizes all seven writes and keeps
  public GET routes classified as reads.

### W7A-TESTABILITY-023 - Node contract test crossed the server-only boundary

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: execute the focused Wave 7A contract suite directly with
  `tsx --test`.
- Observed: importing the API `_shared.ts` module also imports the guarded
  platform server client, so the standalone Node runner stopped at the
  `server-only` sentinel before executing assertions.
- Impact: no product path was affected, but the regression suite could not run
  outside the Next.js build graph.
- Planned correction: keep the API boundary server-only and verify its payload
  allowlists and UUID contract from source, while importing only the pure
  public competition contract at runtime.
- Regression plan: the focused suite must execute without mocking or weakening
  `server-only` and still reject browser-owned actor, snapshot and sequence
  fields.
- Correction: the test imports only pure browser-safe contracts and audits the
  server-only API allowlists from source.
- Regression verified: `npm run test:public-competitions` executes all 17
  assertions without mocking the server boundary.

### W7A-TESTABILITY-024 - Visibility assertion used labels instead of values

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: verify the Configuration Center exposes the three
  visibility states.
- Observed: the first regression expected uppercase display text although the
  control intentionally stores lowercase canonical option values.
- Impact: the product control was correct, but the test failed on presentation
  casing unrelated to the contract.
- Planned correction: assert the exact `private`, `unlisted` and `public`
  option values.
- Regression plan: focused product tests pass while preserving canonical
  lowercase values sent to PostgreSQL.
- Correction: assertions now target the exact lowercase option values.
- Regression verified: all visibility controls pass the focused suite.

### W7A-TESTABILITY-025 - Service Worker route regex was double escaped

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: verify that public competition detail navigation is
  available from the PWA runtime cache.
- Observed: the test searched for the evaluated worker regex, while the source
  contains that regex escaped inside a generated JavaScript template string.
- Impact: the cache route existed, but the static assertion did not recognize
  its source representation.
- Planned correction: assert the stable cache-pattern declaration and escaped
  competition route fragment separately.
- Regression plan: focused product tests prove public navigation is cacheable
  and `/api/` plus non-GET requests remain excluded.
- Correction: assertions inspect the generated route-pattern declaration and
  escaped source fragment independently.
- Regression verified: cached navigation, API exclusion and GET-only behavior
  pass the focused suite.

### W7A-TESTABILITY-026 - Control Center assertion expected an English heading

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: verify the Public Competitions Control Center renderer.
- Observed: the regression searched for the English product name while the
  production control is intentionally localized as `Gates públicos`.
- Impact: moderation and flag controls were present; only the test label was
  wrong.
- Planned correction: assert the localized gate heading together with the
  canonical `flags.set` operation.
- Regression plan: the focused suite recognizes the actual Spanish product
  surface without weakening its authority checks.
- Correction: the test now requires `Gates públicos` and the canonical
  `flags.set` operation.
- Regression verified: Control Center product coverage passes in the 17/17
  focused run.

### W7A-PRODUCT-016 - Public Hub derived initial selection through an effect

- Classification: `PRODUCT_BUG`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run focused React lint over the public Competition Hub.
- Observed: the registration panel synchronously copied the first Team into
  local state from an effect, and the initial hub fetch was invoked directly
  from another effect body.
- Impact: behavior was correct but could introduce an avoidable render and was
  rejected by the repository React quality gate.
- Planned correction: derive the fallback Team directly during render and
  schedule the initial network reconciliation from an effect callback with
  cleanup.
- Regression plan: focused lint, typecheck and Public Competitions tests pass.
- Correction: the fallback Team is derived during render and the initial
  reconciliation runs through a cancellable timer callback.
- Regression verified: focused lint has zero findings; Public Competitions
  17/17, Demo V2.7 16/16 and typecheck pass.

### W7A-TESTABILITY-027 - Demo privacy projection left unused discard bindings

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: lint the V2.7 authority, contract and regression sources.
- Observed: three projections removed `privacyDiagnostics` by rest
  destructuring into an intentionally unused binding.
- Impact: the private diagnostic remained excluded, but lint emitted three
  warnings.
- Planned correction: clone each public record and explicitly delete the
  private diagnostic key.
- Regression plan: Demo V2.7 tests and verify remain green with zero focused
  lint warnings.
- Correction: each public projection is cloned and its diagnostic-only privacy
  key is deleted explicitly.
- Regression verified: focused lint is clean and all 16 Demo V2.7 tests pass.

### W7A-TESTABILITY-028 - Concurrency runner retained an unused response

- Classification: `TESTABILITY_GAP`
- Status: `FIXED / REGRESSION_VERIFIED`
- Original scenario: run repository-wide lint after all focused gates passed.
- Observed: one setup call in the Wave 7A concurrency runner assigned its
  canonical response without reading it.
- Impact: the race executed correctly, but the new test file contributed one
  warning to the otherwise pre-existing global lint debt.
- Planned correction: await the setup command without retaining the unused
  value.
- Regression plan: lint every Wave 7A source, including `.mjs` runners, with
  zero findings and repeat the race suite.
- Correction: the setup command is awaited for its effect without retaining an
  unused response value.
- Regression verified: all Wave 7A sources lint clean and the complete race
  matrix passes again.
