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
- Status: `FIXED`
- Found by: Supabase staging Performance Advisor
- Original scenario: apply the five R6A migrations to an empty ledger-158 staging branch and run the Performance Advisor before any Tournament data exists.
- Observed result: 18 R6A foreign keys are reported without a covering index, including participant-freeze scope references, DrawPlan references, actor references, manual-lock entries and placement lock lineage.
- Expected result: every R6A foreign key has an index whose leading column covers the referenced column, so deletes, validation and relationship reads remain bounded as volume grows.
- Product impact: referential checks and parent updates/deletes could scan Tournament tables at production volume despite the principal query indexes passing local performance tests.
- Security boundary: add indexes only; do not alter authority, RLS, immutable evidence, solver output or public capabilities.
- Required correction: extend the still-unreleased fifth migration with 18 explicit covering indexes and add a database regression that detects any uncovered R6A foreign key.
- Required regression: rebuild staging from ledger 158 with the final five artifacts, require zero R6A `unindexed_foreign_keys` Advisor findings and repeat DB/concurrency tests.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the final ledger-163 branch reports zero R6A
  `unindexed_foreign_keys` findings; all 18 missing leading-column indexes are
  present and the DB, concurrency and scale gates remain green.

## R6A-010 - Supabase CLI default key is not a browser publishable key

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: authenticated staging sign-in before any Tournament command executed
- Original scenario: obtain the ephemeral branch credentials through `supabase branches get`, wire the field named `SUPABASE_DEFAULT_KEY` to the branch-scoped Preview public key, and start the authenticated E2E.
- Observed result: the field contains an `sb_secret_...` key, not an `sb_publishable_...` key; Auth rejects it as a public API key. The isolated Preview build therefore received a secret-class branch credential through a `NEXT_PUBLIC_` variable.
- Expected result: only an enabled `sb_publishable_...` or legacy `anon` key may be used by the browser; secret and service-role credentials must remain server-only.
- Product impact: no production impact and no successful authenticated request. The affected Preview, its three branch-scoped variables and the whole ephemeral Supabase branch were immediately deleted, invalidating all branch credentials.
- Security boundary: never infer browser suitability from a CLI field name; inspect key class without printing the value, fail closed on `sb_secret_`, and recreate the disposable staging boundary from zero.
- Required correction: select `SUPABASE_ANON_KEY` for the client and independently verify that Supabase exposes an enabled publishable key; keep `SUPABASE_SERVICE_ROLE_KEY` only in the local fixture runner and server-only Preview environment.
- Required regression: a fresh branch must reject secret-class values from the browser configuration, pass Auth with the public key, expose no secret/service-role value in its client bundle, and complete the authenticated E2E before teardown.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the replacement Git Preview authenticated with the
  enabled staging public key; all 12 browser chunks contain staging ref
  `zmjmzgdwovluvakfjggs`, contain neither production nor unrelated-staging
  refs, and contain no exact service-role value.

## R6A-011 - Club fixture consumes a revoked private sequence default

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: authenticated staging E2E while preparing the Club organizer fixture
- Original scenario: create a disposable Club through `service_role` table access and rely on the table default for `server_sequence`.
- Observed result: PostgreSQL rejects the fixture with `42501 permission denied for sequence pachanga_club_sequence`; the private sequence is correctly revoked from client roles, including direct `service_role` use through PostgREST.
- Expected result: fixture-only direct inserts supply their own isolated synthetic sequence and never require access to the private product sequence. Tournament mutations remain authenticated RPC calls.
- Product impact: none. The E2E stopped before enabling Tournament flags or issuing a Tournament command; production and canonical Club authority were unchanged.
- Security boundary: do not grant sequence access, do not weaken Club RPC security and do not replace Tournament actions with service-role writes.
- Required correction: assign an explicit monotonic fixture sequence to Club, membership and relationship setup rows.
- Required regression: the same staging story must create Team and Club organizer fixtures, execute all Tournament actions through authenticated canonical RPCs, and complete with zero sequence grants added.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the final E2E completed Team and Club organizer stories
  through canonical authority paths with zero client sequence grants.

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
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the fresh one-shot E2E completed on the rebuilt
  ledger-163 branch; the branch was then deleted, its three branch-scoped
  Vercel variables were removed, and readback confirmed that only production
  and the unrelated `pwa-bridge-staging` branch remain.

## R6A-013 - Direct Club fixture violates the canonical owner-membership invariant

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: final authenticated one-shot staging E2E
- Original scenario: create the disposable Club organizer with two independent PostgREST writes, inserting `pachanga_clubs` first and its `club_owner` membership second.
- Observed result: the deferred canonical owner guard closes at the end of the first HTTP transaction and correctly rejects the Club row with `23514 CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED`.
- Expected result: fixture setup must use the canonical authenticated `club.create` RPC, which creates the Club and primary-owner membership atomically in one server transaction.
- Product impact: none. The E2E stopped before enabling Tournament flags, granting a Tournament bundle or issuing a Tournament command; production was unchanged.
- Security boundary: do not disable or defer the owner guard across requests, do not grant table or sequence access, and do not fabricate an owner membership after a failed Club insert.
- Required correction: enable only the existing Club self-service prerequisites in the disposable branch, create the Club through `command_pachanga_club_foundation_v1`, restore the previous Club flags during cleanup and discard the failed one-shot branch.
- Required regression: a fresh one-shot E2E must create both Team and Club organizers through their valid authority paths, complete the Club Tournament history and restore all Club flags without weakening any Club constraint.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the final E2E created the Club atomically through
  `command_pachanga_club_foundation_v1` and preserved the owner-membership
  invariant.

