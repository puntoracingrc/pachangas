# R6A Tournament Foundation Incidents

## R6A-001 - League guard blocks canonical Tournament creation

- Classification: `PRODUCT_BUG`
- Status: `FIXED`
- Found by: Demo World V2.4 authoritative simulation
- Original scenario: League Private Beta is enabled and the R6A command creates a private competition with `product_key = TOURNAMENT_PRIVATE_BETA_V1`.
- Observed result: PostgreSQL rejects the insert with `TOURNAMENT_ENGINE_NOT_AVAILABLE`.
- Expected result: the R6A Tournament command creates the private Tournament while the existing League guard continues protecting League creation.
- Root cause: `private.pachanga_league_private_beta_guard_competition_v1()` applies League-only validation to every competition insert whenever `league_private_beta_enabled` is true, regardless of the explicit product key.
- Product impact: Tournament creation cannot coexist with the active League Private Beta configuration.
- Security boundary: the correction must not authorize generic direct inserts, weaken League checks, enable public Tournament discovery, or create Tournament matches.
- Correction: replaced the guard forward-only in the first R6A migration with a narrow branch for the canonical Tournament product key, preserving the original League branch unchanged.
- Required regression: enable League Private Beta, create a Tournament through the real R6A command, verify its product key and privacy, and verify that malformed Tournament rows remain rejected.
- Regression status: `REGRESSION_VERIFIED`
- Regression evidence:
  - fresh `158 -> 163` migration reconstruction: `PASS`;
  - SQL/RLS/idempotency suite with League Beta active during `tournament.create`: `PASS`;
  - malformed Tournament type and visibility rejected: `PASS`;
  - Demo World V2.4 authoritative simulation with League Beta and R6A: `PASS`;
  - remote writes: `0`;
- Tournament matches created: `0`.

## R6A-002 - Tournament input checksum includes non-sport randomness

- Classification: `PRODUCT_BUG` (initially detected as a simulation drift)
- Status: `FIXED`
- Found by: `npm run demo-world:v2:verify` after a successful V2.4 export
- Original scenario: rebuild the same logical Demo World V2.4 in a second temporary PostgreSQL database using the same Tournament seeds and rules.
- Observed result: canonical IDs initially changed placements; after making command-created IDs deterministic, placements and result checksums converged but input checksums still changed between equivalent reconstructions.
- Expected result: a fresh reconstruction of the synthetic world must reproduce the exact authority proof and public snapshot.
- Root cause: command-created entities used random UUID defaults, and checksummed JSON duplicated wall-clock `capturedAt` values already represented by authoritative columns and command receipts.
- Product impact: a persisted Tournament remains internally consistent, but equivalent authoritative commands cannot reconstruct the same semantic input checksum.
- Security boundary: do not weaken the production checksum, remove canonical identifiers from the product algorithm, or hard-code a published result.
- Correction: derived command-created internal IDs server-side from `operationId` and scope, and removed duplicated capture timestamps from checksummed JSON while retaining authoritative server dates in relational columns and receipts.
- Required regression: two independent temporary database reconstructions must produce an identical authority hash, result checksums and public snapshot.
- Regression status: `REGRESSION_VERIFIED`
- Regression evidence:
  - fresh SQL/RLS/idempotency reconstruction after the correction: `PASS`;
  - first independent Demo World V2.4 reconstruction exported: `PASS`;
  - second independent reconstruction matched authority proof and snapshot exactly: `PASS`;
  - `snapshotIdentical`: `true`;
  - authoritative result checksum retained: `PASS`;
  - Tournament matches created: `0`.

