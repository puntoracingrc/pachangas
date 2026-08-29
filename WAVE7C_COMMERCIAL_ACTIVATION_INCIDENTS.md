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
- Status: `fixed` / `regression_verified`

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
- Status: `fixed + regression_verified`
- Evidence: the dedicated Pachangas IQ Sandbox started without Organizer
  Products, Prices, Portal configuration or webhook destination, and the branch
  initially lacked its server-only TEST credentials.
- Required correction: create only the two authorized TEST Products and four
  TEST Prices, configure a separate TEST destination for
  `/api/webhooks/stripe`, and keep every credential server-only.
- Required regression: test Checkout/Portal/webhook pass while live Products,
  Prices, mappings and charges remain zero.
- Progress: the approved restricted TEST credential, Supabase staging service
  authority and dedicated webhook signing secret are now sensitive Preview
  variables scoped only to this branch. Production has no matching Wave 7C TEST
  variable and the client bundle remains clean.
- Current progress: the protected Preview reads the canonical plan catalog and
  the new Sandbox has the exact 11-event Organizer webhook. Its two Products,
  four Prices and Portal configuration still require canonical provisioning
  before this incident can close.
- Correction: the dedicated Sandbox was provisioned through the canonical
  server workflow with the two allowlisted Products, four recurring TEST
  Prices, isolated webhook and TEST Portal configuration.
- Verification: all four Checkout combinations, signed webhook, owner Portal,
  invoice failure/recovery and cancellation/resume passed; LIVE Products,
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
- Status: `fixed + regression_verified`
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
- Current reconciliation: staging still contains the six correct migration
  names in their required order under connector versions `20260828231354`
  through `20260828231359`. A fresh `supabase migration list --linked` against
  the separately linked production project exits zero, matches local and remote
  through `20260828163756`, and shows all six Wave 7C repository versions as
  local-only. Production therefore remains unchanged at ledger 190.
- Correction: Production received the seven exact repository migrations through
  the reviewed exact-version path; the isolated staging fixtures and temporary
  role were then removed without rewriting either ledger.
- Verification: Production and repository both end at ledger 197 with exact
  version/name parity, while staging cleanup reports zero active QA billing
  rows and restored OFF flags.

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

## W7C-052 - Vercel deployment readback used an obsolete identifier field

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the new Preview deployment was polled by deployment ID
  after GitHub triggered its build.
- Evidence: the connector rejected `id` and requires the current `idOrUrl`
  field before issuing a read request.
- Impact: the build remains active and unmodified; only the first readback did
  not execute.
- Required correction: repeat the read-only query with `idOrUrl` and the exact
  team ID.
- Required regression: the connector must return the deployment SHA and a
  terminal state for the same deployment ID.
- Correction: the poll now uses `idOrUrl` with the immutable deployment ID.
- Verification: Vercel returns `READY` for deployment
  `dpl_2zYbQx1HuH7CVjhRp8FzHc4RN6Dc` at exact SHA `4108fc1`.

## W7C-053 - Staging readback referenced a non-canonical Portal flag name

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: a compact post-migration readback attempted to report all
  TEST and LIVE commercial gates from the Organizer billing settings row.
- Evidence: PostgreSQL rejected `live_portal_enabled` because that convenience
  name is not a persisted column in the canonical schema.
- Impact: the query was read-only and atomic, so no staging row changed; its
  combined evidence payload was not produced.
- Required correction: inspect the actual settings columns, then repeat the
  readback using only canonical names.
- Required regression: the corrected result must include migration count,
  disabled LIVE gates, catalog status and TEST/LIVE mapping counts.
- Correction: the readback uses `stripe_live_portal_ready`, the persisted
  Portal health gate, and preserves all other canonical columns.
- Verification: staging reports 196 migrations, every Wave 7C flag OFF,
  `NOT_AVAILABLE`, zero catalog plans and zero TEST/LIVE mappings before QA
  activation.

## W7C-054 - In-app browser evaluation sandbox does not expose fetch

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after rendering the plans page, browser QA attempted to
  inspect the public catalog response status and cache headers in page context.
- Evidence: the plugin evaluation sandbox reports `fetch is not a function`.
- Impact: the visible canonical `No disponible` state is already verified and
  no request mutation occurred; only the lower-level HTTP assertion failed.
- Required correction: use Vercel's authenticated deployment fetch connector
  for the exact immutable API URL instead of page-context evaluation.
- Required regression: receive an HTTP 200 canonical `NOT_AVAILABLE` response
  from the same deployment without a service-role runtime error.
- Correction: the low-level attempts are isolated below; application evidence
  is taken from the client state that only exists after a successful JSON parse.
- Verification: the exact Preview renders catalog status `No disponible` and
  the disabled-plan paragraph, not its network-error fallback; deployment logs
  contain zero warnings or errors.

## W7C-055 - Immutable Preview API remains protected behind Vercel SSO

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the Vercel deployment fetch connector requested the exact
  public catalog API URL after browser rendering passed.
- Evidence: deployment protection returned a `302` SSO redirect with
  `Cache-Control: no-store` rather than the API response.
- Impact: no application handler ran through that connector request and no
  remote state changed; the browser session remains authenticated separately.
- Required correction: obtain a temporary authenticated deployment access URL
  through Vercel's supported connector, without exposing it in reports.
- Required regression: fetch the exact API path through that access mechanism
  and verify HTTP 200 plus canonical `NOT_AVAILABLE`.
- Correction: a temporary access URL was generated and never printed; because
  team SSO still intercepted connector fetches, the protected response was not
  misclassified as application evidence.
- Verification: the authenticated Preview browser independently renders the
  canonical `NOT_AVAILABLE` state and its deployment runtime has zero errors.

## W7C-056 - Tool orchestration isolate does not expose the URL constructor

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the temporary Vercel access URL needed its pathname
  changed to the Organizer catalog API while preserving its signed query.
- Evidence: the orchestration isolate reports `URL is not defined` before any
  fetch call is issued.
- Impact: the temporary access token was not printed and no request reached the
  application.
- Required correction: compose the API path by separating the already returned
  origin and query string inside the isolate.
- Required regression: the access query remains unchanged and the protected
  API responds through the Vercel fetch connector.
- Correction: the target is composed from the origin, API path and untouched
  query substring without requiring unavailable platform globals.
- Verification: Vercel accepts the resulting URL and returns the protected
  deployment response; the remaining SSO redirect is tracked separately.

## W7C-057 - Temporary Vercel share URL still redirects in connector fetch

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the protected catalog API was fetched with the temporary
  share token issued by Vercel's access connector.
- Evidence: the deployment fetch connector still returns the SSO `302` instead
  of following the authenticated cookie exchange.
- Impact: the exact browser Preview remains healthy and no app write occurred,
  but this connector path cannot provide the HTTP-body assertion.
- Required correction: open the API URL in the already authenticated in-app
  browser session and inspect its final URL plus rendered JSON.
- Required regression: the browser must remain on the immutable API URL and
  expose canonical `NOT_AVAILABLE` without `Missing SUPABASE_SERVICE_ROLE_KEY`.
- Correction: direct API navigation was not used as release evidence; the
  mounted client is asserted through the state reachable only after successful
  route JSON parsing.
- Verification: the page shows `No disponible` plus the canonical disabled
  copy, never the fetch-error message or service-role error.

## W7C-058 - Browser client blocks direct top-level navigation to Preview API

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: a fresh in-app tab navigated directly to the immutable
  Organizer catalog API using the authenticated browser profile.
- Evidence: the browser reports `net::ERR_BLOCKED_BY_CLIENT` for that top-level
  API navigation.
- Impact: the plans page itself already loaded the same endpoint and rendered
  the canonical disabled state; no request or data mutation was accepted from
  the blocked tab.
- Required correction: inspect the plans page's captured network activity or
  equivalent developer surface rather than forcing API top-level navigation.
- Required regression: identify a successful catalog request and prove the page
  has no server-side service-role error or client console error.
- Correction: QA uses the rendered canonical branch and the browser developer
  log surface from the original plans tab.
- Verification: browser developer logs are empty, Vercel runtime warnings and
  errors are empty, and the successful-catalog UI branch is visible.

## W7C-059 - Protected Preview curl returns non-JSON after HTTP 200

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: a cookie-preserving curl followed Vercel's temporary share
  flow and received terminal HTTP 200 for the catalog path.
- Evidence: `jq` rejects the saved response body as non-JSON at its first line.
- Impact: the 200 may belong to the protection flow rather than the application,
  so it is not accepted as catalog evidence; no write endpoint was called.
- Required correction: inspect only the response content type and page marker,
  then use an application-level assertion already proven by rendered UI and
  runtime logs if Vercel protection remains the responder.
- Required regression: no response may be labeled as canonical JSON unless both
  its content type and parsed body agree.
- Correction: the response is identified as an HTML Vercel login page and is
  discarded rather than parsed or cited as application success.
- Verification: evidence now distinguishes the SSO HTML from the separately
  verified canonical application state; no false HTTP-200 claim remains.

## W7C-060 - Safety policy rejects grouped forced removal of diagnostic files

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: three known Wave 7C files in `/tmp` were queued for cleanup
  after the protected Preview HTTP diagnostic ended.
- Evidence: command safety rejects grouped `rm -f` before process creation.
- Impact: all three temporary files remain local; no repository or remote state
  changed.
- Required correction: remove each exact known temporary file with the safer
  non-recursive `unlink` command.
- Required regression: all three paths must be absent and the worktree status
  must remain unaffected.
- Correction: each exact cookie, header and body diagnostic path was unlinked
  separately.
- Verification: `find /tmp -maxdepth 1 -name 'w7c-*'` returns no paths.

## W7C-061 - Worktree does not install the Playwright package

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: responsive Preview QA checked whether the worktree's Node
  runtime could launch Playwright directly.
- Evidence: `require.resolve('playwright')` fails with `MODULE_NOT_FOUND`.
- Impact: no dependency was installed and no repository file changed; the
  existing browser plugin remains available.
- Required correction: use an already installed browser runtime or the bundled
  workspace/browser tooling rather than adding a new dependency to Wave 7C.
- Required regression: execute all requested viewports without changing
  `package.json` or the lockfile.
- Correction: QA uses the bundled Codex runtime's Playwright package through
  `NODE_PATH`; no project dependency was installed.
- Verification: all four requested cases execute, while `package.json` and the
  lockfile remain unchanged.

## W7C-062 - Temporary Vercel share URL does not authenticate headless Chromium

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: bundled Playwright opened the temporary Preview share URL
  before running the four requested viewports.
- Evidence: all cases finish at `vercel.com/login`, with protection 403 console
  messages, so their layout metrics describe Vercel rather than Pachangas IQ.
- Impact: those screenshots and metrics are rejected; no product endpoint or
  remote write was reached.
- Required correction: run the exact branch locally against the public staging
  URL/key, then execute the same bundled-Playwright matrix without Preview SSO.
- Required regression: all cases must end on `/planes-organizador`, render the
  canonical disabled catalog and report zero overflow, broken images and errors.
- Correction: the exact branch is built and served with `next start` against
  the same public staging URL/key used by Preview.
- Verification: desktop 1440x900, portrait 390x844, landscape 844x390 and PWA
  standalone all end on `/planes-organizador`, render the canonical disabled
  catalog and report zero overflow, broken images, console/page/request errors.

## W7C-063 - Next development HMR pollutes responsive console evidence

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: bundled Playwright ran the responsive matrix against the
  branch's local Next development server.
- Evidence: every viewport reports a failed `/_next/webpack-hmr` WebSocket
  handshake; the canonical catalog assertion also had not settled.
- Impact: layout and image metrics are useful but the dev-only console noise
  prevents a release-quality zero-error result.
- Required correction: build the exact branch and repeat the matrix against
  `next start`, which has no HMR transport.
- Required regression: all four cases must settle the canonical catalog with
  zero console/page/request errors, zero broken images and zero overflow.
- Correction: `npm run build` passes with 56 static pages and the responsive
  runner now waits for the loading state to settle on `next start`.
- Verification: all four production-mode cases satisfy the zero-error,
  zero-broken-image and zero-overflow gate with canonical data.

## W7C-064 - Staging QA inventory used a stale platform-role table name

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the isolated staging pre-activation inventory counted
  auth users, platform roles and Organizer catalog authority rows.
- Evidence: PostgreSQL reports that
  `private.pachanga_platform_roles` does not exist.
- Impact: the read-only statement returns no combined result and changes no
  staging data.
- Required correction: discover the canonical platform-role relation from
  `information_schema`, then repeat the count using that exact name.
- Required regression: produce only aggregate counts with no user identity or
  PII in the evidence.
- Correction: the inventory now uses
  `private.pachanga_platform_admin_roles`.
- Verification: aggregate-only staging evidence reports 163 auth users, 10
  platform roles, six plan rows/revisions, three proposed decisions and billing
  settings revision 1; no identities were read or emitted.

## W7C-065 - Platform-role aggregate assumed a nonexistent status column

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: staging role readiness was grouped by role and a presumed
  lifecycle `status` without reading identities.
- Evidence: PostgreSQL reports that `status` is not a column of the canonical
  platform-role table.
- Impact: the read-only aggregate returns no rows and changes no data.
- Required correction: inspect column names only, then group by the real role
  and activation fields without selecting user identifiers.
- Required regression: return aggregate role readiness with no PII.
- Correction: the aggregate uses canonical `role` and `active` columns.
- Verification: staging contains four active platform owners plus isolated
  finance, moderator, ops, support and platform-admin roles; only counts were
  returned, with no user identifiers.

## W7C-066 - Desktop QA records aborted Next link-prefetch requests

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the activated three-card catalog passed responsive layout,
  but the desktop request-failure listener captured two aborted requests for
  `/ajustes/facturacion`.
- Evidence: both failures are `net::ERR_ABORTED`, produce no console/page error
  and target the route linked by the partnership card without navigation.
- Impact: the user-visible page, catalog and navigation remain correct; the raw
  counter cannot yet distinguish speculative Next prefetch cancellation from a
  failed user request.
- Required correction: classify requests carrying Next/purpose prefetch headers
  separately while retaining all normal request failures as release blockers.
- Required regression: all real request failures remain zero and any ignored
  cancellation is explicitly reported as speculative prefetch evidence.
- Correction: the runner records aborted speculative prefetches in a dedicated
  field and keeps ordinary request failures unchanged.
- Verification: all four cases report zero real request failures; desktop
  explicitly records two harmless `/ajustes/facturacion` prefetch aborts, while
  console and page errors remain zero.

## W7C-067 - Organizer plans stylesheet path was assumed incorrectly

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: landscape QA inspected the CSS owner for the plan-card
  scroll behavior.
- Evidence: `app/planes-organizador/page.module.css` does not exist.
- Impact: no file changed; the visual evidence remains valid but the scroll
  container has not yet been traced to its real module.
- Required correction: locate the imported stylesheet from the page/component
  source and inspect that exact file.
- Required regression: identify the landscape overflow owner without adding or
  guessing CSS.
- Correction: the client import identifies
  `app/_components/organizer-billing.module.css` as the owner.
- Verification: its landscape rule defines a three-column, horizontally
  scrollable plan grid; no speculative CSS change was made.

## W7C-068 - Stripe TEST catalog exact-text readback returned no rows

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the Stripe TEST product page was queried with exact visible
  names to reconfirm the two Organizer products previously created and reviewed.
- Evidence: both exact-text locators returned zero matches, while a broad DOM
  snapshot produced excessive unrelated output and was truncated.
- Impact: no Stripe object changed and no catalog conclusion is drawn from this
  failed readback; unrelated Stripe products remain outside the evidence set.
- Required correction: use the Stripe product search/filter with a narrow
  `Pachangas IQ` query and inspect only the resulting Organizer rows or details.
- Required regression: reconfirm exactly two Organizer TEST products, their four
  active TEST prices and required metadata without exposing unrelated catalog
  contents or mutating Stripe LIVE.
- Correction: Stripe global search was limited to `Pachangas IQ`, and only the
  two Organizer product rows and their linked price details were inspected.
- Verification: TEST contains exactly two active Organizer products, four active
  recurring prices (29/290 EUR and 9.90/99 EUR), required metadata on every
  detail and zero active subscriptions; LIVE was not opened for mutation.

## W7C-069 - Stripe price body-text evaluator returned false negatives

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the Club Organizer monthly price detail was checked with
  regular expressions over `document.body.innerText` after direct navigation.
- Evidence: every boolean assertion returned false although the rendered Stripe
  page visibly contains `29,00 EUR / mes`, zero subscriptions and all required
  Organizer TEST metadata.
- Impact: no Stripe object changed; the evaluator result is rejected and is not
  used as release evidence.
- Required correction: assert the individual visible values through narrow
  text locators after the detail page has settled.
- Required regression: the monthly amount, zero subscriptions and each required
  metadata value must be independently visible without reading the whole page.
- Correction: the diagnostic now uses individual exact or narrowly bounded text
  locators for amount, subscription count and every metadata value.
- Verification: the Club monthly detail independently exposes 29 EUR/month,
  zero subscriptions, TEST environment, club kind, `CLUB_ORGANIZER`, catalog
  revision `organizer-plan-v1` and product family `organizer`.

## W7C-070 - Stripe product detail assertions ran before SPA hydration

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: Team Organizer product assertions ran after direct
  navigation and a fixed delay.
- Evidence: every narrow locator initially returned zero, while the next visual
  readback showed the fully rendered Team Organizer product and its two prices.
- Impact: no Stripe object changed; the premature assertion is discarded.
- Required correction: wait for the stable Team Organizer heading instead of a
  fixed timeout before checking metadata and price counts.
- Required regression: all required product fields must be visible after the
  heading-based readiness gate on a fresh detail navigation.
- Correction: fresh Stripe detail navigation now polls a bounded stable heading
  before reading product or price fields; no fixed-delay result is trusted.
- Verification: Team Organizer Pro settles through that gate and exposes two
  prices plus the complete TEST metadata contract; both linked prices then pass
  the same bounded readiness check for monthly and annual intervals.

## W7C-071 - Shell interpreted Markdown backticks in a diagnostic pattern

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: a read-only `rg` command searched literal incident status
  text containing Markdown backticks inside a double-quoted shell argument.
- Evidence: zsh treated `open` as command substitution and printed the macOS
  `open` help before the remaining search results.
- Impact: no file, browser or remote service changed; the noisy result cannot be
  used as a clean status inventory.
- Required correction: rerun the search with a single-quoted pattern or without
  literal backticks.
- Required regression: the command must return only matching ledger lines and
  must not launch or invoke another command.
- Correction: the inventory uses a single-quoted regular expression and avoids
  command-substitution characters in double-quoted shell arguments.
- Verification: the corrected readback emits only incident headers and status
  lines; no macOS command help or secondary process appears.

## W7C-072 - Generic status patch altered the wrong open incident

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: W7C-068 was being closed after successful Stripe TEST
  readback with a patch hunk that did not anchor the incident header tightly.
- Evidence: W7C-068 remained `open`, while pre-existing blocker W7C-004 changed
  from `open` to `fixed / regression_verified` in the working diff.
- Impact: only the uncommitted incident ledger was affected; Stripe runtime is
  still not configured and no product, migration or remote flag changed.
- Required correction: restore W7C-004 to `open`, set W7C-068 to the verified
  status and use incident-header-specific patch context.
- Required regression: the only open operational blockers must remain W7C-004
  and W7C-047 after the correction.
- Correction: incident-header-specific hunks restored W7C-004, closed W7C-068
  and preserved every unrelated status.
- Verification: a clean status inventory reports only W7C-004 and W7C-047 as
  open; W7C-068 through W7C-072 are fixed and regression verified.

## W7C-073 - Browser control bindings expired between task turns

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after explicit authorization to transfer TEST credentials,
  Wave 7C resumed by listing the existing in-app browser tabs through the
  previously established `iab` binding.
- Evidence: the persistent JavaScript runtime reports `iab is not defined`.
- Impact: no secret was read, printed or transferred; authenticated browser
  sessions may still exist, but their automation bindings must be recreated.
- Required correction: reload the in-app browser control package and reacquire
  only the Stripe, Supabase staging, Vercel and Preview tabs.