## R6A-014 - Canonical Club fixture remains in draft and is correctly excluded from Tournament organizers

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: final authenticated one-shot staging E2E after replacing the direct Club fixture with the canonical creation command.
- Original scenario: create the disposable Club organizer through `command_pachanga_club_foundation_v1` and immediately request the Tournament organizer read model.
- Observed result: the Club is absent because canonical self-service creation leaves `operational_status = 'draft'`, while `private.pachanga_tournament_actor_organizers_v1` correctly admits only active Clubs.
- Expected result: the fixture explicitly completes platform approval through `command_pachanga_club_platform_v1` with `club.status.set = active` and the Club revision confirmed by its creation receipt before requesting Tournament access.
- Product impact: none. The E2E stopped before the Club Tournament bundle grant or any Club Tournament command. The affected Supabase branch and Preview are disposable one-shot staging resources.
- Security boundary: do not weaken the active-Club eligibility predicate, do not update the Club table directly and do not fabricate organizer visibility in the client.
- Required correction: pass the authenticated platform owner into the Club fixture helper, activate the newly created Club with its server-confirmed revision and assert the canonical returned snapshot is active.
- Required regression: a fresh one-shot E2E must prove that the Club appears in the Tournament organizer read model only after canonical activation, can create and cancel its Tournament, and restores all temporary feature flags before branch teardown.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the Club remained excluded while draft, became visible
  only after canonical review and activation, and completed its Tournament
  create/cancel history.

## R6A-015 - Club platform approval correctly rejects a direct draft-to-active transition

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: authenticated one-shot staging E2E while applying the R6A-014 correction.
- Original scenario: create the Club through the canonical foundation RPC and ask the platform owner to set it directly from `draft` to `active`.
- Observed result: the existing Club transition guard rejects the command with `CLUB_APPROVAL_REQUIRES_PENDING_REVIEW`.
- Expected result: the Club owner first submits `club.review.submit`, receives the canonical `pending_review` revision and only then may the platform owner approve that exact revision as `active`.
- Product impact: none. The E2E stopped before creating a Tournament beta grant, Tournament or DrawPlan; production was not addressed.
- Security boundary: do not bypass the review state, weaken the transition guard, update the table directly or reuse the one-shot branch after a failed platform-owner run.
- Required correction: extend the canonical Club fixture to perform `club.create -> club.review.submit -> club.status.set(active)`, using each server-confirmed revision and asserting every returned state.
- Required regression: a fresh one-shot E2E must complete the full Club review transition, expose the active Club to the Tournament organizer read model, execute its create/cancel history and leave zero Tournament matches.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the final Club fixture completed
  `draft -> pending_review -> active` with each server-confirmed revision.

## R6A-016 - Staging preflight obscures the missing project-ref variable

- Classification: `TESTABILITY_GAP`
- Status: `FIXED`
- Found by: final one-shot staging preflight before any network request
- Original scenario: invoke the authenticated E2E with an empty `TOURNAMENT_STAGING_PROJECT_REF` because the ephemeral credential file does not export a project-ref variable.
- Observed result: the runner stops before contacting Supabase, but reports the synthesized name `TOURNAMENT_STAGING_PROJECTREF`; the surrounding diagnostic pipeline also returned the exit code from `tee` instead of Node.
- Expected result: preflight names the exact required variable, the release invocation supplies the known branch ref explicitly, and every diagnostic pipeline preserves the test process exit code.
- Product impact: none. No Supabase request, flag mutation, fixture, Tournament command or production action occurred.
- Security boundary: do not infer a project ref from a secret, do not relax the explicit production-target guard and do not reuse a one-shot branch after a failed certification invocation.
- Required correction: map each preflight field to its exact environment-variable name, run the release command with `set -o pipefail`, discard the current Preview and Supabase branch, and rebuild a fresh ledger-158 branch.
- Required regression: omission of the project ref must report `TOURNAMENT_STAGING_PROJECT_REF is required`; the fresh one-shot E2E must complete against the explicitly supplied non-production ref and clean up all temporary state.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the negative preflight names
  `TOURNAMENT_STAGING_PROJECT_REF` exactly and the full E2E completed against
  explicit non-production ref `zmjmzgdwovluvakfjggs` with `pipefail` enabled.

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
- Status: `FIXED`
- Found by: authenticated one-shot staging E2E
- Original scenario: create the Club canonically and submit it for review immediately from its draft revision.
- Observed result: the existing Club authority rejects the review with `CLUB_PUBLICATION_CONSENT_REQUIRED` because no owner consent exists for the current public content fingerprint.
- Expected result: the owner confirms representation authority and content correctness through `command_pachanga_publication_consent_v1`, then submits the exact confirmed revision for review before platform activation.
- Product impact: none. The guard prevented an unconsented Club from becoming reviewable; no Tournament bundle, Tournament, DrawPlan or match was created.
- Security boundary: do not bypass the consent fingerprint, update Club status directly, weaken the review guard or fabricate consent in fixture tables.
- Required correction: extend the staging Club helper to execute `club.create -> publication.consent -> club.review.submit -> club.status.set(active)` with every server-confirmed revision.
- Required regression: a fresh one-shot E2E must activate both disposable Clubs only after canonical consent, complete Team and Club Tournament histories, restore all temporary flags and leave zero Tournament matches.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: both disposable Clubs obtained canonical publication
  consent before review and activation; no direct status or consent write was
  introduced.