## R6A-003 - Shared dependency symlink is outside Turbopack project root

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: final production build gate
- Original scenario: run `npm run build` from the isolated R6A worktree while its regenerable `node_modules` points to another registered worktree.
- Observed result: Turbopack aborts with `Symlink [project]/node_modules is invalid, it points out of the filesystem root`.
- Expected result: the R6A release candidate builds from dependencies installed inside its own project root.
- Root cause: the local dependency directory was temporarily shared through an absolute symlink to reduce disk use during development.
- Product impact: none; compilation stops before producing a deployable artifact.
- Security boundary: do not modify or remove the source worktree and do not change dependency versions outside the committed lockfile.
- Correction: removed only the regenerable symlink in this worktree and installed its own dependency directory with `npm ci` from the committed lockfile; the source worktree was not modified.
- Required regression: repeat `npm run build` with a real local `node_modules` directory and require a successful production build.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - clean lockfile install: `PASS`;
  - local `node_modules` is a real directory: `PASS`;
  - production build with Next.js 16.2.6 / Turbopack: `PASS`;
  - TypeScript phase inside production build: `PASS`;
  - generated application routes: `53/53` pages.

## R6A-004 - Draw Desk violates React compiler stability rules

- Classification: `PRODUCT_BUG`
- Status: `FIXED`
- Found by: final focused ESLint gate
- Original scenario: lint the new Tournament client surfaces with the React compiler rules enabled.
- Observed result: the wizard synchronously mutates state inside an effect, the Draw Desk memoizes from a render-local mutable collection, and the generate button evaluates an impure seed expression from render code.
- Expected result: the private-beta client remains pure and compiler-safe while preserving server-authoritative commands and a fresh persisted seed for each user-triggered generation.
- Product impact: unnecessary cascading renders and skipped React compiler optimization; the impure render expression may yield unstable UI behavior.
- Security boundary: the client seed is only semantic intent; PostgreSQL must still persist the seed, calculate the draw, validate revisions and return the canonical snapshot.
- Correction: initialized the organizer in the state initializer, built the bounded entry lookup directly, moved UUID seed creation into the explicit click handler and removed the unused Audit View prop.
- Required regression: focused ESLint, TypeScript and production build must pass for the changed client without weakening command authority.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - focused ESLint over every changed TypeScript/TSX/MJS file: `PASS`;
  - TypeScript: `PASS`;
  - production build: `PASS`;
  - server-authoritative command tests: `PASS`;
  - Tournament matches created: `0`.

## R6A-005 - Draw controls are clipped in compact game landscape

- Classification: `PRODUCT_BUG`
- Status: `FIXED`
- Found by: automated visual QA plus screenshot inspection
- Original scenario: open the Tournament Draw laboratory at `667x375`, `740x360` or `844x390` with touch/game-landscape layout.
- Observed result: the Rules rail inherits a full three-track width; its pot and constraint controls extend 76-100 px beyond the visible content viewport.
- Expected result: every control remains fully visible and operable at every required landscape viewport without root overflow.
- Root cause: the `max-width: 900px` rule makes the Rules rail span all columns, while the later low-landscape/tablet rules restore three columns whose combined minimum width exceeds the content area beside the game rail.
- Product impact: pot and constraint controls are visually cut and difficult to use on compact landscape devices.
- Security boundary: responsive styling only; do not change draw commands, permissions, revisions or canonical state.
- Correction: used a two-column participant/board layout below 900 px, constrained the Rules rail to the full available width, and reserved the wider three-column tablet grid for heights above 600 px.
- Required regression: repeat the three failing viewports and the adjacent `932x430` viewport; require zero clipped controls, zero root overflow and zero browser errors.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - `667x375`: zero clipped controls, zero root overflow, zero browser errors;
  - `740x360`: zero clipped controls, zero root overflow, zero browser errors;
  - `844x390`: zero clipped controls, zero root overflow, zero browser errors;
  - `932x430`: zero clipped controls, zero root overflow, zero browser errors;
  - screenshot inspection confirms participant, board and Rules rail remain within the game viewport.

## R6A-006 - Participant commands return organizer-only Tournament state

