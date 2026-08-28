# Wave 7C Commercial Activation Incidents

Date opened: 2026-08-28 CEST

## Checkpoint

- Base `origin/main`: `0040f750dc935ccb43a0f2ccfcf65a243bcb40ef`.
- Supabase production ledger: 190 migrations at the preceding Wave 7B readback.
- Organizer Billing Foundation, plan catalog, partnership grants, sandbox, webhook ingest and reconciliation: active.
- Organizer live Price mappings, billing accounts and Stripe V2 events: 0.
- `live_prices_approved=false`.
- `live_checkout_enabled=false`.
- `portal_enabled=false`.
- `tax_health=UNCONFIGURED`.
- Stripe V1: protected invariant.

## Permanent commercial boundary

The proposed Organizer amounts are non-authoritative test fixtures until a
`platform_owner` records a complete commercial decision through the canonical
approval workflow. Wave 7C must not create live Prices, enable live Checkout or
create a real charge without that decision and `tax_health=LIVE_READY`.

## Incident taxonomy

Every failure found during this wave is recorded here before correction as one
of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

Resolved incidents must include `fixed` and `regression_verified`.

## W7C-001 - Legacy platform command can bypass commercial approval

- Classification: `PRODUCT_BUG`
- Status: `open`
- Found in: `command_pachanga_organizer_billing_platform_v1` and the
  `/api/platform-admin/billing` allowlist.
- Original scenario: a role holding the broad `billing.write` capability can
  submit `settings.flag` for `live_prices_approved`, `portal_enabled` or
  `live_checkout_enabled`, and can submit a `price_mapping.upsert` for live
  mode. Neither path requires a published commercial decision, the
  `platform_owner` role, current Terms/Privacy revisions or `LIVE_READY` tax
  health.
- Required correction: close only the legacy live-write paths and introduce a
  platform-owner, revisioned, idempotent activation workflow. Test mappings
  remain service-confirmed after Stripe readback.
- Required regression: direct legacy calls must fail and cannot mutate live
  settings or mappings.
- Verification: the local SQL suite invokes the legacy flag, tax-health and
  live mapping commands as `authenticated`; every path is rejected by the new
  authority triggers before protected state changes.

## W7C-002 - Tax health cannot represent the commercial gate

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Found in: `private.pachanga_organizer_billing_settings.tax_health`.
- Original scenario: the current enum exposes `SANDBOX_READY` and
  `LIVE_REVIEW_REQUIRED`, but cannot distinguish a missing commercial decision
  from a tax review, nor describe the canonical `TEST_READY` state required by
  Wave 7C.
- Required correction: migrate the enum forward without losing the current
  value and make `LIVE_READY` an explicit platform-owner decision only.
- Required regression: every unsupported state is rejected and live
  activation remains impossible for every state except `LIVE_READY`.
- Verification: the forward migration installs the six-state constraint, the
  canonical command reaches `TEST_READY` and `LIVE_READY`, and the live gate
  remains closed before the complete decision/catalog/runtime fixture exists.

## W7C-003 - Organizer health is not separated from Stripe V1

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Found in: `getStripeHealth` and `/admin/billing`.
- Original scenario: the Control Center receives one broad Stripe health read
  using the legacy credential path. It cannot prove independent TEST/LIVE
  Organizer Product, Price, webhook, signing, Portal and Checkout readiness.
- Required correction: add Organizer-specific, mode-separated health that
  returns only redacted identifiers/counts and never changes the Stripe V1
  connector.
- Required regression: TEST and LIVE cannot be confused and no raw Stripe
  secret or customer identifier reaches the response.

## W7C-004 - Stripe Organizer test runtime is not configured for this branch

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Evidence: Stripe test mode contains zero Pachangas Organizer Products, and
  Vercel has no branch-scoped `STRIPE_TEST_SECRET_KEY` or
  `STRIPE_TEST_WEBHOOK_SECRET` for this worktree branch.
- Required correction: create only the two authorized TEST Products and four
  TEST Prices, configure a separate TEST destination for
  `/api/webhooks/stripe`, and keep every credential server-only.
- Required regression: test Checkout/Portal/webhook pass while live Products,
  Prices, mappings and charges remain zero.

## W7C-005 - Catalog readback assumed a non-existent ordering column

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the initial read-only catalog query ordered
  `pachanga_organizer_plan_catalog` by `display_order`, but that column does not
  exist on the catalog table.
- Required correction: use the stable `plan_code` key for the diagnostic
  readback and do not alter the schema to accommodate a test assumption.
- Required regression: the corrected readback returns all canonical plans and
  their latest revisions without a database error.
- Verification: the stable readback returned all six canonical plans and their
  version 1 revisions ordered by `plan_code`.

## W7C-006 - Fresh local stack health check precedes the simulation schema

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: a fresh `supabase start` launches PostgREST with
  `simulation` in `db-schemas` before the migration reset has created that
  schema. PostgREST repeatedly reports SQLSTATE `3F000` and the CLI exits with
  HTTP 503 before migrations can be exercised.
- Required correction: bootstrap PostgreSQL without PostgREST, apply the full
  local migration chain, then start the complete stack.
