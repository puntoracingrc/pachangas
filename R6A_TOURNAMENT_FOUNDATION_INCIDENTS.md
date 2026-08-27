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