## R6A-019 - Ephemeral branch does not deliver the Tournament invalidation event

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: authenticated one-shot staging E2E after canonical Club activation and Tournament participant acceptance
- Original scenario: subscribe as the authenticated organizer to `INSERT` events from `public.pachanga_tournament_invalidations`, filtered by the canonical Tournament `competition_id`, wait for `SUBSCRIBED`, and then accept the invited teams through the Tournament command RPC.
- Observed result: the channel reached `SUBSCRIBED` and the server persisted 36 invalidation rows with monotonic `server_sequence`, but the filtered callback did not fire within 15 seconds and the runner stopped with `R6A_REALTIME_TIMEOUT`.
- Expected result: at least one authorized invalidation event is delivered after subscription; the client then discards the transport payload as authority and reloads the canonical Tournament snapshot.
- Product impact: canonical Tournament state and invalidation evidence were persisted, but the required Realtime transport proof is incomplete. The runner restored flags, cancelled fixtures where possible and left zero Tournament competitions and zero Tournament match contexts.
- Security boundary: do not treat a direct database read as proof of Realtime, do not consume WAL payloads as canonical state, do not weaken RLS and do not retry the one-shot certification on a previously mutated branch.
- Current diagnostics: the invalidation table is present in the `supabase_realtime` publication, RLS is enabled, one SELECT policy exists, replica identity is `default`, all published INSERT columns include `competition_id`, and 36 untargeted invalidations were persisted for the filtered Tournament. Supabase Realtime logs identify the exact failure as `42501 permission denied for function pachanga_tournament_can_v1` inside `realtime.apply_rls`.
- Required correction: expose only a dedicated current-actor read predicate to `authenticated`, derive the actor from `auth.uid()`, keep the general actor/capability helper revoked, and rebuild staging from ledger 158.
- Required regression: a fresh one-shot E2E must receive the event through Realtime, reload the canonical snapshot, complete all Team and Club Tournament histories, restore temporary flags and leave zero Tournament matches and zero persistent QA entities.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the final E2E waited for PostgreSQL subscription
  readiness, received a real authorized invalidation and refetched revision 18
  from the canonical snapshot; the WAL payload remained invalidation-only.

## R6A-020 - Realtime RLS regression reads harness state after assuming the client role

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: local 158-to-163 SQL/RLS suite for the R6A-019 correction
- Original scenario: switch the SQL session to `authenticated` and calculate the target Tournament ID with a subquery against the harness temporary table `r6a_state`.
- Observed result: PostgreSQL correctly rejects the temporary-table read with `permission denied for table r6a_state`, so the assertion stops before exercising `pachanga_tournament_invalidations` RLS.
- Expected result: fixture state is resolved before assuming the client role; the client-role query touches only the product invalidation table and its RLS predicate.
- Product impact: none. Both product schemas had already installed equivalently in disposable local databases, and the failure occurred inside a transaction that the test runner discards.
- Security boundary: do not grant the client role access to fixture tables and do not execute the RLS assertion as a privileged role.
- Required correction: place the canonical Tournament ID in a transaction-local setting before `SET LOCAL ROLE authenticated`, then use only `current_setting` inside the client-role assertion.
- Required regression: the outsider must read zero invalidations without an ACL error, while the authorized organizer reads at least one; the general actor/capability helper remains non-executable by clients.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - fixture state is resolved into the transaction-local `r6a.competition_id` before assuming the client role;
  - the outsider reads zero invalidations without an ACL error;
  - the authorized organizer reads persisted invalidations through RLS;
  - `authenticated` can execute only `pachanga_tournament_realtime_can_read_v1(uuid)`, while `pachanga_tournament_can_v1(uuid,uuid,text)` remains revoked;
  - upgrade and fresh schemas remain identical and the complete SQL/RLS/idempotency suite passes.

## R6A-021 - Repository configuration disables remote migration push during branch reconstruction

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: clean reconstruction of the fourth disposable Supabase branch
- Original scenario: apply the immutable baseline, repair the exact 36 absorbed migration versions, and ask `supabase db push --db-url` to replay the remaining `origin/main` migrations.
- Observed result: the CLI reports `Skipping migrations because it is disabled in config.toml`; the branch remains consistently at the baseline ledger of 36 and no incremental or R6A migration is applied.
- Expected result: the staging reconstruction reaches the exact production ledger 158 before applying the five R6A artifacts.
- Product impact: none. Only the disposable branch was addressed, production remained read-only and the stopped branch contains the expected baseline schema and 36-version ledger.
- Security boundary: do not enable global migration push as a side effect, do not link the worktree to production and do not mark versions that were not actually executed.
- Required correction: replay the immutable `origin/main` incrementals 37-158 through the session pooler with `psql`, repair only those successfully executed versions from the exported migration filenames, and require exact production/staging version-name digest equality.
- Required regression: staging must read back `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693` before any R6A migration, then advance to 163 only through the five reviewed artifacts.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - the baseline ledger remained exactly 36 after the disabled push;
  - 122 immutable `origin/main` incrementals were executed through the session pooler with `ON_ERROR_STOP`;
  - only the 122 successfully executed versions were repaired from their exported filenames;
  - staging now matches production at `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693` before R6A.

## R6A-022 - Staging runner attempts a manual swap on an automatic draw mode

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: final authenticated one-shot staging E2E on the clean ledger-163 branch
- Original scenario: generate and regenerate the main `SEEDED_POTS` draw, then call `draw.entry.swap` on that automatic plan before validation.
- Observed result: the server correctly rejects the command with `DRAW_MANUAL_EDIT_NOT_AVAILABLE` because manual place, move, swap and remove operations are limited to `MANUAL_ASSISTED` and `HYBRID` plans.
- Expected result: automatic draw determinism remains tested on the seeded plan, while manual swapping is exercised on an existing generated `HYBRID` plan using two unlocked participants.
- Product impact: none. The authority rejected the invalid command, the runner entered its cleanup path, restored temporary flags and did not create Tournament matches. Production was not addressed.
- Security boundary: do not broaden manual editing to automatic modes, weaken draw-plan state checks or change product SQL to accommodate an invalid QA sequence.
- Required correction: remove the swap from the automatic plan, perform it on the generated hybrid plan, and accept the canonical non-editable error when probing the already published automatic plan.
- Required regression: focused tests must prove that the staging script places `draw.entry.swap` only after a `HYBRID` plan has been generated and that a fresh authenticated E2E completes the swap before cleanup.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the final E2E performed the swap on the generated
  HYBRID plan, preserved two locks and kept automatic/published plans
  non-editable.