- Required regression: the migrated local database contains `simulation` and
  the complete stack reaches healthy without `3F000`.
- Verification: the guarded product bootstrap applied all 196 repository
  migrations while proving that no lab schema leaked. The disposable local
  runtime then created `simulation` outside migrations, reloaded PostgREST and
  served the REST schema without SQLSTATE `3F000`.

## W7C-007 - PostgREST image does not declare a Docker health object

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the diagnostic `docker inspect` template assumed every
  local service exposed `.State.Health.Status`; this PostgREST image has no
  Docker health object, so the template itself failed after `supabase status`
  had already succeeded.
- Correction: verify the service through its actual REST endpoint and container
  running state instead of manufacturing a missing Docker health field.
- Verification: the REST schema request returned HTTP 200 and the container
  remained running.

## W7C-008 - Local diagnostic reused a reserved zsh variable

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the REST probe assigned its HTTP code to `status`, which
  is read-only in zsh, so the shell rejected the assignment before the probe.
- Correction: use the neutral variable `http_code`; no product or environment
  configuration was changed.
- Verification: the corrected probe completed and returned the expected REST
  response code.

## W7C-009 - Wave 7B Portal gate cannot distinguish TEST from LIVE

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: `prepare_pachanga_organizer_portal_service_v1` checks only
  the global `portal_enabled` flag before inserting an intent. Wave 7C can
  therefore neither enable TEST Portal independently nor keep LIVE Portal
  closed with the same RPC signature.
- Required correction: preserve the RPC contract but route TEST through
  `stripe_test_portal_enabled` and LIVE through `portal_enabled`; table guards
  remain the final fail-closed layer.
- Required regression: TEST Portal works only after TEST readiness while LIVE
  Portal remains rejected until the commercial activation command succeeds.
- Verification: the SQL suite creates a TEST Portal intent after TEST readiness
  and receives `BILLING_LIVE_PORTAL_DISABLED` for the same organizer before
  canonical live activation.

## W7C-010 - Direct tsx invocation bypassed the npm binary path

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the first focused static-test command invoked `tsx`
  directly, but the interactive shell does not include `node_modules/.bin` in
  its PATH and returned `command not found`.
- Correction: execute the repository-owned `npm run test:organizer-commercial`
  script, which resolves the locked local binary.
- Verification: the focused TypeScript suite completed through npm.

## W7C-011 - Webhook separation test asserted a non-existent helper name

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the new static regression expected the symbol
  `organizerStripeWebhookSecret`, while the existing server-only contract uses
  `organizerWebhookSecrets()` to return mode-tagged TEST/LIVE verifiers.
- Correction: assert the real helper and its mode-separated iteration without
  changing production webhook code.
- Verification: the focused suite passes and still proves that the legacy V1
  route does not import the Organizer verifier.

## W7C-012 - Authenticated SQL fixture reads private state while preparing calls

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the Wave 7C SQL suite correctly switches to the
  `authenticated` role before exercising public commands, but some test
  arguments read revisions and decision identifiers directly from the
  `private` schema. PostgreSQL rejects the fixture read before the public RPC
  can be evaluated, so the test does not reach the intended authority gate.
- Required correction: capture private fixture state through test-only
  `SECURITY DEFINER` helpers owned by the local database bootstrap role. Do not
  grant any product role access to the `private` schema or add a production
  helper for this purpose.
- Required regression: the suite must reach each public RPC as
  `authenticated` or `service_role`, preserve the expected private-schema
  denial for direct writes, and complete without broadening production grants.
- Verification: test-only helpers now supply fixture revisions and IDs; the
  full SQL suite passes while a direct authenticated update still returns
  `permission denied for schema private`.

## W7C-013 - Live activation terms parameters collide with decision columns

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the canonical live-activation RPC reaches its published
  decision checks, but PostgreSQL resolves `terms_revision` and
  `privacy_revision` as ambiguous names because both are function parameters
  and columns in the queried decision table. The command aborts before it can
  return the intended fail-closed commercial gate.
- Required correction: qualify the function parameters explicitly throughout
  the activation body while preserving the RPC signature used by PostgREST.
- Required regression: premature activation returns
  `BILLING_LIVE_ACTIVATION_GATE_INCOMPLETE`; a complete fixture activates once,
  and an identical `operationId` replay returns the original receipt.
- Verification: a fresh 196-migration bootstrap passes the complete Wave 7C
  suite, including the premature gate, one canonical activation and replay of
  the stored receipt.

## W7C-014 - Stripe SDK v22 health probe and nullable Portal metadata

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the first Wave 7C typecheck rejects a parameterless
  `accounts.retrieve()` call under Stripe SDK v22 and reports that Billing
  Portal configuration metadata may be `null`.
- Required correction: use a mode-scoped API probe that does not require an
  account identifier and normalize nullable Portal metadata before reading it.
- Required regression: TypeScript must compile the Organizer Stripe adapter
  without loosening types or exposing a credential.
- Verification: the adapter now probes `balance.retrieve()`, normalizes Portal
  metadata to an empty object when absent, and `npm run typecheck` completes
  without errors.