- Classification: `PRODUCT_BUG`
- Status: `FIXED`
- Found by: authenticated staging E2E design review
- Original scenario: a team owner accepts, declines or withdraws its own Tournament entry while other teams still have pending invitations or the organizer has an unpublished DrawPlan.
- Observed result: the command receipt contains the internal command snapshot with every entry and every DrawPlan, including state that the same actor cannot read through the canonical read RPC.
- Expected result: command confirmation must expose only the actor-authorized snapshot; a participant may see accepted teams, its own entry and published draws, while organizer-only invitations and draft draw state remain private.
- Root cause: `private.pachanga_tournament_command_snapshot_v1` did not receive the actor and aggregated all rows unconditionally.
- Product impact: a participating team could infer pending invitations and unpublished draw metadata after a legitimate self-service action.
- Security boundary: preserve the full organizer response, participant self-service confirmation, immutable receipts and server authority; do not rely on client-side redaction.
- Correction: made the command snapshot actor-aware and applied the same entry and DrawPlan visibility boundaries as the canonical read models before persisting and returning the receipt.
- Required regression: invite a ninth team, withdraw and re-invite an accepted team through the authenticated command, and verify both command responses exclude the other team's pending invitation while the organizer flow remains complete.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - authenticated participant command receipt contract: `PASS`;
  - fresh `158 -> 163` SQL/RLS reconstruction: `PASS`;
  - organizer visibility remains complete while participant receipts hide pending invitations and unpublished plans.

## R6A-007 - Parallel local infrastructure restores collide

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: final local validation orchestration
- Original scenario: run the database reconstruction suite and the concurrency suite simultaneously against separate databases in the same local Supabase PostgreSQL cluster.
- Observed result: one infrastructure restore fails with PostgreSQL `tuple concurrently updated` while both processes restore shared Supabase catalog objects.
- Expected result: each destructive local bootstrap finishes without contending with another bootstrap in the same cluster.
- Root cause: the two suites isolate product data in independent databases, but PostgreSQL role/catalog operations remain cluster-scoped during infrastructure restoration.
- Product impact: none; no production or Tournament command was involved. The failed suite stopped before product assertions.
- Security boundary: do not weaken SQL, skip concurrency cases or reuse production infrastructure to avoid the collision.
- Correction: serialize destructive database bootstrap suites in the release gate. Contract and file-only suites may still run in parallel.
- Required regression: rerun database reconstruction first and concurrency second against an idle local cluster; both must pass with the same five migrations.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - serialized fresh `158 -> 163` database reconstruction: `PASS`;
  - serialized concurrency suite: `10/10 PASS`;
  - every race produced one winner and one `STALE_REVISION` loser;
  - Tournament matches created: `0`.

## R6A-008 - Supabase preview branch inherits an incomplete migration ledger

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: staging preflight readback
- Original scenario: create a new Supabase development branch from the healthy Pachangas production project after verifying production contains 158 migrations.
- Observed result: the branch reports `ACTIVE_HEALTHY` but its canonical `supabase_migrations.schema_migrations` ledger contains only 10 rows and stops at `20260728191429`.
- Expected result: the ephemeral staging branch inherits the exact production ledger of 158 before any R6A migration is applied.
- Product impact: applying R6A on this branch would test against a structurally invalid historical base and could produce false confidence.
- Security boundary: do not repair or backfill production, do not apply R6A over the ten-row branch, and do not rewrite already executed migration history.
- Required correction: use the official branch rebase/reset path or recreate a staging database from the immutable baseline plus the exact forward migration set; require a 158-row readback before continuing.
- Required regression: branch readback must report ledger 158 with the exact last Wave 5A migration, then and only then may R6A apply 159-163.
- Correction: applied the repository's immutable product baseline to the data-free branch, marked only the 36 absorbed historical versions, replayed incrementals 37-158 from an exact `origin/main` export through the session pooler, and then completed a native branch rebase.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - production ledger before R6A: `158`;
  - staging ledger before R6A: `158`;
  - production/staging version and migration-name arrays: exact equality;
  - last version on both: `20260826123500_competition_configuration_control_center_v1`;
  - branch state after reconciliation: `FUNCTIONS_DEPLOYED / ACTIVE_HEALTHY`;
  - production was read-only throughout the repair.

## R6A-009 - Tournament foreign keys lack covering indexes