## R6A-023 - Disposable-branch cleanup readback used stale schema and CLI assumptions

- Classification: `TESTABILITY_GAP`
- Status: `FIXED`
- Found by: cleanup preflight after the failed one-shot staging E2E
- Original scenario: count Tournament rows through a non-existent `competition_kind` column and list branch-scoped Vercel variables with an unsupported `--git-branch` option.
- Observed result: PostgreSQL returned `42703 column competition_kind does not exist`; Vercel CLI 59.4.0 rejected the option, and the first JSON-shape assumption for `env ls --json` was also invalid.
- Expected result: readbacks use the canonical `competition_type = 'TOURNAMENT'` discriminator, inspect flags through `private.pachanga_competition_foundation_settings`, and use the documented positional Git-branch argument for Vercel environment commands.
- Product impact: none. Both failures were read-only diagnostics; no row, flag, migration, deployment or production resource was modified.
- Security boundary: do not infer environment-variable values from CLI output, expose secrets while inspecting shape, or broaden cleanup beyond the exact disposable branch and its three known Vercel variables.
- Required correction: derive the readback from the actual information schema and migration functions, remove the exact branch-scoped variables with positional CLI arguments, and tear down only deployment `dpl_44uiDqSoRVb4Eypx2KGmfofupabb` plus Supabase branch `6c23afdf-0853-48e9-a1a7-7c0cdcc53dcf`.
- Required regression: the corrected readback must prove ledger 163, Tournament flags restored, zero Tournament match contexts, identify any disposable QA rows, and cleanup commands must leave the unrelated `pwa-bridge-staging` branch untouched.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - corrected readback proved ledger `163 / 20260826195040 / 53b5456c21933e614752179568576d18`;
  - all eleven Tournament flags were restored to `OFF`, with two cancelled disposable Tournaments, one DrawPlan, twenty QA users and zero Tournament match contexts;
  - the three exact branch-scoped Vercel variables, deployment `dpl_44uiDqSoRVb4Eypx2KGmfofupabb` and branch `6c23afdf-0853-48e9-a1a7-7c0cdcc53dcf` were removed;
  - `pwa-bridge-staging` remained present and untouched.

## R6A-024 - Incremental reconstruction filter parses the absolute path instead of the migration basename

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: clean fifth staging-branch reconstruction at ledger 36
- Original scenario: select the 122 post-baseline migrations with an `awk` expression that tries to locate the 14-digit version inside each absolute path.
- Observed result: the selector returns zero files and the explicit count guard stops with `incremental file count mismatch: 0` before any incremental SQL or migration-history repair runs.
- Expected result: extract the version from each migration basename, compare it lexicographically with the immutable `absorbsThrough` boundary and require exactly 122 ordered files.
- Product impact: none. The branch remains at the correctly applied baseline and exact 36-version absorbed ledger; production and the unrelated staging branch are untouched.
- Security boundary: do not weaken the exact count guard, infer versions from directory names, skip failed migrations or repair history for SQL that did not execute.
- Required correction: build the ordered file list with a portable basename comparison, execute every migration transactionally, and repair only the 122 versions after all SQL files succeed.
- Required regression: staging must reach exactly `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693` before any R6A artifact is applied.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - basename filtering selected exactly 122 ordered post-baseline migrations;
  - all 122 executed transactionally before migration-history repair;
  - the branch reached exactly `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693`;
  - native branch rebase preserved the same count, last version and digest;
  - only then did the five reviewed R6A artifacts advance the branch to ledger 163.

## R6A-025 - Preview deployment includes uncommitted incident documentation

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: Vercel deployment metadata preflight before authenticated staging E2E
- Original scenario: deploy the corrected runtime commit after recording two reconstruction incidents locally but before committing those documentation-only changes.
- Observed result: deployment `dpl_3gNYzb2YUVzican4io2mTqS6BJcU` is `READY` and reports the intended runtime SHA, but Vercel metadata also reports `gitDirty = 1`.
- Expected result: the certification Preview is built from a clean, published branch HEAD with `gitDirty = 0`, so its artifact maps unambiguously to one immutable commit.
- Product impact: none. The only uncommitted paths are the incident ledger; no authenticated E2E or Tournament command has run on the clean fifth Supabase branch.
- Security boundary: do not ignore dirty provenance, rewrite the existing commit, or run certification against an artifact whose source cannot be reproduced exactly.
- Required correction: commit and publish the incident evidence, remove the dirty Preview, and deploy the new clean HEAD against the unchanged branch-scoped Supabase environment.
- Required regression: Vercel must report `READY`, the exact new commit SHA and `gitDirty = 0` before the one-shot E2E begins.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - dirty deployment `dpl_3gNYzb2YUVzican4io2mTqS6BJcU` was removed before certification;
  - clean deployment `dpl_GgnxzDuq4RqLi14MKQAsjvvQ3QVh` reached `READY` from published commit `a19545455b917a39fa8d8703c22702da2304f303` with no `gitDirty` metadata;
  - `/torneos`, `/torneos/crear`, `/laboratorio-tournament-draw`, `/demo?demo=1&world=tournament`, `/manifest.webmanifest` and `/sw.js` returned `200` through authenticated Vercel access;
  - production was not addressed.

## R6A-026 - Tournament invalidation is not delivered after the Realtime RLS correction