## W7C-015 - A resumed catalog operation could duplicate Stripe resources

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: Stripe idempotency protected retries that reused the same
  `operationId`, but a fresh operation after a partial success could create a
  second Product or Price for the same plan and catalog revision.
- Correction: list and match the exact server-issued Product and Prices before
  creating anything, reuse a unique match, and fail closed if multiple exact
  matches already exist.
- Regression: the focused suite verifies read-before-create, exact metadata and
  explicit duplicate Product/Price errors. Stripe readback remains mandatory
  before PostgreSQL confirms a mapping.

## W7C-016 - Commercial form synchronously repopulates state from an effect

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: selecting or refreshing a commercial decision triggers an
  effect that synchronously calls ten state setters. React's lint contract
  rejects the pattern because it can cascade renders and destabilize the form.
- Required correction: initialize the draft directly from the canonical
  decision and update it only from the explicit plan selector.
- Required regression: focused React lint passes and switching plans still
  loads the selected canonical values without a state-populating effect.
- Verification: the form now initializes from the canonical decision and its
  selector explicitly loads the next draft; focused ESLint, typecheck and the
  Wave 7C suite all pass.

## W7C-017 - Demo verification omitted the Organizer Billing chunk

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: `committedSnapshot()` loaded every Demo World V2 chunk
  except `organizer-billing.json`. The verify run could therefore compare a
  generated commercial snapshot against an object with that domain missing,
  leaving the billing parity gate incomplete and capable of hiding drift.
- Required correction: load Organizer Billing in the committed snapshot,
  generate V2.9 billing states through canonical RPC and webhook processing in
  the disposable PostgreSQL world, and include the domain in drift comparison.
- Required regression: mutate or omit the committed billing chunk and the
  deterministic verification must fail; the unmodified seven-scenario snapshot
  must pass with zero remote writes, zero PII and zero Stripe identifiers.
- Correction: `committedSnapshot()` now includes `organizer-billing.json`; V2.9
  derives its seven states from canonical billing RPCs and signed-webhook
  projections in the disposable PostgreSQL world.
- Verification: the full 196-migration simulation emitted manifest hash
  `300c5490d8e1ff64dd6e9238228d57628bfbae5e70a0cde0f089c04c3adb7e74`
  with `remoteWrites=0`, and the focused test rejects missing or changed billing
  chunks.
## W7C-018

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: Demo World V2.9 failed before preparing the TEST catalog because the authenticated synthetic actor evaluated a direct subquery against `private.pachanga_organizer_commercial_decisions_v1`.
- Evidence: PostgreSQL rejected the simulation with `permission denied for schema private` at the catalog preparation statement.
- Impact: no product authority or remote data changed; the disposable simulation database was destroyed and no V2.9 artifacts were emitted.
- Required correction: resolve the synthetic decision identifier through a temporary `security definer` helper, then keep catalog creation on the canonical platform RPC and add successful full-simulation regression evidence.
- Correction: the disposable script resolves decision IDs through the
  transaction-local `pg_temp.demo_commercial_decision_id` security-definer
  helper; no product grant or private-schema permission was widened.
- Verification: both TEST catalog intents and all four TEST price mappings were
  created through canonical RPCs in the successful full simulation.
## W7C-019

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: Demo World V2.9 prepared and confirmed the TEST catalog, then the service-authority checkout loop could not read the session-local `demo_billing_scenarios` table.
- Evidence: PostgreSQL rejected the loop with `permission denied for table demo_billing_scenarios` and explicitly identified the temporary schema grant required.
- Impact: the disposable simulation transaction rolled back, its database was destroyed, and no generated artifact or remote resource changed.
- Required correction: grant only the synthetic temporary scenario table to `authenticated` and `service_role`, then rerun the full disposable simulation.
- Correction: only the transaction-local `demo_billing_scenarios` table grants
  `select, update` to the two synthetic roles; no persistent table or schema
  grant changed.
- Verification: all six Checkout preparations and seven lifecycle scenarios
  completed, and the disposable database was destroyed after export.
## W7C-020

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: all seven Organizer Billing lifecycle operations completed in the disposable database, but the final combined proof assertion failed without identifying the divergent invariant.
- Evidence: `DEMO_WORLD_V2_9_ORGANIZER_BILLING_PROOF_INVALID` was the only diagnostic after the active, past-due and canceled webhook projections had all returned `PROCESSED`.
- Impact: the transaction rolled back and the temporary database was destroyed; no public snapshot or remote state changed.
- Required correction: expose the already redacted synthetic proof during the local simulation, isolate the mismatching invariant, then retain a regression assertion with actionable evidence.
- Root cause: billing metadata intentionally sanitizes the non-allowlisted
  `surface` key, so the simulator's receipt query returned zero even though 22
  canonical receipts existed.
- Correction: count receipts by the dedicated synthetic actor UUID and emit a
  bounded redacted diagnostic containing only counters and lifecycle states.
- Verification: the full simulation reports 22 receipts, four TEST mappings,
  seven Stripe events, zero LIVE mappings and `testRuntimeReady=true`; all
  V2.9 assertions pass.

