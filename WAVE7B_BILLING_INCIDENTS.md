# Wave 7B Billing Incidents

## INC-W7B-001 - Ranking refresh cron returned 503

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 16:15 CEST
- Surface: `GET /api/internal/rankings/refresh`
- Original scenario: the production cron invoked the authenticated ranking refresh route without `CRON_SECRET` being configured in Vercel Production. The route correctly returned 503 and no ranking formula was changed.
- Root cause: missing production environment secret.
- Correction: generated a strong secret, stored it as a sensitive Vercel Production variable, and redeployed the exact prior production application revision. The secret was not printed or committed.
- Regression evidence: Vercel runtime logs show the old deployment returning 503 at 16:15, 16:20 and 16:25 CEST, followed by the replacement deployment returning 200 at 16:25, 16:30 and 16:35 CEST.
- Product impact: no Billing data and no Ranking formula were modified.

## INC-W7B-002 - Plan mapping command had an ambiguous PL/pgSQL identifier

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:24 CEST
- Surface: `command_pachanga_organizer_billing_platform_v1`, actions `price_mapping.upsert` and `manual.grant`.
- Original scenario: the first explicit test-mode Price mapping failed before writing because `plan_code` could refer to either the PL/pgSQL variable or `pachanga_organizer_plan_catalog.plan_code`.
- Root cause: a local variable reused the column name and was also reused as the capability iterator for a manual entitlement bundle.
- Correction: split it into `requested_plan_code` and `capability_code`, and qualify the catalog comparison.
- Regression evidence: the fresh 190-migration bootstrap and focused suite execute both affected actions successfully.
- Product impact: no remote database was touched; the failure was found in the isolated local database before staging.

## INC-W7B-003 - Manual renewal had an ambiguous expiry identifier

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:27 CEST
- Surface: `command_pachanga_organizer_billing_platform_v1`, action `manual.renew`.
- Original scenario: restoring a revoked Club partnership failed because `valid_until = valid_until` was ambiguous between the PL/pgSQL variable and the access-grant column.
- Root cause: the request expiry variable reused a canonical column name.
- Correction: renamed the request value to `requested_valid_until` throughout grant and renewal paths.
- Regression evidence: after a fresh 190-migration bootstrap, the focused database suite revokes and renews the same audited partnership successfully.
- Product impact: no remote database was touched; no grant escaped the rolled-back local test.

## INC-W7B-004 - Focused test read the wrong organizer snapshot key

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:29 CEST
- Surface: `tests/organizer-plans-stripe-billing-v1-db.sql`.
- Original scenario: the Club-owner assertion queried `access` although the canonical read model returns `accessGrants`.
- Root cause: the newly written assertion used an abbreviated key not present in the RPC contract.
- Correction: assert the documented `accessGrants` array.
- Regression evidence: the owner/non-owner read test passes after a fresh 190-migration bootstrap.
- Product impact: none; the product RPC returned the expected canonical bundle.

## INC-W7B-005 - Checkout preparation used an unqualified operation identifier

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:31 CEST
- Surface: `prepare_pachanga_organizer_checkout_service_v1`.
- Original scenario: the first owner Checkout intent failed while looking for an idempotent replay because `operation_id` was unqualified in the intent query.
- Root cause: the RPC parameter and table column shared a name without a table alias.
- Correction: qualify the stored value as `intents.operation_id`.
- Regression evidence: the database suite prepares an intent and immediately repeats the identical operation to prove exact replay.
- Product impact: no Stripe session was created and no remote database was touched.

## INC-W7B-006 - Checkout confirmation shadowed the Stripe Customer parameter

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:34 CEST
- Surface: `confirm_pachanga_organizer_checkout_service_v1` and checkout-status actor lookup.
- Original scenario: confirmation of a prepared test Checkout failed at the canonical billing-account update because `stripe_customer_id = stripe_customer_id` was ambiguous.
- Root cause: an RPC parameter reused the destination column name; a related status lookup used the same pattern for `actor_id`.
- Correction: qualify the Customer parameter with the RPC name and rename the status actor variable to `request_actor_id`.
- Regression evidence: the suite confirms Checkout, verifies zero entitlement before the signed subscription event, and reads status as the initiating owner.
- Product impact: no Stripe subscription or entitlement was created; all activity remained local and rolled back.