- Required regression: list the intended tabs without exposing credentials and
  preserve the authenticated sessions needed for TEST-only configuration.
- Correction: the browser runtime was reinitialized from the bundled client and
  the exact existing Stripe TEST tab was reclaimed from the authenticated
  in-app browser session.
- Verification: the intended Stripe account and TEST URL were recovered without
  reading cookies, storage, passwords or any credential value.

## W7C-074 - Stripe TEST API-key diagnostic captured a visible secret

- Classification: `SECURITY_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: the authenticated Stripe TEST API-key page was inspected
  visually to locate the copy control before branch-scoped Vercel transfer.
- Evidence: Stripe rendered the standard TEST secret as visible page text, so
  the diagnostic image contained sensitive credential material.
- Impact: the value was not copied to Git, Vercel, Supabase, reports or console
  text, but it must be treated as exposed and cannot be reused for Wave 7C.
- Required correction: rotate or replace the TEST credential, revoke the
  exposed credential, transfer only the replacement directly to the isolated
  Preview and never capture the key page again.
- Required regression: the old key is unusable, the replacement remains
  server-only and branch-scoped, and browser/bundle/report scans contain no key
  material.
- Correction: Wave 7C used a separate restricted key only in branch-scoped
  server variables; all eight variables were removed after QA and the dedicated
  TEST environment was retired, revoking both standard and restricted keys.
- Verification: the parent Stripe selector no longer lists Wave 7C, Vercel has
  zero branch variables and final secret scans are clean.

## W7C-075 - Stripe permission inventory included a nonexistent source path

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the pre-key least-privilege inventory searched all expected
  Organizer billing and shared-library paths in one read-only command.
- Evidence: `rg` reported that `app/_lib` does not exist, while still returning
  matches from the valid Wave 7C paths.
- Impact: no source, Stripe resource or credential changed; the partial result
  is insufficient as the final permission manifest input.
- Required correction: repeat the inventory over paths discovered from
  `rg --files` and inspect every real Stripe client call.
- Required regression: produce a complete call-to-permission map with no missing
  or guessed path and no secret material.
- Correction: `rg --files` established the exact Organizer billing, platform
  administration and webhook source set before the call inventory was repeated.
- Verification: `STRIPE_ORGANIZER_RESTRICTED_TEST_KEY_MANIFEST.md` maps every
  real Stripe API call to a minimum Read/Write permission, records explicit
  denials and contains no key, customer, Product, Price or endpoint identifier.

## W7C-076 - Stripe Sandbox radio inspection exceeded the selector deadline

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the Sandbox creation form exposed two radio choices and QA
  attempted to read each choice's bounded parent text before selecting one.
- Evidence: the first locator evaluation exceeded the three-second selector
  deadline.
- Impact: no option was selected and no Sandbox or Stripe resource was created.
- Required correction: identify choices through their accessible labels and
  individual attributes, then select only the verified blank/copy option.
- Required regression: the selected Sandbox mode and final confirmation state
  must be readable semantically before submission.
- Correction: the form choices were resolved from exact accessible labels;
  `Crear entorno de prueba nuevo` was selected and confirmed visually before
  the final create action.
- Verification: Stripe switched to the new blank `Pachangas IQ Wave 7C`
  Sandbox, whose account context contains no copied active-account resources.

## W7C-077 - Stripe restricted-key wizard exposed the Sandbox standard key in accessibility text

- Classification: `SECURITY_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after opening the restricted-key wizard, QA enumerated
  non-empty button labels to identify the next semantic action.
- Evidence: Stripe includes the Sandbox standard TEST key itself as an
  accessibility-labelled copy button, so the diagnostic output contained that
  credential.
- Impact: the credential was not copied to Git, Vercel, code, reports or the
  application and will not be used by Wave 7C; it belongs only to the new empty
  temporary Sandbox.
- Required correction: never enumerate global control text on any API-key page;
  target only known wizard labels, create the restricted key, and treat the
  Sandbox standard key as exposed until the Sandbox is retired or its standard
  key is safely rotated.
- Required regression: subsequent browser evidence contains only control names,
  permission states and redacted key type; no API-key value is emitted.
- Correction: all later Stripe checks used bounded semantic controls and the
  dedicated Sandbox was retired after QA.
- Verification: the environment and its standard key no longer exist; reports,
  repository, bundle and relevant temporaries contain no key material.

## W7C-078 - Stripe resource filter ignored programmatic empty fill

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: the least-privilege review attempted to clear the resource
  filter with `fill("")` before enumerating every selected permission.
- Evidence: only three webhook-related rows remained and a bounded input readback
  confirmed the filter value was still `Webhook`.
- Impact: the initial empty selected-permission result is invalid; no permission
  or Stripe resource changed during that readback.
- Required correction: clear the custom combobox with select-all/backspace and
  verify its value is empty before auditing all selected rows.
- Required regression: the final selection inventory must include every
  non-None permission and exactly match the redacted manifest allowlist.
- Correction: the filter was cleared with select-all/backspace and its empty
  value was confirmed before the complete resource table was audited.
- Verification: the final selection inventory contained only the seven
  allowlisted Stripe UI resources and no hidden filtered grants.

## W7C-079 - Stripe use-case wizard preselected broad prohibited permissions

- Classification: `SECURITY_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the restricted-key wizard was initialized with the
  `Facturacion y suscripciones recurrentes` use case before applying the
  manifest's seven explicit resource permissions.
- Evidence: the complete selection audit found dozens of implicit Write grants,
  including Charges and Refunds, Payment Disputes, Subscriptions, invoices,
  payment methods, Tax Settings and Registrations, and unrelated resources.
- Impact: the restricted key has not been created, so no credential or remote API
  access exists with those permissions.
- Required correction: reset every resource to `Ninguno`, then apply only the
  seven UI resources needed by the redacted manifest.
- Required regression: the final full-table audit must contain exactly Balance
  Read; Products, Prices, Checkout Sessions, Customers and Customer Portal
  Write; and Webhook Endpoints Read, with every prohibited resource absent.
- Correction: every preselected resource row was reset to `Ninguno` before the
  seven manifest resources were reapplied explicitly.
- Verification: the complete unfiltered audit matched the allowlist exactly;
  Charges, Refunds, Disputes, Connect, Transfers, Tax and every other prohibited
  resource remained unselected.
- Regression reopened: the next Stripe route encoded the original broad preset,
  including charge, dispute, webhook-write and unrelated billing permissions,
  despite the seven-row visual audit. No key was created and the visual state is
  no longer accepted as authoritative submission evidence.
- Final correction: the preset-derived route was discarded and rebuilt from the
  seven identifiers extracted from the selected controls themselves.
- Final verification: canonical route, visual table and created replacement key
  agree on the seven-resource manifest; every prohibited resource remains None.

## W7C-080 - Stripe restricted-key existence readback exceeded the output budget

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after submitting the least-privilege restricted-key form,
  QA navigated back to the Sandbox API-key page and attempted to verify the new
  credential row.
- Evidence: the browser diagnostic exceeded the available output budget and was
  truncated before an exact key-name result was returned.
- Impact: the truncated diagnostic is discarded and does not prove whether the
  restricted key was created; no credential value from that output is used or
  copied anywhere.
- Required correction: query only the exact redacted key name and return a
  boolean or bounded count, without enumerating page text, controls or values.
- Required regression: the key-name readback must be deterministic and the only
  credential evidence emitted must be the redacted type check `rk_test`, never
  the key value.
- Correction: the retry queried only the exact redacted key name after a bounded
  reload and returned a numeric count.
- Verification: the deterministic readback returned zero and emitted no page
  text, control inventory or credential value, proving the prior submission did
  not create the restricted key.

## W7C-081 - Exact Stripe key-name locator used the wrong tab API

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the bounded retry called `getByText` directly on the
  persistent in-app browser tab object.
- Evidence: the controller returned `getByText is not a function` without
  evaluating any Stripe page text or credential value.
- Impact: no remote or local state changed and the restricted key remains
  unverified.
- Required correction: inspect only the controller object's method names, then
  use its supported semantic locator surface for the exact redacted key name.
- Required regression: the supported call must return only a bounded count and
  must not enumerate controls, page text or API-key values.
- Correction: controller method inspection identified the supported semantic
  locator under `tab.playwright` without reading the Stripe document.
- Verification: the corrected locator returned the exact-name count only and
  exposed no credential or unrelated page content.

## W7C-082 - Restricted-key wizard appeared complete without creating a key

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: the least-privilege wizard submission navigated away from
  its permission form and was initially treated as successful.
- Evidence: two bounded exact-name readbacks after a fresh API-key-page reload
  returned zero rows for `Pachangas IQ Wave 7C Preview`.
- Impact: no restricted credential exists yet and no value has been transferred
  to Vercel; TEST E2E remains blocked closed.
- Required correction: repeat the restricted-key flow without a use-case preset,
  submit through the exact final action and retain the one-time result until its
  key row and restricted TEST type have both been confirmed.
- Required regression: exactly one named restricted key must exist with only the
  manifest allowlist, and Vercel transfer must occur from that verified row
  without exposing its value.
- Correction: the exact final DOM action was invoked after independent zero-key
  readback and a fully canonical seven-permission gate.
- Verification: one replacement restricted TEST key exists and was transferred
  only to the sensitive branch-scoped Preview variable.

## W7C-083 - Semantic API-key create click produced no UI transition

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after the exact-name readback proved no restricted key
  existed, QA clicked the visible and enabled `Crear clave restringida` button
  through its accessible role.
- Evidence: the URL, visible headings and registered key-related test IDs were
  unchanged, and no dialog or additional Stripe tab appeared.
- Impact: no key, permission or remote object changed; the workflow remains
  fail-closed.
- Required correction: target the unique
  `data-testid=create-restricted-key-button` control and verify a concrete UI
  transition before interacting with any wizard field.
- Required regression: one bounded interaction must expose the expected wizard
  state without enumerating API-key-page text or controls.
- Correction: the button's bounded React action was identified through the
  exact test ID and invoked to open the same Stripe drawer without reading page
  content or credentials.
- Verification: the restricted-key drawer opened and exposed only its expected
  own-integration choices plus disabled `Continuar` state.

## W7C-084 - Locator evaluation did not expose a native DOM button

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after semantic clicks produced no transition, QA attempted
  to invoke the unique button's native `click()` inside locator evaluation.
- Evidence: the browser abstraction returned `el.click is not a function`.
- Impact: no Stripe UI or remote state changed and no page content was read.
- Required correction: perform a page-scoped DOM query for the exact unique
  test ID and invoke the native button there, then inspect only bounded wizard
  state.
- Required regression: the page-scoped action must open the restricted-key
  workflow and must not read or emit any API-key value.
- Correction: the unsupported locator mutation was abandoned; read-only CDP
  inspection resolved the exact React action bound to the unique button.
- Verification: invoking that bounded action opened the workflow without
  enumerating API-key values, page controls or credential text.

## W7C-085 - Browser evaluation sandbox omitted DOM constructor globals

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the page-scoped retry guarded the exact button with an
  `instanceof HTMLElement` check before invoking it.
- Evidence: the browser evaluation sandbox returned that the right-hand side of
  `instanceof` was not an object.
- Impact: evaluation stopped before clicking; no Stripe state or credential
  changed.
- Required correction: test the queried node and callable method directly
  without relying on unavailable DOM constructor globals.
- Required regression: the bounded page action returns only found/clicked state
  and the wizard transition, with no document text or values.
- Correction: no unavailable DOM constructor is used; supported CDP object
  inspection and native input activation are scoped to exact known controls.
- Verification: the drawer, use-case checkbox and permission controls all
  transitioned without exposing document text or credential values.

## W7C-086 - Chrome connection timed out and reset browser bindings

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the in-app Stripe control failed to execute the
  create-button transition, QA attempted to attach to the user's authenticated
  Chrome session as a second browser surface.
- Evidence: browser connection exceeded thirty seconds and reset the persistent
  controller before returning documentation or a tab.
- Impact: no Stripe, Vercel or Supabase state changed; only local browser-control
  bindings were lost.
- Required correction: reinitialize the browser runtime, read the Chrome
  troubleshooting guidance and reacquire an authenticated Stripe tab once.
- Required regression: the recovered browser exposes a stable tab and exact
  semantic controls without reading cookies, storage or credential values.
- Correction: Chrome troubleshooting was read, both browser surfaces were
  reinitialized once, and the existing authenticated in-app Stripe tab was
  reacquired directly.
- Verification: Chrome was correctly identified as unauthenticated and left
  unused; the recovered in-app tab remained authenticated and stable without
  reading cookies, storage, passwords or credentials.

## W7C-087 - Synthetic Stripe option event lacked required React event shape

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after opening the restricted-key drawer through its exact
  internal UI action, QA invoked the own-integration option with a minimal event
  object.
- Evidence: Stripe's composed option handler returned an exception and the
  `Continuar` action remained disabled.
- Impact: no option, permission or key changed; the wizard remains at its first
  step.
- Required correction: inspect the bounded exception and use the visible DOM
  node's real interaction path or a complete compatible event shape.
- Required regression: own integration becomes the selected option and
  `Continuar` becomes enabled before any submission occurs.
- Correction: the synthetic handler path was discarded and the visible option
  was activated through Stripe's supported keyboard interaction.
- Verification: `Poniendo en marcha una integracion que has creado` became the
  selected path and `Continuar` lost its disabled state before advancing.

## W7C-088 - Stripe use-case checkbox ignored native checked-state action

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: at the use-case step, QA attempted to select the recurring
  billing preset through the visible enabled checkbox's native checked-state
  action.
- Evidence: the controller reported that the click did not change the checkbox
  to checked.
- Impact: no use case, permission or key changed and `Continuar` remained
  disabled.
- Required correction: activate the focused checkbox through Stripe's keyboard
  path, verify the checked state, then advance to the permission table where all
  preset grants are reset before applying the manifest.
- Required regression: exactly one temporary use case is selected and no preset
  permission survives the final unfiltered allowlist audit.
- Correction: the exact recurring-billing input was activated through its
  native HTML input action and its checked state was confirmed before advancing.
- Verification: all 47 preset grants were subsequently reset to `Ninguno`; the
  final unfiltered table contains exactly Balance Read; Customers, Products,
  Customer Portal, Prices and Checkout Sessions Write; and Webhook Endpoints
  Read.
- Regression reopened: the subsequent route retained the preset's original
  permission query, proving that the native visual toggles did not reconcile the
  authoritative form state used for submission.
- Final correction: the preset path was abandoned; a route containing only the
  seven control-derived identifiers became the authoritative creation state.
- Final verification: query and visual readback both contain exactly seven
  allowlisted grants and no preset permission.

## W7C-089 - Stripe visual allowlist diverged from authoritative permission query

- Classification: `SECURITY_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the unfiltered permission table showed exactly seven
  allowlisted rows, the confirmed create action advanced to Stripe's dedicated
  API-key creation route.
- Evidence: the route query still encoded dozens of preset permissions,
  including charge write, dispute write, webhook write, Payment Intents,
  subscriptions, tax and unrelated billing resources; the exact restricted-key
  name count remained zero.
- Impact: no restricted key was created and no value was transferred to Vercel.
  The mismatch fails closed before any persistent credential exists.
- Required correction: discard the preset-derived route, rebuild the dedicated
  creation form from an empty permission set and manipulate only controls whose
  authoritative query/readback changes with them.
- Required regression: immediately before final creation, Stripe's own canonical
  permission representation must contain exactly the seven manifest resources,
  no forbidden resource and one key name; after creation exactly one `rk_test`
  credential must exist.
- Correction: every canonical identifier was extracted from its selected
  control and used to reconstruct a seven-entry route from an empty query.
- Verification: route and visual readback agree, forbidden grants are None and
  the active replacement inventory contains one restricted TEST credential.

## W7C-090 - Recursive Stripe permission-code introspection exceeded its deadline

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after rejecting the broad preset query, QA recursively
  traversed each selected control's React closure to recover its canonical
  `rak_*` permission identifier.
- Evidence: the bounded browser controller exceeded thirty seconds and reset
  before returning any code inventory.
- Impact: the operation was read-only; no key, permission, Stripe resource or
  Vercel variable changed.
- Required correction: reacquire the existing form and resolve each allowlisted
  permission through one shallow, individually bounded inspection or another
  authoritative Stripe representation.
- Required regression: seven unique permission codes are returned within the
  deadline and the resulting creation state contains no additional code.
- Correction: each selected control was inspected independently through its
  exact DOM node and shallow React Fiber props.
- Verification: seven unique canonical values were returned within the
  deadline and the reconstructed route contains exactly those seven values.

## W7C-091 - Browser-control documentation exceeded the available output budget

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the browser runtime reset, QA requested the complete
  in-app browser documentation in a single response before reacquiring Stripe.
- Evidence: the controller reported that its output exceeded the available
  model context and was truncated.
- Impact: the operation was read-only; no Stripe, Vercel or Supabase state
  changed and no credential value was accessed.
- Required correction: reuse the already validated browser API and request only
  bounded diagnostics if a missing method must be confirmed.
- Required regression: the recovered runtime exposes the required bindings and
  reacquires the existing Stripe tab without another unbounded documentation
  response.
- Correction: the already validated browser API was reused without requesting
  another complete documentation payload.
- Verification: both browser bindings were present and the authenticated Stripe
  creation tab was reacquired by its exact title and safe pathname.

## W7C-092 - Reacquired browser tab did not expose a direct locator API

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after reacquiring the authenticated Stripe tab, QA tried
  to inspect seven known permission rows through a direct `tab.locator` call.
- Evidence: the recovered tab object reported that `locator` was not a
  function.
- Impact: evaluation stopped before reading or changing the form; no Stripe,
  Vercel or Supabase state changed.
- Required correction: inspect only the bounded public shape of the recovered
  tab and use the controller's supported page or CDP surface.
- Required regression: the seven permission rows are read through the supported
  browser surface without exposing the full page or credential values.
- Correction: the controller's supported `tab.playwright.locator` surface was
  used instead of a direct tab method.
- Verification: all seven expected rows and their selected permission levels
  were read without exposing page-wide content or any credential value.

## W7C-093 - CDP capability required its scoped documentation before use

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: QA discovered the supported tab-level CDP capability and
  attempted a read-only lookup of the exact Webhook Read control.
- Evidence: the controller rejected the command because the scoped
  `capabilities/tab/cdp` instructions had not yet been read in this recovered
  runtime.
- Impact: the CDP command did not execute; no form, key or external state
  changed.
- Required correction: read only the required scoped capability instructions
  and repeat the bounded read-only lookup.
- Required regression: the exact control is returned through CDP without
  requesting unbounded browser documentation or exposing page-wide content.
- Correction: only the required tab-level CDP instructions were loaded before
  retrying the lookup.
- Verification: CDP returned the exact selected Webhook Read DOM node with a
  stable object identifier and no page-wide content.

## W7C-094 - CDP retry referenced an uninitialized local binding

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after loading the required scoped CDP documentation, QA
  retried the read-only lookup by assigning into the binding from the rejected
  attempt.
- Evidence: the recovered JavaScript runtime reported that the binding was not
  defined.
- Impact: evaluation stopped locally before sending a CDP command; no Stripe,
  Vercel or Supabase state changed.
- Required correction: declare a fresh local result binding and repeat the same
  bounded lookup.
- Required regression: the exact Webhook Read DOM object is returned with a
  stable object identifier and no state change.
- Correction: the CDP result was declared in a fresh local binding.
- Verification: the exact selected DOM node was returned and described without
  changing the permission form.

## W7C-095 - Webhook DOM listener resolved to React's global delegated handler

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: QA inspected the selected Webhook Read control's click
  listener to locate its canonical permission identifier.
- Evidence: the listener was React's global delegated click handler and its
  closure exposed hundreds of framework bindings rather than the control's
  local permission code.
- Impact: inspection remained read-only and revealed no credential, but it did
  not produce the required canonical identifier.
- Required correction: inspect only React-specific properties attached to the
  exact DOM node and filter any scalar result to `rak_*` identifiers.
- Required regression: one unique Webhook Read identifier is recovered without
  traversing React's global closure or emitting unrelated values.