## W7C-021 - Demo graph retained the V2.7 migration-count assertion

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after V2.9 generated and verified successfully with 196
  migrations, the focused Demo suite still expected the protagonist graph to
  report the historical V2.7 count of 183.
- Evidence: `tests/demo-world-v2.test.ts` failed with `196 !== 183`; the other
  16 Demo tests and all seven Wave 7C static tests passed.
- Impact: no product behavior, database or generated snapshot changed; the
  stale expectation only blocked the regression suite.
- Required correction: assert the canonical V2.9 migration count of 196 in
  every current-snapshot test while retaining immutable historical manifests.
- Required regression: rerun the complete focused Demo suite with 17/17 PASS.
- Verification: the corrected suite passes 17/17 with zero skipped, todo or
  cancelled tests; the V2.1 through V2.8 immutable-hash assertions remain
  unchanged.

## W7C-022 - Stripe Dashboard metadata controls are not exposed as stable Playwright buttons

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the TEST Dashboard exposes its metadata pencil as an
  unlabeled custom anchor. A semantic Playwright button click and a later
  verification call against the tab wrapper both failed even though the
  Stripe form itself remained healthy.
- Correction: locate the existing `data-testid=metadata_edit_button` or its
  DOM CUA node, then use the already bounded metadata helper. Never inspect
  browser storage, cookies or secrets to work around Dashboard controls.
- Regression: read back all five exact metadata pairs from each Organizer
  Product and Price after save.
- Verification: both TEST Products and all four recurring TEST Prices expose
  the canonical product family, plan, organizer kind, environment and catalog
  revision metadata; no LIVE resource was touched.

## W7C-023 - Wave 7B stress runners pin the historical 190-migration ledger

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: Wave 7C adds six forward-only migrations, but the shared
  Wave 7B concurrency and scale runners still assert an exact ledger count of
  190. Running them from the Wave 7C branch would fail before exercising any
  billing invariant.
- Required correction: derive the current expected ledger from the migration
  directory while retaining an explicit latest-version assertion in the Wave
  7C suite. Do not rewrite or delete any historical migration.
- Required regression: both runners bootstrap all 196 migrations and keep the
  Wave 7B authority, idempotency and scale assertions unchanged.

## W7C-024 - Wave 7C had no executable proof for its nine requested races

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the inherited billing runner covers operation replay,
  stale settings, duplicate Stripe delivery, expiry and queue claims, but it
  does not name or exercise all nine commercial activation races required by
  Wave 7C.
- Required correction: add a disposable local-PostgreSQL runner for approval,
  withdrawal, catalog publication, owner transfer, webhook/reconciliation,
  cancellation/payment, plan/competition, Portal/revocation and
  expiry/continuity races.
- Required regression: every race must converge to one canonical winner plus
  a stale, replayed or otherwise fail-closed loser, and the disposable database
  must be removed in `finally`.

## W7C-025 - First concurrency draft tried to derive a catalog RPC by string replacement

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the first local draft correctly implemented the approval
  races, then attempted to transform a commercial-command SQL string into a
  catalog-preparation call with regular-expression replacement. That is not a
  structured or reviewable test contract and was caught before execution.
- Impact: no test database, Stripe resource or remote system was touched.
- Required correction: define an explicit typed SQL helper for every RPC used
  by the runner and complete all nine named races without source-string
  rewriting.
- Required regression: syntax-check the runner, execute it against the
  disposable 196-migration database and verify cleanup on success and failure.

## W7C-026 - Live publication race used Terms and Privacy revisions outside the approved settings

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the first executable concurrency run approved a new
  superseding decision with dedicated race revisions, while the fixture kept
  the previous canonical Terms and Privacy revisions in billing settings.
  `prepare_pachanga_organizer_stripe_catalog_platform_v1` correctly rejected
  the mismatch with `BILLING_LIVE_CATALOG_GATE_INCOMPLETE` before the race.
- Impact: the disposable database was removed in `finally`; no remote Stripe,
  Supabase or Vercel state changed.
- Required correction: update the fixture's canonical settings through its
  protected authority context to the same explicit revisions before preparing
  the two live intents.
- Required regression: both preparations pass the commercial gate, one
  confirmation publishes, and the second loses with `STALE_REVISION`.

## W7C-027 - Ownership transfer leaves the previous owner's Checkout and Portal intents active

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: a TEST Checkout preparation raced the authoritative team
  ownership transfer. The group converged to the new owner, but two existing
  Checkout intents owned by the previous owner remained `PREPARED` or
  `SESSION_CREATED`.
- Evidence: the disposable concurrency test read `2` active intents after the
  transfer where the authority contract requires `0`.
- Impact: an obsolete owner could retain a billing link after losing owner
  authority. No remote Checkout Session was created by this local test.
- Required correction: in the same PostgreSQL transaction as a canonical owner
  change, move the billing contact to the new owner, increment the account
  revision and expire every unconfirmed Checkout and Portal intent belonging
  to the previous owner.
- Required regression: both Checkout/transfer and Portal/transfer races leave
  the canonical group owner and billing contact aligned, with zero actionable
  intents for the former owner.