- Classification: `PRODUCT_BUG`
- Status: `FIXED`
- Found by: final authenticated one-shot staging E2E on the clean ledger-163 branch after the R6A-019 RLS correction.
- Original scenario: subscribe as the authenticated Tournament organizer, wait for the Supabase client to report `SUBSCRIBED`, accept participants through the canonical command RPC and await the filtered invalidation insert.
- Observed result: the channel reported `SUBSCRIBED`, but no event reached the callback within 15 seconds and the runner stopped with `R6A_REALTIME_TIMEOUT`. Realtime logs show the disposable tenant starting its stream-replication slot during the same cold-start window and contain no `42501` or `apply_rls` permission error. The server persisted 34 invalidations for the target Tournament, including rows after logical decoding reached a consistent point.
- Expected result: the client and staging certification must distinguish WebSocket subscription from Postgres replication readiness, refetch canonically at both lifecycle points and prove one real post-readiness event before accepting the transport gate.
- Product impact: the server-authoritative command state remains canonical, but a Tournament client could refetch too early and miss a change made in the gap between WebSocket subscription and replication readiness until another invalidation or reconnect. The runner entered cleanup and production was not addressed.
- Security boundary: do not consume WAL payloads as authority, weaken RLS, convert a timeout into a pass, or silently retry the one-shot scenario on the mutated branch.
- Interim correction invalidated by regression: the client and runner opted into `config.broadcast.replication_ready` and waited for `extension = system`. A seventh clean branch still missed 16 persisted invalidations because that signal certified the `realtime.messages` Broadcast connection rather than the `postgres_changes` subscription used by Tournament invalidations.
- Current diagnostics: an authenticated-role readback with organizer JWT claims sees the target invalidations through RLS; `authenticated` cannot execute the general capability helper and can execute only the dedicated current-actor Realtime predicate. Realtime and PostgreSQL logs contain no `42501` or `apply_rls` error. A protocol probe captured `SUBSCRIBED`, then `system { extension: postgres_changes, status: ok, message: Subscribed to PostgreSQL }`, then the inserted invalidation. Repeating the probe without `config.broadcast.replication_ready` preserved that ordering and removed the unrelated `extension = system` signal.
- Required correction: remove the Broadcast readiness option, refetch the Tournament read model only after the successful `postgres_changes` system signal, and prevent the E2E from issuing observed commands until both channel subscription and PostgreSQL subscription readiness are confirmed.
- Required regression: a fresh one-shot E2E must observe a real invalidation after the tenant is ready, refetch the canonical snapshot, complete every draw history, restore flags and leave zero Tournament matches.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: a fresh one-shot E2E observed the
  `postgres_changes` readiness signal, then a real invalidation, refetched the
  canonical snapshot, completed every draw history, restored all flags and
  left zero Tournament match contexts.

## R6A-027 - Final staging readback references a non-existent match table

- Classification: `TESTABILITY_GAP`
- Status: `FIXED`
- Found by: read-only post-failure staging diagnostic after R6A-026.
- Original scenario: assemble one consolidated readback for ledger, flags, Tournament fixtures, invalidations, publication and function ACLs.
- Observed result: PostgreSQL rejected the diagnostic with `42P01 relation public.pachanga_matches does not exist` before returning any readback row.
- Expected result: the zero-Tournament-match assertion derives its source from the current canonical schema and remains valid across the reconstructed production baseline.
- Product impact: none. The failed statement was read-only and returned no partial result; flags, fixtures and production were not modified.
- Security boundary: do not create a compatibility table, infer a zero from the failed query, or weaken the explicit zero-match release gate.
- Required correction: inspect the current catalog and reuse the same canonical match-context source already exercised by the R6A SQL and staging suites.
- Required regression: the corrected readback must execute successfully and report the exact ledger, restored flags, Tournament row counts, Realtime ACL/publication state and zero Tournament match contexts.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - the canonical source is `public.pachanga_competition_match_contexts` joined to `public.pachanga_competitions` by `competition_id`;
  - the corrected readback returned ledger `163 / 20260826195040 / 53b5456c21933e614752179568576d18`;
  - all eleven Tournament flags were restored to `OFF`, the Realtime publication and narrow helper ACL were present, and Tournament match contexts were exactly zero;
  - the diagnostic remained read-only and production was not addressed.

## R6A-028 - JavaScript orchestration expands Bash array-length syntax

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: sixth disposable-branch reconstruction command composition.
- Original scenario: pass the reviewed portable Bash reconstruction script through the JavaScript tool orchestrator using a template literal.
- Observed result: JavaScript parsed Bash `${#array[@]}` as template interpolation and stopped with `Private field '#absorbed' must be declared in an enclosing class` before launching the shell.
- Expected result: the orchestrator forwards Bash parameter expansion verbatim and the shell executes the existing exact-count guards.
- Product impact: none. No command reached Supabase, no migration or history row was applied, and production was not addressed.
- Security boundary: do not remove the 36/122 count assertions or replace the exact migration selection with inferred history.
- Required correction: escape JavaScript template interpolation while preserving the Bash script byte-for-byte at the shell boundary.
- Required regression: the command must launch, report baseline `36|20260731080738`, select exactly 122 incrementals and reach the exact production digest at ledger 158.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - the escaped command launched under macOS Bash without changing any count guard;
  - the baseline reached exactly `36|20260731080738`;
  - basename selection returned exactly 122 ordered incrementals;
  - staging reached exactly `158|20260826123500|ff75c105ff5fa08802cc004390e29693` before any R6A migration.