## INC-W7B-007 - Invoice upserts collided with the Stripe mode parameter

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:36 CEST
- Surface: signed `invoice.payment_failed` and `invoice.paid` event projection.
- Original scenario: both signed invoice events were retained as `FAILED_TERMINAL` because `ON CONFLICT (stripe_mode, ...)` was ambiguous with the webhook RPC parameter.
- Root cause: inference-form conflict targets used a parameter name inside PL/pgSQL.
- Correction: assign stable explicit unique constraints to invoice and failure identities and target those constraints by name.
- Regression evidence: the suite projects one failed invoice, recovers it with `invoice.paid`, and asserts one `RECOVERED` failure row.
- Product impact: failure evidence was preserved locally; no remote Stripe or Supabase state changed.

## INC-W7B-008 - Continuity did not block direct Competition creation

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:41 CEST
- Surface: `pachanga_billing_guard_competition_limits_v1`.
- Original scenario: after cancellation moved an organizer into continuity and revoked `competition_create`, a direct canonical Competition insert still succeeded because the trigger checked only commercial limits.
- Root cause: the new-edition guard enforced entitlement authority, but the Competition limit guard omitted the equivalent creation-authority check.
- Correction: every canonical Competition insert now calls `pachanga_organizer_billing_creation_allowed_v1` before evaluating limits and fails with `ORGANIZER_PLAN_CREATION_BLOCKED`.
- Regression evidence: the focused suite attempts both a new Competition and a new Edition after cancellation while an existing edition remains manageable.
- Product impact: no remote state was changed; the unauthorized local row was rolled back with the failed test transaction.

## INC-W7B-009 - Legacy-write regression expected an unreachable trigger message

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 19:48 CEST
- Surface: `tests/organizer-plans-stripe-billing-v1-db.sql`, authenticated legacy Stripe-field write.
- Original scenario: the regression expected the billing trigger to return a custom error, but PostgreSQL rejected the authenticated client first because `UPDATE` on `pachanga_groups` was already revoked by Rating V2.
- Root cause: the assertion modeled the defense-in-depth trigger as the first authorization boundary even though the stronger table privilege boundary is reached first by a real client.
- Correction: keep the existing `UPDATE` revocation intact and require the real client-visible `permission denied` failure. The trigger remains installed for privileged internal paths and must not be made reachable by reopening V1 table writes.
- Regression evidence: after a fresh 190-migration bootstrap, the complete focused database suite verifies PostgreSQL rejects the direct authenticated write before any legacy field can change.
- Product impact: none; the attempted local write was rejected and no remote database was touched.

## INC-W7B-010 - Concurrency fixture omitted its deferred-constraint transaction

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:03 CEST
- Surface: `tests/organizer-plans-stripe-billing-v1-concurrency.mjs` fixture bootstrap.
- Original scenario: the ephemeral concurrency database rejected the Club row with `CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED` before its owner membership could be inserted.
- Root cause: the shared fixture relies on the canonical deferred Club-owner constraint, but the new runner loaded each statement in autocommit mode instead of the transaction used by the focused SQL suite.
- Correction: load the fixture in one explicit `BEGIN`/`COMMIT` session so the Club and its owner membership are validated together at commit.
- Regression evidence: the complete multi-connection runner now loads the fixture transactionally and passes replay, stale-revision, duplicate-event, expiry and reconciliation races with cleanup confirmed.
- Product impact: none; the ephemeral database was removed in `finally` and no remote database was touched.

## INC-W7B-011 - Subscription expiry produced a zero-length access interval

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:07 CEST
- Surface: `private.pachanga_billing_sync_entitlement_v1` during `process_pachanga_billing_expirations_service_v1`.
- Original scenario: a real concurrent expiry run reached the signed-subscription access projection and failed its table constraint because the transient upsert row used the same server timestamp for `valid_from` and `valid_until`.
- Root cause: revoked and expired access used an interval endpoint even though their authoritative end evidence is `revoked_at`; PostgreSQL validates the proposed insert before applying the conflict update.
- Correction: revoked or expired subscription access now stores `valid_until = NULL` and retains the exact server cutoff in `revoked_at`. Active, grace and continuity intervals remain unchanged.
- Regression evidence: the complete concurrency suite retains the original expiry race and verifies the one canonical access becomes `revoked` exactly once.
- Product impact: no remote database was touched; the failing transaction rolled back and the ephemeral database was removed.