## W7C-028 - Checkout can resume after an ownership lock with stale actor authority

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the Checkout transaction validated the original owner,
  then waited for the billing account row while the ownership transfer
  completed. Once unblocked, it inserted a new `PREPARED` intent for the former
  owner after the transfer trigger had already finished its invalidation pass.
- Evidence: the second disposable concurrency run read `1` actionable Checkout
  intent for the former owner after the group had converged to the new owner.
- Impact: checking owner authority only before a blocking row lock creates a
  time-of-check/time-of-use gap. No remote Checkout Session was created by this
  local test.
- Required correction: revalidate current canonical owner authority at intent
  insertion time for Checkout and Portal, after any preceding lock wait, and
  reject stale actors before an actionable intent can exist.
- Required regression: both operations may start concurrently, but after owner
  transfer the former owner has zero `PREPARED` or `SESSION_CREATED` Checkout
  and Portal intents, independently of lock acquisition order.

## W7C-029 - Snapshot-only owner revalidation does not serialize the authority race

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: a `BEFORE INSERT` trigger re-read owner authority after
  the billing-account wait, but the same Checkout/transfer race still left one
  actionable intent for the former owner.
- Evidence: the third disposable concurrency run again read `1` instead of `0`
  after the static trigger coverage passed.
- Impact: a plain snapshot re-read is not a serialization boundary and cannot
  prove that ownership remained stable through intent creation. No remote
  Checkout Session was created by this local test.
- Required correction: lock the canonical team or club row while validating
  the current owner. The intent insert and the ownership mutation must then
  serialize on the same authoritative row.
- Required regression: repeat the Checkout/transfer and Portal/transfer races
  with both lock orders and converge to zero actionable intents for the former
  owner.

## W7C-030 - Concurrency runner assumes ownership transfer must win the lock race

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after both operations were serialized on the canonical
  group row, Checkout won one execution and the ownership transfer correctly
  lost. The runner nevertheless required the new owner immediately.
- Evidence: the fourth disposable run read the original owner after a clean
  serialized winner instead of the test's unconditional expected next owner.
- Impact: the test confused a valid race outcome with lack of convergence and
  could reject a correct authority boundary. No remote state changed.
- Required correction: accept either serialized first winner, then retry the
  requested ownership transfer against the confirmed canonical revision when
  necessary.
- Required regression: the test must finish with the requested owner, aligned
  billing contact and zero actionable intents for the former owner regardless
  of which operation obtained the canonical row lock first.

## W7C-031 - Canceled subscription leaves competition creation grants active

- Classification: `SIMULATION_BUG` (initially suspected `PRODUCT_BUG`)
- Status: `fixed` / `regression_verified`
- Original scenario: a competition-creation request raced a canonical
  `customer.subscription.deleted` event after the paid plan had been
  reactivated.
- Evidence: the subscription projection converged to `canceled`, but the
  disposable database still contained `2` active `competition_create` or
  `tournament_create` entitlement grants instead of `0`.
- Triage: the fixture sent a future `current_period_end`. The approved Portal
  contract supports cancellation at period end, so keeping ordinary paid
  access until that date is correct. The failing expectation described an
  already-effective cancellation but the event did not.
- Impact: false positive in the concurrency runner; no product authority defect
  and no remote Stripe or Supabase state change.
- Required correction: make this particular race use an already-ended billing
  period. Keep the separate cancel-at-period-end and continuity behavior intact.
- Required regression: regardless of whether competition creation or the
  cancellation event commits first, the final subscription is canceled and no
  active creation grant remains.

## W7C-032 - Plan race does not replay the webhook after the competing winner

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after correcting the cancellation period, competition
  creation won the lock race and the cancellation delivery lost. The runner
  immediately required the projection to be canceled without simulating the
  provider's delivery retry.
- Evidence: the fifth disposable run read subscription status `active` where
  the runner unconditionally expected `canceled`.
- Impact: the test stopped before exercising eventual webhook convergence; no
  remote state changed.
- Required correction: when the cancellation delivery loses the race, resend
  the same canonical Stripe event through the real ingestion path with a fresh
  delivery identifier.
- Required regression: both first-winner orders must converge to a canceled
  projection and zero active creation grants after bounded replay.

## W7C-033 - Duplicate cancellation delivery did not repair the active projection

- Classification: `SIMULATION_BUG` (triaged from `TESTABILITY_GAP`)
- Status: `fixed` / `regression_verified`
- Original scenario: the bounded replay added for W7C-032 returned without a
  command error, but the subscription projection still read `active`.
- Evidence: the sixth disposable run failed after the replay at the canonical
  status assertion (`active` instead of `canceled`).
- Impact: the current runner does not expose enough event-ledger evidence to
  distinguish an out-of-order event, an already-processed duplicate or a
  failed retryable projection. No remote state changed.
- Required correction: include event processing status, projection ordering
  fields, delivery count and both race outcomes in the regression diagnostic,
  then fix only the demonstrated authority path. The diagnostic proved that
  `currentPeriodStart` and `currentPeriodEnd` were equal, so the canonical row
  constraint correctly classified the event as `FAILED_TERMINAL`; use a valid
  already-ended period instead.