- Classification: `PRODUCT_BUG`
- Status: `OPEN`
- Found by: Supabase staging Performance Advisor
- Original scenario: apply the five R6A migrations to an empty ledger-158 staging branch and run the Performance Advisor before any Tournament data exists.
- Observed result: 18 R6A foreign keys are reported without a covering index, including participant-freeze scope references, DrawPlan references, actor references, manual-lock entries and placement lock lineage.
- Expected result: every R6A foreign key has an index whose leading column covers the referenced column, so deletes, validation and relationship reads remain bounded as volume grows.
- Product impact: referential checks and parent updates/deletes could scan Tournament tables at production volume despite the principal query indexes passing local performance tests.
- Security boundary: add indexes only; do not alter authority, RLS, immutable evidence, solver output or public capabilities.
- Required correction: extend the still-unreleased fifth migration with 18 explicit covering indexes and add a database regression that detects any uncovered R6A foreign key.
- Required regression: rebuild staging from ledger 158 with the final five artifacts, require zero R6A `unindexed_foreign_keys` Advisor findings and repeat DB/concurrency tests.
- Regression status: `PENDING`.

## R6A-010 - Supabase CLI default key is not a browser publishable key

- Classification: `ENVIRONMENT_ISSUE`
- Status: `OPEN`
- Found by: authenticated staging sign-in before any Tournament command executed
- Original scenario: obtain the ephemeral branch credentials through `supabase branches get`, wire the field named `SUPABASE_DEFAULT_KEY` to the branch-scoped Preview public key, and start the authenticated E2E.
- Observed result: the field contains an `sb_secret_...` key, not an `sb_publishable_...` key; Auth rejects it as a public API key. The isolated Preview build therefore received a secret-class branch credential through a `NEXT_PUBLIC_` variable.
- Expected result: only an enabled `sb_publishable_...` or legacy `anon` key may be used by the browser; secret and service-role credentials must remain server-only.
- Product impact: no production impact and no successful authenticated request. The affected Preview, its three branch-scoped variables and the whole ephemeral Supabase branch were immediately deleted, invalidating all branch credentials.
- Security boundary: never infer browser suitability from a CLI field name; inspect key class without printing the value, fail closed on `sb_secret_`, and recreate the disposable staging boundary from zero.
- Required correction: select `SUPABASE_ANON_KEY` for the client and independently verify that Supabase exposes an enabled publishable key; keep `SUPABASE_SERVICE_ROLE_KEY` only in the local fixture runner and server-only Preview environment.
- Required regression: a fresh branch must reject secret-class values from the browser configuration, pass Auth with the public key, expose no secret/service-role value in its client bundle, and complete the authenticated E2E before teardown.
- Regression status: `PENDING`.

## R6A-011 - Club fixture consumes a revoked private sequence default

- Classification: `SIMULATION_BUG`
- Status: `OPEN`
- Found by: authenticated staging E2E while preparing the Club organizer fixture
- Original scenario: create a disposable Club through `service_role` table access and rely on the table default for `server_sequence`.
- Observed result: PostgreSQL rejects the fixture with `42501 permission denied for sequence pachanga_club_sequence`; the private sequence is correctly revoked from client roles, including direct `service_role` use through PostgREST.
- Expected result: fixture-only direct inserts supply their own isolated synthetic sequence and never require access to the private product sequence. Tournament mutations remain authenticated RPC calls.
- Product impact: none. The E2E stopped before enabling Tournament flags or issuing a Tournament command; production and canonical Club authority were unchanged.
- Security boundary: do not grant sequence access, do not weaken Club RPC security and do not replace Tournament actions with service-role writes.
- Required correction: assign an explicit monotonic fixture sequence to Club, membership and relationship setup rows.
- Required regression: the same staging story must create Team and Club organizer fixtures, execute all Tournament actions through authenticated canonical RPCs, and complete with zero sequence grants added.
- Regression status: `PENDING`.

## R6A-012 - Failed one-shot staging run leaves the unique platform owner occupied

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: retrying the authenticated E2E after R6A-011 stopped the first run
- Original scenario: reuse the same disposable Supabase branch after a failed run that had already bootstrapped its single platform owner.
- Observed result: the new account cannot bootstrap a second owner and PostgreSQL correctly returns `Platform owner already bootstrapped`.
- Expected result: each certification run starts from an unmodified ledger-158 branch; failed runs are discarded rather than repaired by deleting audit or role history.
- Product impact: none; Tournament flags were still OFF and no Tournament command had executed.
- Security boundary: do not delete platform audit history, weaken the single-owner bootstrap or reuse unknown credentials.
- Correction: removed the affected Preview variables, deployment and entire ephemeral branch. The final runner is executed once on a newly reconstructed branch.
- Regression status: `PENDING` until the fresh one-shot E2E and teardown complete.