## INC-W7B-012 - Expiration cron reprocessed the same Stripe subscription forever

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:10 CEST
- Surface: `process_pachanga_billing_expirations_service_v1` subscription batch selection.
- Original scenario: two simultaneous cron calls converged, but a third operation selected the already revoked `past_due` subscription again, incremented revisions and would repeat the mandatory warning on every schedule.
- Root cause: the batch predicate considered only the Stripe projection status and deadline; that projection intentionally remains `past_due`, so it did not account for the already finalized canonical access state.
- Correction: a due subscription is selected only when it has no access projection yet or its canonical access still remains `active`/`grace`. Revoked, expired and continuity access is not reprocessed.
- Regression evidence: the concurrency runner executes two different expiry operations simultaneously and then a third operation, which reports zero additional expirations and leaves the access revision unchanged.
- Product impact: no remote database was touched; all failed-run effects were confined to a removed ephemeral database.

## INC-W7B-013 - Expiration guard alias collided with its PL/pgSQL record variable

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:13 CEST
- Surface: the new canonical-access predicate in `process_pachanga_billing_expirations_service_v1`.
- Original scenario: both expiry clients failed before selecting work because PostgreSQL could resolve `access.subscription_projection_id` as either the query alias or the function's `access` record variable.
- Root cause: the first correction reused an existing PL/pgSQL identifier as a nested-query alias.
- Correction: use the unambiguous alias `projected_access` in both existence predicates.
- Regression evidence: the complete ephemeral concurrency suite passes both simultaneous expiry clients and the stable no-op replay.
- Product impact: none; both local transactions failed before writes and the ephemeral database was removed.

## INC-W7B-014 - Scale assertion ignored PostgreSQL identifier truncation

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:26 CEST
- Surface: Stripe event identity `EXPLAIN` assertion in the Wave 7B scale runner.
- Original scenario: the 10,000-row webhook lookup used an index and completed in 0.07 ms, but the assertion expected the untruncated generated constraint name.
- Root cause: PostgreSQL limits identifiers to 63 bytes and stored the unique index as `pachanga_stripe_webhook_events__stripe_mode_stripe_event_id_key`.
- Correction: assert the exact catalog name reported by PostgreSQL rather than the longer source-derived candidate.
- Regression evidence: the complete representative-volume runner selects the catalog-reported truncated index name and completes the lookup in 0.049 ms.
- Product impact: none; all scale data lived in an ephemeral database removed after the assertion.

## INC-W7B-015 - Reconciliation fixture was too small to exercise its queue index

- Classification: `TESTABILITY_GAP`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:29 CEST
- Surface: representative-volume validation of `pachanga_stripe_reconciliation_queue_idx`.
- Original scenario: with only 200 pending rows PostgreSQL correctly chose a 0.105 ms sequential scan, so the test could not prove that the partial queue index takes over at operational volume.
- Root cause: the queue fixture was materially smaller than the webhook and delivery fixtures and asserted a planner choice that was not economical at that size.
- Correction: raise only the reconciliation queue to 10,000 rows, distributed across the same 2,000 billing accounts, and keep natural planner settings.
- Regression evidence: the complete scale run loads 10,000 reconciliation rows and naturally selects the partial queue index without disabling sequential scans.
- Product impact: none; no production index or remote data was changed.

## INC-W7B-016 - Reconciliation queue index did not match canonical claim ordering

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:32 CEST
- Surface: `pachanga_stripe_reconciliation_queue_idx` and `claim_pachanga_billing_reconciliation_service_v1`.
- Original scenario: at 10,000 pending reconciliations the claim query still performed a sequential scan plus top-N sort because its index began with `status` while the canonical queue is ordered across both eligible states by `server_sequence,id`.
- Root cause: the physical index order did not match the server-authoritative sequence used to claim mixed `PENDING`/`FAILED` work.
- Correction: retain the same partial predicate but index `(server_sequence,id)` directly, matching the stable claim order and avoiding a cross-status sort.
- Regression evidence: the full representative-volume run naturally selects the corrected partial index for the canonical `(server_sequence,id)` claim order and completes the lookup in 0.13 ms.
- Product impact: no remote database was touched; the old definition only existed in the unshipped migration and ephemeral databases were removed.

## INC-W7B-017 - Isolated worktree had no installed TypeScript toolchain

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:01 CEST
- Surface: first `npm run typecheck` after adding the Wave 7B HTTP boundary.
- Original scenario: the command stopped before compilation with `tsc: command not found`.
- Root cause: this isolated worktree had intentionally not installed `node_modules` yet; the repository lockfile and source were present.
- Correction: install the exact lockfile dependency graph with `npm ci` under the repository-supported Node 24 runtime.
- Regression evidence: `npm ci` installed the lockfile graph under Node 24 and the repeated full TypeScript check completed successfully.
- Product impact: none; no application code executed and no remote service or database was touched.