- Required regression: a bounded replay must either repair the canonical
  projection or return an explicit non-success state that the reconciliation
  path can process; silent non-convergence is forbidden.

## W7C-034 - Continuity race repeats the invalid zero-length billing period fixture

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the final entitlement-expiry/continuity race reused a
  cancellation period whose start and end were both 1 August.
- Evidence: both `psql` processes exited successfully because Stripe ingestion
  reports terminal event failures as an accepted JSON result, but the canonical
  access grant remained `active` instead of becoming `continuity`.
- Impact: the ninth race did not exercise entitlement expiry at all. No remote
  state changed.
- Required correction: use a valid already-ended billing period and assert the
  webhook event ledger is `PROCESSED`, not merely that the SQL call exited zero.
- Required regression: the expiration worker and valid cancellation event may
  interleave, but the subscription-backed grant must converge to `continuity`
  and the immutable edition snapshot must survive.

## W7C-035 - Wave 7C public catalog overrides the inherited OFF state

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the Wave 7B regression suite queried the public catalog
  with billing foundation and plan catalog both disabled.
- Evidence: the canonical settings read all relevant flags as `false`, but the
  Wave 7C wrapper returned `CATALOG_AVAILABLE` instead of the inherited
  `NOT_AVAILABLE` state.
- Impact: a dormant release could advertise a catalog surface before platform
  activation, violating fail-closed rollout semantics. No remote state changed.
- Required correction: preserve the legacy `NOT_AVAILABLE` response whenever
  its foundation gate is closed; only enrich an already available catalog with
  Wave 7C pricing and Checkout state.
- Required regression: the complete Wave 7B database suite must pass against
  the 196-migration schema, while Wave 7C still exposes approved prices after
  its explicit activation.

## W7C-036 - Wave 7B fixture activates a flag now protected by Wave 7C

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the inherited Wave 7B database fixture enabled
  `portal_enabled` through the old generic settings command after Wave 7C had
  correctly protected that flag behind commercial authority.
- Evidence: the clean 196-migration database rejected the fixture with
  `BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED` after seven earlier legacy
  flags were enabled normally.
- Impact: regression setup could no longer construct its historical Portal
  state, while weakening the production guard would reintroduce a bypass. No
  remote state changed.
- Required correction: grant the temporary fixture-only authority exactly
  around the historical Portal setup call and clear it immediately afterward.
  Do not change the product RPC or trigger.
- Required regression: Wave 7B behavior passes in its controlled transaction,
  and the Wave 7C suite still proves that an ordinary authenticated call to the
  old route is rejected.

## W7C-037 - Wave 7B fixture inserts a Price through the retired generic mapping path

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after the Portal fixture was isolated, the historical
  suite attempted its one TEST Price mapping through
  `command_pachanga_organizer_billing_platform_v1`.
- Evidence: the clean 196-migration schema rejected it with
  `BILLING_STRIPE_CATALOG_AUTHORITY_REQUIRED`.
- Impact: reopening the old route would bypass Wave 7C's exact Product/Price
  readback; the fixture instead needs an explicit, temporary setup authority.
  No remote state changed.
- Required correction: scope `pachangas.billing_mapping_authority` to this one
  local mapping setup call and clear it before the behavioral assertions.
- Required regression: Wave 7B can exercise its historical TEST projection,
  while Wave 7C continues to reject an ordinary legacy mapping write.

## W7C-038 - Wave 7B Checkout fixture omits the new TEST activation evidence

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after inserting its historical single TEST Price, the
  inherited suite prepared Checkout without Wave 7C's four canonical mappings,
  tax state, runtime health or explicit TEST flags.
- Evidence: the 196-migration schema rejected Checkout with
  `BILLING_TEST_CHECKOUT_GATE_INCOMPLETE`.
- Impact: relaxing the gate would allow optimistic local setup to masquerade as
  a verified Stripe catalog. No remote state changed.
- Required correction: before the historical Checkout assertions, prepare and
  confirm both TEST catalog intents through the real Wave 7C RPCs, record TEST
  runtime health and activate only the TEST flags.
- Required regression: Wave 7B Checkout/idempotency/entitlement assertions pass
  on top of exactly four verified TEST mappings; LIVE remains disabled.

## W7C-039 - Wave 7B TEST setup queries a private decision as authenticated

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the new compatibility setup selected commercial decision
  IDs directly from the `private` schema after switching to `authenticated`.
- Evidence: PostgreSQL rejected the first catalog preparation with
  `permission denied for schema private`.
- Impact: the fixture accidentally requested broader read access than the
  product exposes. No remote state changed.
- Required correction: resolve only the decision UUID needed by the test through
  a `pg_temp` security-definer helper; do not grant private-schema access.
- Required regression: catalog preparation succeeds for the platform actor and
  ordinary authenticated actors still cannot read commercial authority rows.

## W7C-040 - Wave 7B concurrency setup writes protected rows without fixture authority

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the separate Wave 7B concurrency runner bootstrapped all
  196 migrations, then directly updated billing settings and inserted its local
  TEST mapping without the new authority contexts.
- Evidence: setup failed with
  `BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED` before any race started.
