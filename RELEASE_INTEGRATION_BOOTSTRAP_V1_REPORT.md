# Release Integration and Database Bootstrap V1

## Audit identity

- Base commit: `e50fac5f97eca5cd07765c869a08a8f9d3284924` (PR #120).
- Branch: `codex/release-integration-bootstrap-v1`.
- Started: 2026-08-09, Europe/Madrid.
- Environment: isolated Git worktree, local Docker/PostgreSQL/Supabase-compatible services only.
- Production: not accessed or modified.
- Supabase remote: not accessed or modified.
- Product semantics: frozen for this task.

## Permanent integration incidents

### RI-001 - ENVIRONMENT_ISSUE - zsh pair splitting in ancestry audit

- Status: fixed, regression verified.
- Expected: every adjacent PR head is checked with two explicit SHA arguments.
- Actual: the first audit loop passed a quoted pair as one object name under `zsh`, `git merge-base` failed, and the diagnostic line still printed `ancestor=yes`.
- Impact: diagnostic only; no repository or database state changed.
- Reproduction: run `set -- $pair` in `zsh` without `SH_WORD_SPLIT`, then call `git merge-base --is-ancestor "$1" "$2"`.
- Resolution: replaced the implicit pair split with explicit `a` and `b` extraction.
- Regression evidence: all six adjacent ancestry checks passed from base `53fa0860` through PR #120 `e50fac5f`.

### RI-002 - ENVIRONMENT_ISSUE - invalid disposable Supabase config rewrite

- Status: fixed, regression verified.
- Expected: start an isolated local Supabase database and replay historical migrations.
- Actual: the temporary copied config was rejected before container startup with `Unsupported Config Type`.
- Impact: no migration ran and no repository, existing container or database state changed.
- Root cause: the locally configured Supabase CLI profile was rejected before project parsing.
- Resolution: ran the disposable project with an isolated temporary `HOME`, avoiding global CLI state.
- Regression evidence: the isolated Supabase platform initialized and began replaying repository migrations.

### SW-0134 - PRODUCT_BOOTSTRAP_BUG - historical chain depends on an unversioned table

- Status: fixed, regression verified.
- Environment: disposable Supabase/PostgreSQL 17 project `pachangas-bootstrap-repro-v1` on dedicated local ports and volume.
- Bootstrap input: the 80 repository migrations only; `supabase/pachangas.sql` was deliberately absent.
- Applied successfully: migrations 1-10, through `20260728191429_harden_pachanga_critical_actions.sql`.
- Failing migration: `20260728191804_require_registered_users_for_group_policies.sql`, statement 15.
- Exact error: `relation "public.pachanga_admin_invites" does not exist (SQLSTATE 42P01)`.
- Missing dependency: `public.pachanga_admin_invites` is defined in the unversioned consolidated `supabase/pachangas.sql`, but no earlier migration creates it.
- Cause: development historically combined a manually applied consolidated schema with later migrations. The migration ledger therefore described upgrades to that implicit baseline, not a complete empty-database bootstrap.
- Resolution: preserve migrations 1-36 as deployed audit history and introduce the immutable, hash-verified fresh-install baseline `20260731080738_pachangas_product_baseline.sql`; existing installations continue only through their ledger.
- Regression evidence: Route A reaches all 80 migration versions from an empty platform, Route B upgrades from version 77, and both export the exact same normalized schema contract.

### RI-003 - TESTABILITY_GAP - schema contract exceeded the child-process buffer

- Status: fixed, regression verified.
- Expected: export the complete normalized product schema contract for Route A.
- Actual: `spawnSync psql` stopped with `ENOBUFS` while returning function definitions.
- Impact: read-only diagnostic failure; database and repository schema were not modified.
- Resolution: the exporter uses an explicit 128 MiB maximum buffer.
- Regression evidence: both 1,957,884-byte route contracts exported and matched byte for byte.

### RI-004 - ENVIRONMENT_ISSUE - local CLI database URL attempted TLS

- Status: fixed, regression verified.
- Expected: Supabase CLI repairs the migration ledger over the isolated loopback PostgreSQL URL.
- Actual: the baseline transaction completed, then `supabase migration repair --db-url` failed because the local server refused TLS.
- Impact: the disposable Route A database was left with only the baseline and will be destroyed before retry; no shared or remote database was touched.
- Resolution: product SQL continues to use the validated loopback URL, while Supabase ledger operations use the CLI's local-project mode and explicit workdir.
- Regression evidence: Route A recorded all 80 migrations and completed with `BOOTSTRAP_COMPLETE` after a full volume deletion.

### RI-005 - MIGRATION_CONTRACT - Core Social migration is intentionally non-reentrant

- Status: documented; no product fix required.
- Expected: the migration ledger applies `20260809214500_core_social_flows_closure_v1.sql` exactly once.
- Actual under forced SQL replay: PostgreSQL rejects recreation of `respond_pachanga_team_challenge_without_expiry_v1(...)` because the internal function already exists.
- Impact: none in the supported path. `supabase migration up` reports the database is up to date and does not replay the file.
- Safety evidence: the forced replay ran inside a transaction, rolled back on error and left the schema contract SHA-256 unchanged.
- Decision: do not add broad `IF EXISTS` guards to conceal an unsupported raw migration replay.

### RI-006 - TESTABILITY_GAP - stacked Core Social changed the historical Team Social fixture outcome

- Status: fixed, regression verified.
- Expected: `tests/team-social-db.sql` passes after migrations #118-#120.
- Actual: the idempotent-create assertion at line 98 did not find exactly one challenge.
- Prior gates: Rating V2 SQL and concurrency both passed on the same rebuilt database.
- Root cause: the test used global `count(*)` and `limit 1` assertions. The pre-existing Route B compatibility Reto was therefore counted as if it belonged to the test transaction.
- Impact: the joint DB suite stopped immediately; the failing test transaction was rolled back.
- Resolution: scope every affected assertion to the test groups and operation identifiers; no product RPC or migration changed.
- Regression evidence: `test:team-social:db` passes on the same populated Route B database while the unrelated compatibility Reto remains present.

### RI-007 - TESTABILITY_GAP - achievements fixture accepted an already expired Reto

- Status: fixed, regression verified.
- Expected: achievements SQL creates an external historical match used to test progression.
- Actual: its helper created a Reto one day in the past and changed it to `accepted`; the Core Social deadline guard correctly rejected that transition.
- Impact: the achievements test transaction rolled back; product data remained unchanged.
- Resolution: accept the synthetic Reto with a future lifecycle date, then set only the generated external match's sporting date to the requested historical timestamp.
- Product code changed: no.
- Regression evidence: the complete achievements/crests SQL suite passes with Core Social active.

### RI-008 - TESTABILITY_GAP - historical achievement fixture no longer reaches its first-win expectation

- Status: fixed, regression verified.
- Expected: after the corrected challenge lifecycle, the first external win awards the match and win achievements once.
- Actual: the assertion at `tests/achievements-crests-db.sql:257` failed.
- Impact: the test transaction rolled back; no product or fixture data persisted.
- Root cause: the test expected legacy catalog key `team.external.matches.001`; catalog V3 canonically uses `team.matches.001` while retaining `team.external.wins.001`.
- Resolution: update only the historical assertion to the current catalog key.
- Product code changed: no.
- Regression evidence: the complete achievements/crests SQL suite passes and verifies the canonical V3 grants.

### RI-009 - ENVIRONMENT_ISSUE - temporary diagnostic cleanup command was rejected

- Status: fixed, regression verified.
- Expected: run a truncated achievements fixture and remove its temporary SQL file.
- Actual: command execution was rejected before startup because it contained `rm -f`.
- Impact: no command ran and no file or database state changed.
- Resolution: stream the diagnostic SQL directly to `psql` without creating or deleting a temporary script.
- Regression evidence: the replacement diagnostic is executed through a pipe only.

### RI-010 - TESTABILITY_GAP - diagnostic queried a nonexistent match-fact column

- Status: fixed, regression verified.
- Expected: inspect the first external progression fact and its achievement grants.
- Actual: the read-only query referenced nonexistent `pachanga_progression_match_facts.occurred_at` and aborted the diagnostic transaction.
- Impact: diagnostic transaction rolled back; product data unchanged.
- Resolution: query canonical `played_at` instead.
- Regression evidence: the read-only transaction exposed both match facts and all ten resulting grants, then rolled back.

### RI-011 - ENVIRONMENT_ISSUE - achievements concurrency URL alias was not exported

- Status: fixed, regression verified.
- Expected: continue the integrated SQL/concurrency suite against the isolated Route B database.
- Actual: `test:achievements-crests:concurrency` stopped before opening a database connection because `ACHIEVEMENTS_DATABASE_URL` was absent.
- Impact: no SQL ran and no repository or database state changed.
- Resolution: export every suite-specific database URL alias to the same validated loopback Route B URL before rerunning the sequence.
- Product or test code changed: no.
- Regression evidence: the runner connected to the isolated Route B database and completed successfully.

### RI-012 - TESTABILITY_GAP - achievements concurrency fixture accepted expired challenges

- Status: fixed, regression verified.
- Expected: create two accepted external matches, then exercise publication and expiry races.
- Actual: fixture setup attempted to accept challenges scheduled one and two days in the past; the Core Social deadline guard rejected the transition.
- Impact: setup transaction failed before the race and left no fixture data behind.
- Resolution: accept both synthetic challenges with valid future lifecycle dates, then move only their generated external matches to the historical sporting dates required by the achievements scenario.
- Product code changed: no.
- Regression evidence: `test:achievements-crests:concurrency` passes and still exercises both publication and deadline races.

### RI-013 - TESTABILITY_GAP - catalog V2 suite assumed all V2 collective rows remained active

- Status: fixed, regression verified.
- Expected: the historical V2 progression suite remains useful on the fully integrated V3 schema.
- Actual: its opening assertion required 101 active V2 rows, although catalog V3 intentionally leaves 45 individual V2 definitions active and replaces 56 collective V2 definitions with 60 collective V3 definitions.
- Impact: the test transaction rolled back before generating progression facts.
- Resolution: assert the exact supported split (45 active individual V2 definitions and 60 active collective V3 definitions), then retain the complete historical progression, reward, correction and Rating V2 invariance checks.
- Product code changed: no.
- Regression evidence: the complete V2 progression suite passes on the integrated V3 schema.

### RI-014 - TESTABILITY_GAP - catalog V2 exclusivity assertion failed only inside the integrated fixture

- Status: fixed, regression verified.
- Expected: one player scoring tier per player and canonical match fact.
- Actual: after the 500-match fixture, the global exclusivity assertion found more than one `player.match_goals` grant for at least one origin fact; the populated Route B database has no such duplicate before the test.
- Impact: the test transaction rolled back; no fixture or product data persisted.
- Root cause: the assertion grouped only by `origin_match_fact_id`, so valid scoring tiers belonging to different players in the same match looked like duplicates. Grouping by match fact and `subject_id` shows no duplicates.
- Resolution: enforce exclusivity per player and match fact.
- Product code changed: no.
- Regression evidence: all 500 generated matches pass the per-player highest-tier exclusivity assertion.

### RI-015 - ENVIRONMENT_ISSUE - catalog diagnostic truncated an SQL statement

- Status: fixed, regression verified.
- Expected: run the V2 fixture through its last passing assertion, inspect grants, and roll back.
- Actual: the diagnostic stream stopped at line 258, in the middle of the next `assert_true`, so the appended query caused a syntax error.
- Impact: the diagnostic transaction rolled back and no data persisted.
- Resolution: stop at line 247, after the preceding complete assertion, then append the read-only diagnostic query and explicit rollback.
- Product or test code changed: no.
- Regression evidence: the corrected diagnostic completed, found zero per-player duplicates, and rolled back explicitly.

### RI-016 - TESTABILITY_GAP - catalog V2 recipient assertion inspected unrelated Route B rewards

- Status: fixed, regression verified.
- Expected: every collective reward created by the catalog fixture belongs to a canonical participant in that fixture.
- Actual: the assertion scanned all reward recipients in the populated database and treated valid compatibility-fixture users as foreign recipients.
- Impact: the catalog test transaction rolled back; no fixture or product data persisted.
- Resolution: scope the participant assertion to progression facts owned by the catalog test group.
- Product code changed: no.
- Regression evidence: the scoped canonical-participant assertion and the complete catalog V2 suite pass while Route B compatibility rewards remain present.

### RI-017 - TESTABILITY_GAP - collective box suite expected the pre-V3 reward count

- Status: fixed, regression verified.
- Expected: a canonical 5-0 grants one equivalent sealed box per participant for every qualifying collective achievement.
- Actual: the fixture produced a pending-box count different from the hard-coded four achievements times ten participants.
- Impact: the transaction rolled back; no rewards or fixture data persisted.
- Root cause: catalog V3 canonically adds `team.external.absolute_dominance.001` to a 5-0, producing five team grants and 50 participant boxes instead of the pre-V3 four and 40.
- Resolution: include the fifth canonical key and update every count invariant for this match from 40 to 50.
- Product code changed: no.
- Regression evidence: the complete collective box suite passes with five V3 team grants and 50 sealed participant boxes.

### RI-018 - ENVIRONMENT_ISSUE - collective reward diagnostic used a nonexistent recipient column

- Status: fixed, regression verified.
- Expected: count recipient boxes per achievement key inside the diagnostic transaction.
- Actual: the query referenced `pachanga_reward_recipients.id`; the stable identifier is `box_id`.
- Impact: the diagnostic transaction rolled back; no fixture data persisted.
- Resolution: count non-null `box_id` values.
- Product or test code changed: no.
- Regression evidence: the corrected diagnostic returned five canonical V3 keys with ten boxes each and rolled back.

### RI-019 - TESTABILITY_GAP - box resume assertion retained the pre-V3 pending count

- Status: fixed, regression verified.
- Expected: after opening one of the five V3 boxes assigned to the fixture player, the canonical snapshot exposes four pending boxes.
- Actual: the historical assertion expected three remaining boxes from the former four-box sequence.
- Impact: the transaction rolled back after all preceding box security and opening checks passed.
- Resolution: update only the pending-sequence count from three to four; the four deliberately selected reward-kind boxes remain the focused opening sample.
- Product code changed: no.
- Regression evidence: the canonical snapshot reports four pending boxes after the first opening and the full opening/reconnection sequence passes.

### RI-020 - ENVIRONMENT_ISSUE - notification database URL alias was not exported

- Status: fixed, regression verified.
- Expected: execute the notification foundation SQL against Route B.
- Actual: `psql` fell back to the absent local socket because `NOTIFICATION_DATABASE_URL` was not set.
- Impact: no database connection was established and no SQL ran.
- Resolution: export the notification-specific alias to the same validated loopback Route B URL.
- Product or test code changed: no.
- Regression evidence: the complete notification foundation SQL suite passes against Route B.

### RI-021 - TESTABILITY_GAP - two concurrency suites leave synthetic fixtures behind

- Status: fixed, regression verified.
- Expected: concurrency tests preserve the pre-existing Route B fixture and remove their generated users, groups, evidence and rewards.
- Actual: successful Rating V2 and catalog V3 concurrency runs left one Rating group, two V3 groups and their dependent rows in the disposable database.
- Impact: product behavior passed, but the database was no longer a clean input for Synthetic World or backup/restore validation.
- Resolution: add deterministic, ordered fixture cleanup to both concurrency runners and verify the original Route B counts after execution.
- Product code changed: no.
- Regression evidence: both concurrency suites pass and the database returns to exactly the two `Route B A/B` groups afterward.

### RI-022 - TESTABILITY_GAP - direct synthetic user deletion is blocked by reward evidence

- Status: fixed, regression verified.
- Expected: determine whether deleting only generated `auth.users` could clean the concurrency fixtures by cascade.
- Actual: PostgreSQL correctly rejected deletion because `pachanga_reward_recipients.user_id` is restrictive evidence.
- Impact: the diagnostic transaction aborted and persisted no deletion.
- Resolution: retain the restrictive product foreign key and delete synthetic sealed contents, recipients, grants and dependent evidence explicitly before users.
- Product code changed: no.
- Regression evidence: transactional cleanup removes sealed contents, recipients and grants before users while leaving the restrictive foreign key unchanged.

### RI-023 - ENVIRONMENT_ISSUE - foreign-key diagnostic ordered by an unavailable alias

- Status: fixed, regression verified.
- Expected: inspect deletion actions for references to users, groups and universal profiles.
- Actual: PostgreSQL rejected the metadata query because its `ORDER BY` referenced a projected alias outside the accepted expression scope.
- Impact: read-only diagnostic failure; no state changed.
- Resolution: order by `confrelid`, `conrelid` and the child attribute directly.
- Product or test code changed: no.
- Regression evidence: the corrected query returned the complete deletion-action matrix used to design the ordered cleanup.

### RI-024 - ENVIRONMENT_ISSUE - local API start used obsolete Supabase service aliases

- Status: fixed, regression verified.
- Expected: add PostgREST/Auth/Kong to the isolated DB-only stack for persistent Synthetic World QA.
- Actual: CLI 2.107.0 rejected several exclusion aliases and then reported the project already running because its DB container existed, leaving API services stopped.
- Impact: database state remained intact; no Synthetic World API operation ran.
- Resolution: stop the isolated project while preserving its volume, then restart with the CLI's current service names and exclude only nonessential services.
- Product code changed: no.
- Regression evidence: the isolated loopback API returned its OpenAPI document and persisted a complete Synthetic World season through PostgREST.

### RI-025 - TESTABILITY_GAP - Synthetic World CLI requires a physical `.env.local`

- Status: fixed, regression verified.
- Expected: a clean isolated worktree can run the CLI when every required loopback variable is explicitly exported.
- Actual: `loadSyntheticLocalEnv()` throws `ENOENT` before environment validation if the ignored root `.env.local` file does not exist.
- Impact: no API or database operation ran; the persisted season was not created.
- Resolution: treat a missing optional environment file as an empty overlay while continuing to propagate every other filesystem error.
- Product code changed: no.
- Regression evidence: the focused missing-overlay test passes and seed `20260821` completed at revision 302 with 1,257 matches without any `.env.local` file.

### RI-027 - ENVIRONMENT_ISSUE - empty restore used `--clean` and the shell did not fail closed

- Status: fixed, regression verified.
- Expected: restore the product archive into the freshly initialized empty local platform and compare the contract byte for byte.
- Actual: `pg_restore --clean --if-exists` tried `DROP POLICY ... ON` a table that did not yet exist and aborted; because the compound diagnostic omitted `set -e`, it continued and printed a success label after `cmp` had actually failed.
- Impact: only the three synthetic Auth users were restored; no product schema or data was accepted as recovered.
- Resolution: drop only the empty product schemas, restore without a clean phase, and run every restore/comparison command under `set -e`.
- Product code changed: no.
- Regression evidence: the corrected fail-closed restore completed and exact contract/fixture comparisons passed.

### RI-028 - ENVIRONMENT_ISSUE - local restore cannot alter `supabase_admin` default privileges

- Status: fixed, regression verified.
- Expected: restore the product archive as the local `postgres` role after dropping empty product schemas.
- Actual: object and data restoration reached a `DEFAULT ACL` owned by `supabase_admin`; the managed local role cannot change another role's default privileges and `pg_restore --exit-on-error` stopped.
- Impact: the partially restored product schemas will be dropped before retry; Auth users and backup archives remain intact.
- Resolution: generate a reviewed TOC list that excludes only `DEFAULT ACL` entries while preserving all explicit schema/object ACLs, RLS, policies, functions and data.
- Product code changed: no.
- Regression evidence: the reviewed TOC excluded six managed `DEFAULT ACL` entries; explicit ACL normalization and the complete contract hash match the source exactly.

### RI-029 - TESTABILITY_GAP - filtered archive restore completed but schema contract differed

- Status: fixed, regression verified.
- Expected: excluding only managed `DEFAULT ACL` entries still reproduces the exact explicit product schema contract hash `4a2f278...`.
- Actual: `pg_restore` completed, but the exported contract hash was `3fd681...`; fail-closed `cmp` rejected it.
- Impact: restored data remains confined to the disposable local database and is not accepted as a successful recovery.
- Root cause: schema-scoped archives omit global publication membership, while `--no-owner` normalizes owner-only ACL representation for two schemas and four private tables.
- Resolution: restore a reviewed metadata phase containing the exact explicit schema/table ACLs and the 16 `supabase_realtime` memberships.
- Regression evidence: post-restore contract SHA-256 is exactly `4a2f278293329560e1b202d81080222b8a5077b346757f8885fe866fbeefcc34`; fixture SHA-256 is exactly `9a790a5893cc04f8ba9174bc9a7ff99cab14bff18f94748c874784cc41a69da8`; authenticated social snapshot and all 80 ledger rows are present.

### RI-030 - TESTABILITY_GAP - report edit introduced a duplicate section heading

- Status: fixed, regression verified.
- Expected: the permanent report contains one `Bootstrap strategy` section.
- Actual: the RI-029 registration patch inserted a second adjacent heading.
- Impact: documentation structure only; no code, test or database state changed.
- Resolution: remove the duplicate and verify the heading occurs exactly once.
- Regression evidence: `rg '^## Bootstrap strategy'` returns one line.

### RI-031 - ENVIRONMENT_ISSUE - zsh passed the focal lint file list as one argument

- Status: fixed, regression verified.
- Expected: ESLint receives every changed JavaScript/TypeScript path separately.
- Actual: zsh preserved the newline-delimited scalar as one filename and ESLint exited before reading any source.
- Impact: no file was linted or modified.
- Resolution: pipe NUL-delimited Git paths through `xargs -0`.
- Regression evidence: NUL-delimited focused lint completed with zero findings.

### RI-032 - ENVIRONMENT_ISSUE - lint wrapper used a reserved zsh variable

- Status: fixed, regression verified.
- Expected: capture the global lint exit code while preserving its full output.
- Actual: the wrapper assigned to zsh's read-only `status` parameter and exited before running the report step.
- Impact: the global lint result was not collected; no source, test or database state changed.
- Resolution: use `lint_exit` and repeat the same fail-open diagnostic wrapper.
- Regression evidence: the wrapper reported `LINT_EXIT=1` and ESLint's unchanged summary of 43 historical problems (23 errors, 20 warnings).

### RI-033 - TESTABILITY_GAP - ACL inventory query ordered by a missing output column

- Status: fixed, regression verified.
- Expected: list explicit table ACLs in stable schema/table order for the recovery runbook.
- Actual: the read-only diagnostic concatenated its output into one column but retained `ORDER BY 2`; PostgreSQL rejected the table-ACL statement.
- Impact: schema ACLs and Realtime membership were listed, but table ACL evidence was incomplete; no database mutation occurred.
- Resolution: order by the underlying `n.nspname` and `c.relname` expressions.
- Regression evidence: the corrected query returned the complete stable explicit ACL inventory without SQL errors.

### RI-034 - TESTABILITY_GAP - bootstrap did not bind the validated URL to the local CLI project

- Status: fixed, regression verified.
- Expected: baseline SQL, migration-ledger repair and forward migrations all target the same disposable local database.
- Actual: SQL commands use the validated loopback URL while Supabase CLI commands use `--local --workdir`; the script did not yet compare those two endpoints before mutation.
- Impact: the validated rehearsal used matching endpoints, but a future caller could accidentally combine local database A with workdir B and mutate B's migration ledger before the final mismatch aborts.
- Resolution: resolve the workdir's local database endpoint through `supabase status --output json` and compare normalized host, port and database before any mutation.
- Regression evidence: a deliberately mismatched local URL/workdir is rejected without invoking the `psql` test stub; the real matching workdir reaches the non-empty guard and leaves its schema contract byte-identical.

### RI-035 - TESTABILITY_GAP - alternate local workdir could supply a different migration set

- Status: fixed, regression verified.
- Expected: the migrations whose manifest and order are audited are exactly the migrations applied by Supabase CLI.
- Actual: the manifest check reads this repository, while `supabase migration up --workdir` reads the selected local workdir; the script did not compare their contents.
- Impact: the rehearsal workdir contains an exact copy, but a future alternate local workdir could silently provide different forward SQL.
- Resolution: compare the complete sorted migration filename set and SHA-256 of every file before querying or mutating either database.
- Regression evidence: a temporary workdir with one altered migration is rejected without invoking either command; an exact workdir completes the final Route A.

### RI-036 - ENVIRONMENT_ISSUE - Supabase help aliases differed from effective exclusion aliases

- Status: fixed, regression verified.
- Expected: restart only PostgreSQL for the final clean Route A.
- Actual: CLI 2.107.0 help advertised generic names such as `rest`, `storage` and `meta`, while startup accepted `postgrest`, `storage-api` and `postgres-meta`; it warned and started unnecessary local services.
- Impact: extra disposable containers only; the new product database remained empty and no bootstrap SQL had run.
- Resolution: stop the disposable project without backup and retry with the exact aliases emitted by the CLI.
- Regression evidence: the invalid aliases were removed; the subsequent database-only limitation is separately recorded as RI-037 and the final full-stack route passed.

### RI-037 - ENVIRONMENT_ISSUE - excluding every non-database service left no local database

- Status: fixed, regression verified.
- Expected: the valid exclusion list leaves the dedicated PostgreSQL container healthy.
- Actual: CLI startup returned after `Starting database...`, but no project container remained and port 56322 refused connections.
- Impact: no database existed and no product SQL or migration ledger mutation occurred.
- Resolution: start the complete disposable Supabase stack on isolated ports instead of relying on an undocumented database-only combination.
- Regression evidence: the dedicated database became healthy, reported zero Pachangas product relations, and completed the final bootstrap.

### RI-038 - ENVIRONMENT_ISSUE - Docker prune overlap interrupted local stack initialization

- Status: fixed, regression verified.
- Expected: the complete disposable stack initializes after the database-only attempt is removed.
- Actual: Docker reported `a prune operation is already running`; Supabase stopped the new containers and returned `exit 143` during schema initialization.
- Impact: initialization aborted before product bootstrap and left no accepted database state.
- Resolution: wait for Docker's prior cleanup to finish, verify no project containers remain, and retry once from the same isolated workdir.
- Regression evidence: the retry reached a healthy empty platform; final Route A produced 80 ledger rows, no `simulation` schema and canonical contract SHA-256 `4a2f278293329560e1b202d81080222b8a5077b346757f8885fe866fbeefcc34`.

### RI-039 - ENVIRONMENT_ISSUE - disposable database stopped after final Route A evidence

- Status: fixed, regression verified.
- Expected: the isolated database remains available long enough to read final feature flags after bootstrap and contract export.
- Actual: the bootstrap completed, reported 80 ledger rows and exported the canonical contract, but a subsequent read-only connection to port 56322 was refused.
- Impact: final feature-flag sampling is pending; already captured Route A output and contract files remain intact.
- Resolution: isolate the slow CLI health-check from the bootstrap command, wait for healthy containers, and run bootstrap plus metadata reads in one fail-closed session before local cleanup.
- Regression evidence: the repeated empty route produced 80 ledger rows, 16 Realtime product tables, 102 RLS-enabled relations, all safe flag values and the canonical schema contract.

### RI-040 - TESTABILITY_GAP - final feature-flag diagnostic guessed triage column names

- Status: fixed, regression verified.
- Expected: read every safe feature flag from the final Route A in fail-closed mode.
- Actual: the diagnostic queried nonexistent `triage_enabled` columns and its `psql` invocation omitted `ON_ERROR_STOP`, so later read-only contract export still ran.
- Impact: no data changed; ledger, RLS, Realtime and canonical contract evidence were captured, but the flag row must be re-read correctly.
- Resolution: inspect the canonical migration, repeat with `-v ON_ERROR_STOP=1`, and use `conduct_triage_enabled` plus `conduct_triage_shadow_mode`.
- Regression evidence: the final Route A returned `false, false, false, false, true` for attendance closure, conduct reports, social restrictions, triage and triage shadow respectively.

### RI-041 - ENVIRONMENT_ISSUE - temporary cleanup assumed an `unlink` executable

- Status: fixed, regression verified.
- Expected: delete only this rehearsal's `/private/tmp` paths without using destructive worktree commands.
- Actual: zsh reported `command not found: unlink` when the cleanup reached a file; earlier matched directories may already have been removed safely.
- Impact: temporary files remained; no repository, worktree, Docker project or unrelated temporary path was changed.
- Resolution: use `find <exact-path> -depth -delete` for both files and directories.
- Regression evidence: the corrected cleanup completed and the exact temporary-path inventory returned zero.

### RI-042 - ENVIRONMENT_ISSUE - zsh cleanup variable shadowed the PATH array

- Status: fixed, regression verified.
- Expected: the replacement loop invokes `find` for every exact temporary path.
- Actual: naming the loop variable `path` overwrote zsh's special `path` array, so the first nested `find` was not found.
- Impact: the replacement pass stopped before deleting its first target; repository and unrelated paths remained untouched.
- Resolution: rename the loop variable to `target_path` and repeat the exact-match cleanup.
- Regression evidence: the corrected cleanup completed; task temporary paths, containers and volumes all returned zero.

### RI-043 - TESTABILITY_GAP - process cleanup grep matched its own command line

- Status: fixed, regression verified.
- Expected: prove no process is executing from the integration worktree.
- Actual: the text-based `ps | rg` check matched the verifier's own shell and regex arguments.
- Impact: the result was inconclusive but did not reveal an application server or test process.
- Resolution: inspect open current-working-directory handles with `lsof` instead of matching command text.
- Regression evidence: `lsof` returned no process with the integration worktree as its current working directory.

## Bootstrap strategy

- Immutable fresh-install baseline: `20260731080738_pachangas_product_baseline.sql`.
- Baseline SHA-256: `f382816e1e7854b8da9abf0302ae75fb12495df2222741a7117d2bac531b4c45`.
- Absorbed deployed history: migrations 1-36.
- First forward migration after the baseline: `20260803053357_rating_system_v2_schema.sql`.
- Existing installations never apply the baseline; their ledger remains authoritative and only pending forward migrations run.
- Fresh bootstrap rejects remote URLs, non-empty product schemas, baseline hash drift, migration-list drift and any `simulation` schema leak.

## Route evidence

### Route A - empty database

- Deleted the dedicated local Supabase volume.
- Initialized a PostgreSQL 17 Supabase platform database with no product schema.
- Applied the versioned baseline in one transaction.
- Recorded 36 absorbed migration versions and applied migrations 37-80 with Supabase CLI.
- Result: 80 ledger entries and `BOOTSTRAP_COMPLETE`.
- Final metadata: 102 product relations with RLS and 16 product tables in `supabase_realtime`.
- Reexecution: rejected before mutation; schema hash before and after remained identical.

### Route B - existing pre-stack database

- Rebuilt to migration 77, the state immediately before PR #118.
- Added two groups, three memberships and three universal profiles.
- Added Rating V2 facets, one active peer opinion and its rating history.
- Added two finalized historical match snapshots and participants.
- Added one active Reto, four achievement grants, four sealed reward boxes and a durable notification.
- Applied migrations 78-80 in order.
- The selected pre-existing data snapshot SHA-256 stayed `8876bb11f6fc40c94ff0ce917f5ec31d440fc6e2bf24e918a89ebc121f6c98cf` before and after.

### Schema convergence

Both routes produced the same 1,957,884-byte normalized schema contract with SHA-256 `4a2f278293329560e1b202d81080222b8a5077b346757f8885fe866fbeefcc34`.

The comparison covers relations, columns, constraints, indexes, RLS flags, policies, functions and signatures, function ACLs, triggers, schema/table ACLs and Realtime publication membership.

## Safe feature flags

| Feature | Final state | Source |
| --- | --- | --- |
| Provincial rankings pilot | ON in laboratory pilot | `PROVINCIAL_PILOT_FLAGS` |
| Provincial awards | OFF | `PROVINCIAL_PILOT_FLAGS` |
| Attendance closure | OFF | `private.pachanga_conduct_settings` |
| Conduct reports | OFF | `private.pachanga_conduct_settings` |
| Social restrictions | OFF | `private.pachanga_conduct_settings` |
| Conduct triage | OFF | `private.pachanga_conduct_settings` |
| Conduct triage shadow | ON | `private.pachanga_conduct_settings` |

## Reexecution contract

- Fresh bootstrap is fail-closed on a non-empty product database and makes no mutation.
- Re-running the supported migration command returns `Local database is up to date`.
- Conduct V1 (#118) and Conduct V1.1 (#119) completed a forced transactional replay followed by rollback.
- Core Social (#120) is not raw-SQL reentrant and must be ledger-applied exactly once.

## Audited PR stack

The Git ancestry is exact and linear:

`main@53fa0860` -> `#115@4c75d52` -> `#116@f73226d` -> `#117@e62fd139` -> `#118@9aa2fa2` -> `#119@93361fe` -> `#120@e50fac5f`

| PR | Scope | Classification | Database contribution |
| --- | --- | --- | --- |
| #115 | Season Score and integrity validation | LAB | No product migration; simulation engine, generated evidence, reports and tests. |
| #116 | Synthetic World | LAB / LOCAL INFRASTRUCTURE | No product migration; local Supabase config plus service-role-only `simulation` schema loaded explicitly by the simulator. |
| #117 | TOPS provincial pilot | LAB / PILOT UI | No product migration; lab route, readiness simulation and tests. Provincial awards remain disabled. |
| #118 | Conduct V1 | PRODUCT + LAB VALIDATION | Adds `20260809162859_conduct_reports_no_show_v1.sql`; product UI/RPC contract plus Synthetic World coverage. |
| #119 | Conduct V1.1 | PRODUCT + LAB VALIDATION | Adds `20260809203000_conduct_triage_v1_1.sql`; product triage contract plus lab coverage. |
| #120 | Core Social closure | PRODUCT + LAB VALIDATION | Adds `20260809214500_core_social_flows_closure_v1.sql`; product social closure plus lab coverage. |

Only the three migrations from PRs #118-#120 enter the product database from this PR stack. Files under `simulation/`, generated synthetic data, the simulation dashboard and laboratory routes are not bootstrap inputs and must never be applied to production schemas.

## Validation matrix

| Gate | Result | Evidence |
| --- | --- | --- |
| PR stack ancestry | PASS | Six explicit adjacent `git merge-base --is-ancestor` checks. |
| SW-0134 empty reproduction | PASS | Fresh isolated Supabase failed at migration 11 with SQLSTATE `42P01`, proving the missing baseline dependency. |
| Route A empty bootstrap | PASS | Baseline plus migrations 37-80; 80 ledger rows. |
| Route B incremental upgrade | PASS | Migration 77 fixture upgraded through 78-80. |
| Schema equivalence | PASS | Identical normalized contract SHA-256. |
| Existing-data preservation | PASS | Identical selected-data SHA-256 before/after. |
| Feature flags | PASS | Pilot ranking ON; awards and active Conduct features OFF; triage shadow ON. |
| SQL, RLS and concurrency | PASS | Rating V2, Retos/social, guests, achievements/rewards, notifications, Conduct V1/V1.1, Core Social and adversarial Synthetic World gates. |
| Synthetic World from clean DB | PASS | New world `93a7d58c-5742-47ba-879d-ff049f9acdaa`; revision 302, 1,257 matches and 57,975 events; full 27/27 Synthetic tests pass. |
| Backup/restore | PASS | Three Auth users, all 80 ledger rows, exact schema hash and exact fixture hash restored after deleting the isolated volume. |
| Typecheck | PASS | `npm run typecheck`. |
| Build and product tests | PASS | `npm test`: Next.js production build, 12 Node tests and 196 TS/TSX tests. |
| Focused lint | PASS | All changed JavaScript/TypeScript files; zero findings. |
| Global lint | EXPECTED DEBT | Unchanged historical total: 43 problems (23 errors, 20 warnings); no changed path appears in the findings. |

## Synthetic World clean-room evidence

The simulator was loaded explicitly after the product bootstrap; the `simulation` schema is absent from both Route A and Route B product contracts. A new local API-backed world was then persisted against the reconstructed database with seed `20260821`:

- world revision: 302;
- matches: 1,257;
- events: 57,975;
- rating opinions: 3,215;
- conduct incidents: 147;
- achievement/reward records: 4,090;
- notifications: 26,378;
- possible no-shows: 298.

The Route B product fixture fingerprint remained unchanged after the season, proving that the new world used its own synthetic identities instead of mutating compatibility evidence.

## Recovery rehearsal

The dedicated Route B platform was backed up, its Docker volume was deleted, and an empty local Supabase platform was initialized again. Recovery restored Auth identities separately from product schemas and filtered only six managed-role `DEFAULT ACL` archive entries that a local `postgres` role cannot own. Explicit schema/table ACLs and the 16 `supabase_realtime` memberships were then verified against the source contract.

- product archive SHA-256: `36973ee365712b035174c5a01ac8aaf1126d8f89f2642234589db53740acec2d`;
- Auth archive SHA-256: `683e32989e65d14337fa66868daa390d93e20446bdbb92d0698a10bac0db1743`;
- restored Auth users: 3;
- restored migration ledger: 80;
- restored schema contract: `4a2f278293329560e1b202d81080222b8a5077b346757f8885fe866fbeefcc34`;
- restored fixture: `9a790a5893cc04f8ba9174bc9a7ff99cab14bff18f94748c874784cc41a69da8`;
- authenticated read check: Route B user A reads its group and active challenge.

The repeatable local procedure and its fail-closed boundaries are documented in `docs/database-bootstrap-v1.md`.

## Integration order

The recommended order remains the linear Git ancestry already proven:

`#115 -> #116 -> #117 -> #118 -> #119 -> #120 -> release integration/bootstrap`

No squash or rebase is required for schema correctness. The integration PR should remain stacked on the current #120 head until the six predecessors are merged in order; after #120 lands, it can be rebased directly onto `main` without changing the baseline or migrations.

## Deliberately unresolved product decisions

This task does not implement or decide `team.admin_invite.revoke`, `challenge.proposal_ttl`, TOPS interaction with social sanctions, or production no-show thresholds. Their current behavior and flags remain unchanged.

## Release conclusion

The supported history now satisfies both required statements:

1. A completely empty local Pachangas IQ platform can apply the immutable baseline plus forward migrations and reach the canonical product contract.
2. An installation at the pre-Conduct/Core-Social state can apply only migrations 78-80 without losing memberships, Rating V2, facets, history, challenges, results, achievements, reward boxes or notifications.

No production service, linked Supabase project, remote schema or product feature flag was modified during this rehearsal.

The final change set contains exactly 22 logical file paths, counting the baseline move as one rename. It contains infrastructure, tests, Synthetic World incident evidence and documentation only; no application UI, product migration, Rating V2 formula or feature implementation is modified.