## INC-W7B-018 - Local database still contained the prior revision of an unshipped migration

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:02 CEST
- Surface: first focused SQL run after extending the unshipped Wave 7B read-model migration.
- Original scenario: the ledger correctly reported migration version `20260828163754`, but PostgreSQL did not yet contain the newly added owner organizer selector because the local database had been bootstrapped before that migration file changed.
- Root cause: migration versions alone cannot reveal source drift while an unshipped forward migration is still being authored; the focused runner deliberately consumes the current local database instead of resetting it on every invocation.
- Correction: reset the local Supabase stack, then rebuild it from the exact worktree through the guarded immutable bootstrap.
- Regression evidence: the rebuilt ledger contains exactly 190 migrations through `20260828163756`, exposes the new selector, and the complete focused SQL/RLS suite passes.
- Product impact: none; only the local Supabase database was queried and no remote database was touched.

## INC-W7B-019 - Supabase reset intentionally produced an empty migration ledger

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:04 CEST
- Surface: focused Wave 7B runner immediately after `supabase db reset --local`.
- Original scenario: the runner could not read `supabase_migrations.schema_migrations` because the reset recreated an empty database.
- Root cause: this repository intentionally sets `[db.migrations].enabled = false`; fresh databases must be populated by the guarded `npm run db:bootstrap:fresh` command.
- Correction: execute the canonical fresh bootstrap after every local reset before invoking a focused migration-dependent runner.
- Regression evidence: the bootstrap recreated the complete 190-migration ledger and the focused Wave 7B suite passed immediately afterward.
- Product impact: none; the empty database was local and no remote service was contacted.

## INC-W7B-020 - Guarded bootstrap rejected an implicit database target

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:05 CEST
- Surface: first invocation of `npm run db:bootstrap:fresh` after the local reset.
- Original scenario: the bootstrap stopped before opening a connection with `PACHANGAS_BOOTSTRAP_DATABASE_URL_OR_DB_URL_REQUIRED`.
- Root cause: the guarded bootstrap requires an explicit database URL so it cannot infer or accidentally reach a linked remote project.
- Correction: repeat the command with `PACHANGAS_BOOTSTRAP_DATABASE_URL` set to the known local-only PostgreSQL URL at `127.0.0.1:55322`.
- Regression evidence: the guarded bootstrap accepted the explicit loopback target, applied all 190 migrations, and the focused SQL/RLS suite passed.
- Product impact: none; the process failed before connecting to any database.

## INC-W7B-021 - Reconciliation test read a private revision as an authenticated actor

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:10 CEST
- Surface: new canonical reconciliation repair regression.
- Original scenario: the test called the platform reconciliation RPC as an authenticated platform owner while an inline subquery tried to read `private.pachanga_organizer_billing_accounts`.
- Root cause: the fixture did not snapshot the server-confirmed account revision before switching to the restricted authenticated role.
- Correction: capture the canonical revision in the permitted temporary test state before switching to the authenticated platform role.
- Regression evidence: the full SQL/RLS suite now reaches and completes both reconciliation scenarios while private-table reads remain denied to authenticated actors.
- Product impact: none; PostgreSQL rejected the unauthorized read and rolled back the test transaction.

## INC-W7B-022 - Reconciliation snapshot Price identifier was ambiguous in PL/pgSQL

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:12 CEST
- Surface: `apply_pachanga_billing_reconciliation_snapshot_service_v1` during the first real repair scenario.
- Original scenario: a valid server-side snapshot reached the active Price mapping lookup and PostgreSQL rejected `stripe_price_id` as ambiguous.
- Root cause: the function parameter and the private mapping column intentionally share the domain name but the parameter was not function-qualified in that predicate.
- Correction: function-qualify both Price and Subscription snapshot identifiers in their private-table predicates.
- Regression evidence: a newer Stripe snapshot now repairs the canonical projection, an older snapshot is ignored, replay is idempotent, and the complete SQL/RLS suite passes.
- Product impact: none; the test transaction rolled back before changing the projection and no remote database was touched.