## R6A-013 - Direct Club fixture violates the canonical owner-membership invariant

- Classification: `SIMULATION_BUG`
- Status: `OPEN`
- Found by: final authenticated one-shot staging E2E
- Original scenario: create the disposable Club organizer with two independent PostgREST writes, inserting `pachanga_clubs` first and its `club_owner` membership second.
- Observed result: the deferred canonical owner guard closes at the end of the first HTTP transaction and correctly rejects the Club row with `23514 CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED`.
- Expected result: fixture setup must use the canonical authenticated `club.create` RPC, which creates the Club and primary-owner membership atomically in one server transaction.
- Product impact: none. The E2E stopped before enabling Tournament flags, granting a Tournament bundle or issuing a Tournament command; production was unchanged.
- Security boundary: do not disable or defer the owner guard across requests, do not grant table or sequence access, and do not fabricate an owner membership after a failed Club insert.
- Required correction: enable only the existing Club self-service prerequisites in the disposable branch, create the Club through `command_pachanga_club_foundation_v1`, restore the previous Club flags during cleanup and discard the failed one-shot branch.
- Required regression: a fresh one-shot E2E must create both Team and Club organizers through their valid authority paths, complete the Club Tournament history and restore all Club flags without weakening any Club constraint.
- Regression status: `PENDING`.

## R6A-014 - Canonical Club fixture remains in draft and is correctly excluded from Tournament organizers

- Classification: `SIMULATION_BUG`
- Status: `OPEN`
- Found by: final authenticated one-shot staging E2E after replacing the direct Club fixture with the canonical creation command.
- Original scenario: create the disposable Club organizer through `command_pachanga_club_foundation_v1` and immediately request the Tournament organizer read model.
- Observed result: the Club is absent because canonical self-service creation leaves `operational_status = 'draft'`, while `private.pachanga_tournament_actor_organizers_v1` correctly admits only active Clubs.
- Expected result: the fixture explicitly completes platform approval through `command_pachanga_club_platform_v1` with `club.status.set = active` and the Club revision confirmed by its creation receipt before requesting Tournament access.
- Product impact: none. The E2E stopped before the Club Tournament bundle grant or any Club Tournament command. The affected Supabase branch and Preview are disposable one-shot staging resources.
- Security boundary: do not weaken the active-Club eligibility predicate, do not update the Club table directly and do not fabricate organizer visibility in the client.
- Required correction: pass the authenticated platform owner into the Club fixture helper, activate the newly created Club with its server-confirmed revision and assert the canonical returned snapshot is active.
- Required regression: a fresh one-shot E2E must prove that the Club appears in the Tournament organizer read model only after canonical activation, can create and cancel its Tournament, and restores all temporary feature flags before branch teardown.
- Regression status: `PENDING`.

## R6A-015 - Club platform approval correctly rejects a direct draft-to-active transition

- Classification: `SIMULATION_BUG`
- Status: `OPEN`
- Found by: authenticated one-shot staging E2E while applying the R6A-014 correction.
- Original scenario: create the Club through the canonical foundation RPC and ask the platform owner to set it directly from `draft` to `active`.
- Observed result: the existing Club transition guard rejects the command with `CLUB_APPROVAL_REQUIRES_PENDING_REVIEW`.
- Expected result: the Club owner first submits `club.review.submit`, receives the canonical `pending_review` revision and only then may the platform owner approve that exact revision as `active`.
- Product impact: none. The E2E stopped before creating a Tournament beta grant, Tournament or DrawPlan; production was not addressed.
- Security boundary: do not bypass the review state, weaken the transition guard, update the table directly or reuse the one-shot branch after a failed platform-owner run.
- Required correction: extend the canonical Club fixture to perform `club.create -> club.review.submit -> club.status.set(active)`, using each server-confirmed revision and asserting every returned state.
- Required regression: a fresh one-shot E2E must complete the full Club review transition, expose the active Club to the Tournament organizer read model, execute its create/cancel history and leave zero Tournament matches.
- Regression status: `PENDING`.

