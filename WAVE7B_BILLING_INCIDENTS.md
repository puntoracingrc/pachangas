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