## INC-W7B-023 - Timestamp-only reconciliation guard left a late-webhook race

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:16 CEST
- Surface: design review of the cron-to-PostgreSQL reconciliation boundary before adding the HTTP route.
- Original scenario: a webhook created earlier could be delivered and update the projection after the reconciliation claim but before the Stripe read completed; comparing only Stripe timestamps could then let the cron overwrite that newer server mutation.
- Root cause: the claim exposed the latest event identity but not the exact projection revision that the apply transaction must still observe.
- Correction: add `localProjectionRevision` to the claim and require the same expected projection revision in the repair transaction.
- Regression evidence: the focused suite claims revision 6, processes a webhook that advances it, receives `STALE_REVISION` from the repair, preserves the webhook state and records the reconciliation as failed for retry.
- Product impact: none; the route has not been shipped or connected to Stripe.

## INC-W7B-024 - Concurrent-webhook regression was inserted before billing setup

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:19 CEST
- Surface: first execution of the new projection-revision race scenario.
- Original scenario: the reconciliation request received a null account identifier and failed with `BILLING_INVALID_RECONCILIATION_REQUEST`.
- Root cause: a broad patch anchor placed the race block after the partnership grant rather than after the account, subscription and initial reconciliation fixtures.
- Correction: move the entire race scenario immediately after the successful and stale-observation reconciliation cases.
- Regression evidence: the relocated scenario now creates the account and subscription first, reaches the intended race, and the full focused suite passes.
- Product impact: none; the invalid request was rejected and the test transaction rolled back.

## INC-W7B-025 - Failed reconciliation completion had an ambiguous safe error parameter

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:22 CEST
- Surface: `complete_pachanga_billing_reconciliation_service_v1` after the projection-revision race was correctly rejected.
- Original scenario: the service attempted to mark the reconciliation `FAILED` with `STALE_REVISION`, and PostgreSQL rejected the update because `safe_error_code` could name either the function parameter or the table column.
- Root cause: the failure-only branch had not previously been exercised by the focused SQL suite and its parameter was not function-qualified.
- Correction: function-qualify `safe_error_code` in the failure sanitization expression.
- Regression evidence: the concurrent-webhook scenario now closes as `FAILED` with the safe `STALE_REVISION` code and the complete SQL/RLS suite passes.
- Product impact: none; the transaction rolled back and no remote database was touched.

## INC-W7B-026 - Bootstrap log wrapper used a reserved zsh variable

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:27 CEST
- Surface: clean-bootstrap output capture before the final local regression battery.
- Original scenario: the shell returned `read-only variable: status` after the bootstrap command.
- Root cause: `status` is reserved by zsh and cannot be assigned as a generic exit-code variable.
- Correction: inspect the command log directly and use a non-reserved name such as `rc` for any later exit-code capture.
- Regression evidence: the bootstrap log ends in `BOOTSTRAP_COMPLETE` and direct PostgreSQL readback reports exactly `190|20260828163756`.
- Product impact: none; only local bootstrap orchestration was involved.

## INC-W7B-027 - Webhook regression expected the pre-verification variable name

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 22:06 CEST
- Surface: first focused TypeScript contract run for the organizer Stripe server boundary.
- Original scenario: the webhook implementation correctly compared the verified Stripe event mode with the candidate endpoint mode, but the source regression searched for `stripeEventMode(event)` instead of the actual verified local value `stripeEventMode(verified)`.
- Root cause: the assertion encoded a stale local variable name rather than the required security behavior.
- Correction: make the regression assert the mode comparison on the object returned by `Stripe.webhooks.constructEvent`.
- Regression evidence: the repeated focused organizer billing suite passes while still requiring raw-body signature verification and rejecting endpoint-mode mismatches.
- Product impact: none; the failure was limited to a local source-contract assertion and no endpoint or remote service was invoked.

## INC-W7B-028 - Realtime invalidation regression required undeclared replica identity

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 22:06 CEST
- Surface: first focused TypeScript contract run for organizer billing Realtime invalidation.
- Original scenario: the migration published the canonical invalidation table and exposed only RLS-filtered revision signals, but did not explicitly declare the replica identity required by the regression contract.
- Root cause: the source assertion and migration declaration had drifted while the invalidation table was introduced.
- Correction: set `REPLICA IDENTITY FULL` on the small one-row-per-scope invalidation table before adding it to the Realtime publication.
- Regression evidence: the repeated focused suite requires the explicit replica identity, publication, safe event taxonomy and absence of WAL-payload authority.
- Product impact: none; the migration remains unshipped and only the local source file changed.