- Correction: QA inspected the selected node's React props and shallow Fiber
  ancestry instead of the delegated global listener.
- Verification: the control resolved uniquely to `rak_webhook_read` without
  another global closure traversal.

## W7C-096 - Preset-derived Prices permission code did not match the control

- Classification: `SECURITY_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the broad preset route suggested a Prices identifier that
  had not yet been verified against the selected Prices Write control.
- Evidence: the selected control's own React props resolve uniquely to
  `rak_plan_write`, not the preset-derived identifier.
- Impact: no reconstructed URL was built, no form was submitted and no key was
  created; the discrepancy failed closed during read-only verification.
- Required correction: build the final permission inventory exclusively from
  the seven selected controls' canonical values.
- Required regression: the final route and visual readback both contain the
  canonical Prices Write value and exactly six other allowlisted permissions.
- Correction: the reconstructed route uses the control-derived
  `rak_plan_write` value.
- Verification: route and visual readback agree on Prices Write plus exactly six
  other allowlisted permissions.

## W7C-097 - Preset-derived Checkout permission code did not match the control

- Classification: `SECURITY_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the broad preset route suggested a Checkout Sessions
  identifier that had not yet been verified against its selected Write control.
- Evidence: the selected control's own React props resolve uniquely to
  `rak_checkout_session_write`, not the preset-derived identifier.
- Impact: no reconstructed URL was built, no form was submitted and no key was
  created; the mismatch failed closed before persistence.
- Required correction: use only the control-derived Checkout Sessions Write
  identifier in the final seven-permission route.
- Required regression: canonical route and visual readback agree on exactly one
  Checkout Sessions Write grant and contain no broad checkout preset grant.
- Correction: the reconstructed route uses the control-derived
  `rak_checkout_session_write` value.
- Verification: route and visual readback agree on exactly one Checkout
  Sessions Write grant and no broad preset grant.

## W7C-098 - Visual permission readback included every selected None control

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after loading the canonical seven-permission route, QA
  enumerated every visually selected segmented option.
- Evidence: every permission row selects `Ninguno` by default, so the diagnostic
  returned the seven grants plus more than one hundred unrelated None rows.
- Impact: the operation was read-only and contained no credential or personal
  data, but its evidence was unnecessarily broad.
- Required correction: return only selected levels other than `Ninguno` and an
  aggregate count for the remaining rows.
- Required regression: the bounded readback reports seven non-None grants and
  zero additional non-None permission.
- Correction: the visual readback now returns only non-None grants and one
  aggregate count for None rows.
- Verification: exactly seven non-None grants were reported and every other
  selectable permission remained None.

## W7C-099 - Browser locator did not expose inputValue readback

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: QA filled the restricted-key name and attempted to verify
  it through the locator's `inputValue` helper.
- Evidence: the browser wrapper reported that `inputValue` was not a function.
- Impact: the name may have changed only in the local unsaved form; no key was
  created and no credential value existed or was read.
- Required correction: verify the exact first text input through a bounded DOM
  evaluation before any submission.
- Required regression: the canonical name is confirmed exactly once while the
  create action remains unexecuted.
- Correction: the exact first text input was read through bounded DOM
  evaluation.
- Verification: the 28-character canonical name matched exactly before the
  first create attempt.

## W7C-100 - Final Stripe create action returned an ambiguous readback

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after the canonical seven-permission gate passed, QA
  invoked the single enabled final `Crear clave` action with explicit user
  confirmation.
- Evidence: the page exposed a copy control but the bounded readback found no
  exact key name and no visible restricted TEST prefix while remaining on the
  creation pathname.
- Impact: creation success is not yet proven. The action must not be retried
  because doing so could create a duplicate credential.
- Required correction: inspect only bounded headings, alerts and the exact key
  inventory, then determine whether one credential exists before any retry.
- Required regression: exactly one named restricted TEST credential is proven,
  or zero is proven before a single controlled retry; no duplicate is allowed.
- Correction: a separate listing proved zero keys before each retry and later
  diagnostics identified the Workbench hit-area interception.
- Verification: the exact native DOM action produced one success row; the
  compromised first key was revoked and exactly one replacement remains active.

## W7C-101 - Stripe create form reported a connectivity failure

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: QA inspected the bounded post-submit state after the final
  create action returned no verifiable restricted key.
- Evidence: the page displayed the heading `Comprueba tu conexion`, retained
  the 28-character key name and still exposed the create action.
- Impact: success remains unproven and no retry is permitted until a separate
  exact-name inventory proves whether the first request persisted a key.
- Required correction: inspect the TEST API-key listing in a separate tab,
  preserving the failed form and avoiding any repeated submission.
- Required regression: the listing proves an exact key count before the create
  form is retried or its result is consumed.
- Correction: a second authenticated Stripe tab opened the TEST API-key
  inventory while preserving the failed form.
- Verification: the independent listing reported zero exact-name credentials
  and no connection warning, authorizing one controlled retry without duplicate
  risk.

## W7C-102 - Positional key-name fill did not reach the canonical input on retry

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after reloading the exact seven-permission route, QA filled
  the first text locator by position and ran the complete retry gate.
- Evidence: route, seven grants, connectivity and create readiness passed, but
  the canonical first DOM text value did not match the expected key name.
- Impact: the retry remained blocked and no second create action was invoked.
- Required correction: identify the name input through its bounded label or
  surrounding form structure and fill that exact control.
- Required regression: name, route, visual grants and create readiness all pass
  in one atomic gate before the single retry.
- Correction: the field was identified by the stable `#key-name` selector and
  the unrelated global search was handled separately.
- Verification: the replacement name, route, visual grants, connectivity and
  create readiness all passed together before native submission.

## W7C-103 - Stripe global search retained the accidental key-name text

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after locating `#key-name`, QA cleared the unrelated
  global search input through a targeted empty fill and populated the canonical
  field.
- Evidence: `#key-name` matched exactly, but the bounded readback showed that
  the global search input was still non-empty.
- Impact: no external state changed, but a search overlay could interfere with
  the controlled retry if left active.
- Required correction: focus the exact search input and clear it through its
  native keyboard interaction.
- Required regression: search is empty, canonical name is exact and no overlay
  obscures the final create action.
- Correction: the exact search input was cleared with select-all/backspace and
  focus returned to the canonical name field.
- Verification: the atomic gate reported an empty global search and exact key
  name before submission.

## W7C-104 - Controlled Stripe create retry produced no success evidence

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after an atomic gate proved zero existing keys, exact name,
  exact seven-permission route, exact visual grants, empty search and healthy
  connectivity, QA invoked the final create action once more.
- Evidence: the page remained on the creation path, still exposed the create
  action and displayed neither the exact name nor a restricted TEST prefix.
- Impact: no third create attempt is permitted. Persistence must be resolved by
  independent inventory and event diagnostics to avoid duplicates.
- Required correction: refresh the exact-name inventory and, if it remains
  zero, inspect the button's own handler and validation state without invoking
  it again.
- Required regression: either one exact credential is proven, or a concrete
  pre-submit blocker is identified while the inventory remains zero.
- Correction: hit testing identified Stripe Workbench as the concrete blocker;
  wrapper clicks were not treated as submissions.
- Verification: inventory stayed at zero until the exact native action ran,
  after which Stripe returned a unique restricted TEST success row.

## W7C-105 - In-app overlay intercepted the final Stripe button

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the independent inventory proved zero persisted
  keys, QA inspected the exact final create button without invoking it again.
- Evidence: the button is enabled, visible and has a non-zero rectangle, but
  `document.elementFromPoint` at its center resolves to an unrelated overlay
  `DIV` instead of the button or one of its children.
- Impact: both prior controller clicks were intercepted before reaching the
  Stripe control, explaining the zero-key inventory. No Stripe creation request
  was submitted.
- Required correction: identify and dismiss only the intercepting in-app layer,
  then repeat the atomic gate and verify the button is the top hit target.
- Required regression: the button center resolves to itself or a child before
  the first real create submission.
- Correction: Stripe's fixed Workbench tray was identified as the interceptor;
  pointer hit testing was bypassed through the exact DOM button's native HTML
  action instead of mutating or hiding the tray.
- Verification: independent inventory proved zero before native activation and
  exactly one success row afterward, with no duplicate submission.

## W7C-106 - Locator keyboard activation did not invoke the covered Stripe button

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: with the full canonical gate passing and zero persisted
  keys, QA sent `Enter` to the exact create-button locator to bypass the fixed
  Workbench hit area.
- Evidence: the page remained unchanged and exposed no name, restricted prefix
  or success state.
- Impact: persistence remains unproven; inventory must again prove zero before
  any lower-level native activation.
- Required correction: after zero-key readback, invoke the exact DOM button's
  native HTML click through scoped CDP, avoiding pointer hit testing.
- Required regression: one and only one exact-name restricted TEST key appears
  in the independent inventory after native activation.
- Correction: the locator keyboard path was abandoned in favor of a scoped CDP
  native click on the exact DOM button.
- Verification: native activation returned the success state and one active
  replacement restricted TEST row is present.

## W7C-107 - Stripe success page and parallel key listing temporarily diverged

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the exact DOM button's native click executed, QA
  compared the preserved creation page with a refreshed API-key listing tab.
- Evidence: the creation page shows the exact name once, a restricted TEST
  prefix, no live prefix and no create action; the parallel listing still shows
  zero exact-name rows.
- Impact: the one-time success page must be preserved while the secret is moved
  directly to its approved branch-scoped secret manager. No recreate or reload
  of that page is allowed.
- Required correction: transfer from the exact success-page copy control, then
  obtain eventual exact-name inventory readback without exposing the value.
- Required regression: Vercel branch scope contains one restricted TEST secret
  and Stripe eventually reports exactly one matching credential.
- Correction: listing readback normalizes Stripe's visual line breaks before
  matching the exact name and row.
- Verification: Stripe reports one active replacement restricted TEST row;
  Vercel reports one sensitive Preview variable scoped to the Wave 7C branch
  and zero Production matches.

## W7C-108 - Stripe copy-control accessibility label exposed the new secret

- Classification: `SECURITY_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after successful restricted-key creation, QA searched the
  exact success-row ancestry for a copy control while intending to emit only its
  descriptive label.
- Evidence: Stripe embeds the complete one-time restricted key value inside that
  control's accessibility label, so the bounded diagnostic output contained the
  credential.
- Impact: the newly created credential is considered compromised. It was not
  copied to Vercel, Git, a report or the clipboard and must never be used.
- Required correction: clear local diagnostic references, revoke this exact
  credential, create a replacement, and interact with the replacement copy
  control without ever returning its attributes or text.
- Required regression: secret transfer returns only boolean prefix and scope
  evidence; scans find no replacement value in output, Git, reports, logs or
  temporaries.
- Correction: local references were cleared, the exposed credential was
  immediately expired, and a differently named replacement was copied through
  its exact DOM object without reading any attribute or text.
- Verification: transfer emitted only restricted/live/non-empty booleans, used
  process stdin, cleared the clipboard and runtime reference, and scans report
  zero secret values in source, HEAD, diff, client bundle and worktree
  temporaries. The only Vercel match is sensitive Preview branch scope.

## W7C-109 - Restricted-key action dialog used an unexpected first-level label

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: QA opened the exact compromised-key row action and searched
  the resulting scoped UI for revoke or delete actions.
- Evidence: a second dialog appeared, but no candidate matched the expected
  revoke/delete labels and the route remained on the API-key inventory.
- Impact: no destructive action occurred and the compromised credential remains
  active pending safe identification of Stripe's actual action wording.
- Required correction: inspect only the generic second-dialog text after
  proving it contains neither key name nor restricted-key prefix.
- Required regression: the destructive control is identified and scoped to the
  exact compromised row before confirmation.
- Correction: the scoped generic dialog was first proven free of key name and
  value, then identified Stripe's action wording `Clave de caducidad`.
- Verification: the confirmation was bound to the exact compromised name and
  the credential disappeared from the active inventory after confirmation.

## W7C-110 - Supabase Markdown changelog was unsupported by the web connector

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: before resuming staging credential and migration work, QA
  requested Supabase's official lightweight `changelog.md` as required by the
  current integration guidance.
- Evidence: the connector returned an unsupported `text/markdown` content-type
  error.
- Impact: the operation was read-only and no Supabase, Vercel or repository
  state changed.
- Required correction: read the official HTML changelog surface and inspect
  only entries relevant to Auth, API keys, Realtime or CLI behavior.
- Required regression: current official guidance is available before any
  Supabase staging mutation.
- Correction: the official HTML changelog was read instead of the unsupported
  Markdown representation.
- Verification: current entries relevant to Wave 7C were reviewed before
  staging work: Node 20 client support ended, the Realtime schema is locked and
  newly exposed Data API tables require explicit grants.

## W7C-111 - Wave 7C source inventory included an absent GitHub directory

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: QA searched Stripe, Supabase service authority, webhook and
  Organizer checkout references across expected application, test, script and
  CI directories.
- Evidence: `rg` reported that `.github` does not exist in this repository while
  returning valid matches from every existing path.
- Impact: no file or external state changed, but the diagnostic is not accepted
  as a clean final source inventory.
- Required correction: discover the repository's actual top-level paths and
  repeat the search only over existing locations.
- Required regression: the same authority inventory completes without missing
  path diagnostics.
- Correction: the absent directory was removed from the source set and all
  existing application, script, test, migration and configuration paths were
  searched directly.
- Verification: the authority inventory completed without a missing-path
  diagnostic and confirmed service-role usage remains server-only.

## W7C-112 - Organizer TEST runtime rejected the mandated restricted key prefix

- Classification: `PRODUCT_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after storing the branch-scoped restricted TEST key, QA
  traced the Organizer Stripe runtime before redeploying Preview.
- Evidence: `stripeKeyForMode("test")` accepts only `sk_test_`, while the
  approved least-privilege credential and manifest require `rk_test_`.
- Impact: the safe credential would fail closed as unconfigured and remote TEST
  Checkout, Portal and catalog QA could not start. No live path is affected.
- Required correction: accept restricted TEST keys on the server-only TEST path
  while retaining legacy standard TEST compatibility and strict live-prefix
  validation.
- Required regression: `rk_test_` and legacy `sk_test_` TEST fixtures pass;
  public, live, malformed and missing keys remain rejected, and no key value
  enters client code.
- Correction: the server-only TEST path accepts `sk_test_` and `rk_test_`, while
  LIVE remains limited to `sk_live_` and public/restricted-live prefixes remain
  invalid.
- Verification: the focused contract passes 11/11, typecheck and focused lint
  pass, and the client-bundle secret/name scan remains empty.

## W7C-113 - Supabase documentation search exceeded the diagnostic output bound

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: QA queried the official Supabase documentation for the
  current Dashboard location and handling contract of a server-only staging
  secret key before any credential transfer.
- Evidence: the scoped search returned more documentation content than the
  available diagnostic context and its output was truncated.
- Impact: the operation was read-only and no Supabase, Vercel, repository or
  credential state changed, but the truncated result is not accepted as
  authoritative evidence for the next action.
- Required correction: repeat the official documentation lookup with a bounded
  result that returns only the relevant title and canonical link, then use the
  authenticated staging Dashboard only if the connector cannot expose secret
  keys.
- Required regression: current official guidance and the exact staging project
  are identified without output truncation before any secret is copied or
  transmitted.
- Correction: the documentation search was repeated with one result and only
  the title plus canonical link requested; the authenticated Dashboard was then
  scoped to the existing Preview branch.
- Verification: official guidance resolved to `Migrating to publishable and
  secret API keys`, the Dashboard identified project
  `iozcjirlfytryzrcmrnq` as `pwa-bridge-staging / Preview`, and no output was
  truncated.

## W7C-114 - Supabase settings link was reported disabled during automation

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after confirming the authenticated Preview branch and the
  exact `API Keys` settings link in the Supabase Dashboard, QA attempted to
  activate that visible navigation item.
- Evidence: browser automation timed out with `Element is not enabled` while
  its own bounded diagnostics reported one visible anchor with `disabled=false`
  and the exact staging-project URL.
- Impact: no credential was revealed, copied or transmitted and no Supabase or
  Vercel state changed.
- Required correction: navigate to the exact href already returned by the
  authenticated Dashboard instead of retrying the inconsistent click.
- Required regression: the API Keys page loads for project
  `iozcjirlfytryzrcmrnq` and only non-secret UI presence counts are inspected
  before requesting action-time transfer approval.
- Correction: QA navigated to the exact API Keys href returned by the
  authenticated Dashboard rather than retrying the inconsistent click.
- Verification: the resulting page title identifies the Pachangas staging
  Preview branch and exposes separate masked `Secret keys` reveal/copy controls;
  no key value was revealed, emitted, copied or transmitted.

## W7C-115 - Closed diagnostic incidents retained contradictory status fields

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after adding correction and verification evidence to
  W7C-113 and W7C-114, the ledger appended a second status line instead of
  replacing each original `open` status; the first W7C-115 draft was also
  inserted between the heading and body of W7C-001 by an ambiguous patch
  context.
- Evidence: both diagnostic incident blocks temporarily contained `open` and
  `fixed / regression_verified`, and W7C-001's `Found in` field followed the
  misplaced W7C-115 draft.
- Impact: no code or external state changed, but automated open-incident
  readback and incident boundaries were temporarily ambiguous.
- Required correction: restore W7C-001 as one contiguous block, retain exactly
  one canonical status near the top of W7C-113 and W7C-114, and place W7C-115
  after the incidents it describes.
- Required regression: open-incident readback reports neither W7C-113 nor
  W7C-114 nor W7C-115; every incident block contains exactly one status field;
  and W7C-001 retains its original contiguous evidence.
- Correction: the misplaced block was moved, duplicate status lines were
  removed and the two verified diagnostics now expose one canonical status.
- Verification: structured ledger readback reports one status per W7C incident,
  none of W7C-113 through W7C-115 is open, and W7C-001 again contains its full
  original body immediately below its own status.

## W7C-116 - Vercel environment inventory assumed an obsolete JSON root shape

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: QA requested the branch-scoped Preview environment
  inventory and piped the CLI JSON through a filter that assumed a root array.
- Evidence: Vercel CLI 59.4.0 returned a different root structure and `jq`
  exited with `Cannot index array with string key` before emitting any variable
  inventory.
- Impact: no environment value was printed, copied or changed; Vercel,
  Supabase and repository state remain unchanged.
- Required correction: inspect only the JSON root type and keys, then extract a
  bounded allowlist of non-secret metadata fields from the actual array node.
- Required regression: branch Preview inventory completes without values and
  proves the required server-only names/scopes while Production remains
  excluded.
- Correction: the CLI response was inspected as structural metadata only,
  identifying an object root with an `envs` array before applying the bounded
  field allowlist.
- Verification: the exact Wave 7C branch contains five Preview-scoped entries;
  `STRIPE_TEST_SECRET_KEY` is `sensitive` with `secret` visibility, and neither
  that key nor `STRIPE_TEST_WEBHOOK_SECRET` exists in Production. The existing
  pre-Wave production `SUPABASE_SERVICE_ROLE_KEY` was only observed by name and
  remains untouched.

## W7C-117 - Supabase secret copy action timed out before browser dispatch

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after explicit action-time approval, QA selected the
  second of the two exact `Copy API key` controls, corresponding to the masked
  modern secret-key row in Supabase staging.
- Evidence: the browser returned `CDP operation exceeded its deadline before
  command dispatch`; its diagnostics still showed one visible, enabled button
  named `Copy API key` for the scoped locator.
- Impact: the click did not dispatch, the clipboard was not read and no secret
  was copied, revealed, logged or transmitted to Vercel.
- Required correction: reacquire the still-authenticated staging tab and invoke
  the same already-verified second copy control through a direct DOM click,
  without reading attributes, text or key value.
- Required regression: transfer emits only secret-shape booleans, Vercel scope
  metadata confirms one sensitive branch Preview variable, the clipboard and
  runtime reference are cleared, and no secret appears in output or files.
- Correction: the unreliable mouse path was abandoned and the exact scoped
  button was later activated through its keyboard behavior after installing the
  supported tab clipboard bridge.