## R6A-029 - Published audit assertion reads quality from an absent top-level field

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: authenticated one-shot staging E2E after successful replication-readiness and Realtime invalidation delivery.
- Original scenario: publish the deterministic seeded draw, load its participant-visible audit read model and assert zero hard violations through `audit.quality.hardViolations`.
- Observed result: the audit response has no top-level `quality` object and the runner stops with `TypeError: Cannot read properties of undefined (reading 'hardViolations')`.
- Expected result: the E2E asserts the canonical published-audit contract at its actual stable location, or the product read model explicitly exposes the documented quality field if that field is part of the public contract.
- Product impact: Realtime transport, deterministic generation and publication completed; certification stopped while interpreting the read model. The disposable branch entered cleanup and production was not addressed.
- Security boundary: do not expose private solver diagnostics, bypass the participant audit RPC, infer zero violations from successful publication or silently remove the assertion.
- Required correction: compare the RPC implementation, UI consumer, local SQL contract and actual staging payload to determine the authoritative audit shape before changing either product or runner.
- Correction implemented: the runner now asserts `validationStatus = VALID`, `manualOverrideCount = 0` and the public hard `SAME_CLUB_AVOIDANCE` constraint. It no longer expects the private solver-quality object. The participant-visible RPC and product UI remain unchanged.
- Contract evidence: authenticated readback from the disposable branch returned `validationStatus = VALID`, one public hard `SAME_CLUB_AVOIDANCE` constraint, `manualOverrideCount = 0`, 16 placements and no top-level `quality` field.
- Required regression: a fresh one-shot E2E must validate quality through the canonical audit contract, complete all remaining histories, restore flags and leave zero Tournament matches.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the final authenticated E2E validated the published
  audit through `validationStatus`, public hard constraints and
  `manualOverrideCount`, then completed all remaining histories and cleanup.

## R6A-030 - Final readback uses the obsolete Tournament discriminator name

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: post-E2E staging readback and PostgreSQL logs.
- Original scenario: count Tournament competitions after the final authenticated E2E with `competition_kind = 'TOURNAMENT'`.
- Observed result: PostgreSQL correctly rejects the read-only diagnostic with `42703 column competition_kind does not exist` because the canonical discriminator is `competition_type`.
- Expected result: release readbacks use the canonical schema and complete without adding noise to PostgreSQL error logs.
- Product impact: none. The statement was read-only, returned no partial row and did not change flags, fixtures, migrations or production.
- Security boundary: do not create a compatibility column, infer a zero from a failed query or alter the canonical Competition schema for a release diagnostic.
- Correction: the readback now uses `competition_type = 'TOURNAMENT'` and joins Tournament match contexts through `competition_id`.
- Required regression: the corrected readback must return ledger 163, all Tournament flags OFF, the disposable fixture counts, zero active grants and zero Tournament match contexts.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the corrected readback returned `163 / 20260826195040 / 53b5456c21933e614752179568576d18`, eleven flags OFF, five disposable Tournaments, zero active grants and zero Tournament match contexts.

## R6A-031 - Manual Vercel Preview ignores branch-scoped Supabase variables

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: browser-bundle credential and project-ref scan after the final staging E2E.
- Original scenario: add three Preview variables scoped to `codex/tournament-foundation-draw-engine-v1` and create a manual CLI deployment from a clean worktree.
- Observed result: deployment `dpl_Hgu8b98oJyQ1D58UL4qde1WJTrjd` is `READY` at commit `285a05706228384ede174e9dce4f3a3f0be67152`, but its browser chunks contain production ref `qonbngfrnrqgmxbdfbea` and do not contain staging ref `zmjmzgdwovluvakfjggs`. The deployment has no `gitSource`, so Vercel did not select the branch-scoped environment.
- Expected result: the certification Preview contains only the ephemeral staging project ref and browser publishable key; production and unrelated staging refs are absent, and service-role material remains server-only.
- Product impact: no Tournament mutation reached production because the Preview smoke was unauthenticated and the authenticated E2E addressed staging directly. The Preview cannot certify product-to-staging integration and must be replaced.
- Security boundary: do not continue with the mismatched Preview, do not expose service-role material through build variables, and do not modify general Preview or Production variables.
- Required correction: build and deploy an exact clean artifact with an explicitly pulled branch environment or safe build/runtime overrides, then scan every browser chunk for project refs and the exact service-role secret before rerunning the Preview integration gate.
- Required regression: the replacement deployment must be `READY` at the exact branch HEAD, contain staging ref `zmjmzgdwovluvakfjggs`, contain neither production nor unrelated-staging refs, contain no service-role value, return the six protected routes as `200` and complete the authenticated E2E against the same staging ref.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: automatic Git deployment
  `dpl_CcoXgisaJH6jQ68vpRcgcU3SaGNR` reached `READY` at exact commit
  `5cd821c55a009bf4a74e020d60a7228edbb8a2c0`; its bundle contains only the
  intended staging ref, all six protected routes return HTTP 200 and runtime
  logs contain zero error/fatal entries.

## R6A-032 - zsh route loop shadows the executable search path

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: six-route smoke on the replacement Git Preview.
- Original scenario: iterate the protected Preview routes with a zsh variable
  named `path` and call `vercel curl` inside the loop.
- Observed result: zsh treats `path` as its special array tied to `PATH`; the
  assignment removes the executable search path and every iteration reports
  `command not found: vercel` before sending a request.
- Expected result: the diagnostic uses a neutral loop variable and returns an
  explicit HTTP status for each protected route.
- Product impact: none. No HTTP request, deployment, database command, flag or
  production action occurred.
- Security boundary: do not infer route success from blank output and do not
  bypass Deployment Protection to compensate for a local shell error.
- Required correction: rename the loop variable, rerun the exact six routes
  through authenticated `vercel curl` and require six HTTP 200 responses.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the neutral `route_name` variable preserved `PATH` and
  `/torneos`, `/torneos/crear`, `/laboratorio-tournament-draw`, Demo V2.4,
  manifest and Service Worker each returned HTTP 200.

## R6A-033 - Read-only browser evaluation does not expose fetch

- Classification: `TESTABILITY_GAP`
- Status: `FIXED`
- Found by: responsive/PWA browser smoke on the replacement Git Preview.
- Original scenario: after validating portrait and landscape DOM geometry,
  call `fetch` inside the browser runner's read-only evaluation to inspect the
  manifest and Service Worker responses.
- Observed result: the isolated evaluation reports `TypeError: fetch is not a
  function` after the responsive measurements and before returning the grouped
  result.
- Expected result: visual DOM checks and HTTP asset checks return independently
  so a runner capability limitation cannot obscure evidence already collected.
- Product impact: none. The protected manifest and Service Worker had already
  returned HTTP 200 through `vercel curl`; no browser or server state changed.