## INC-W7B-029 - SQL source regression treated keyword capitalization as behavior

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 22:08 CEST
- Surface: repeated focused TypeScript contract run after declaring the Realtime replica identity.
- Original scenario: PostgreSQL source contained the required `replica identity full` declaration, but the assertion accepted only the uppercase spelling `REPLICA IDENTITY FULL`.
- Root cause: the source regression was case-sensitive even though SQL keywords are case-insensitive.
- Correction: make only that semantic keyword assertion case-insensitive.
- Regression evidence: the repeated focused organizer billing suite passes all nine contracts with zero skips, todos or cancellations.
- Product impact: none; the failing check did not execute application code or contact a remote service.

## INC-W7B-030 - Realtime source regression expected non-canonical dotted event names

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 22:10 CEST
- Surface: repeated focused organizer billing contract run after the replica-identity check passed.
- Original scenario: the migration correctly emitted the canonical invalidation kinds `BILLING_ACCOUNT`, `ACCESS_GRANT`, `SUBSCRIPTION`, `INVOICE`, `PAYMENT_FAILURE` and `RECONCILIATION`, while the source assertion searched for undeclared dotted names such as `billing.subscription`.
- Root cause: the regression encoded an abandoned naming sketch instead of the persisted event taxonomy.
- Correction: assert the canonical account, access, subscription and reconciliation entity kinds used by the migration.
- Regression evidence: the repeated focused organizer billing suite passes all nine source contracts with zero skips, todos or cancellations.
- Product impact: none; no migration was executed and no remote service was contacted.

## INC-W7B-031 - Canonical billing expiration processor had no scheduled caller

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 22:18 CEST
- Surface: pre-commit authority review of the Wave 7B internal billing routes and Vercel cron schedule.
- Original scenario: PostgreSQL and an authenticated internal route implemented subscription grace, manual grant, continuity and hosted-session expiration, but `vercel.json` scheduled only reconciliation, leaving the expiration route unreachable without a manual call.
- Root cause: the processor and cron were added in separate slices and their invocation contract was not connected.
- Correction: invoke the idempotent server-clock expiration RPC at the beginning of the existing hourly billing reconciliation cron, failing closed before claiming reconciliations when expiration cannot run.
- Regression evidence: the focused source suite requires both `process_pachanga_billing_expirations_service_v1` and `claim_pachanga_billing_reconciliation_service_v1` in the one scheduled route, while SQL/RLS keeps both RPCs service-only.
- Product impact: none; the route and migrations are not deployed and no remote database was modified.

## INC-W7B-032 - Platform reconciliation request was routed to the generic command RPC

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:43 CEST
- Surface: pre-UI review of `POST /api/platform-admin/billing` before exposing the Control Center V2 reconciliation action.
- Original scenario: an administrator submitting `reconciliation.request` would pass through the generic command dispatcher, whose allowlist does not implement reconciliation requests, instead of reaching the dedicated server-authoritative reconciliation RPC.
- Root cause: the HTTP adapter did not branch the dedicated reconciliation contract before validating and dispatching generic settings, Price mapping and manual-grant commands.
- Correction: validate the reconciliation envelope separately and invoke `request_pachanga_billing_reconciliation_platform_v1` with the authenticated actor, expected account revision, idempotent operation ID and sanitized reason.
- Regression evidence: the focused source suite now requires the dedicated reconciliation branch and RPC, confirms the billing account identifier is server-bound, and passes all 9 contracts with zero skips, todos or cancellations.
- Product impact: none; no Control Center action exposes this path yet and Wave 7B is not deployed.

## INC-W7B-033 - Billing status fallback mixed nullish and boolean precedence

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:49 CEST
- Surface: first TypeScript pass after adding the Organizer Plans and owner Billing clients.
- Original scenario: the shared status formatter combined `??` and `||` without an explicit grouping, so TypeScript correctly refused to compile the client contract.
- Root cause: the fallback expression encoded two precedence rules in one ungrouped statement.
- Correction: compute the humanized fallback separately and then apply the nullish fallback.
- Regression evidence: the repeated strict TypeScript pass compiles the formatter and both new product surfaces successfully.
- Product impact: none; the UI exists only in the unshipped Wave 7B worktree.

## INC-W7B-034 - Realtime cleanup retained a nullable Supabase reference

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 20:49 CEST
- Surface: first TypeScript pass after adding the owner Billing Realtime invalidation subscriber.
- Original scenario: TypeScript could not prove that the module-level nullable Supabase singleton remained non-null inside the effect cleanup closure.
- Root cause: the effect narrowed the singleton at entry but did not capture the narrowed client in a stable local constant.
- Correction: capture the configured client once and use that exact reference for channel creation and removal.
- Regression evidence: the repeated strict TypeScript pass verifies channel subscription and cleanup use the same non-null client reference.
- Product impact: none; the UI exists only in the unshipped Wave 7B worktree.