## R6A-016 - Staging preflight obscures the missing project-ref variable

- Classification: `TESTABILITY_GAP`
- Status: `OPEN`
- Found by: final one-shot staging preflight before any network request
- Original scenario: invoke the authenticated E2E with an empty `TOURNAMENT_STAGING_PROJECT_REF` because the ephemeral credential file does not export a project-ref variable.
- Observed result: the runner stops before contacting Supabase, but reports the synthesized name `TOURNAMENT_STAGING_PROJECTREF`; the surrounding diagnostic pipeline also returned the exit code from `tee` instead of Node.
- Expected result: preflight names the exact required variable, the release invocation supplies the known branch ref explicitly, and every diagnostic pipeline preserves the test process exit code.
- Product impact: none. No Supabase request, flag mutation, fixture, Tournament command or production action occurred.
- Security boundary: do not infer a project ref from a secret, do not relax the explicit production-target guard and do not reuse a one-shot branch after a failed certification invocation.
- Required correction: map each preflight field to its exact environment-variable name, run the release command with `set -o pipefail`, discard the current Preview and Supabase branch, and rebuild a fresh ledger-158 branch.
- Required regression: omission of the project ref must report `TOURNAMENT_STAGING_PROJECT_REF is required`; the fresh one-shot E2E must complete against the explicitly supplied non-production ref and clean up all temporary state.
- Regression status: `PENDING`.

## R6A-017 - Branch reconstruction assumes a non-portable shell builtin

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: clean staging ledger reconstruction
- Original scenario: read the 36 absorbed migration versions into an array with `readarray` after applying the immutable baseline.
- Observed result: macOS Bash 3.2 does not provide `readarray`; execution stops before migration-history repair, leaving the ledger at its inherited 10 rows.
- Expected result: the reconstruction command works on the repository's supported macOS shell and passes the exact 36 immutable versions without changing their order or content.
- Product impact: none. The baseline transaction completed, but no history repair, incremental migration, flag change, fixture or product RPC ran.
- Security boundary: do not mark any migration outside the manifest, do not rewrite production history and do not infer an absorbed version from filenames.
- Required correction: populate the array with a portable `while read` loop, assert the manifest count is 36, then require exact production/staging ledger equality at 158 before R6A.
- Required regression: reconstruction must reach 158 with the same version/name array and digest as production, then 163 only after the five reviewed R6A migrations.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - portable manifest read asserted exactly 36 absorbed versions;
  - production and staging matched at `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693`;
  - the five reviewed R6A migrations then advanced staging to `163 / 20260826195040`;
  - production remained read-only.

## R6A-018 - Canonical Club review requires publication consent

- Classification: `SIMULATION_BUG`
- Status: `OPEN`
- Found by: authenticated one-shot staging E2E
- Original scenario: create the Club canonically and submit it for review immediately from its draft revision.
- Observed result: the existing Club authority rejects the review with `CLUB_PUBLICATION_CONSENT_REQUIRED` because no owner consent exists for the current public content fingerprint.
- Expected result: the owner confirms representation authority and content correctness through `command_pachanga_publication_consent_v1`, then submits the exact confirmed revision for review before platform activation.
- Product impact: none. The guard prevented an unconsented Club from becoming reviewable; no Tournament bundle, Tournament, DrawPlan or match was created.
- Security boundary: do not bypass the consent fingerprint, update Club status directly, weaken the review guard or fabricate consent in fixture tables.
- Required correction: extend the staging Club helper to execute `club.create -> publication.consent -> club.review.submit -> club.status.set(active)` with every server-confirmed revision.
- Required regression: a fresh one-shot E2E must activate both disposable Clubs only after canonical consent, complete Team and Club Tournament histories, restore all temporary flags and leave zero Tournament matches.
- Regression status: `PENDING`.