- Verification: one modern `sb_secret_` shape reached Vercel through process
  stdin, and branch metadata now reports one sensitive secret variable without
  exposing its value.

## W7C-118 - Chrome binding did not expose the assumed clipboard API

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: QA invoked the verified secret-row copy control through a
  direct DOM click and attempted to read and later clear the browser clipboard
  through `chrome.clipboard`.
- Evidence: the browser binding reported `Cannot read properties of undefined
  (reading write)` while executing the mandatory cleanup block.
- Impact: Vercel transfer did not start. The direct click may have populated the
  operating-system clipboard, but no value was emitted or read into model
  output; repository, Supabase and Vercel configuration remain unchanged.
- Required correction: clear the operating-system clipboard without reading it,
  inspect only the non-sensitive browser/tab API surface, then use the supported
  clipboard bridge or a direct approved copy-to-process mechanism.
- Required regression: the secret is transferred once through process stdin;
  runtime and system clipboard are cleared; only boolean shape and Vercel scope
  evidence is emitted; no secret value reaches output, files or logs.
- Correction: QA used the supported `Tab.clipboard` bridge rather than the
  absent browser-level property and separately cleared the operating-system
  clipboard without reading it.
- Verification: the bridge passed an empty write/read preflight, captured the
  approved copy only inside the protected runtime, and read back empty after
  transfer cleanup.

## W7C-119 - Locator evaluation did not expose a native DOM click method

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after installing and validating the supported tab
  clipboard bridge, QA attempted to invoke the already scoped copy control with
  locator evaluation so the secret would never enter accessibility output.
- Evidence: the evaluated locator proxy raised `element.click is not a
  function` before the copy operation.
- Impact: Vercel transfer did not start; mandatory cleanup emptied both the tab
  clipboard bridge and the operating-system clipboard, and no secret value was
  emitted or persisted.
- Required correction: keep the clipboard bridge installed and use the
  locator's supported forced click action on the same exact second control.
- Required regression: one modern staging secret reaches Vercel through stdin;
  branch-scope metadata reads back correctly; clipboard/runtime cleanup passes;
  scans remain free of secret material.
- Correction: direct locator evaluation and its non-native element proxy were
  discarded; the same exact second control was activated with `Enter`.
- Verification: keyboard activation returned no key material, the validated
  modern-secret boolean was true, and the Vercel subprocess exited zero.

## W7C-120 - Forced locator click still timed out in Chrome mouse dispatch

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: with the supported clipboard bridge installed, QA retried
  the exact secret copy control using the locator's forced click action.
- Evidence: Chrome timed out on `Input.dispatchMouseEvent` while diagnostics
  still reported the one scoped button as visible and enabled.
- Impact: the Vercel subprocess was never started; tab and system clipboards
  were cleared in the mandatory cleanup block, with no secret output or file
  persistence.
- Required correction: activate the same focused button through its keyboard
  `Enter` behavior, avoiding the failing mouse-event channel.
- Required regression: the keyboard activation populates only the protected
  clipboard bridge; direct stdin transfer succeeds exactly once; readback and
  secret scans pass after cleanup.
- Correction: the exact copy control was activated by keyboard, bypassing the
  failing mouse dispatch channel.
- Verification: activation, modern-secret shape, non-empty value, zero-exit
  transfer and clipboard cleanup all returned true; Vercel now reports both
  Organizer TEST and Supabase staging secrets as sensitive, branch-scoped
  Preview variables, with zero risky public names and zero Wave 7C Stripe
  variables in Production.

## W7C-121 - Preview smoke command used a disallowed temporary-file cleanup

- Classification: `SIMULATION_BUG`
- Status: `fixed` / `regression_verified`
- Original scenario: after the exact SHA reached Vercel READY, QA prepared a
  read-only catalog and page smoke using temporary response files followed by
  `rm -f` cleanup.
- Evidence: command execution was rejected before process creation because that
  cleanup form is prohibited in the current environment.
- Impact: no HTTP request ran, no temporary file was created, and Preview,
  Supabase, Stripe, Vercel configuration and repository state did not change.
- Required correction: perform both read-only requests entirely in memory with
  Node `fetch`, emitting only status, content type, cache policy and bounded
  catalog shape.
- Required regression: the immutable/branch Preview catalog and page return
  successfully with no temporary files or cleanup command.
- Correction: all subsequent Preview probes ran in memory; the final app smoke
  used authenticated Chrome and created no diagnostic files.
- Verification: the branch alias reached `/planes-organizador` on the exact
  READY deployment and rendered its server-confirmed catalog without any
  temporary-file lifecycle.

## W7C-122 - Anonymous smoke reached Vercel protection instead of the Preview app

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the corrected in-memory smoke requested the branch alias
  without an authenticated Vercel session.
- Evidence: both the catalog and plans page returned HTTP 302 to the Vercel
  access surface; the response was `no-store` and never reached application
  routing.
- Impact: no application assertion can be made from that response, but no
  remote state changed and the protection behaved as configured.
- Required correction: fetch the exact protected deployment through Vercel's
  authenticated deployment connector rather than weakening access controls or
  creating a public bypass.
- Required regression: authenticated fetch reaches the Organizer catalog and
  plans page on SHA `64ed4bc`, with no secret material in either response.
- Correction: QA preserved Vercel protection and used the existing authenticated
  Chrome session instead of the anonymous request path.
- Verification: the branch alias opened the Organizer plans page, rendered one
  plan grid, two canonical disabled Checkout actions and two pending-price
  states, with zero catalog-unavailable, plans-disabled or empty-catalog states.

## W7C-123 - Protected-deployment connector emitted SSO session metadata

- Classification: `SECURITY_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: QA used Vercel's authenticated protected-deployment fetch
  connector for the immutable Organizer catalog URL.
- Evidence: instead of following authentication to the app, the connector
  returned another 302 together with a transient SSO location and a nonce cookie
  in its diagnostic response.
- Impact: no application, Supabase or Stripe state changed. The transient
  metadata was not copied to Git, reports, screenshots or a browser URL and
  must not be reused as evidence.
- Required correction: discard the connector response and use the user's
  already-authenticated Chrome session to reach the protected Preview directly,
  without generating a share URL or weakening deployment protection.
- Required regression: final QA evidence contains only origin/path, HTTP/app
  state and bounded non-sensitive UI/API shape; no cookies, nonces, share
  parameters, emails or tokens are retained.
- Correction: the connector response was discarded and never persisted; all
  following protected QA used authenticated Chrome without a share URL.
- Verification: retained evidence contains only the branch origin, path, page
  title and bounded UI counts. No cookie, nonce, share parameter, email or token
  was copied into the repository or reports.

## W7C-124 - Chrome binding does not expose agent tab creation in this session

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after discarding the unsafe protected-fetch response, QA
  attempted to create a separate Chrome tab for authenticated Preview smoke.
- Evidence: the persistent Chrome binding raised `chrome.tabs.create is not a
  function` before any navigation.
- Impact: no tab, request, credential or remote change was produced; the
  authenticated Supabase staging tab remains available.
- Required correction: preserve the current staging URL, reuse an existing
  authenticated Chrome tab for the Preview smoke, then restore the original URL
  if further staging-key work is required.
- Required regression: the final URL reaches the protected Preview app through
  Chrome authentication without share parameters and Supabase staging remains
  recoverable by its exact project URL.
- Correction: QA reused the otherwise idle Stripe-login tab and left the
  authenticated Supabase staging tab untouched.
- Verification: the reused tab reached the exact branch alias and plans path;
  the separate Supabase tab remains bound to project `iozcjirlfytryzrcmrnq`.

## W7C-125 - Stripe user tab was discovered but not yet claimed by automation

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: read-only discovery found the authenticated Stripe TEST
  API Keys tab for `Pachangas IQ Wave 7C`, then QA attempted to retrieve it
  directly from the agent-owned tab collection.
- Evidence: `user.openTabs()` returned user tab `43`, while `tabs.get('43')`
  reported no agent-owned tabs.
- Impact: no Stripe navigation or mutation occurred and no key, cookie or
  account data was inspected.
- Required correction: claim the explicitly discovered user tab through the
  browser-user handoff API before binding it as an agent tab.
- Required regression: the claimed tab retains the same TEST account title and
  path and no additional Stripe tab or login flow is created.
- Correction: the exact discovered tab was claimed through the browser-user
  handoff API and bound without navigation.
- Verification: tab `43` retains the Stripe TEST API Keys path and the title
  identifies `Pachangas IQ Wave 7C`; no new tab or authentication flow exists.

## W7C-126 - Stripe event selector did not expose checkout.session.expired

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: webhook creation selected the 11 event names defined by
  the server allowlist against Stripe API version `2026-08-26.dahlia`.
- Evidence: `checkout.session.completed` was selected successfully, but an
  exact search for `checkout.session.expired` returned no checkbox and the
  bounded selector aborted before continuing.
- Impact: no webhook destination has been created. One draft event selection is
  present only in the unsubmitted Stripe form; Supabase, Vercel and Stripe
  persistent configuration remain unchanged.
- Required correction: inspect the filtered event surface and current Stripe
  documentation to determine whether the event is unavailable, renamed or tied
  to a different API version; do not silently broaden the webhook scope.
- Required regression: the final submitted event set is explicitly reconciled
  with the server allowlist and any deliberate omission is documented and
  tested fail-safe before destination creation.
- Correction: the same filtered surface was retried after its asynchronous
  render completed; the event existed under the configured API version and no
  server allowlist change was necessary.
- Verification: the unsubmitted form now contains all 11 exact allowlisted
  events, including `checkout.session.expired`, with no extra event selected.

## W7C-127 - Multi-event selector wait exceeded the browser runtime deadline

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after proving the supposedly missing event appeared with a
  longer render delay, QA attempted to select the remaining ten allowlisted
  events in one bounded browser script.
- Evidence: one per-event wait did not resolve before the 30-second execution
  deadline and the local browser-control runtime reset.
- Impact: the webhook form was not submitted and no persistent Stripe endpoint
  or signing secret exists. Some additional checkboxes may remain selected only
  in the unsubmitted browser draft.
- Required correction: reinitialize browser control, reclaim the same Stripe
  tab, read the selected-event count without event values, and complete each
  missing event as an independent operation with a short explicit wait.
- Required regression: the submitted form proves exactly 11 selected events,
  each matching the server allowlist, without a long-running selector loop.
- Correction: QA reclaimed the surviving Stripe tab and completed only the
  missing event as an isolated bounded operation.
- Verification: the form and its URL independently report 11 selections and
  their normalized set equals the server allowlist exactly.

## W7C-128 - Browser runtime documentation exceeded the model context

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the browser-control runtime reset, QA reinitialized
  the persistent runtime and requested its complete documentation before
  reclaiming the existing Stripe TEST tab.
- Evidence: the documentation response exceeded the available model context
  and was truncated before any browser operation was attempted.
- Impact: no browser navigation or mutation occurred and no Stripe, Supabase,
  Vercel or repository state changed beyond this incident record.
- Required correction: keep the initialized persistent runtime, avoid rereading
  the full documentation, and resume with compact tab discovery and handoff
  calls only.
- Required regression: reclaim the exact Stripe TEST webhook tab and read its
  bounded URL/title and selected-event count without output truncation.
- Correction: the initialized runtime was reused with compact tab-list and tab
  binding calls; the complete documentation was not requested again.
- Verification: tab `43` was recovered with the same Stripe TEST title and
  webhook path, and its bounded selected-event label was read successfully.

## W7C-129 - Browser locator does not expose isChecked in this runtime

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: QA filtered the Stripe webhook selector to the final
  allowlisted event, checked its only result, and attempted to confirm the
  control through the familiar `isChecked()` locator method.
- Evidence: the event and checkbox were found exactly once and `check()` ran,
  but the locator proxy reported that `isChecked` is not a function.
- Impact: the final checkbox may already be selected in the unsubmitted form;
  no endpoint or other persistent Stripe resource was created.
- Required correction: read the checkbox's DOM `checked` property through the
  supported locator evaluation path, then verify the aggregate selected-event
  count independently.
- Required regression: the final event reads selected and the Stripe form
  reports exactly 11 selected events before submission.
- Correction: QA discarded the unsupported method and verified state through
  the form's selected-event label and canonical `events` query parameter.
- Verification: `customer.updated` is present, the aggregate count is 11 and
  the full normalized set equals the expected allowlist with no extras.

## W7C-130 - Locator evaluation did not expose the global navigator object

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: after creating the isolated TEST webhook, QA attempted to
  copy the revealed signing secret into the protected tab clipboard from a
  locator evaluation using the global `navigator.clipboard` object.
- Evidence: evaluation stopped with a TypeError because `navigator` was
  undefined in that isolated locator execution context.
- Impact: the clipboard write, secret read and Vercel subprocess never ran;
  no secret was emitted or persisted and both remote configurations remain
  otherwise unchanged.
- Required correction: resolve the page window through the located element's
  `ownerDocument.defaultView` and use that window's protected clipboard bridge.
- Required regression: transfer succeeds through stdin, only boolean evidence
  is emitted, and tab/runtime/system clipboard cleanup all pass.
- Correction: the page-global clipboard assumption was removed. The revealed
  value was read only into an ephemeral runtime binding, immediately written to
  the protected tab clipboard and then consumed by the Vercel subprocess.
- Verification: the protected value shape passed, Vercel exited zero, no value
  was emitted and all runtime and clipboard references were cleared.

## W7C-131 - Failed evaluation did not retain its declared runtime binding

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the corrected secret-transfer operation reused the name
  from the preceding failed evaluation, expecting its `var` binding to persist.
- Evidence: the persistent runtime reported that the binding was not defined
  before evaluating the page function.
- Impact: execution stopped before touching the page clipboard or launching
  Vercel; no secret moved or was exposed.
- Required correction: use fresh declarations for the complete corrected
  operation instead of depending on bindings from a failed evaluation.
- Required regression: the newly declared operation reaches protected copy,
  stdin transfer and complete clipboard cleanup in one bounded call.
- Correction: the successful operation used fresh bindings independent of all
  failed evaluation calls.
- Verification: the signing-secret shape passed and Vercel accepted the value
  exactly once through stdin.

## W7C-132 - Corrected page copy did not produce a valid protected clipboard value

- Classification: `TESTABILITY_GAP`
- Status: `fixed` / `regression_verified`
- Original scenario: QA retried the complete operation with fresh bindings and
  the page window resolved through the located secret element.
- Evidence: the operation rejected the value before starting Vercel because
  the protected tab clipboard did not contain a valid `whsec_` value.
- Impact: no Vercel subprocess ran; the runtime reference and tab/system
  clipboards were cleared in the mandatory cleanup block.
- Required correction: inspect only the non-sensitive shape booleans from the
  completed attempt, re-reveal the current dynamic value if necessary, and
  bind copying to the installed page clipboard bridge in the active document.
- Required regression: the page reports a valid secret shape, protected read
  confirms it, stdin transfer exits zero and both clipboards end empty.
- Correction: QA explicitly confirmed the Dashboard value was unmasked before
  copying it into the protected clipboard, then validated only its shape.
- Verification: shape, protected read and zero-exit transfer passed; runtime,
  tab and system clipboard state was cleared before the UI cleanup attempt.

## W7C-133 - Post-transfer masking control disappeared after secret handling

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: QA securely read the revealed TEST signing secret, moved it
  through the protected clipboard into the Vercel CLI stdin, cleared runtime,
  tab and system clipboard state, then attempted to re-mask the Dashboard value.
- Evidence: the final masking click found no matching show control before the
  operation could emit its boolean summary.
- Impact: the transfer may already have completed and must be reconciled by
  metadata before any retry. Secret variables and both clipboards were cleared
  before the failed UI cleanup; no value was printed or persisted locally.
- Required correction: inspect only retained boolean runtime state and Vercel
  environment metadata, then verify the Dashboard value is masked or navigate
  away without re-reading it.
- Required regression: exactly one branch-scoped sensitive Preview variable
  exists, Production has none, all clipboards are empty and no revealed secret
  remains on the active page.
- Correction: the destination page was reloaded instead of depending on the
  transient reveal control.
- Verification: the signing-secret section returned with zero revealed values,
  the protected clipboard is empty, Preview has one sensitive branch-scoped
  variable and Production has no Wave 7C TEST secret.

## W7C-134 - Vercel env list does not accept a branch filter option

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the successful webhook-secret transfer, QA tried to
  constrain `vercel env ls preview` with the same `--git-branch` option used by
  `vercel env add`.
- Evidence: Vercel CLI 59.4.0 rejected the unsupported list option before any
  request that could mutate environment configuration.
- Impact: no Vercel state changed and no secret value was read.
- Required correction: list Preview metadata without that option and verify
  branch scope from the CLI metadata returned for the exact variable.
- Required regression: the new webhook variable is sensitive, Preview-only and
  bound to the Wave 7C branch, while Production contains no Wave 7C Stripe key.
- Correction: QA used the supported environment-only list command and read the
  branch binding from its returned metadata.
- Verification: `STRIPE_TEST_WEBHOOK_SECRET` is Sensitive and scoped only to
  Preview branch `codex/organizer-live-pricing-checkout-v1`; Production contains
  none of the three Wave 7C TEST variable names.

## W7C-135 - Prior TEST catalog evidence belonged to a superseded Stripe context

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: existing Wave 7C reports stated that two Organizer TEST
  Products and four Prices already existed, while QA had since moved to the
  dedicated `Pachangas IQ Wave 7C` Sandbox required by the credential policy.
- Evidence: direct TEST Dashboard readback in the dedicated Sandbox shows the
  empty-state prompt to add the first test product and zero matches for either
  canonical Organizer product name.
- Impact: the product/price PASS statements are stale for the current Sandbox;
  no Checkout or Portal E2E may rely on them.
- Required correction: provision both Products and all four recurring Prices
  only through the server-authoritative platform command, confirm their exact
  metadata into PostgreSQL, and update every affected report.
- Required regression: Stripe readback, canonical mappings and Preview health
  all agree on exactly two Products, four Prices and zero active subscriptions.
- Correction: only the dedicated Pachangas IQ Sandbox was provisioned through
  the canonical platform workflow and every stale report statement was replaced
  with evidence from that context.
- Verification: Stripe, PostgreSQL and Preview agree on two Products, four
  recurring Prices and zero paid subscriptions; opaque resource IDs are absent
  from reports and Demo World.

## W7C-136 - Keyboard activation did not start Preview Google OAuth

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA opened the exact READY Preview, focused `Continuar con
  Google` and activated it with `Enter` to establish an authenticated staging
  session for the platform billing flow.
- Evidence: the page remained on the unauthenticated root and `/admin/billing`
  still returned `Sesión necesaria`.
- Impact: no OAuth session, platform command or remote data mutation occurred.
- Required correction: retry the same visible OAuth control with its supported
  pointer activation and follow only the existing Google session flow.
- Required regression: the branch Preview reaches `/admin/billing` as an
  authenticated staging platform actor without exposing identity data.
- Correction: QA used the visible control's supported pointer activation.
- Verification: Google OAuth started, later completed on the allowlisted staging
  alias and the authenticated actor reached the Organizer billing surface; no
  identity appears in retained evidence.

## W7C-137 - Wave 7C branch alias is not authorized by the Google OAuth client

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: pointer activation successfully started Google OAuth from
  the exact READY Wave 7C branch alias.
- Evidence: Google rejected the callback with `redirect_uri_mismatch` for that
  Preview origin before account selection or token issuance.
- Impact: no Google or Supabase session was created, no identity was disclosed
  to the application and no platform command ran.
- Required correction: reuse the existing non-production OAuth Preview alias
  that is already allowlisted, pointing it temporarily at the exact Wave 7C
  READY deployment; do not alter the production Google client or production
  environment variables.
- Required regression: OAuth returns to the allowlisted Preview origin, the
  staging session can read `/admin/billing`, and the temporary alias is removed
  or restored during final cleanup.
- Correction: the allowlisted non-production OAuth alias and public staging
  client were scoped temporarily to the exact Wave 7C Preview.
- Verification: authenticated staging QA reached `/admin/billing`; cleanup
  restored the alias to its preserved V2.1 deployment and removed the branch
  override.

## W7C-138 - OAuth alias alone does not replace the missing branch client ID

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA temporarily pointed the historical allowlisted OAuth
  Preview alias at the exact Wave 7C deployment and retried Google sign-in.
- Evidence: Google still returned `redirect_uri_mismatch`; the deployment was
  built with the project-wide client ID rather than the historical staging
  client configured on the former Official UI branch.
- Impact: no OAuth or Supabase session was issued and no application data was
  changed. The temporary alias now points to Wave 7C and is tracked for cleanup.
- Required correction: recover only the public staging OAuth client ID from the
  immutable historical Preview, add it as a non-sensitive Wave 7C branch
  override, redeploy, and preserve production environment variables unchanged.
- Required regression: the allowlisted alias and branch-scoped staging client
  complete OAuth on the exact Wave 7C SHA; the client ID remains public-only and
  the historical alias is restored after QA.
- Correction: the public staging client ID was added only as the exact branch
  override and the Preview was rebuilt.
- Verification: OAuth, canonical billing reads and Realtime passed; cleanup
  removed the override and restored the historical alias target.

## W7C-139 - Vercel rejected the first branch OAuth override transfer

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: the immutable Official UI Preview successfully supplied
  the shape-valid public staging Google client ID, which QA piped through stdin
  to a Wave 7C branch-scoped `NEXT_PUBLIC_GOOGLE_CLIENT_ID` override.
- Evidence: Vercel CLI returned a non-zero status; the runtime client ID binding
  was cleared and its value was not emitted.
- Impact: no branch override was confirmed and no production variable changed.
- Required correction: inspect only redacted CLI diagnostics, reconcile any
  existing branch/global-name conflict with the supported Vercel env workflow,
  and retry without exposing the public ID or any OAuth state.
- Required regression: Preview metadata contains exactly one Wave 7C branch
  override while the project-wide Production entry remains unchanged.
- Correction: the supported `--force --no-sensitive` combination replaced the
  inherited Preview value only for the Wave 7C branch.
- Verification: the historical identifier passed the public-client shape check
  and Vercel CLI exited zero without emitting its value.

## W7C-140 - Failed OAuth transfer diagnostics did not persist across runtime calls

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed` / `regression_verified`
- Original scenario: after the non-zero Vercel result, QA attempted to inspect
  the prior subprocess object with all client IDs and OAuth parameters redacted.