## INC-W7B-035 - Demo privacy guard mistook a pricing status for a Stripe identifier

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 22:54 CEST
- Surface: first deterministic Demo World V2.8 generation with organizer billing scenarios.
- Original scenario: the read-only catalog used the legitimate status `AWAITING_PRICE_APPROVAL`, but the privacy guard interpreted the `PRICE_` substring as if it were a live Stripe `price_*` identifier and rejected the snapshot.
- Root cause: the detector searched for identifier prefixes anywhere inside any JSON string rather than restricting the match to actual serialized identifier values.
- Correction: constrain the guard to exact serialized string values beginning with `cus_`, `sub_`, `price_` or `prod_`.
- Regression evidence: the 17/17 Demo World V2 suite accepts `AWAITING_PRICE_APPROVAL`, rejects actual Stripe-style values, verifies five canonical lifecycle scenarios, and confirms the immutable chunk remains GET-only and readable offline.
- Product impact: none; generation failed locally before any snapshot was written and no remote service was contacted.

## INC-W7B-036 - Billing clients synchronously derived local state inside effects

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 23:03 CEST
- Surface: first focused ESLint pass across the new Organizer Plans and owner Billing clients.
- Original scenario: the catalog cache, initial online state, missing-Supabase message and selected-organizer snapshot could call React state setters synchronously from an effect body. The first lint pass exposed three failures; after those were removed, a fourth failure of the same root cause became reachable.
- Root cause: local-cache hydration and the first snapshot call were started directly in effects even though they synchronize with browser or network state.
- Correction: schedule browser-state hydration, configuration messaging and the initial snapshot call through cancelable microtask callbacks while preserving cache-as-read-model semantics and the same canonical server refetch.
- Regression evidence: the focused ESLint pass across all new TS/TSX surfaces completes with zero warnings and zero errors; the source contract continues to require read-only cache, offline write blocking and canonical Realtime refetch.
- Product impact: none; both clients are unshipped and the failure was detected before browser QA or deployment.

## INC-W7B-037 - Organizer plan surfaces were not discoverable from Profile

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 23:12 CEST
- Surface: product-contract review after the Plans, owner Billing and Control Center screens compiled.
- Original scenario: `/planes-organizador` and `/ajustes/facturacion` existed, but the normal desktop/mobile Profile navigation had no entry to either surface. The plan card also lacked a generic unavailable-capabilities section and its future approved Price row did not expose canonical tax behavior.
- Root cause: route implementation and product navigation were completed in separate slices, while optional catalog fields had only their empty-state rendering.
- Correction: expose public Plans from desktop/mobile Profile, expose owner Billing only to the team owner, render unavailable capabilities when present, and label the tax behavior supplied by the canonical approved Price mapping.
- Regression evidence: the 12/12 organizer billing source suite requires both Profile links and the owner-only condition, canonical tax labels, unavailable capabilities, and the permanent PWA write boundary.
- Product impact: none; the routes are unshipped and remain protected server-side regardless of client navigation.

## INC-W7B-038 - Legacy app page prevents a zero-error whole-file focal lint

- Classification: `TESTABILITY_GAP`
- Status: `open_preexisting`
- Regression: `baseline_verified`
- Detected at: 2026-08-28 23:17 CEST
- Surface: focused ESLint pass after adding two Profile navigation links to the existing 500 KB `app/page.tsx`.
- Original scenario: linting all touched TS/TSX files reports 30 findings in `app/page.tsx` (13 errors and 17 warnings), while every new Wave 7B file passes.
- Root cause: the legacy page already contains the same hook, purity, dependency and unused-value debt before the two declarative links were added.
- Evidence: running ESLint against `git show HEAD:app/page.tsx` through stdin produces the same 30 findings and the same 13/17 split; none points to a Wave 7B line.
- Resolution boundary: do not rewrite the unrelated legacy page inside Billing. Keep the exact baseline visible in the release report and require zero findings for all Wave 7B-owned TS/TSX files.
- Product impact: no new lint regression; the pre-existing debt remains outside this release scope.