- Security boundary: do not weaken Deployment Protection or inject a page
  script solely to add network access to a read-only evaluation.
- Required correction: read responsive geometry and console state in the
  browser, and retain the authenticated HTTP evidence for manifest/SW from
  `vercel curl` as a separate gate.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: browser checks independently returned desktop,
  `390x844` and `844x390` geometry with zero overflow, broken images, overlays
  or console errors; authenticated HTTP checks independently returned 200 for
  manifest and Service Worker.

## R6A-034 - Browser runner cannot certify installed standalone display mode

- Classification: `TESTABILITY_GAP`
- Status: `OPEN`
- Found by: replacement Git Preview PWA smoke.
- Original scenario: request `display-mode: standalone` through the available
  CDP emulated-media command at `390x844` and verify the page media query.
- Observed result: the page remains in browser display mode even though the DOM
  is responsive and error-free; the current browser runner does not create an
  installed PWA application window.
- Expected result: an installed-PWA run proves the standalone media state and
  app-shell behavior on the exact release artifact.
- Product impact: no defect demonstrated. Manifest and Service Worker return
  HTTP 200, local PWA emulation passed, and browser/portrait/landscape Preview
  checks are clean.
- Security boundary: do not fake `matchMedia`, inject state into the page or
  report physical/installed QA as passed.
- Required follow-up: retain `PWA instalada fisica: PENDING` and test on a real
  installed device after release; this is explicitly non-blocking under the
  R6A release contract.
- Regression status: `PENDING_PHYSICAL_QA`.

## R6A-035 - GitHub HTTPS push stalls after the local commit

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: publication of the final Preview evidence commit.
- Original scenario: push commit
  `396313f` to `codex/tournament-foundation-draw-engine-v1` over the configured
  GitHub HTTPS remote.
- Observed result: `git-remote-https` remains blocked for more than one minute
  without output or completion after the earlier network interruption.
- Expected result: the remote either accepts the commit or returns an explicit
  network/authentication error within a bounded interval.
- Product impact: none. The commit is durable locally; no Supabase, Vercel or
  production state changed during the stalled transport.
- Security boundary: do not start concurrent pushes, rewrite the commit or
  assume remote success without reading the remote branch SHA.
- Required correction: stop only the stalled process, query the remote branch,
  retry once if the SHA is absent, and confirm exact remote/local equality.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence: the stalled process was stopped without another push in
  flight; `ls-remote` proved the commit absent, one bounded retry succeeded,
  and local/remote now both resolve to
  `841fc60b75ccb537669d9e0fd6da625884393584`.

## R6A-036 - Release worktree has no Supabase linked project ref

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: mandatory production `supabase migration list --linked` preflight.
- Original scenario: run the linked migration reconciliation from the isolated
  R6A worktree before any production write.
- Observed result: Supabase CLI 2.107.0 stops with `Cannot find project ref`;
  no remote request or database mutation is made.
- Expected result: the release preflight addresses the known production ref
  explicitly and proves remote/local history equality before migration.
- Product impact: none. Production remains at ledger 158 and no migration, flag
  or data command has run.
- Security boundary: do not infer a ref from browser state, do not link to the
  unrelated `pwa-bridge-staging` project and do not continue on a failed list.
- Required correction: establish only the verified production link or use the
  explicit production connection for readback, repeat migration reconciliation
  and require the exact 158-version digest before applying R6A.
- Correction: linked the isolated worktree explicitly to the verified Pachangas
  IQ production ref and repeated `supabase migration list --linked`. Local and
  remote histories match through version `20260826123500`; only the five ordered
  R6A versions remain local-only.
- Regression status: `REGRESSION_VERIFIED`.

## R6A-037 - Data-only logical backup reports circular foreign keys

- Classification: `TESTABILITY_GAP`
- Status: `FIXED`
- Found by: pre-migration production logical backup.
- Original scenario: dump the linked production schema and then all application
  data with `supabase db dump --data-only --use-copy`.
- Observed result: pg_dump completes extraction but warns that multiple
  canonical revision/evidence tables have circular foreign keys and that a
  plain data-only restore may require disabled triggers.
- Expected result: release evidence proves a usable recovery path rather than
  treating file creation alone as restoration proof.
- Product impact: none. The operation is read-only and production remains at
  ledger 158.
- Security boundary: keep dumps mode 600, do not print their contents or retain
  production data beyond the release window, and do not restore over staging or
  production.
- Required correction: validate schema plus data in an isolated PostgreSQL
  target with the documented trigger strategy, or confirm a completed managed
  backup through the Supabase backup API before applying migrations.
- Correction: restored the application schema into an isolated PostgreSQL
  17.6 target after bootstrapping the external Supabase Auth and Realtime
  primitives that are intentionally outside the application dump. Regenerated
  the data-only backup with the strict `public,private` schema perimeter and
  restored it with `session_replication_role = replica` for the load only.
- Regression evidence: the production dump and restored database contain the
  same 272 application tables and 1,536 rows, with zero per-table count
  differences. No staging or production data was modified.
- Regression status: `REGRESSION_VERIFIED`.

## R6A-038 - CLI cannot cache pg-delta catalog after production push

- Classification: `ENVIRONMENT_ISSUE`
- Status: `FIXED`
- Found by: production `supabase db push` after the five reviewed R6A files.
- Original scenario: apply exactly the five dry-run-approved migrations through
  the linked CLI release workdir and allow the CLI to refresh its local
  pg-delta catalog.
- Observed result: all five migrations report as applied and the command exits
  successfully, but the optional catalog-cache export warns that its container
  cannot read the temporary `pgdelta-target-ca.crt` path.
- Expected result: the database migration and the local catalog refresh both
  complete without warnings.
- Product impact: pending direct readback. No flag activation or Tournament data
  command has run after the warning.