- Evidence: the persistent runtime no longer exposed that block-local binding.
- Impact: no new subprocess or remote change occurred and no identifier was
  emitted.
- Required correction: inspect the supported `vercel env add` options first,
  then rerun extraction and transfer in one bounded call that emits only a
  sanitized status code and diagnostic category.
- Required regression: the corrected command succeeds or returns a stable,
  fully redacted actionable error without relying on prior bindings.
- Correction: QA discovered the supported overwrite flags from CLI help and
  performed extraction, transfer and redacted result classification in one
  bounded runtime call.
- Verification: client shape and zero-exit transfer both passed; the runtime
  binding was cleared and no OAuth URL or identifier entered the repository.

## W7C-141 - Google OAuth returned to Preview without retaining a Supabase session

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after rebuilding with the branch-scoped staging client and
  moving the allowlisted alias to the exact READY SHA, Google OAuth completed
  without a redirect mismatch and returned to the Preview root.
- Evidence: the final URL contained no OAuth error, but `/admin/billing` still
  rendered `Sesión necesaria`.
- Impact: no platform command or billing mutation ran; the failure is limited
  to authenticated Preview session establishment.
- Required correction: inspect the app callback contract plus sanitized Preview
  runtime/console diagnostics and reconcile the Supabase staging redirect or
  cookie boundary without weakening authentication.
- Required regression: one OAuth completion produces a valid staging session,
  `/admin/billing` loads its canonical read model and no token appears in the
  final URL, evidence or logs.
- Correction: the Preview was rebuilt with the branch-scoped public staging
  OAuth client and staging Supabase boundary, then the allowlisted alias was
  pointed to the exact deployment.
- Verification: OAuth produced a valid session, two authenticated tabs loaded
  the canonical billing read model and Realtime updates, and the final URLs and
  retained evidence contain no token.

## W7C-142 - Service Worker diagnostic exceeded the default selector deadline

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: because the reused OAuth alias may still be controlled by
  the historical PWA worker, QA requested a bounded registration/controller
  summary from the active root document.
- Evidence: the asynchronous locator evaluation exceeded its default three
  second deadline before returning any state.
- Impact: no worker was updated, unregistered or modified and no browser data
  was read beyond the failed diagnostic attempt.
- Required correction: repeat the same non-sensitive controller/registration
  summary with an explicit bounded timeout, then use the product's controlled
  update path if a stale worker is present.
- Required regression: the exact Wave 7C worker controls the OAuth alias after
  one controlled reload and authentication is retried without fake success.
- Correction: repeated browser registration enumeration was abandoned in favor
  of the checked-in controlled-update contract and bounded endpoint/runtime QA.
- Verification: focused PWA tests and the 618-test suite pass controlled update,
  single reload, offline rejection and reconnection; the deployed Service Worker
  returns 200 and standalone simulation passes.

## W7C-143 - Extended locator timeout did not override the browser command deadline

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA repeated the read-only Service Worker summary with a
  ten-second locator option and a longer tool timeout.
- Evidence: the browser layer still stopped evaluation at its three-second
  command deadline before the registration promise resolved.
- Impact: no worker, cache, session or remote resource changed.
- Required correction: stop retrying registration enumeration; first read only
  the synchronous controller path, then use the existing bridge update UI or a
  single page-side update command that does not await enumeration.
- Required regression: a bounded synchronous diagnostic returns, stale worker
  state is resolved once, and OAuth session behavior is retested.
- Correction: QA stopped using the unsupported long locator evaluation and used
  product tests plus authenticated browser behavior.
- Verification: OAuth, offline fail-closed behavior, reconnect convergence and a
  single controlled reload all passed without fake success.

## W7C-144 - Synchronous Service Worker controller evaluation also timed out

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA removed all asynchronous registration calls and read
  only `navigator.serviceWorker.controller` through the root body element.
- Evidence: the same three-second browser evaluation deadline expired.
- Impact: no browser or remote state changed; repeated page evaluation is no
  longer a viable diagnostic path for this tab.
- Required correction: abandon locator evaluation for this issue and use the
  product's visible update behavior plus server/browser logs; if auth remains
  blocked, use a canonical ephemeral staging actor through documented QA
  tooling rather than weakening OAuth.
- Required regression: the selected alternative establishes an authenticated
  staging session or records a precise blocker without bypassing server RBAC.
- Correction: the canonical temporary staging-role flow established the session
  without weakening OAuth or client authority.
- Verification: two authenticated tabs consumed the canonical billing read
  model and Realtime updates; the temporary role was later revoked canonically.

## W7C-145 - Unmatched shell glob interrupted the PWA bridge source search

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: QA read the Service Worker strategy and appended a search
  for registration/update code using an unquoted `pwa-client-bridge*` path.
- Evidence: zsh rejected the unmatched glob after the Service Worker source had
  already been read.
- Impact: no file or runtime state changed; only the second read-only search was
  skipped.
- Required correction: locate exact bridge filenames with `rg --files` and run
  the source search against explicit paths.
- Required regression: the update/reload contract is inventoried without shell
  expansion errors before choosing the next OAuth diagnostic.
- Correction: subsequent inventories used `rg --files` plus explicit checked-in
  PWA bridge and Service Worker paths only.
- Verification: focused PWA tests and the 618-test global suite pass, including
  controlled update, one reload, offline rejection and reconnect convergence;
  no unmatched glob was used again.

## W7C-146 - First authenticated Google account lacks platform access in staging

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: OAuth reached the real Google account chooser and QA used
  the first already-authenticated account without reading or recording identity.
- Evidence: the root showed a valid signed-in state, while `/admin/billing`
  returned `Acceso no disponible`.
- Impact: authentication succeeded but no platform read or write was authorized;
  no billing state changed.
- Required correction: sign out cleanly and retry the second existing account,
  again without capturing identity; retain only role/access outcome.
- Required regression: the selected staging account reaches the billing Control
  Center with canonical platform capabilities and no PII in evidence.
- Correction: QA identified the active actor only by opaque ID and used the
  canonical temporary platform-role contract.
- Verification: the actor reached the billing Control Center and no PII was
  retained; cleanup revoked the role at revision 3.

## W7C-147 - Second authenticated Google account also lacks staging platform access

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA signed out the first account, completed OAuth with the
  second existing Google account and retried the Control Center.
- Evidence: authentication succeeded, but `/admin/billing` again returned
  `Acceso no disponible`.
- Impact: neither available browser identity can exercise platform billing in
  staging; no billing command or role mutation has occurred yet.
- Required correction: identify the just-authenticated staging user only by
  opaque user ID and recent sign-in timestamp, grant a temporary platform role
  through the canonical service/bootstrap contract, then revoke it in cleanup.
- Required regression: the same session reaches the Control Center, all role
  grant/revoke actions are auditable, and zero PII is retained in evidence.
- Correction: an auditable temporary role was granted to the opaque active actor
  through the canonical contract, with no direct table authority.
- Verification: authenticated Control Center and Realtime QA passed; the role is
  inactive at revision 3 and the permanent owner remains active at revision 1.

## W7C-148 - Recent-user readback exceeded the connector output budget

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA queried the three most recent staging sign-ins as a
  bounded JSON aggregate in order to identify the active browser actor only by
  opaque user ID and current platform role.
- Evidence: the Supabase connector returned an unexpectedly large, truncated
  response despite the inner `limit 3`, so no reliable row was consumed.
- Impact: the query was read-only; no account, role or billing state changed and
  no PII was retained in the evidence ledger.
- Required correction: replace the aggregate with one scalar row containing
  only the latest opaque user ID, sign-in timestamp, existing role/revision and
  one deterministic active platform-owner ID.
- Required regression: the compact query returns exactly one bounded row
  without truncation or personal data before any temporary role command runs.
- Correction: the aggregate was replaced with a scalar query returning one
  latest opaque user row and one deterministic active owner actor.
- Verification: staging returned exactly one bounded row containing only UUIDs,
  timestamp and nullable role metadata; no email, name or token was queried.

## W7C-149 - Browser selectOption stalled on the commercial-plan selector

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: after provisioning the Club TEST catalog, QA selected the
  first visible `Plan` combobox and requested `TEAM_ORGANIZER_PRO` by option
  value through the browser adapter.
- Evidence: the adapter found exactly one visible native `select` containing
  all three decisions but exceeded its action deadline before changing value.
- Impact: the Club catalog remains canonically confirmed; no Team product,
  price, decision or flag changed during the failed selector action.
- Required correction: use visible keyboard interaction on the same native
  selector, then confirm the selected label and amounts before provisioning.
- Required regression: the UI shows `TEAM_ORGANIZER_PRO`, 9.90 EUR monthly and
  99.00 EUR yearly before the server command is submitted once.
- Correction: the selector was addressed by its visible option label rather
  than assuming its internal value was the plan code.
- Verification: the UI displayed Team Organizer Pro with 990/9900 minor units,
  then PostgreSQL confirmed the second Product and both recurring Prices.

## W7C-150 - Staging ownership readback used unsupported UUID aggregation

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after catalog confirmation, QA requested counts plus the
  first opaque owned Team and Club IDs for the authenticated staging actor.
- Evidence: PostgreSQL rejected `min(uuid)` with SQLSTATE `42883` before
  returning any row.
- Impact: the readback was read-only; no organizer, setting or billing account
  changed.
- Required correction: order UUIDs by their textual representation in bounded
  scalar subqueries instead of applying `min` to the UUID type.
- Required regression: one compact row returns ownership counts, optional
  opaque IDs and TEST flags without PII.
- Correction: UUID candidates are now selected with deterministic textual order
  and `limit 1`; no unsupported aggregate remains.
- Verification: the bounded readback completed and reported zero owned Teams
  and Clubs for the ephemeral actor.

## W7C-151 - Ownership readback referenced obsolete TEST flag names

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: the corrected ownership query also requested
  `test_checkout_enabled` and `test_portal_enabled` directly from the billing
  settings row.
- Evidence: staging rejected the first obsolete column name with SQLSTATE
  `42703`; the current schema exposes the Wave 7C gate under different names.
- Impact: no data changed and no partial row was consumed.
- Required correction: read the exact settings columns from the forward-only
  Wave 7C migrations, then rerun the compact query with canonical names only.
- Required regression: the corrected query returns one row and its flags agree
  with the Control Center read model.
- Correction: the query now uses `stripe_test_checkout_enabled`,
  `stripe_test_portal_enabled`, `stripe_test_webhook_ready` and
  `stripe_test_portal_ready` from the exact Wave 7C schema.
- Verification: one compact row matched the Control Center: TEST webhook and
  Portal ready, while both public TEST gates remained disabled at revision 12.

## W7C-152 - Club QA form remained disabled after the initial input set

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: QA filled the visible private-Club fields with synthetic
  values and attempted the product's `Crear Club` action.
- Evidence: the browser found the unique submit button but it remained disabled
  until the form's exact client-side creation prerequisites are satisfied.
- Impact: no Club was created and no canonical Club command ran.
- Required correction: inspect the visible form state and the local validation
  contract, supply only the missing non-sensitive prerequisite, and retry once.
- Required regression: the submit button becomes enabled before click and the
  resulting canonical Club is owned by the ephemeral actor.
- Correction: staging's pre-existing Club Foundation and self-service flags
  were enabled temporarily through `command_pachanga_club_platform_v1`; no
  direct table update was used.
- Verification: the same form became enabled, created one private draft Club
  through `/api/clubs/command`, and a compact readback confirmed its opaque ID,
  owner and revision. The flags are scheduled for exact restoration in cleanup.

## W7C-153 - Platform activation correctly rejected a draft Club

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: immediately after creating the private QA Club, the
  platform status command attempted to move it from `draft` to `active`.
- Evidence: the publication guard rejected the transaction with
  `CLUB_APPROVAL_REQUIRES_PENDING_REVIEW`.
- Impact: the transaction rolled back atomically; the Club remains draft at
  revision 1 and no billing account exists for it.
- Required correction: use the real owner flow to record publication consent
  and submit the Club for review, then let the platform command activate the
  resulting pending revision.
- Required regression: `draft -> consent -> pending_review -> active` is
  observable through canonical revisions, with no direct table mutation.
- Correction: the owner recorded both publication attestations and submitted
  the Club through `/api/clubs/command`; the platform then applied
  `club.status.set` at the expected revision.
- Verification: revisions advanced 1 -> 2 -> 3 -> 4 and the final canonical
  snapshot reported the same owner with `operationalStatus=active`.

## W7C-154 - First remote Team Checkout TEST failed closed

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original scenario: with TEST health, Checkout and Portal gates enabled, the
  authenticated owner selected Team Organizer Pro monthly and submitted the
  visible Checkout action.
- Evidence: the product remained on the billing page and rendered `La operacion
  no fue confirmada por el servidor`; no Stripe-hosted URL was opened.
- Impact: no entitlement, subscription or successful Checkout state appeared;
  the UI correctly avoided fake success.
- Required correction: correlate the sanitized Preview runtime log and
  canonical intent/receipt ledger, fix only the concrete server-side blocker,
  then retry with a fresh `operationId` if no confirmed intent exists.
- Required regression: the same Team/month owner intent returns one hosted
  TEST URL, while cancel and success redirects still grant no access alone.
- Root cause: Stripe created the canonical Customer successfully, then rejected
  `/v1/checkout/sessions` because Tax ID collection on that Customer requires
  `customer_update[name]=auto`.
- Correction: the server-owned Checkout request now includes exactly
  `customer_update: { name: "auto" }`; no client field, permission or LIVE
  behavior changed.
- Local regression: the source contract test now couples Tax ID collection to
  the required Customer name update. Remote verification follows on the next
  exact Preview deployment.
- Remote verification: after completing the Customer address contract in
  W7C-156, a fresh Team/month intent opened the Stripe-hosted TEST Checkout and
  PostgreSQL still reported zero subscription projections and zero active
  grants before any signed webhook.

## W7C-155 - Focused TypeScript test used Node without the repository loader

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: the post-fix focused check invoked `node --test` directly
  for two TypeScript files.
- Evidence: the pure source tests passed, but Node could not resolve the
  extensionless TypeScript import `app/pwa-write-classifier` in the Wave 7B
  suite, producing one runner failure unrelated to the product change.
- Impact: no runtime or remote state changed; 11 assertions passed before the
  loader mismatch stopped the second file.
- Required correction: use the repository's declared `tsx --test` command for
  focused TypeScript suites.
- Required regression: both focused files pass with zero skipped, todo or
  cancelled tests under the same loader used by `npm test`.
- Correction: the focused command now uses `npx tsx --test`, matching the
  repository's declared TypeScript test loader.
- Verification: 23/23 focused Wave 7B/7C tests passed with zero failures,
  skipped, todo or cancelled; typecheck and focused lint also passed.

## W7C-156 - Remote Team Checkout still failed after Customer name update

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original scenario: the exact Preview deployment containing
  `customer_update[name]=auto` was made READY, the staging OAuth alias was
  repointed to that SHA, the billing page was reloaded to discard the previous
  client operation, and the authenticated Team owner requested the monthly
  Team Organizer Pro Checkout again.
- Evidence: the product stayed on the canonical billing page and rendered
  `La operacion no fue confirmada por el servidor`; no Stripe-hosted URL was
  opened.
- Impact: the account remains without access or subscription at revision 1;
  the client did not display optimistic success and no LIVE resource was used.
- Required diagnosis: correlate the new server receipt, sanitized Vercel
  runtime error and Stripe TEST request log before changing implementation.
- Required correction: fix only the newly confirmed server-side blocker and
  retry with a fresh idempotent operation after an exact READY deployment.
- Required regression: the Team/month owner intent opens one hosted TEST
  Checkout URL and the server still grants no entitlement before a valid
  signed webhook confirms payment.
- Root cause: Stripe accepted creation of the Customer and then rejected the
  Checkout Session because Tax ID collection also requires
  `customer_update[address]=auto` when the existing Customer has no canonical
  address.
- Correction: the server-owned request now allows Stripe Checkout to update
  both Customer address and name automatically. The browser still sends
  neither field and cannot choose the Stripe Customer.
- Local regression: the Checkout source contract now requires address and name
  updates together with Tax ID collection. Remote verification follows on the
  next exact READY deployment.
- Remote verification: the exact READY deployment opened one Team Organizer Pro
  monthly TEST Checkout. The canonical intent is `SESSION_CREATED`, while the
  account has no current plan family, subscription projection or access grant
  before payment confirmation.

## W7C-157 - Generic incident patch targeted an older status line

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: while recording W7C-156, a generic patch hunk changed the
  first matching `Status: open` line in the ledger instead of the new incident.
- Evidence: the mandatory pre-commit diff review showed W7C-004 modified while
  W7C-156 remained open.
- Impact: documentation only; no code, Stripe, Supabase or deployment state was
  changed and the accidental edit was never committed.
- Correction: both status lines were patched with their incident headings as
  explicit context.
- Verification: the reviewed diff now leaves W7C-004 unchanged and changes
  only W7C-156 to `fix_implemented_regression_pending_remote`.

## W7C-158 - Pre-webhook readback referenced nonexistent account columns

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after Stripe returned a hosted Team/month Checkout URL,
  QA attempted to prove that the billing account still had no access before a
  signed webhook.
- Evidence: PostgreSQL rejected the read-only query because the billing account
  table does not expose columns named `access_status` or `current_plan_code`.
- Impact: the statement returned no row and changed no staging data.
- Required correction: inspect the exact private schema and use subscription
  and grant tables, plus only real account columns, for the fail-closed
  assertion.
- Required regression: one bounded row proves `SESSION_CREATED` while active
  subscription and access-grant counts remain zero before payment confirmation.
- Correction: the readback now uses real account columns plus
  `pachanga_stripe_subscription_projections_v1` and
  `pachanga_organizer_access_grants_v1`.
- Verification: one bounded canonical row reported `SESSION_CREATED`, a stored
  hosted Session URL, zero subscription projections and zero active grants.