- Impact: the disposable runner could not reach its inherited idempotency,
  stale-revision, webhook, expiry and queue races. No remote state changed.
- Required correction: scope both settings and mapping authority GUCs to the
  local setup transaction and clear them before starting concurrent clients.
- Required regression: the unchanged Wave 7B races pass on a 196-migration
  disposable database and cleanup still succeeds.

## W7C-041 - Wave 7B concurrency account uses the removed SANDBOX_READY tax state

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after the setup authorities were scoped correctly, the
  fixture inserted its TEST billing account with legacy tax status
  `SANDBOX_READY`.
- Evidence: the Wave 7C constraint
  `pachanga_organizer_billing_accounts_tax_health_v2_ck` rejected the row.
- Impact: no race executed; no remote state changed.
- Required correction: use the canonical equivalent `TEST_READY` in the local
  fixture.
- Required regression: the account satisfies the V2 tax-state domain and all
  inherited concurrency assertions run unchanged.

## W7C-042 - Scale runner applies Wave 7C before the Wave 7B tables it extends

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the scale bootstrap excluded only the seven Wave 7B
  migrations from its pre-wave batch, so the six later Wave 7C migrations were
  executed first.
- Evidence: `bootstrap pre-Wave 7B scale schema` failed before representative
  rows were loaded; the verbose baseline notices obscured the dependency-order
  failure in the initial output.
- Impact: no scale result was produced and the disposable database was cleaned.
  No remote state changed.
- Required correction: treat the thirteen Wave 7B + Wave 7C migrations as one
  ordered measurement batch after the pre-wave schema.
- Required regression: all thirteen migrations apply in repository order, each
  emits timing/lock/index metrics, and the final ledger reports 196.

## W7C-043 - Representative scale seed bypasses Wave 7C setup contracts

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after applying all thirteen billing migrations in order,
  the 2,000-account seed directly changed protected settings and inserted its
  synthetic Price without fixture authority. It also retained the removed
  `SANDBOX_READY` account tax state.
- Evidence: volume loading stopped at line 44 with
  `BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED`; static review found the
  mapping guard and tax-state constraint would be next.
- Impact: representative rows and query plans were not measured; the disposable
  database was cleaned. No remote state changed.
- Required correction: scope both private setup authorities to the seed
  transaction, clear them after the mapping, and use `TEST_READY` for synthetic
  TEST accounts.
- Required regression: the exact representative row counts, index plans,
  timing, memory, locks and size thresholds pass on the 196-migration schema.

## W7C-044 - Wave 7B Control Center regression expects the retired live Price control

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the complete repository suite reaches the inherited Wave
  7B Control Center test after Wave 7C has replaced the generic live Price
  toggle with dedicated commercial-decision, exact catalog-provisioning and
  live-activation actions.
- Evidence: the static assertion still requires
  `priceMode === "live" && priceApproved && !canApproveLive`, a branch that no
  longer exists in the Wave 7C admin client. The other repository tests pass.
- Impact: the stale assertion blocks the full test gate; restoring the old UI
  branch would reopen an obsolete path and weaken the commercial boundary.
  No product, Stripe or remote database state changed.
- Required correction: update the inherited regression to require the new
  `canApproveLive`-gated commercial approval and LIVE activation controls,
  while retaining reconciliation and manual-grant coverage.
- Required regression: the full repository suite passes and the client still
  contains no service authority or raw Stripe Customer/Subscription IDs.
- Correction: the inherited assertion now requires the dedicated approval,
  exact catalog-provisioning and final activation actions, including their
  `canApproveLive`, decision-state, `LIVE_READY`, checklist and explicit
  confirmation gates. Reconciliation and manual grant assertions remain.
- Verification: the Wave 7B focused suite passes 12/12 and the Wave 7C focused
  suite passes 9/9; the full repository suite is rerun as a final release gate.

## W7C-045 - Stripe Workbench exposes two controls with the same accessible name

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: while reviewing the TEST Customer Portal, the Stripe
  Dashboard Workbench overlay exposes two visible controls both named
  `Cerrar Workbench`.
- Evidence: strict browser selection reports two matches: the real minimize
  button and a tray action link.
- Impact: the first semantic click is intentionally rejected as ambiguous;
  no Stripe resource or Pachangas IQ state changed.
- Required correction: select Stripe's stable Workbench minimize test ID and
  continue read-only Portal inspection.
- Required regression: the overlay closes once and the Customer Portal page
  remains in TEST mode.
- Correction: the browser selected `wb-WorkbenchMinimize`, the uniquely scoped
  minimize control, rather than either duplicated accessible name.
- Verification: Workbench closed once; the URL retained `/test/` and exposed
  the existing default TEST Portal read-only. That shared configuration was
  not edited; Wave 7C will create its separate metadata-scoped Organizer
  configuration through the server adapter.

## W7C-046 - Combined Supabase linked checks hang without output

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the release preflight invoked linked migration parity and
  branch discovery in one shell process.
- Evidence: the process produced no stdout or stderr for more than 90 seconds
  and required an interrupt before either result could be attributed.