## INC-W7B-039 - Integrated browser does not support network-idle waits

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 23:22 CEST
- Surface: first local desktop browser QA of `/planes-organizador`.
- Original scenario: the integrated browser rejected `waitForLoadState({ state: "networkidle" })` before the screenshot and diagnostics could run. Its read-only evaluation scope also omits `fetch`, so it cannot inspect an API response body directly.
- Root cause: this browser transport supports `load` and `domcontentloaded`, but not Playwright's `networkidle` state, and intentionally restricts evaluated page capabilities.
- Correction: wait for `load`, then use a bounded settling delay and explicit DOM/loading diagnostics; inspect read-only HTTP responses with terminal `curl` when needed.
- Regression evidence: subsequent viewport checks use the supported wait contract and inspect content, overlays, console and overflow directly.
- Product impact: none; the page had already navigated and no product code or remote service was affected.

## INC-W7B-040 - Local PostgREST cannot load its configured simulation schema

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 23:24 CEST
- Surface: local desktop browser QA of `/planes-organizador`.
- Original scenario: the route, shell and responsive layout rendered without overflow, but `GET /api/billing/organizer/catalog` returned a guarded 400. Direct PostgreSQL readback confirmed all 190 migrations and the catalog RPC, while direct PostgREST returned `PGRST002` because it could not refresh its schema cache.
- Root cause: `supabase/config.toml` correctly exposes `public`, `graphql_public` and the test-only `simulation` schema, but the preserved local database volume no longer contains `simulation`. PostgREST 14.13 therefore rejects the complete schema cache with PostgreSQL `3F000 schema "simulation" does not exist` and fails its health check. This is not a missing Wave 7B migration or frontend-contract failure.
- Recovery evidence: a clean `supabase start -x edge-runtime,imgproxy,logflare,vector` connects PostgREST to PostgreSQL 17.6 successfully, then deterministically fails only while loading the absent configured schema.
- Correction: start the local stack without PostgREST, recreate the empty test-only `simulation` namespace, preserve it in the local Docker volume, then restart the complete API stack. No repository configuration or remote database was changed.
- Regression evidence: PostgREST passes its health check and the anonymous HTTP call to `get_pachanga_organizer_plan_catalog_v1` returns `200` with the canonical `NOT_AVAILABLE` state while all Wave 7B flags remain deliberately OFF.
- Product impact: none; production is unchanged and the UI correctly displays an explicit unavailable state instead of a false success.

## INC-W7B-041 - An installed PWA display mode is not reproducible in browser emulation

- Classification: `TESTABILITY_GAP`
- Status: `open_environment_boundary`
- Regression: `contract_verified`
- Detected at: 2026-08-28 23:58 CEST
- Surface: local responsive and PWA QA of Organizer Plans and owner Billing.
- Original scenario: Chrome viewport emulation verifies the exact portrait and landscape dimensions, but CDP media emulation cannot turn a normal browser tab into an installed `display-mode: standalone` application. The local development origin also has no active Service Worker registration, as expected for this development run.
- Evidence: desktop, `390x844` and `844x390` browser checks have zero horizontal overflow and zero console errors; the manifest link is present. The source contract and focused regression suite verify the Service Worker caches only the public plan catalog, never caches owner billing, never queues sporting or billing writes, and keeps rejected/offline actions unconfirmed.
- Resolution boundary: validate a genuinely installed PWA against the deployed Preview/production origin after deployment. Do not claim physical Android, iPhone or installed-PWA PASS from emulation alone.
- Product impact: none; this is an evidence boundary, not a runtime failure.

## INC-W7B-042 - Isolated worktree did not inherit the Supabase project link

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Regression: `regression_verified`
- Detected at: 2026-08-28 21:52 CEST
- Surface: mandatory pre-deployment `supabase migration list --linked` readback.
- Original scenario: the command exited before contacting the remote database with `Cannot find project ref` because the isolated Git worktree does not inherit the ignored `supabase/.temp` link metadata from another checkout.
- Root cause: Supabase CLI project-link state is local, ignored workspace metadata rather than committed repository state.
- Safety evidence: the failure occurred before any remote query or mutation; production ledger and schema remain unchanged.
- Correction: linked this worktree explicitly to the known Pachangas IQ project without supplying or persisting a database password.
- Regression evidence: `supabase migration list --linked` connected successfully and proved 183 matching local/remote migrations through `20260828072053`; the only local-only rows are the seven intentional Wave 7B versions `20260828163750` through `20260828163756`.
- Product impact: none; no application or database request was executed.