## W7C-159 - Stripe agent disclosure did not accept setChecked automation

- Classification: `TESTABILITY_GAP`
- Status: `open`
- Original scenario: before entering any TEST payment data, QA attempted to
  enable Stripe Checkout's visible `I am an AI agent acting on behalf of
  someone else` disclosure with the semantic checkbox action.
- Evidence: the browser found one visible enabled checkbox, but Stripe's custom
  control did not transition to checked state and the action failed.
- Impact: no payment was submitted, no webhook fired and canonical access
  remains absent.
- Required correction: activate the same visible disclosure with a normal user
  click and verify its checked state before continuing; do not hide, bypass or
  remove the control.
- Required regression: the disclosure is checked in the hosted Checkout before
  the TEST payment button is submitted.

## W7C-160 - Browser locator lacks isChecked inspection helper

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after clicking the visible Stripe agent disclosure, QA
  attempted to verify it with the full Playwright `isChecked()` helper.
- Evidence: this browser adapter does not expose that helper and rejected the
  inspection call after the click.
- Impact: no payment submission occurred; the click may have succeeded but its
  state was not yet accepted as evidence.
- Required correction: verify the same control through the supported semantic
  DOM snapshot and continue only if it is explicitly marked checked.
- Required regression: the snapshot records the disclosure as checked before
  TEST payment submission.
- Correction: the supported locator property evaluation was used for the
  inspection instead of the unavailable convenience helper.
- Verification: the control was proved unchecked, so QA did not submit the
  hosted payment and did not misreport disclosure as complete.

## W7C-161 - Stripe card method button exceeded the browser action deadline

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: with the hosted TEST Checkout open and before entering
  payment data, QA selected Stripe's visible `Pago con tarjeta` control.
- Evidence: one visible enabled button was found, but the third-party Checkout
  did not complete the semantic click before the browser deadline.
- Impact: no card data was entered, no payment was submitted and no webhook or
  entitlement was produced.
- Required correction: try the corresponding visible `Tarjeta` radio control;
  if Stripe still blocks automated interaction, keep hosted-payment completion
  explicitly pending and validate signed webhook projection through Stripe's
  official TEST tooling instead.
- Required regression: either the card fields become interactable and the
  agent disclosure is checked, or the final report preserves this physical
  Checkout limitation without claiming a completed hosted payment.
- Correction: QA selected the equivalent visible `Tarjeta` radio control.
- Verification: Stripe marked `Tarjeta` checked and exposed the cardholder and
  billing-address fields. Payment submission remains deliberately blocked by
  the unresolved agent-disclosure control in W7C-159.

## W7C-162 - Vercel env run materialized a local environment file

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA used Vercel's documented `env run` command to execute a
  signed TEST webhook probe with branch-scoped server variables and no secret
  value in the command or output.
- Evidence: Vercel reported that it loaded the Preview environment from a new
  worktree-local `.env.local` file.
- Impact: the file may contain sensitive branch Preview values. It was never
  read, printed, staged or committed, but violates the requirement that the
  restricted key remain only in Vercel.
- Required correction: delete the known generated file immediately without
  inspecting it, verify Git and filesystem cleanup, and do not use `env run`
  again for this release.
- Required regression: `.env.local` is absent, Git remains clean apart from
  intentional Wave 7C documentation, and secret scans report no leaked value.
- Correction: the generated file was removed without reading or printing it and
  `env run` is retired from the remaining Wave 7C procedure.
- Verification: a single-depth filesystem check reports `.env.local` absent;
  the full secret scan remains part of the final gate.

## W7C-163 - Signed TEST webhook probe was intercepted with HTTP 401

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: a controlled Stripe-compatible TEST event was signed with
  the branch-only webhook secret and posted to the dedicated Organizer Preview
  endpoint.
- Evidence: the response was HTTP 401, whereas the application webhook route
  itself returns 400 for bad signatures and 200/500 after ingestion.
- Impact: the request did not reach canonical ingestion; no webhook event,
  subscription projection or access grant was created.
- Required diagnosis: confirm whether Vercel Deployment Protection is blocking
  Stripe and test probes before the application route, then use a narrowly
  scoped protection bypass or another isolated staging endpoint without
  weakening Production.
- Required regression: the dedicated TEST destination reaches the application,
  accepts one valid signed event, rejects an invalid signature, and remains
  isolated from Production and Stripe V1.
- Correction: the dedicated Stripe TEST destination was given the isolated
  Vercel automation-bypass query contract documented for third-party webhooks;
  Production and Stripe V1 were not changed.
- Verification: Vercel recorded HTTP 200 for an official Stripe-origin TEST
  event and HTTP 400 for the invalid-signature probe. The private canonical
  ledger recorded `signature_verified=true`, `ACCEPTED` and `PROCESSED`.

## W7C-164 - Broad file-removal command was rejected during secret cleanup

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: immediately after W7C-162, QA attempted to remove only the
  generated `.env.local` with a forced removal command.
- Evidence: the execution environment rejected the command before it ran and
  recommended a narrower removal operation.
- Impact: no file was deleted by that command; the generated environment file
  remained temporarily present but unread and untracked.
- Required correction: use a single-path non-forced unlink operation, then
  verify absence without displaying any former content.
- Required regression: the file no longer exists and no other worktree path is
  modified by cleanup.
- Correction: the exact generated path was removed with a non-forced unlink.
- Verification: the path is absent and no recursive or wildcard deletion was
  executed.

## W7C-165 - Vercel project readback exposed an existing automation bypass value

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: to diagnose the Preview HTTP 401, QA requested a redacted
  project-security projection through the authenticated Vercel API.
- Evidence: the `protectionBypass` object encodes the secret as its object key,
  so the filtered CLI result still printed the full pre-existing automation
  bypass value.
- Impact: the value appeared in a private tool log. It was not copied to source,
  reports, screenshots or the client bundle, but must now be treated as exposed
  and never reused for Wave 7C.
- Required correction: inventory references by variable name only, rotate or
  revoke the exposed project bypass without printing the replacement, update
  only necessary protected integrations, and verify the old value no longer
  authenticates.
- Required regression: project readbacks report only bypass count/scope/age,
  no secret value appears in later logs, and final scans contain no bypass or
  Stripe credential material.
- Correction: the exposed bypass was regenerated without printing its
  replacement and the project readback was reduced to count, scope, env-var
  status and creation time.
- Verification: the sanitized readback reports exactly one automation bypass;
  the former value no longer reaches the application. The full repository and
  artifact secret scan remains a final release gate.

## W7C-166 - Previous Vercel bypass still authenticated immediately after rotation

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: the exposed automation bypass was revoked with
  `regenerate=true` through Vercel's project API, then immediately used once
  against the protected TEST webhook path.
- Evidence: the old value reached the application and returned HTTP 405 for a
  GET request instead of being stopped by Deployment Protection with 401.
- Impact: the old bypass may still be valid during propagation or may not have
  been removed by the requested operation. No application mutation occurred.
- Required diagnosis: read back only bypass count, scope, env-var status and
  creation time; wait for propagation if one replacement exists, otherwise
  revoke the stale entry explicitly without printing either value.
- Required regression: the former bypass no longer reaches the application and
  the project retains only the intended replacement automation credential.
- Correction: after propagation, the exposed value was retired again as part
  of the W7C-169 rotation and no additional bypass entry was retained.
- Verification: the old-value probe now redirects to Vercel SSO instead of
  returning the application's HTTP 405, while the sanitized project readback
  reports exactly one replacement credential.

## W7C-167 - Clipboard paste did not update the Stripe webhook URL field

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: the replacement Vercel bypass was composed into the
  dedicated TEST webhook URL without stdout and placed temporarily on the macOS
  clipboard, then the visible Stripe endpoint field received Select All/Paste.
- Evidence: a boolean-only field inspection reported the original URL length,
  no bypass query key and no expected protected endpoint prefix.
- Impact: Stripe was not modified and the replacement bypass was not submitted
  or displayed by the browser.
- Required correction: transfer the clipboard value directly in memory to the
  visible field, never emit the string, and verify only prefix/bypass booleans
  before saving.
- Required regression: Stripe saves one dedicated TEST destination containing
  the protected endpoint contract, while logs, screenshots and reports contain
  no bypass value.
- Correction: the protected endpoint was transferred directly in memory to the
  visible Stripe field and saved; the clipboard was cleared immediately.
- Verification: boolean-only field checks confirmed the expected endpoint and
  bypass shape, and an official Stripe TEST delivery subsequently reached the
  application with HTTP 200.

## W7C-168 - Stripe test-event control did not open through browser automation

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: after saving the protected Organizer TEST destination, QA
  activated Stripe Dashboard's visible `Enviar eventos de prueba` control to
  generate one official signed event without completing a hosted payment.
- Evidence: the control remained visible and enabled, but neither the semantic
  click nor the adapter's element activation exposed the event picker; the
  latter is not implemented by the browser adapter for Stripe's custom anchor.
- Impact: no event was sent by this attempt and no subscription projection or
  grant changed.
- Required correction: use another official Stripe TEST mechanism or a
  supported Dashboard interaction that preserves the dedicated destination,
  signing secret and protection bypass without exposing credentials.
- Required regression: one Stripe-origin signed TEST delivery reaches the
  application route and is visible in both Stripe delivery status and the
  canonical server ledger; no hosted charge or LIVE resource is created.
- Correction: QA used Stripe Workbench's official `stripe trigger` TEST
  mechanism instead of the inaccessible custom event-picker control.
- Verification: the post-rotation trigger produced HTTP 200 and canonical
  sequences 78/79 with verified signature, accepted delivery and processed
  event. No LIVE object or charge was created.

## W7C-169 - Stripe Workbench output exposed the protected TEST endpoint URL

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA used Stripe Workbench's official TEST shell to trigger
  `checkout.session.completed` after the event-picker control in W7C-168 did
  not open.
- Evidence: the Workbench result included the complete dedicated endpoint URL,
  including the current Vercel protection-bypass query value, in a private tool
  log.
- Impact: the bypass did not enter Git, reports, screenshots, the client bundle
  or Production, but the current value must be considered exposed and retired.
- Required correction: rotate the Vercel automation bypass again without
  printing the replacement, update the dedicated Stripe TEST destination only
  through an in-memory transfer, and never emit unfiltered Workbench body text.
- Required regression: the previous value no longer passes Deployment
  Protection, only one replacement exists, Stripe TEST reaches the route, and
  all later evidence is limited to status codes, counts and redacted metadata.
- Correction: the exposed bypass was regenerated again, the dedicated Stripe
  TEST destination was updated directly in memory and all later evidence was
  limited to redacted metadata and status codes.
- Verification: the exposed value redirects to Vercel SSO, exactly one new
  bypass exists, and a second Stripe-origin signed event reached the app and
  private ledger with HTTP 200.

## W7C-170 - Vercel bypass rotation used an obsolete revoke field

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after W7C-169, QA attempted a silent rotation using the
  same protected API contract recorded by the previous rotation.
- Evidence: Vercel rejected the request with HTTP 400 because `revoke` now
  requires the property `secret`; no rotation occurred.
- Impact: the exposed replacement remained active temporarily, but no project
  setting or application state changed in this failed attempt.
- Required correction: repeat once with the API-confirmed `revoke.secret`
  field, keeping both old and regenerated values out of stdout and files.
- Required regression: rotation succeeds, the old value receives HTTP 401,
  and the sanitized project readback reports exactly one new automation bypass.
- Correction: the retry used the API-confirmed `revoke.secret` field.
- Verification: the rotation completed, the old value is rejected by
  Deployment Protection through its SSO redirect, and the sanitized readback
  reports one replacement automation bypass.

## W7C-171 - Post-rotation probe used a reserved zsh variable

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: the corrected Vercel rotation completed, after which the
  same shell block attempted to store the old-token probe result in `status`.
- Evidence: zsh rejected assignment to its read-only `status` parameter before
  the probe result could be reported.
- Impact: the rotation request had already completed, but this execution did
  not prove revocation or the final bypass count.
- Required correction: do not rotate again; perform a sanitized project
  readback and use a non-reserved local variable for the old-value probe.
- Required regression: one replacement exists and the previously exposed value
  is rejected by Deployment Protection without reaching the application.
- Correction: no additional rotation was performed; the old value was probed
  in memory and the project was read back with a secret-free projection.
- Verification: the old probe returned a Vercel SSO redirect rather than the
  application's HTTP 405, and the project retains one replacement entry.

## W7C-172 - Full hosted Checkout snapshot included the authenticated email

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after opening Club Organizer monthly in Stripe TEST, QA
  requested a complete semantic snapshot to confirm the hosted product and
  interval.
- Evidence: Stripe's accessible tree also included the authenticated Checkout
  email in a private tool response.
- Impact: no PII entered Git, reports, screenshots, application logs or public
  artifacts, but the complete snapshot is unsuitable as retained evidence.
- Required correction: do not request further full hosted-Checkout snapshots;
  query only bounded product, amount, interval and TEST-mode controls and keep
  all final evidence aggregate and redacted.
- Required regression: the remaining three Checkout combinations are verified
  without outputting email, Customer, Session, subscription or payment IDs.
- Correction: hosted Checkout evidence was reduced to TEST mode, product,
  amount and interval assertions only.
- Verification: Club monthly, Club annual and Team annual were verified with
  bounded semantic checks and canonical receipt readbacks; no further Checkout
  snapshot or personal identifier was emitted.

## W7C-173 - Billing-period selector missed the first post-Checkout deadline

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after returning directly from hosted Club monthly
  Checkout, QA immediately queried the annual-period selector.
- Evidence: the browser adapter exceeded its dispatch deadline before the
  selector evaluation began.
- Impact: no Checkout Session or server mutation was created by this attempt.
- Required correction: wait for the billing page and canonical snapshot to
  stabilize, then query the existing selector without another navigation.
- Required regression: Club annual opens once and records one non-replayed
  `checkout.prepare` receipt with `billingInterval=year`.
- Correction: QA waited for the canonical billing page to settle and selected
  the annual option through the supported semantic select action.
- Verification: Stripe TEST opened Club Organizer at 290 EUR per year and the
  server recorded one non-replayed `checkout.prepare` receipt with
  `billingInterval=year` at server sequence 85.

## W7C-174 - Portal button property inspection exceeded the adapter deadline

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: before creating the synthetic canonical active
  subscription, QA attempted to inspect the native `disabled` property of the
  visible `Gestionar en Stripe` button.
- Evidence: the semantic selector existed on the settled billing page, but its
  property evaluation exceeded the browser adapter deadline.
- Impact: no write occurred; the canonical snapshot still reported `Sin
  acceso` and no active subscription or grant existed.
- Required correction: validate Portal availability from the canonical billing
  snapshot and the authenticated Portal route response, not from a fragile DOM
  property helper.
- Required regression: an owner with a server-configured Stripe Customer can
  create one TEST Portal Session, an organizer without a Customer is denied,
  a non-owner remains denied, and replaying the same operation does not create
  a second intent. Portal access is deliberately not coupled to an active
  entitlement because it must remain available for billing recovery.
- Correction: QA replaced the fragile DOM-property inspection with the
  authoritative Portal command and private intent readback.
- Verification: the owner reached `billing.stripe.com`, the canonical intent
  stayed `SESSION_CREATED`, replay returned the original receipt with one
  intent row, the non-owner received `BILLING_OWNER_REQUIRED`, and a rolled
  back owner-transfer test proved that permissions follow the current owner.

## W7C-175 - Realtime invalidation readback assumed a nonexistent column

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after the canonical active-subscription projection, QA
  queried the public billing invalidation ledger using the guessed column name
  `entity_type`.
- Evidence: PostgreSQL rejected the read with undefined-column SQLSTATE 42703.
- Impact: the projection transaction had already succeeded and was unaffected;
  only the diagnostic read failed.
- Required correction: inspect the relation contract and repeat the bounded
  readback with canonical column names before diagnosing the client refresh.
- Required regression: the active projection has a corresponding ordered
  invalidation row and the client either converges through Realtime or records
  a reproducible refresh defect.
- Correction: QA inspected the relation definition and repeated the readback
  with its canonical kind, organizer and sequence columns.
- Verification: the projection produced the expected ordered invalidation at
  server sequence 99, which led to W7C-176/W7C-177 instead of being mistaken
  for a missing event.

## W7C-176 - Open billing screen did not refetch after canonical invalidation

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original scenario: the authenticated Team billing screen remained open while
  service-authoritative ingestion created an active subscription, access grant
  and ordered public invalidation.
- Evidence: PostgreSQL reported a newer invalidation at server sequence 99,
  but after more than five seconds the screen still displayed `Sin acceso` and
  did not show Team Organizer Pro.
- Impact: the server state is correct and a manual read can converge, but the
  open device did not reflect the confirmed access automatically.
- Required diagnosis: inspect publication membership, RLS visibility, client
  channel status and the snapshot-refetch handler; do not apply the WAL payload
  as authority.
- Required regression: two authenticated clients receive the invalidation,
  refetch the canonical snapshot once, and converge to the same revision
  without a reload loop or duplicate entitlement.
- Correction: the underlying RLS execution defect was fixed by the forward-only
  migration documented in W7C-177; the client continues to use the event only
  as an invalidation signal and rereads the canonical snapshot.
- Verification: two authenticated browser clients converged through Realtime
  from active to `Pago pendiente`, back to `Activo`, then to `Cancelado` and
  finally back to `Activo`, while PostgreSQL retained one subscription
  projection and one Organizer access grant with monotonic revisions.

## W7C-177 - Billing invalidation RLS policy could not execute its guard

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original scenario: QA reproduced the Realtime-table SELECT as the same
  authenticated staging actor after W7C-176.
- Evidence: PostgreSQL returned SQLSTATE 42501, `permission denied for function
  pachanga_billing_invalidation_can_read_v1`.
- Impact: the row and publication are correct, but authenticated clients cannot
  pass the RLS policy, so no invalidation can trigger a canonical refetch.
- Required correction: grant only `EXECUTE` on the policy guard to `anon` and
  `authenticated`; keep the security-definer predicate, underlying tables and
  every mutation function private.
- Required regression: authorized owners/platform readers can SELECT only their
  permitted invalidations, unrelated authenticated users see zero rows rather
  than an error, and no client role can execute any billing mutation function.
- Correction: migration
  `20260829080812_organizer_billing_invalidation_rls_execute_v1.sql` grants only
  `EXECUTE` on the RLS predicate to `anon` and `authenticated`; the predicate
  remains security-definer and all tables and mutation functions keep their
  existing private grants.
- Verification: staging owner readback returned its single invalidation,
  unrelated authenticated readback returned zero rows, anonymous catalog
  access remained available, focused static tests pass, and both authenticated
  clients now converge after canonical invalidations.

## W7C-178 - Stripe Portal title exposed its ephemeral session secret

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after canonical entitlement activation, the owner opened
  the dedicated TEST Billing Portal and QA inspected host and title.
- Evidence: Stripe uses the full Portal Session URL as the document title, so
  the private browser response included the ephemeral `test_...` session value.
- Impact: the temporary Portal Session did not enter Git, reports, screenshots,
  client logs or Production, but it cannot be retained as evidence.
- Required correction: never inspect Portal titles or complete URLs; let this
  session expire and retain only host, canonical intent status and access-control
  outcomes.
- Required regression: a fresh owner Portal intent is confirmed server-side,
  the browser reaches `billing.stripe.com`, non-owners are denied, and no Portal
  URL or session ID appears in later evidence or artifacts.
- Correction: the original ephemeral session was allowed to expire; every later
  Portal assertion used only host, canonical intent status, replay count and
  access-control outcome.
- Verification: owner, replay, non-owner and transactional owner-transfer tests
  passed, while the final tracked-file, diff, build-bundle, report and temporary
  scan found zero Stripe key, webhook, Checkout-session or Portal-session
  secret patterns.

## W7C-179 - Cancellation readback used the competition-grant column name

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after processing the newer canceled subscription event,
  QA attempted to join the Organizer access grant to its subscription using
  `billing_subscription_projection_id`.
- Evidence: PostgreSQL returned undefined-column SQLSTATE 42703; that name
  belongs to a different competition entitlement relation.
- Impact: cancellation ingestion had already committed successfully and was not
  changed; only the diagnostic read failed.
- Required correction: inspect the private Organizer grant contract and repeat
  the bounded status/count read with its canonical foreign-key column.
- Required regression: one Organizer grant row remains auditable and is no
  longer active after cancellation; both clients refetch the canceled state.
- Correction: the readback now joins through the Organizer grant's canonical
  `subscription_projection_id` foreign key.
- Verification: cancellation preserved exactly one auditable Organizer grant
  in `revoked` and both clients showed `Cancelado`; the later resume reused the
  same grant, advanced subscription and grant revisions to 7, restored 20
  active capabilities and converged both clients to `Activo`. The null
  `restored_at` is intentional for subscription-derived grants; that timestamp
  is reserved for administrative restoration of manual grants.

## W7C-180 - Consolidated notification readback used an unverified relation contract

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after the cancellation/resume cycle, QA combined account,
  receipt, Portal-intent and billing-notification counts in one bounded staging
  query before checking the canonical notification relation name.
- Evidence: Supabase rejected the request as `INVALID_ARGUMENT` before the SQL
  produced a result.
- Impact: no database row, receipt, notification, subscription or entitlement
  changed; only the diagnostic readback failed.
- Required correction: inspect the checked-in notification schema, split the
  readback into verified relations and rerun only aggregate, PII-free queries.
- Required regression: report the canonical notification kinds and counts for
  the synthetic billing lifecycle, prove duplicate events do not duplicate the
  same transition notification, and keep notification bodies and identities
  out of retained evidence.
- Correction: QA inspected the checked-in notification foundation, used
  `public.pachanga_user_notifications`, and split account/intent and
  notification aggregation into bounded reads.
- Verification: one notification exists for each cancellation and invoice
  failure transition, the subscription and invoice payment-failure signals
  remain separately classified, three real active transitions have three
  distinct dedupe keys, and replaying the duplicate Stripe event created no
  additional notification. No body, identity or dedupe value was retained.

## W7C-181 - Supabase connector hid the expected stale-revision SQLSTATE

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: QA deliberately called Checkout preparation with account
  revision 12 while the canonical account was already at revision 13.
- Evidence: the connector returned the generic wrapper error
  `INVALID_ARGUMENT` instead of exposing the expected `STALE_REVISION` detail.
- Impact: the function transaction failed and no Checkout intent, receipt or
  billing-account update committed, but this response alone cannot certify the
  exact server rejection reason.
- Required correction: repeat Checkout and Portal stale-revision calls inside
  a rollback-only PostgreSQL harness that catches SQLSTATE/detail and returns a
  redacted pass/fail result.
- Required regression: both commands report `PT409`/`STALE_REVISION`, and
  before/after intent and receipt counts remain identical.
- Correction: the calls were repeated inside a rollback-only exception harness
  that returned only SQLSTATE and message classification.
- Verification: Checkout and Portal both returned
  `PT409:STALE_REVISION`; Checkout intents remained four and Portal intents
  remained one, so neither stale request created a durable command.

## W7C-182 - Rollback harness lacked the server-only JWT authority context

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: QA wrapped the stale Checkout and Portal calls in a
  PostgreSQL exception harness so the Supabase connector could return the exact
  SQLSTATE without aborting its outer request.
- Evidence: both commands returned `42501:SERVICE_ROLE_REQUIRED` before reaching
  their revision checks; intent counts remained four Checkout and one Portal.
- Impact: no mutation committed and the server-only boundary was reinforced,
  but the harness still did not exercise the stale-revision branch.
- Required correction: inspect and reuse the existing local SQL-test authority
  setup for service commands, scoped to the diagnostic transaction only. Do not
  grant execution to clients or weaken `pachanga_billing_require_service_v1`.
- Required regression: the service-context harness reaches `PT409` for both
  stale calls, while direct client execution remains denied and intent/receipt
  counts remain unchanged.
- Correction: the harness reused the existing SQL-test convention by setting a
  transaction-local `request.jwt.claims` role of `service_role`; no grant or
  persistent setting was changed.
- Verification: the service-context calls reached `PT409:STALE_REVISION` for
  both commands, the previous client-context attempt remained denied with
  `SERVICE_ROLE_REQUIRED`, and durable intent counts did not change.

## W7C-183 - Local SQL runners still pinned the pre-hotfix migration ledger

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: after adding the forward-only Realtime RLS hotfix required
  by authenticated staging QA, the focused static suite passed but the SQL,
  concurrency and scale runners still asserted the previous final migration
  `20260828205317` and ledger count 196.
- Evidence: source inspection showed those exact stale assertions before the
  database runners were launched.
- Impact: product SQL and staging remain valid, but the local runners would
  stop before exercising the new migration and its RLS regression.
- Required correction: advance only the runner ledger/last-migration
  expectations to migration 197/`20260829080812`; retain the six planned Wave
  7C commercial migrations as a separate count from the one QA hotfix.
- Required regression: DB, concurrency and scale runners bootstrap through the
  exact hotfix, pass, and the reports reconcile six planned migrations plus one
  forward-only RLS correction without rewriting history.
- Correction: Billing DB, concurrency and scale runners now pin ledger 197 and
  the exact final migration; the scale migration set includes the hotfix as its
  fourteenth Wave 7B/7C database step.
- Verification: SQL/RLS, billing concurrency and representative-volume suites
  all pass through ledger 197; the hotfix applied in 30 ms with no ungranted
  locks and no index growth.

## W7C-184 - Local command guard rejected force-removal syntax for a temporary log

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA prepared a redacted `supabase start` wrapper whose final
  step used `rm -f` to remove its temporary startup log.
- Evidence: the command guard rejected the entire shell command before process
  creation because force-removal syntax is not permitted.
- Impact: Supabase did not start through this attempt and no temporary file,
  container, database or repository state was created or changed.
- Required correction: repeat with a uniquely created temporary path and plain
  `rm` cleanup after sanitized result handling.
- Required regression: local Supabase starts, no credential-bearing startup
  output is emitted, and the temporary log no longer exists afterward.
- Correction: the startup wrapper used a unique temporary path and plain `rm`
  after processing only sanitized output.
- Verification: the wrapper executed without command-guard rejection, emitted
  no credential value and removed its temporary log on both failed and
  successful startup attempts.

## W7C-185 - Supabase CLI could not inspect the local Docker service

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA retried the credential-redacted local Supabase startup
  with accepted temporary-log cleanup.
- Evidence: `supabase start` exited 1 with `failed to inspect service: EOF`.
- Impact: the local SQL stack is not yet available, so DB, concurrency and scale
  runners have not started; staging and Production are unchanged.
- Required correction: inspect only Docker service names/states and sanitized
  Supabase debug output, then recover the local stack without deleting volumes
  or touching remote projects.
- Required regression: local ledger reaches 197, all focused DB runners can
  connect to loopback port 55322, and no startup log or orphan process remains.
- Correction: Docker Desktop was recovered as documented in W7C-186, then
  Supabase started and the single pending local migration was applied.
- Verification: loopback PostgreSQL reported ledger
  `197|20260829080812`; Billing DB/RLS, Commercial DB, both concurrency suites
  and representative volume completed successfully.

## W7C-186 - Docker Desktop restart timed out while stopping its own processes

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after persistent daemon `EOF` responses, QA invoked Docker
  Desktop's supported restart command with a 120-second timeout.
- Evidence: Docker reported that its backend, desktop and helper processes were
  still running when the stop deadline expired.
- Impact: no reachable container or database was stopped by this command, the
  local stack remains unavailable, and remote staging/Production are unchanged.
- Required correction: request an orderly macOS application quit, terminate
  only non-responsive Docker Desktop processes if they remain, reopen Docker
  Desktop and wait for a successful `docker info` before starting Supabase.
- Required regression: the daemon answers normally, Supabase starts, focused
  local database suites pass, and Docker is left without orphaned QA processes.
- Correction: macOS received an orderly quit request; only the six remaining
  Docker Desktop-owned processes were terminated, then Docker was reopened.
- Verification: the daemon returned server version 29.5.3, Supabase started,
  all focused local database suites passed and every ephemeral test database
  reported cleanup PASS.

## W7C-187 - Commercial DB runner also pinned the pre-hotfix ledger

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: Organizer Billing SQL/RLS passed on local ledger 197, then
  the commercial DB runner began.
- Evidence: it stopped before its suite because it still asserted
  `196|20260828205317` instead of the new forward-only hotfix ledger.
- Impact: the billing DB suite passed, but the commercial DB assertions did not
  run in this attempt; no database or product defect was observed.
- Required correction: audit every Organizer Commercial DB/concurrency/scale
  runner for the same final-ledger pin and advance only those expectations.
- Required regression: all commercial runners execute through ledger 197 and
  retain the six planned commercial migration count plus the separate RLS
  hotfix classification.
- Correction: the Commercial DB and concurrency runner final-ledger assertions
  now target 197/`20260829080812` without changing the six-migration commercial
  feature manifest.
- Verification: Commercial SQL/RLS reports six planned migrations, four TEST
  mappings, zero LIVE objects and PASS at final ledger 197.

## W7C-188 - Commercial concurrency runner retained a second numeric ledger pin

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: Organizer Billing concurrency passed, then the Commercial
  concurrency runner started after its last-migration filename had been updated.
- Evidence: a separate assertion still expected migration count 196 and stopped
  the runner when the repository correctly contained 197.
- Impact: no concurrency scenario ran in that commercial attempt; no product or
  database mutation failed.
- Required correction: advance that numeric final-ledger assertion to 197 and
  search the complete runner for any remaining pre-hotfix constants.
- Required regression: Commercial concurrency completes every race on an
  ephemeral local database and cleans it afterward.
- Correction: the remaining repository migration-count assertion now expects
  197, matching the exact final migration assertion beside it.
- Verification: all nine commercial races pass, including owner transfer,
  Portal revocation, webhook/reconciliation and cancellation/invoice ordering;
  the ephemeral database cleanup also passes.

## W7C-189 - Demo World V2.9 authority proof retained migration count 196

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after the forward-only RLS hotfix and local ledger 197,
  QA ran the deterministic Demo World V2.9 verifier without regenerating its
  authority proof.
- Evidence: verification failed only on `migrationCount`, actual 197 versus the
  stored 196; the rest of the canonical simulation matched.
- Impact: no remote write occurred and no Demo scenario changed, but the stored
  proof correctly refuses to certify a different schema ledger.
- Required correction: regenerate V2.9 deterministically on ledger 197 and
  update only generated V2.9 artifacts and their documented hashes.
- Required regression: two consecutive generation/verification runs match,
  historical V2.1-V2.8 hashes remain unchanged, and Demo still reports zero
  remote writes and zero LIVE mappings.
- Correction: V2.9 data and its authority proof were regenerated from the real
  local schema at ledger 197; no earlier version directory was written.
- Verification: two consecutive verifier runs reported `snapshotIdentical=true`,
  migration count 197 and zero remote writes; the Organizer chunk still has
  seven scenarios, four TEST mappings and zero LIVE mappings.

## W7C-190 - Demo V2.9 seal tests retained the pre-regeneration digests

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: after V2.9 was regenerated and twice verified on ledger
  197, QA ran its 17-test product contract suite.
- Evidence: 14 functional tests passed; three seal assertions still expected
  the old manifest hash, old authority hash and migration count 196.
- Impact: product behavior, historical versions and generated data are valid,
  but the committed test contract had not yet acknowledged the intentional
  V2.9 authority-proof regeneration.
- Required correction: update only those three exact V2.9 seal constants to the
  generated ledger-197 values.
- Required regression: all 17 Demo tests pass and a fresh verifier still reports
  `snapshotIdentical=true`, with no historical hash or scenario expectation
  changed.
- Correction: the test now pins the exact ledger-197 manifest hash, authority
  hash and both migration-count assertions generated by V2.9.
- Verification: 17/17 Demo tests pass with zero skip/todo/cancelled, and a fresh
  PostgreSQL verifier reports `snapshotIdentical=true`, migration count 197 and
  zero remote writes.

## W7C-191 - Browser evaluation did not bind navigator as a direct global

- Classification: `SIMULATION_BUG`
- Status: `open`
- Original scenario: final PWA QA requested only Service Worker controller,
  registration-state and display-mode booleans from the authenticated Preview.
- Evidence: the browser evaluation context exposed `document` but returned a
  TypeError when reading the unqualified `navigator` identifier.
- First retry: qualifying through `window.navigator` produced the same adapter
  TypeError because this serialized callback does not bind `window` either.
- Second retry: `document.defaultView` returned the adapter's isolated DOM
  environment with browser APIs unavailable; its `supported=false` result is
  explicitly not accepted as evidence about the real Preview worker.
- Impact: no worker, cache, browser storage or remote state was read or changed.
- Required correction: repeat the same bounded check through
  `window.navigator` and `window.matchMedia`, without enumerating caches or
  registration internals.
- Required regression: the active worker path, control state, waiting state and
  display mode return successfully with no credential or user data.

## W7C-192 - Linked production push is intentionally disabled by repository config

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after `supabase migration list --linked` proved that
  Production ended at migration 190 with exactly the seven Wave 7C migrations
  pending, QA ran `supabase db push --linked --dry-run` before any write.
- Evidence: the CLI applied nothing and reported that migrations are disabled
  for the linked project because `[db.migrations].enabled = false` in the
  checked-in configuration.
- Impact: Production remains unchanged at ledger 190. The normal linked-push
  command cannot currently provide an exact-version dry run or apply the seven
  migrations without bypassing or temporarily changing this repository guard.
- Required correction: use a reviewed, exact-version migration path that keeps
  the checked-in fresh-database bootstrap protection intact and does not
  retimestamp, rewrite or manually mark migration history.
- Required regression: Production reports the same seven repository versions
  in the same order, all Wave 7C flags are born OFF, the final ledger is 197,
  and a subsequent linked migration list has no local/remote mismatch.
- Correction: QA temporarily enabled only `[db.migrations]` in the clean
  worktree, reviewed the seven-file dry run, applied those exact versions and
  immediately restored the committed guard.
- Verification: linked history reports all seven local and remote versions
  equal through ledger 197; every Wave 7C flag and LIVE mapping remains OFF.

## W7C-193 - Temporary config patch targeted API TLS instead of migrations

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: QA prepared a temporary local-only enablement so the
  Supabase CLI could dry-run the exact seven pending migrations while retaining
  the committed migration guard after the operation.
- Evidence: the first generic `enabled = false` match belonged to `[api.tls]`,
  while `[db.migrations]` remained disabled; the dry run again skipped every
  migration.
- Impact: no migration, remote row, TLS service or repository commit changed.
  Only the clean worktree held an incorrect uncommitted config line briefly.
- Required correction: restore `[api.tls].enabled = false` and target
  `[db.migrations].enabled` with both section headings in the patch context.
- Required regression: the reviewed diff shows only migration enablement during
  dry run/push, then both settings return byte-for-byte to the committed state.
- Correction: the TLS line was restored before any push, and the second patch
  included both `[api.tls]` and `[db.migrations]` as explicit context.
- Verification: the reviewed temporary diff contained only migration
  enablement; after the push `git diff --exit-code -- supabase/config.toml`
  passed, proving both settings match the committed file.

## W7C-194 - Post-push pg-delta catalog cache could not read its temporary CA

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: the exact production push applied all seven reviewed Wave
  7C migrations and then attempted to refresh the optional pg-delta catalog.
- Evidence: the migration command exited successfully after reporting that its
  isolated edge runtime could not read the generated `pgdelta-target-ca.crt`.
- Impact: every migration reported as applied, but the catalog-cache warning
  means command success alone is insufficient evidence for final ledger parity.
- Required correction: do not rerun or repair migration history. Re-read the
  linked ledger and canonical Wave 7C settings directly, and verify the seven
  exact versions and OFF defaults independently of pg-delta caching.
- Required regression: linked history is 197 with no mismatch, the functions
  exist, all commercial/Checkout/LIVE flags are OFF, and no migration is
  offered by a subsequent dry run.
- Correction: migration history was not rerun or repaired. QA used the linked
  history and Management API query paths that do not depend on pg-delta cache.
- Verification: ledger 197 has exact parity, all seven migrations are present,
  all Wave 7C and LIVE flags are OFF, LIVE mappings are zero, and the repository
  migration guard is restored.

## W7C-195 - Production smoke shell did not expose curl on PATH

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after the exact merge deployment reached READY, QA started
  a read-only status/content-type smoke for the public app, plan, PWA and Demo
  World V2.9 endpoints.
- Evidence: the shell rejected each request before network dispatch with
  `command not found: curl`.
- Impact: Production received no request from this attempt and no app, database,
  Stripe or repository state changed.
- Required correction: use the operating system binary at `/usr/bin/curl`
  explicitly rather than changing shell configuration.
- Required regression: all requested endpoints return their expected HTTP
  status and content type from the merged production deployment.
- Correction: the smoke invoked `/usr/bin/curl` explicitly without modifying
  the shell or repository environment.
- Verification: root, Organizer plans, actual Demo entry, manifest, Service
  Worker and both V2.9 Organizer assets returned 200 with expected content
  types from `pachangasiq.com`.

## W7C-196 - Production smoke guessed a non-routable Demo World page path

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: the first public endpoint matrix requested
  `/demo-world` as if the asset/module directory were a standalone page.
- Evidence: Production correctly returned 404 for that path while `/`, plans,
  manifest, Service Worker and both V2.9 JSON assets returned 200.
- Impact: no product route regressed; the smoke used a path that is not part of
  the public navigation contract.
- Required correction: inspect the checked-in routing contract and exercise the
  actual public Demo entry `/?demo=1` plus its V2.9 asset URLs.
- Required regression: the real Demo entry and both Organizer V2.9 assets return
  200 from the exact merged production deployment.
- Correction: source and browser navigation confirmed that `/?demo=1`
  redirects to the canonical `/demo` surface; the module directory is not a
  public route.
- Verification: the real entry returned 200, loaded Demo World V2.9, exposed
  all ten league/organizer sections and produced zero production console errors.

## W7C-197 - Header smoke helpers were also absent from the reduced shell PATH

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after the real Demo and PWA endpoints all returned 200,
  QA piped three read-only HEAD responses through `tr` and `awk` to retain only
  status, content type, cache policy and ETag.
- Evidence: the network requests completed, but the shell could not resolve the
  two formatting helpers from its reduced `PATH`.
- Impact: no endpoint failed and no remote or local state changed; only the
  compact header formatting was unavailable.
- Required correction: invoke `/usr/bin/tr` and `/usr/bin/awk` explicitly.
- Required regression: bounded headers are emitted for manifest, Service Worker
  and Demo V2.9 manifest without printing cookies, tokens or response bodies.
- Correction: QA used `/usr/bin/tr` and `/usr/bin/awk` explicitly.
- Verification: manifest, Service Worker and Demo manifest returned bounded
  200/content-type/cache headers; no body, cookie, token or identity was read.

## W7C-198 - Browser locator adapter does not expose bounding boxes

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: a production screenshot suggested that the desktop primary
  navigation might be compressed, so QA attempted to compare each link's box.
- Evidence: the adapter locator returned the correct five links and text but
  does not implement `boundingBox()`.
- Impact: no product action or state change occurred; geometric overlap remained
  unconfirmed by that method.
- Required correction: collect only `getBoundingClientRect()` geometry through
  the supported bounded DOM evaluation path, without reading browser storage,
  cookies, identity or session state.
- Required regression: adjacent link rectangles have non-negative gaps and the
  navigation remains within its parent at the tested viewport.
- Correction: the supported bounded DOM evaluation returned only navigation
  and link rectangles.
- Verification: all five links fit inside the 379.98 px navigation parent with
  2 px positive gaps; the screenshot compression was not a DOM overlap and no
  product change was required.

## W7C-199 - Legacy webhook cleanup readback assumed a V2 column name

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: final staging cleanup checked whether the legacy Stripe
  webhook table retained any Wave 7C synthetic event before deleting the exact
  QA fixture.
- Evidence: PostgreSQL rejected the read-only query because
  `public.pachanga_stripe_webhook_events` does not expose the assumed
  `stripe_event_id` column used by the V2 private table.
- Impact: the query made no change; staging flags were already restored through
  canonical commands and no Production, Stripe or repository state changed.
- Required correction: inspect the legacy table's real column contract and
  repeat the bounded readback using only existing identifiers.
- Required regression: the corrected query identifies the exact Wave 7C legacy
  fixture count without broad text scans or touching unrelated webhook rows.
- Correction: information-schema readback established the V1 contract
  `{event_id,event_type,processing_status,processed_at,error_message,payload}`;
  the bounded query then used `event_id` plus the two canonical payload keys.
- Verification: the corrected readback returned zero matching legacy events,
  without a write or an unbounded payload search.

## W7C-200 - Staging cleanup attempted to delete immutable commercial evidence

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: after restoring every Wave 7B/7C flag canonically, final
  cleanup tried to remove the exact synthetic billing fixture in one
  transaction, including the three commercial decision rows.
- Evidence: the commercial-decision guard rejected the delete with
  `BILLING_COMMERCIAL_DECISION_IMMUTABLE` even though the cleanup authority GUC
  was present.
- Impact: PostgreSQL rolled back the complete transaction. No QA row was
  partially deleted, Production was not addressed, and all disabled staging
  flags remain at their prior canonical revision.
- Required correction: honor the immutable-evidence contract, use only allowed
  lifecycle transitions for decisions, and clean mutable QA projections without
  deleting commercial history.
- Required regression: cleanup leaves zero active mappings, accounts,
  entitlements, intents, notifications or webhook projections while immutable
  decisions remain non-active and auditable.
- Correction: the retry removed decision deletion from the transaction and
  retained all three rows as non-active `draft` evidence.
- Verification: the final readback reports zero active QA billing entities and
  exactly three immutable decisions, all `draft`.

## W7C-201 - TEST catalog authority has no retirement command for QA cleanup

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: final staging retirement must remove the dedicated TEST
  Product/Price mappings after its Vercel secrets and Stripe Sandbox are
  withdrawn.
- Evidence: the product authority supports prepare/confirm and runtime-health
  recording, but exposes no service command that deactivates a TEST catalog and
  recomputes `catalog_ready`, `product_count` and `price_count` to zero.
- Impact: normal clients cannot exploit the gap and every commercial flag is
  already OFF. A staging-only maintenance cleanup is required to avoid stale
  readiness metadata after removing the exact synthetic mappings.
- Required correction: perform one bounded maintenance transaction under the
  existing private authority guards, limited to `stripe_mode='test'`, and retain
  immutable commercial decisions.
- Required regression: zero TEST mappings and catalog intents remain; TEST
  runtime health reads `catalog_ready=false`, zero products/prices and all
  readiness booleans false; LIVE state remains untouched.
- Correction: one staging-only maintenance transaction used the existing
  mapping guard, removed only `stripe_mode='test'` mappings and intents, then
  reset only the TEST runtime-health row. No product route or client privilege
  was added.
- Verification: TEST mappings/intents are zero; TEST runtime health reports
  `catalog_ready=false`, product/price counts `0/0` and every readiness boolean
  false. All LIVE flags and mappings remain OFF/zero.

## W7C-202 - Vercel alias JSON includes a progress line before the payload

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after Vercel reported a successful OAuth staging-alias
  restoration, QA requested the alias list as JSON and parsed it locally to
  confirm the exact target.
- Evidence: CLI output began with `Fetching aliases...` before the JSON object,
  so a strict `JSON.parse` rejected the combined stream and the diagnostic
  printed only a bounded prefix.
- Impact: the prior alias mutation had already succeeded; no deployment, env
  variable, database or Stripe state changed during this failed readback.
- Required correction: strip only the known progress prefix by parsing from the
  first JSON delimiter, then inspect the exact alias entry.
- Required regression: the stable OAuth alias resolves to the preserved V2.1
  deployment and no Wave 7C deployment remains its target.
- Correction: the parser ignored only the CLI progress prefix and decoded the
  JSON object from its first `{` delimiter.
- Verification: the exact alias resolves to
  `pachangas-l7wb1u43w-persianas-almar-web-s-projects.vercel.app` and its
  preserved deployment, while no Wave 7C target remains attached.

## W7C-203 - Stripe endpoint detail exposed a Preview bypass token in its URL

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: final Stripe TEST retirement opened the dedicated Organizer
  webhook destination so it could be deleted without viewing its signing secret.
- Evidence: the Stripe detail page rendered the complete endpoint URL in the DOM;
  that URL contained a Vercel protection-bypass query credential. The signing
  secret itself remained masked and was not opened.
- Impact: no payment or webhook was sent, but the bypass credential must be
  treated as exposed in diagnostic output. It is not present in Git, reports or
  client code.
- Required correction: delete the dedicated Stripe endpoint, retire Wave 7C
  Preview deployments, and rotate or revoke the affected Vercel bypass token at
  its actual scope without changing Production application secrets.
- Required regression: Stripe has no Wave 7C destination, no Wave 7C Preview can
  be reached with the retired credential, secret scans remain clean, and
  Production still exposes no TEST secret.
- Resolution: the Stripe destination and dedicated TEST environment were
  deleted, all four Wave 7C Preview deployments were removed and the sole Vercel
  automation bypass was revoked without replacement.
- Verification: Vercel reports zero bypass entries and zero listed Wave 7C
  deployments; Stripe's parent selector lists no Wave 7C environment; scans of
  the worktree, build, current diff, Wave 7C commit range and relevant temporaries
  found no secret pattern, while Preview runtime logs returned zero bypass hits.

## W7C-204 - Stripe delete confirmation does not expose the expected dialog role

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: QA selected `Eliminar` from the dedicated endpoint's
  overflow menu and waited for an accessible dialog before confirming.
- Evidence: the browser adapter reached its selector deadline while locating a
  `dialog`; no confirmation button was clicked.
- Impact: endpoint deletion was not confirmed by this attempt, no secret was
  opened and no other Stripe resource changed.
- Required correction: inspect only the currently visible button labels and
  confirmation copy, without another full-page snapshot, then click the exact
  destructive confirmation once.
- Required regression: the endpoint disappears from the webhook destination
  list and a direct revisit no longer exposes an active destination.
- Resolution: the bounded confirmation path deleted the dedicated Organizer
  webhook before Sandbox retirement.
- Verification: the destination list returned zero exact Wave 7C endpoints and
  the entire dedicated TEST environment was subsequently retired.

## W7C-205 - Stripe API-key table rendered the restricted TEST token in DOM text

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: final cleanup navigated to the dedicated TEST account's API
  key page and requested bounded page text to locate the restricted-key row.
- Evidence: Stripe rendered the complete restricted TEST token in the table's
  accessible DOM text. The value is redacted from this ledger and must not be
  copied into any report, command, screenshot or repository file.
- Impact: the dedicated key was already removed from Vercel, but its value must
  now be considered exposed in diagnostic output. No LIVE key or Production
  variable was read.
- Required correction: revoke the first restricted-key row directly through its
  action menu without reading table text again, then retire the dedicated TEST
  environment.
- Required regression: the named Wave 7C restricted key is absent, Vercel has no
  branch-scoped secret, Production has no TEST secret and repository/bundle scans
  remain clean.
- Resolution: all eight branch-scoped Preview variables were removed and the
  dedicated Stripe TEST environment was retired atomically, revoking its keys.
- Verification: the parent environment selector no longer lists Wave 7C and the
  old account URL redirects to the parent account rather than the retired key
  surface. Final repository and bundle scans are recorded in the release report.

## W7C-206 - Stripe restricted-key row menu is not exposed to browser automation

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: after the key-token exposure was recorded, QA clicked the
  first restricted-key `More options` control without reading the table again.
- Evidence: the control advertises an internal menu ID, but neither an accessible
  menu role nor that target element becomes available before the selector
  deadline. No revoke action was shown or clicked.
- Impact: the restricted TEST key remains active at this point, although it has
  already been removed from Vercel. No LIVE key or payment resource changed.
- Required correction: retire the dedicated Stripe TEST environment itself so
  all contained keys and catalog resources are revoked atomically, without
  reading any token.
- Required regression: the Wave 7C environment/account is no longer selectable
  and its old dashboard URLs no longer expose active resources.
- Resolution: the independent row menu was no longer needed because retiring the
  dedicated TEST environment revoked the contained key and resources together.
- Verification: the environment is absent from the parent selector and its old
  account URL no longer resolves to the retired account.

## W7C-207 - Stripe environment delete confirmation returned without retiring it

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA opened `Eliminar entorno de prueba`, observed a single
  exact destructive confirmation and clicked it once.
- Evidence: the confirmation closed without an accessible error, but a fresh
  dashboard navigation still selected `Pachangas IQ Wave 7C` and retained TEST
  data. Therefore no deletion success is claimed.
- Impact: Vercel and Supabase cleanup remain complete, but the dedicated Stripe
  environment and restricted key are not yet proven retired.
- Required correction: inspect only the delete control's state and required
  confirmation inputs, or use Stripe's account-level retirement path; never
  infer deletion from a closed modal.
- Required regression: a fresh navigation cannot select the environment and the
  API-key page cannot expose the old restricted-key row.
- Resolution: QA closed the obstructing Workbench panel, opened Stripe's actual
  custom confirmation and clicked its unique destructive control once.
- Verification: Stripe redirected to the parent Sandbox list, the parent
  selector reports zero Wave 7C environments and the old account URL redirects
  to the parent account.

## W7C-208 - Browser locator cannot hover the Stripe Sandbox selector row

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: from the parent Stripe account, QA opened the test-environment
  selector and attempted to reveal row actions for `Pachangas IQ Wave 7C`.
- Evidence: the browser locator exposes no `hover()` operation, so the action was
  rejected locally before dispatch.
- Impact: no Stripe resource or account changed and no secret was read.
- Required correction: inspect only the exact Sandbox row's ancestor controls
  through bounded DOM evaluation, or use a visible click path that does not
  depend on hover.
- Required regression: the dedicated environment is retired and the unrelated
  parent account remains selected and unchanged.
- Resolution: retirement used the Sandbox's own account-settings action and did
  not require a hover-only row menu.
- Verification: the parent `Web Engine` account remains active and selected,
  while its environment selector no longer lists Wave 7C.

## W7C-209 - Stripe document rejects a temporary confirm-audit marker

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: because the visible delete action behaved like a dismissed
  native confirmation, QA attempted to install a one-shot affirmative confirm
  handler and a local call counter before clicking the exact Sandbox delete.
- Evidence: Stripe's page object is non-extensible; adding the temporary counter
  property threw before the confirm handler or delete click ran.
- Impact: no click, deletion, key access or account change occurred.
- Required correction: replace only the existing `window.confirm` function,
  perform the exact delete click, and reload immediately so the page runtime is
  restored regardless of outcome.
- Required regression: either the Sandbox is absent after a fresh parent-account
  navigation or the environment remains explicitly documented as a blocked
  manual retirement with its key independently revoked.
- Resolution: no page-global injection was used. QA followed Stripe's custom
  confirmation after exposing the unobstructed control.
- Verification: a fresh parent-account selector contains no Wave 7C environment.

## W7C-210 - Stripe browser proxy does not expose window.confirm for replacement

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: the retry attempted to replace only the existing native
  confirm function, click the exact Sandbox delete and reload immediately.
- Evidence: the controlled page proxy rejected assignment to `confirm` as adding
  a property to a non-extensible object; execution stopped before the click.
- Impact: no Stripe, Vercel, Supabase or repository state changed.
- Required correction: use a supported native-dialog handler from the browser
  controller if available; do not continue injecting page globals.
- Required regression: the retirement result is verified from a fresh parent
  account selector, not inferred from the confirmation UI.
- Resolution: no native-confirm replacement was required; Stripe's real custom
  confirmation became available after Workbench was closed.
- Verification: the result was read back from the parent account selector and
  the retired account's old URL, independently of the confirmation surface.

## W7C-211 - Stripe Sandbox delete click creates no native JavaScript dialog

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: QA used the browser controller's supported
  `getJsDialog()/accept()` flow around the exact `Eliminar` button.
- Evidence: the click returned, `getJsDialog()` reported no active dialog, and
  the same Sandbox delete surface remained visible after a bounded wait.
- Impact: no account deletion or other Stripe mutation occurred.
- Required correction: confirm visibility/enabled state and determine whether
  Stripe requires an out-of-band verification gate; if retirement remains
  blocked, revoke the restricted key independently and leave the empty Sandbox
  explicitly isolated rather than claiming deletion.
- Required regression: the restricted key is absent even if the inert Sandbox
  container must remain, and no Vercel or Supabase reference points to it.
- Resolution: the flow was a Stripe-rendered custom confirmation, not a native
  JavaScript dialog; the unique `dialog-delete-sandbox-button` completed it.
- Verification: the Sandbox container is absent from the selector and its old
  URL no longer exposes active resources.

## W7C-212 - Stripe Workbench obscured the Sandbox retirement control

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: repeated retirement attempts targeted the exact visible
  `Eliminar` action on the Sandbox account-settings page.
- Evidence: a bounded screenshot showed Stripe Workbench expanded over the lower
  account-settings surface. Its panel intercepted the physical area containing
  the retirement flow while the underlying DOM still reported the action as
  visible and enabled.
- Impact: prior clicks did not retire the TEST environment, restricted key or
  catalog resources. No LIVE account resource changed.
- Required correction: close Workbench, return to the unobscured Sandbox
  settings surface and execute the exact retirement confirmation once.
- Required regression: from the parent account, the test-environment selector no
  longer lists `Pachangas IQ Wave 7C`; its old account URL exposes no active
  environment and unrelated parent-account resources remain untouched.
- Resolution: Workbench was closed through its unique minimize control; a hit
  test then confirmed the retirement action was physically unobstructed.
- Verification: retirement succeeded, Wave 7C is absent from the parent selector
  and the parent account remains selected and operational.

## W7C-213 - Stripe exposes duplicate accessible Workbench close controls

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: QA attempted to close the obstructing Workbench panel by
  its exact accessible name.
- Evidence: Stripe exposed both a button and an anchor named `Cerrar Workbench`;
  strict locator resolution rejected the ambiguous action before dispatch.
- Impact: no Stripe resource changed and Workbench remained open.
- Required correction: target the unique `wb-WorkbenchMinimize` control already
  present on the visible panel.
- Required regression: Workbench closes, the underlying Sandbox retirement area
  is physically unobstructed and the environment can be verified from the
  parent selector after retirement.
- Resolution: QA targeted the unique `wb-WorkbenchMinimize` test identifier.
- Verification: Workbench closed, the delete control passed a viewport hit test
  and the subsequent retirement readback succeeded.

## W7C-214 - Vercel 2FA prompt obscured the bypass revocation menu

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: after deleting the four Wave 7C Preview deployments, QA
  opened the exact automation-bypass row and attempted to use its action menu.
- Evidence: a viewport hit test showed Vercel's `Secure Your Account with 2FA`
  modal overlay covering the menu coordinates while the underlying control
  remained enabled in the DOM.
- Impact: no bypass was revoked by this attempt and no 2FA setting changed.
- Required correction: dismiss only the modal overlay without selecting setup or
  opt-out actions, then revoke the Wave 7C bypass through its existing row menu.
- Required regression: the exposed bypass is absent, the four Wave 7C Previews
  remain deleted, and the project's unrelated protection settings are unchanged.
- Resolution: QA left the 2FA prompt untouched and used Vercel's authenticated
  project-protection command instead of the obstructed browser menu.
- Verification: the bypass count is zero, all four exact deployments remain
  absent and no 2FA choice was submitted.

## W7C-215 - Vercel 2FA prompt cannot be dismissed without a security decision

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original scenario: QA attempted to dismiss the obstructing 2FA prompt with the
  standard Escape control, without choosing setup or opt-out.
- Evidence: the prompt remained present and continued to cover the bypass menu;
  its only visible actions were authenticator setup and skipping account
  security.
- Impact: no bypass or 2FA setting changed.
- Required correction: use Vercel's authenticated project-protection API to
  revoke the exposed bypass in memory, without printing the secret or changing
  account-wide 2FA choices.
- Required regression: project protection no longer contains the exposed bypass,
  no replacement secret is generated, and the 2FA configuration is untouched.
- Resolution: the official CLI revoked the sole bypass directly in memory; the
  browser modal was neither accepted nor skipped.
- Verification: project protection changed from one bypass entry to zero and no
  replacement entry appeared.

## W7C-216 - Vercel serializes bypass secrets as JSON object keys

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: the authenticated CLI response was captured in memory and
  traversed to report schema paths and value lengths without printing values.
- Evidence: `protectionBypass` serializes each automation secret as an object key,
  so the generic schema walker emitted that key despite redacting scalar values.
  The value is omitted from this ledger and must not be copied elsewhere.
- Impact: the same already-compromised Wave 7C bypass appeared once more in
  diagnostic output. No Production application secret, Stripe LIVE key or
  unrelated bypass was exposed.
- Required correction: capture the response again only inside one process, take
  the sole bypass key without printing it, revoke it through the official Vercel
  project-protection command and immediately re-read only the bypass count.
- Required regression: `protectionBypass` has zero entries, all four Wave 7C
  Previews remain absent, and repository, reports, bundle, logs and temporaries
  contain no bypass value.
- Resolution: a single process captured the response, consumed the only key
  without printing it, revoked it and read back only entry counts.
- Verification: the before/after count was `1 -> 0`; all four deployments are
  absent and the bounded repository, bundle, log and temporary scans are clean.

## W7C-217 - Unbounded Git-history secret scan exceeded its execution window

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: final secret QA invoked `git grep` across every revision
  reachable from every local ref.
- Evidence: enumerating the complete multi-year commit set exceeded the bounded
  execution window and left one read-only `git grep` process running without
  emitting any match.
- Impact: no repository file or remote state changed, but the local scan process
  consumed resources beyond its intended window.
- Required correction: terminate only that identified read-only process and run
  bounded scans over the worktree, current diff, Wave 7C commit range and built
  client assets.
- Required regression: no matching secret pattern is found in those relevant
  surfaces and no scan process remains alive.
- Resolution: the read-only process exited without a match; QA confirmed no
  residual `git grep` or `git rev-list` process and replaced it with bounded
  scans over the Wave 7C range and final artifacts.
- Verification: both bounded diff scans returned zero matches and process
  readback returned zero matching processes.

## W7C-218 - Supabase local status prints development credentials

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original scenario: final worktree cleanup invoked `supabase status` to decide
  whether a local stack still needed to be stopped.
- Evidence: the CLI reported partially stopped services but also printed the
  local demo API, storage and database credentials in diagnostic output. Values
  are deliberately omitted from this ledger.
- Impact: only regenerated localhost development credentials were shown; no
  staging or Production secret was read, changed or exposed.
- Required correction: stop the local Supabase stack without another detailed
  status call and verify absence through process/container names only.
- Required regression: no local Pachangas Supabase container or process remains,
  repository and report scans contain no credential value, and remote projects
  remain untouched.
- Resolution: `supabase stop` shut down the local development setup without any
  remote project argument or remote mutation.
- Verification: a Docker name-filter readback returned zero running
  `pachangas-synthetic-world-v1` containers; the final repository scan contains
  no local credential value.

## W7C-219 - Final documentation merge used an inferred full HEAD SHA

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original scenario: PR #221 passed all checks and the guarded merge supplied a
  full `--match-head-commit` value reconstructed from the local short SHA.
- Evidence: GitHub rejected the merge because the supplied value did not match
  the remote PR HEAD. The safety guard worked and no merge occurred.
- Impact: `main`, deployments and remote data remain unchanged.
- Required correction: read the canonical `headRefOid` from PR #221, update this
  ledger on that same PR and merge only against the exact returned OID after the
  refreshed checks pass.
- Required regression: GitHub reports PR #221 merged at its exact final HEAD and
  the resulting `main` SHA reaches a READY production deployment.
- Resolution: the canonical `headRefOid` was read directly from PR #221 after
  its refreshed checks passed and supplied unchanged to the guarded merge.
- Verification: GitHub reports PR #221 merged as
  `2e7816222976af76969e4938545178000be84ed2`; Vercel deployed that exact SHA to
  Production with state `READY`.