- Security boundary: do not repair migration history or rerun applied SQL merely
  to populate a local cache; verify the remote ledger and schema directly.
- Required correction: prove versions, names, flag defaults, ACL and schema by
  remote readback, then treat only the disposable local pg-delta cache as stale.
- Correction: no migration was repeated or history repaired. Direct PostgreSQL
  readback returned ledger `163 / 20260826195040 /
  53b5456c21933e614752179568576d18`, the exact five R6A names, all eleven flags
  OFF, zero Tournament rows, RLS enabled, the invalidation table in Realtime and
  the reviewed function ACL matrix.
- Regression status: `REGRESSION_VERIFIED`.

## R6A-039 - Transactional canary assumes Competition Foundation is already active

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: pre-production rehearsal on the disposable R6A Supabase branch.
- Original scenario: execute the production rollback canary after the staging
  certification has restored every feature flag to its original OFF value.
- Observed result: the canonical `tournament.flags.set` command rejects the
  attempted private-beta activation with
  `TOURNAMENT_FOUNDATION_DEPENDENCY_DISABLED` before any Tournament, grant or
  DrawPlan is created.
- Expected result: the transaction-scoped canary must establish every existing
  prerequisite through its canonical platform RPC, independently of the
  disposable branch's restored flag state, and roll those changes back with the
  rest of the fixture.
- Product impact: none. The platform dependency guard behaved correctly, the
  statement aborted atomically, and neither staging nor production retained a
  write.
- Security boundary: do not update settings directly, weaken the dependency
  guard or persist staging activation merely to make the harness pass.
- Required correction: call the existing revisioned
  `foundation_flags.set` platform command inside the same explicit transaction
  before activating Tournament capabilities.
- Required regression: the complete canary must pass on the restored-OFF
  disposable branch, return its evidence row, execute the final `ROLLBACK` and
  leave the branch at the exact pre-run flag and fixture counts.
- Correction: the canary now establishes Competition Foundation through
  `command_pachanga_competition_platform_v1` before the Tournament flag command;
  no settings table is updated directly.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - the complete RPC-only story returned `PASS` with 8 accepted participants,
    one freeze, 4 pots, one manual move, 2 active locks, a valid hybrid result,
    8 audited placements and zero Tournament match contexts;
  - the final explicit `ROLLBACK` removed the run tag entirely;
  - independent branch readback returned the exact pre-run state: 5 historical
    disposable Tournaments, 1 non-cancelled plan, 16 current placements, zero
    active grants and all eleven Tournament flags OFF.

## R6A-040 - Final production readback references an obsolete notification table

- Classification: `SIMULATION_BUG`
- Status: `FIXED`
- Found by: independent readback immediately after the successful production
  rollback canary.
- Original scenario: verify that the canary run tag left no notification row by
  querying `public.pachanga_notifications` alongside Tournament counts, flags
  and migration history.
- Observed result: PostgreSQL rejects the read-only statement with `42P01`
  because that relation does not exist in the canonical production schema.
- Expected result: the release readback resolves the current notification
  relation from the repository/catalog and returns every requested count in one
  successful read-only result.
- Product impact: none. The failed statement was read-only, the canary had
  already completed its explicit `ROLLBACK`, and no partial result is treated
  as evidence.
- Security boundary: do not create a compatibility table, infer zero from the
  failed query or omit the notification-residue check silently.
- Required correction: identify the canonical notification table and its
  columns from the production catalog, then repeat the complete readback.
- Required regression: the corrected statement must return ledger 163, the
  final private-beta flag matrix, zero run-tag residue and zero Tournament
  competitions, plans, placements, grants and match contexts.
- Correction: production catalog readback identified
  `public.pachanga_user_notifications` with canonical `title`, `body` and
  `payload` fields; the complete diagnostic now uses that relation.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - ledger `163`, last version `20260826195040` and the exact five ordered R6A
    names;
  - settings revision `11`, eight private-beta capabilities ON and Public
    Discovery, Match Generation and Bracket Progression OFF;
  - zero run-tag competitions, groups and notifications;
  - zero Tournament competitions, active DrawPlans, current placements, active
    grants and canonical match contexts;
  - `pachanga_tournament_invalidations` remains in `supabase_realtime`.

## R6A-041 - Isolated browser evaluation omits the navigator global alias

- Classification: `TESTABILITY_GAP`
- Status: `FIXED`
- Found by: production PWA controller readback after the responsive smoke.
- Original scenario: inspect Service Worker support, controller and
  registrations with `navigator.serviceWorker` inside the browser runner's
  read-only evaluation context.
- Observed result: the runner throws `TypeError` because its isolated context
  does not expose the bare `navigator` alias, although `window`, the DOM and
  responsive geometry are available.
- Expected result: the diagnostic reads the real page-owned browser API without
  injecting or faking PWA state.
- Product impact: no product defect demonstrated. Manifest and Service Worker
  already return HTTP 200, the Service Worker has the exact release SHA and the
  visual routes remain clean.
- Security boundary: do not fabricate `matchMedia`, emulate installed mode or
  present physical PWA QA as passed.
- Required correction: read the same native object through `window.navigator`
  or a supported CDP page context, then retain physical installed-PWA QA as
  `PENDING`.
- Required regression: the corrected diagnostic must report the production
  Service Worker registration/controller without altering page state; physical
  standalone/fullscreen remains explicitly unverified.
- Correction: the final readback uses the supported CDP page context rather
  than the runner's isolated evaluator.
- Regression status: `REGRESSION_VERIFIED`.
- Regression evidence:
  - Service Worker support is present;
  - the active registration and current controller both resolve to
    `https://pachangasiq.com/sw.js` with root scope;
  - no worker is waiting or installing;
  - browser display mode correctly remains neither standalone nor fullscreen;
  - physical installed-PWA, Android and iPhone QA remain `PENDING` and are not
    represented as PASS.