- Impact: no migration, branch or production data changed, but the combined
  command cannot prove ledger parity or staging availability.
- Required correction: execute migration parity and branch discovery as
  separate bounded commands, preserving their individual exit status.
- Required regression: obtain an explicit linked ledger result and an explicit
  branch-list result before any remote schema write.
- Correction: the purpose-built Supabase connector replaced the unauthenticated
  CLI session for these two read-only checks; no schema command was retried.
- Verification: production returned the exact 190-row ledger ending at
  `20260828163756_organizer_billing_hardening_flags_v1`; branch discovery
  returned the isolated `pwa-bridge-staging` project as `ACTIVE_HEALTHY`.

## W7C-047 - Supabase connector timestamps staging migrations independently

- Classification: `ENVIRONMENT_ISSUE`
- Status: `open`
- Original scenario: the six Wave 7C SQL files were applied in the correct
  order to the disposable staging branch through the Supabase migration
  connector.
- Evidence: staging reaches 196 migrations, but the connector records versions
  `20260828231354` through `20260828231359` instead of the repository versions
  `20260828205310` through `20260828205317`.
- Impact: SQL order and branch behavior are correct, but that mechanism cannot
  be used for production because linked history must preserve exact repository
  versions. Production remains unchanged at 190.
- Required correction: treat this branch ledger as ephemeral QA evidence only;
  use an exact-version migration path for production and retire/reset the
  staging branch after QA.
- Required regression: before production, compare local and remote lists by
  exact version and name; after deployment they must both end at
  `20260828205317_organizer_commercial_hardening_flags_v1` with 196 rows.

## W7C-048 - In-app tab creation ignores its initial URL argument

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: visual QA requested a new in-app browser tab with the
  exact Wave 7C Preview URL supplied at creation time.
- Evidence: the tab was created successfully but remained at `about:blank`.
- Impact: no application request or remote write occurred; visual QA had not
  started.
- Required correction: navigate the already created tab explicitly with
  `goto` and retain the exact immutable Preview hostname.
- Required regression: the final URL and title must identify Wave 7C before
  viewport assertions begin.
- Correction: the existing tab navigated explicitly to the immutable
  deployment hostname.
- Verification: the final URL is the exact Preview `/planes-organizador` and
  the title is `Planes de organizacion | Pachangas IQ`. The catalog correctly
  remains unavailable until the branch-specific staging environment is wired.

## W7C-049 - In-app tab wrapper does not expose direct semantic locators

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the LIVE Stripe catalog verification attempted to call
  `getByText` directly on the persistent in-app tab wrapper.
- Evidence: the browser binding reports `getByText is not a function` while
  the same binding still returns the correct Stripe LIVE URL and page title.
- Impact: no Stripe resource or Pachangas IQ state changed; the intended
  read-only product-name assertion did not run.
- Required correction: use the browser plugin's supported page-inspection API
  from the existing tab binding, without reading cookies, storage or secrets.
- Required regression: count both exact Organizer product names on the LIVE
  catalog and confirm zero matches while the URL remains outside `/test/`.
- Correction: the assertion now uses the supported `tab.playwright.getByText`
  surface while preserving the already authenticated LIVE tab.
- Verification: both exact Organizer product-name counts are zero, the URL is
  the LIVE `/products` catalog and it does not contain the `/test/` segment.

## W7C-050 - Environment scan included a directory absent from this repository

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the Preview environment dependency scan included a
  conventional root `lib` directory alongside the repository's real paths.
- Evidence: `rg` returned the useful matches but also reported `lib: No such
  file or directory`.
- Impact: no file or remote state changed; the partial output is not accepted
  as the final inventory.
- Required correction: rerun the same scan against existing repository paths
  only.
- Required regression: the corrected command must exit cleanly and retain the
  Supabase, service-role and Organizer Stripe environment references.
- Correction: the scan now targets `app`, `scripts`, `tests` and the existing
  root configuration files only.
- Verification: the command exits 0 and retains all required public Supabase,
  server service-role and dedicated Organizer Stripe environment references.

## W7C-051 - Public Organizer catalog unnecessarily requires service role

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the isolated Preview receives the public staging URL and
  publishable key, then requests `/api/billing/organizer/catalog`.
- Evidence: the route calls `billingServiceClient()`, which fails closed when
  `SUPABASE_SERVICE_ROLE_KEY` is absent, although
  `get_pachanga_organizer_plan_catalog_v1()` explicitly grants execution to
  `anon` and returns a public redacted read model.
- Impact: the public plans page cannot render its canonical catalog in a
  least-privilege Preview unless an unrelated privileged secret is supplied.
- Required correction: execute this read-only public RPC with a server-created
  Supabase client using the publishable key; retain service role for privileged
  Organizer commands and Stripe event confirmation only.
- Required regression: the catalog route must not reference service role and
  the focused tests must prove the public RPC still drives the canonical page.
- Correction: the billing server helpers now expose a least-privilege public
  client and the catalog route uses it for the anonymous canonical RPC.
- Verification: the Organizer Wave 7B/7C suites pass 22/22, typecheck passes,
  focused lint passes and the regression rejects any service-role reference in
  the public catalog route.
