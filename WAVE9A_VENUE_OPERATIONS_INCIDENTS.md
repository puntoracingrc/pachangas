# Wave 9A Venue Operations Incidents

## Checkpoint

- Initial `origin/main`: `056414a8967933c2d839b0e27e39ae00d1fcc572`.
- Supabase ledger baseline: 212 migrations.
- Test baseline: 20 Node + 662 TS/TSX = 682/682.
- Skipped / todo / cancelled: 0 / 0 / 0.
- Global lint baseline: 0 errors / 0 warnings.
- Demo World baseline: V3.3 live; V3.2 authority must remain unchanged.
- Real entities, external notifications, Stripe operations and Demo remote writes: 0.

## Classification

Every issue discovered during Wave 9A is recorded before correction as one of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

Fixed issues must include the original reproducer and finish with
`fixed + regression_verified`.

## Ledger

### W9A-001 - Diagnostic cleanup command rejected

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: the first ad-hoc ephemeral PostgreSQL compile command
  included shell `rm -f` cleanup and was rejected by the command safety layer
  before any database or repository mutation occurred.
- Impact: no product state, local database or migration was changed.
- Correction: replaced the ad-hoc shell with the permanent
  `tests/venue-operations-v1-db-runner.mjs`, which owns database creation,
  schema comparison and cleanup through bounded Node/PostgreSQL operations.
- Regression: the runner verifies both 212 -> 220 upgrade and fresh bootstrap,
  then proves both temporary databases and its infrastructure dump are removed.

### W9A-002 - Public consent had no canonical tariff source

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the first Venue/Pitch schema exposed
  `publicRateAllowed` in publication consent, but contained no canonical Pitch
  tariff fields from which the public projection could safely render `FREE`,
  `FIXED_QUOTE`, `NEGOTIABLE` or `CONTACT_CLUB`.
- Impact: a consent could authorize a field that no authoritative read model
  was capable of producing.
- Correction and regression: add informational, non-payment Pitch tariff fields;
  expose them only when the current Venue consent explicitly permits public
  rate display; cover the redaction path in SQL and contract tests.

### W9A-003 - Session timezone could corrupt the stored Venue offset

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: request/read-model code used
  `extract(timezone from timestamptz)`, whose result follows the PostgreSQL
  session timezone instead of the canonical Venue IANA timezone.
- Impact: an otherwise correct instant could expose or persist a wrong
  `resolvedOffsetMinutes`, especially around Europe/Madrid DST transitions.
- Correction and regression: calculate offset from the difference between the same
  instant rendered in the Venue timezone and UTC; cover winter, summer,
  nonexistent and duplicated local hours.

### W9A-004 - Synthetic referee used a non-canonical source identifier

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the first functional DB run attempted to seed a
  `competition_generated` referee assignment with the descriptive source ID
  `wave9a-r4d-referee`. The production assignment trigger rejected it with
  `REFEREE_CANONICAL_MATCH_REQUIRED` before the Wave 9A assertions ran.
- Impact: no product authority was bypassed; the isolated fixture failed fast
  and both ephemeral databases were removed by the runner.
- Correction and regression: point the synthetic assignment at the canonical
  published schedule item already bound to the target CanonicalMatch, then
  rerun the full fixture from an empty ephemeral database.

### W9A-005 - Synthetic match rule did not enable referee assignments

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after correcting the source identifier, the isolated
  assignment seed was rejected with
  `REFEREE_ASSIGNMENTS_DISABLED_BY_RULE_REVISION`. The inherited historical R5
  rule fixture predates the later canonical referee-policy document.
- Impact: the production policy guard remained fail-closed; no assignment or
  Venue row was written and the runner removed the temporary databases.
- Correction and regression: append a new synthetic RuleRevision carrying the
  canonical `operations.refereePolicy`, point only the target synthetic match
  context to that revision and enable the existing private-beta assignment gate
  before seeding the confirmed official. The original revision remains frozen.

### W9A-006 - Synthetic referee attempted a retired direct-write path

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after creating the valid synthetic RuleRevision, the
  fixture still inserted the assignment row directly. The canonical transition
  trigger rejected it with `REFEREE_LEGACY_ASSIGNMENT_WRITE_DISABLED`.
- Impact: the old assignment mutation path remained unreachable and no
  assignment or Venue operation was persisted.
- Correction and regression: create the synthetic official exclusively through the
  existing `assignment.propose -> assignment.accept -> assignment.confirm`
  RPC lifecycle before exercising the R4D Venue replacement.

### W9A-007 - Synthetic referee policy omitted the organizer owner role

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the first canonical `assignment.propose` call resolved
  the fixture organizer as `competition_owner`, while the synthetic policy
  allowlisted only `competition_director`; the policy guard returned
  `REFEREE_PROPOSER_ROLE_NOT_ALLOWED`.
- Impact: proposal creation remained fail-closed and no product data was
  written outside the disposable database.
- Correction and regression: include the existing canonical `competition_owner` role
  in the synthetic RuleRevision proposer policy and rerun the complete path.

### W9A-008 - Synthetic referee proposal used a non-canonical fee mode

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the canonical proposal reached its terms parser with
  `feeMode=CONTACT_REFEREE`; that value is not part of the existing assignment
  terms contract and was rejected as `REFEREE_ASSIGNMENT_TERMS_INVALID`.
- Impact: no assignment was created and the isolated run was rolled back.
- Correction and regression: use the already-supported synthetic `FIXED` terms shape
  with an explicitly non-payment amount and currency; Stripe remains untouched.

### W9A-009 - DST regression expected the wrong canonical error label

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the nonexistent Europe/Madrid hour was correctly
  rejected as `VENUE_LOCAL_TIME_DOES_NOT_EXIST`, while the new assertion
  expected the unused label `VENUE_LOCAL_TIME_NONEXISTENT`.
- Impact: timezone authority behaved correctly; only the test matcher failed.
- Correction and regression: assert the canonical error emitted by the resolver and
  retain the same March transition input as the permanent regression.

### W9A-010 - Reservation command variables collided with request columns

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the canonical Club counterproposal reached the
  `reservation.counter` update and PostgreSQL rejected the unqualified
  `pitch_id` expression as ambiguous between the PL/pgSQL variable and the
  request table column.
- Impact: a valid counterproposal could not be persisted; no partial request,
  hold, reservation or notification was produced because the command is
  transactional.
- Correction and regression: qualify command-local pitch and time variables at every
  request update boundary. The full counterproposal/acceptance lifecycle is
  the permanent regression.
- Correction attempt note: qualifying locals with the function name is valid
  for parameters but not local declarations; PostgreSQL returned a missing
  FROM-clause error. The final fix uses an explicit PL/pgSQL block label.

### W9A-011 - Private reservation terms survived inside nested snapshots

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after a requester confirmed the Club counterproposal,
  `get_pachanga_venue_reservation_v1` removed the `private_notes` column but
  returned the same text through `terms_snapshot` and
  `request.current_proposal.terms.privateNotes`.
- Impact: an authorized requester could read an internal Club note that was
  not part of the agreed public terms. Public directory projections remained
  redacted.
- Correction and regression: build an explicit safe terms projection, remove the raw
  terms snapshot and strip nested private notes from the request proposal.
  The confirmed-reservation privacy assertion is the regression.

### W9A-012 - Match binding variable collided with the binding column

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after a confirmed reservation entered
  `reservation.bind_match`, the unique-binding guard compared the table column
  to an unqualified `canonical_match_id`; PostgreSQL rejected the ambiguous
  identifier before creating a binding.
- Impact: no duplicate binding was possible, but the valid first binding was
  also blocked transactionally.
- Correction and regression: qualify the command-local CanonicalMatch ID at every
  lookup, insert and reservation update. The unique initial binding plus R4D
  replacement assertions are the regressions.

### W9A-013 - Synthetic RuleRevision omitted the canonical R4D policy

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the first `reservation.replace_venue` delegated to the
  real R4D command, which rejected the synthetic RuleRevision with
  `R4D_RULE_POLICY_REQUIRED` because it carried referee policy but no
  `operations.exceptionPolicy`.
- Impact: R4D remained fail-closed and neither the old nor new binding changed.
- Correction and regression: compose the established R4D exception policy into the
  appended synthetic RuleRevision and rerun replacement, lineage and referee
  reconfirmation together.

### W9A-014 - Synthetic hold expiry violated the creation-time invariant

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the expiry regression moved only `expires_at` to one
  second before the database clock while leaving `created_at` unchanged. The
  canonical hold constraint correctly rejected `expires_at <= created_at`.
- Impact: the product invariant remained intact, but the disposable database
  could not reach the service expiry worker assertion.
- Correction and regression: move the synthetic hold creation and expiry timestamps
  together while preserving `created_at < expires_at < server time`. The same
  worker replay, claim release and request convergence checks remain the
  permanent regression.

### W9A-015 - Ledger assertion counted rejected intents and idempotent replays

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the final SQL assertion expected 30 Venue events and
  receipts. The scenario contains 26 accepted top-level intentions plus one
  deterministic hold-expiry child operation; rejected stale/conflicting
  requests and repeated `operationId` calls correctly create no new rows.
- Impact: every accepted operation remained paired and ordered, but the suite
  failed after completing the canonical lifecycle.
- Correction and regression: assert the exact 27 accepted operations and retain the
  equality of event count, receipt count and matching `server_sequence` as the
  permanent ledger regression.

### W9A-016 - Outsider read test resolved its fixture after dropping table access

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after switching to the `authenticated` database role,
  the negative read assertion selected a reservation ID directly from the
  protected reservations table as the RPC argument. PostgreSQL rejected that
  fixture lookup before invoking the `SECURITY DEFINER` read model.
- Impact: direct table access was correctly closed, but the test could not
  distinguish that guard from the canonical `VENUE_RESERVATION_READ_FORBIDDEN`
  response.
- Correction and regression: capture the synthetic reservation ID in a temporary
  reference before lowering privileges, grant only that disposable reference
  to the test role and rerun both direct-write and outsider-read assertions.

### W9A-017 - Wave 9A policy was grafted onto an immutable published schedule

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the fixture replaced only the RuleRevision of an
  inherited published MatchContext. At transaction commit, the deferred
  competition relation trigger detected that its round and ScheduleItem still
  belonged to the original RuleRevision and raised
  `COMPETITION_GENERATED_CONTEXT_INVALID`.
- Impact: all Venue assertions completed, but PostgreSQL correctly refused to
  commit an internally inconsistent synthetic competition graph.
- Correction and regression: preserve the inherited fixture and create a separate,
  internally consistent Wave 9A schedule plan, revision, round, slot,
  ScheduleItem, CanonicalMatch, binding and MatchContext using the new frozen
  policy. R4D replacement and referee reconfirmation will target that graph.

### W9A-018 - Synthetic schedule duplicated an active competition scope

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the first isolated Wave 9A SchedulePlan reused the
  exact edition, stage, category, division and competition-group scope of the
  inherited published plan. The active-scope unique index rejected it.
- Impact: no duplicate schedule authority was created; fixture setup stopped
  before any Venue operation ran.
- Correction and regression: keep the same synthetic competition and entries but use
  the valid no-group schedule scope consistently across plan, round, slot and
  MatchContext. The deferred relation checks remain enabled.

### W9A-019 - Synthetic Venue match overlapped an inherited team fixture

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the isolated Wave 9A MatchContext used the same teams
  and March 15 window as an inherited league fixture. During
  `reservation.replace_venue`, R4D correctly rejected the duplicate sporting
  schedule with `VENUE_SLOT_CONFLICT`.
- Impact: neither Venue binding nor the existing schedule changed; the
  replacement transaction rolled back.
- Correction and regression: move the isolated match to a free Monday in the same
  rule window and use the canonical Europe/Madrid summer offset consistently
  in schedule, requests and reservations.

### W9A-020 - Concurrency runner committed the Club fixture too early

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: `node tests/venue-operations-v1-concurrency.mjs`
  loaded `venue-operations-v1-fixture.sql` without one enclosing transaction.
  The deferred Club ownership guard therefore ran after the Club insert and
  before the immediately following primary-owner membership insert, raising
  `CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED`.
- Impact: the disposable database was cleaned correctly, but none of the
  twelve concurrency races started. Product SQL and shared data were not
  modified.
- Correction and regression: load the deterministic fixture in one transaction,
  as the canonical DB suite already does. All twelve races and database cleanup
  now pass.

### W9A-021 - Synthetic owner insert assumed a non-existent membership key

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after fixing W9A-020, the concurrency runner attempted
  `ON CONFLICT (club_id,user_id,role)` while adding its replacement owner.
  Memberships preserve temporal history and intentionally have no matching
  unique constraint, so PostgreSQL rejected the fixture statement.
- Impact: setup stopped before product commands or races ran; the ephemeral
  database was destroyed.
- Correction and regression: insert the guaranteed-new synthetic membership
  directly. The owner-transfer versus reservation-acceptance race is the
  permanent regression.

### W9A-022 - Concurrency fixture used an out-of-policy referee deadline

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: assignment setup sent a fixed May 2027 response
  deadline. From the August 2026 execution date this exceeded the canonical
  maximum of 30 days and the referee RPC raised
  `INVALID_ASSIGNMENT_DEADLINE`.
- Impact: the referee guard worked as designed and setup stopped before Venue
  races; no data escaped the disposable database.
- Correction and regression: derive the synthetic deadline as ten days after
  the runner starts, retaining the production deadline guard.

### W9A-023 - Expired hold fixture violated its own temporal invariant

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the hold-expiry race moved only `expires_at` into the
  past. The canonical constraint requires expiry after creation, so PostgreSQL
  rejected a row whose synthetic expiry preceded its unchanged creation time.
- Impact: four races had completed inside the disposable database, but the
  fifth fixture could not be prepared and all state was cleaned.
- Correction and regression: move synthetic `created_at` two minutes back and
  `expires_at` one second back together. Expiry versus accept now converges to
  one expiry winner and one stale acceptance.

### W9A-024 - R4D fixture invented a non-canonical Venue reason

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the setup replacement used
  `CONCURRENCY_PREPARE_REPLACEMENT` and the actual R4D command rejected it with
  `R4D_VENUE_REASON_INVALID` because sporting Venue changes use a closed reason
  catalogue.
- Impact: races before the R4D sequence ran, while the replacement transaction
  rolled back and the disposable database was removed.
- Correction and regression: use canonical `PITCH_UNAVAILABLE` in both
  preparatory and concurrent replacements without widening product policy.

### W9A-025 - Synthetic referee could not serve the replacement Venue

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: after a valid R4D replacement, the referee attempted
  `assignment.reconfirm`, but its inherited synthetic service area did not
  include the newly created concurrency Venue. The transition guard raised
  `REFEREE_SERVICE_AREA_INCOMPATIBLE`.
- Impact: R4D correctly requested reconfirmation and the referee authority
  correctly refused an incompatible field operation; no shared state changed.
- Correction and regression: name the disposable Venue inside the referee's
  existing Barcelona/Pista service area. The compatibility guard remains
  unchanged and the R4D versus reconfirmation race now passes.

### W9A-026 - Maintenance race omitted the canonical rejection code

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: the maintenance command won and the delayed reservation
  acceptance failed with `VENUE_PITCH_NOT_AVAILABLE`, but the test matcher only
  listed two synonymous, non-emitted variants.
- Impact: product convergence was correct; the runner rejected valid evidence
  after the race.
- Correction and regression: accept the exact canonical error code while still
  asserting one successful maintenance transition plus one rejected
  acceptance.

### W9A-027 - User reservation read model hid its next canonical action

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: inspect the response contract of
  `get_pachanga_my_venue_reservations_v1()` for a request in
  `COUNTER_PROPOSED` or `HELD`.
- Impact: the read model removed private notes correctly, but also removed the
  complete current proposal and exposed no hold projection. A compatible
  client could identify the high-level status but could not show the proposed
  slot, hold expiry or next action without querying tables directly.
- Correction and regression: the canonical read now includes a
  privacy-filtered proposal and latest hold while keeping messages, claim IDs
  and Club-only notes out of the payload. The ephemeral PostgreSQL suite
  creates an active hold, reads it as its requester and verifies both the next
  action and the excluded fields.

### W9A-028 - Club desk omitted availability and review context

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: inspect `get_pachanga_club_venue_desk_v1()` as a
  `club_booking_manager` after creating a template, an exception and a
  reservation request with a requester message.
- Impact: the authorized Club desk returned Venues, Pitches and high-level
  reservations, but no availability templates, exceptions, Match bindings or
  maintenance conflicts. It also removed the requester message required to
  review a legitimate request.
- Correction and regression: the authorized Club desk now includes templates,
  exceptions, request review context, Match bindings and maintenance conflicts.
  The SQL suite verifies all collections plus the exact requester message;
  public projections and requester caches remain unchanged.

### W9A-029 - Club desk regression targeted the wrong synthetic Club

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: `node tests/venue-operations-v1-db-runner.mjs` after
  adding the W9A-028 regression.
- Impact: the booking manager belongs to synthetic Club `e902...`, but the new
  assertion requested the desk of inherited R4D Club `c402...`. The canonical
  ACL correctly returned `VENUE_CLUB_DESK_AUTHORITY_REQUIRED`; no product data
  or permissions changed.
- Correction and regression: the test queries Club `e902...` for its valid
  read and explicitly preserves the rejected cross-Club `c402...` call.

### W9A-030 - Venue API shared helper resolved policy from the wrong depth

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: `npm run typecheck`.
- Impact: `app/api/venues/_shared.ts` resolved `client-policy` as though it
  lived inside a nested route, so TypeScript could not build the new API.
- Correction and regression: the helper now imports the actual sibling policy
  module; the complete TypeScript check passes.

### W9A-031 - Status label mixed nullish and boolean precedence

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: `npm run typecheck`.
- Impact: TypeScript rejected a status-label expression that combined `??`
  and `||` without explicit grouping. No runtime bundle was produced.
- Correction and regression: the empty fallback is explicitly grouped and the
  complete TypeScript check passes.

### W9A-032 - Club Realtime reconciliation retained the initial Club

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open the Club Venue desk with access to two Clubs,
  change the selected Club and then receive a
  `pachanga_venue_invalidations` event.
- Impact: the Realtime callback closed over the Club selected during the
  initial mount, so it could replace the visible desk with the first Club's
  canonical snapshot after the user had moved to another Club.
- Correction and regression: reconciliation now reads the currently selected
  Club from a stable ref. The UI regression verifies that the callback no
  longer calls `loadDesk(initialClub, ...)` and uses the selected-Club ref.

### W9A-033 - Stale reservation detail checked previous React message state

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: submit a reservation mutation with an obsolete
  revision from `/reservas/[reservation]` and return `STALE_REVISION`.
- Impact: the catch block updated `message` and immediately inspected the old
  React state value, so the detail could remain stale instead of replacing its
  preview with the canonical server snapshot.
- Correction and regression: the handler now inspects the local exception
  detail, explains the conflict and reloads the canonical reservation. The UI
  regression verifies the local-detail check.

### W9A-034 - Home status API referenced nonexistent helper names

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: `npm run typecheck` after adding
  `/api/venues/home`.
- Impact: the route imported aliases that were not exported by the shared
  Venue API module, preventing a production bundle.
- Correction and regression: the route now uses `venueApiSession` and
  `venueApiJson`, the same authenticated no-store helpers as the other Venue
  reads. The complete TypeScript check and route contract regression pass.

### W9A-035 - Initial UI regression asserted draft aliases instead of canonical names

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: `npm run test:venue-operations` after adding the first
  Wave 9A source-contract suite.
- Impact: five assertions used planning-language aliases for canonical flags,
  RPCs, the client-version gate, the service-worker sensitive-path guard and
  offline copy. They failed against valid implementation without identifying
  a product defect.
- Correction and regression: assertions now target the persisted flag/RPC
  names and semantic fail-closed patterns actually shipped. All Wave 9A UI
  and Demo V3.4 tests pass together.

### W9A-036 - Scale certification omitted the public Control Center read model

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: compare the measured paths in
  `tests/venue-operations-v1-scale.sql` with the production read models added
  by Wave 9A.
- Impact: the corpus measured the private health digest but did not execute
  `get_pachanga_venue_control_center_v1()`. Its platform ACL, aggregate counts
  and operational projection therefore had no representative latency sample.
- Correction and regression: the scale transaction now executes the public
  Control Center RPC 25 times as the synthetic platform administrator. The
  runner requires the `control_center` metric and validates its sample count
  and percentile ordering with every other canonical path.

### W9A-037 - Control Center partner candidates did not scale

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run `npm run test:venue-operations:scale` with the
  public Control Center read model included in its 25-sample read suite.
- Impact: on the representative corpus the Control Center produced p50
  `12339.393 ms`, p95 `13912.765 ms` and maximum `14244.875 ms`. The health
  digest itself remained at p95 `344.516 ms`, isolating the regression to the
  additional Control Center projection.
- Correction and regression: visible Venues and confirmed reservations are
  each aggregated once before ranking partner candidates, backed by the
  `(venue_id,status)` reservation index. The same 25-sample path now measures
  p50 `368.280 ms`, p95 `375.104 ms` and maximum `394.097 ms`. The runner
  enforces p95 below `2000 ms`; the complete corpus and write samples roll
  back cleanly.

### W9A-038 - Club Venue selector performed a synchronous effect correction

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run focused ESLint over the Wave 9A TS/TSX surface.
- Impact: `ClubVenueOperationsClient` called `setSelectedVenueId` directly in
  an effect whenever a refreshed desk removed or replaced the current Venue,
  triggering the React cascading-render rule. The same lint run also exposed
  an unused date helper and obsolete Demo V3.3 type import.
- Correction and regression: the render-time canonical fallback now remains
  the sole automatic selection path; state changes only after an explicit
  Venue choice. The two dead symbols were removed and focused ESLint passes
  across every changed TS, TSX and MJS file.

### W9A-039 - Context selector inherited unreadable light-shell text

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: render Demo World V3.4 at `390x844` and inspect the
  active-context `<select>` in the light product header.
- Impact: the dark control background resolved to `rgb(20,33,29)`, while its
  text inherited `--official-text` as `rgb(16,32,26)`. The selected context
  was almost invisible in portrait and equally affected the desktop header.
- Correction and regression: the intrinsically dark native select now has an
  explicit `#f1f6f2` foreground and dark color scheme. At `390x844` its
  computed contrast is `15.18:1`, it introduces no horizontal overflow and
  the Demo V3.4 source regression prevents inheritance from returning.

### W9A-040 - Hero link color overrode the primary action foreground

- Classification: `PRODUCT_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: open `/reservas` at `390x844` and measure the active
  `Buscar campo` link rendered with the shared `.action` class.
- Impact: `.hero a` had higher specificity than `.action`, producing lime text
  on a lime background with contrast `1.23:1` for an enabled primary action.
- Correction and regression: informational link colors now explicitly exclude
  all action classes. The same control computes to `11.63:1`, remains fully
  visible in portrait, and the source test preserves the specificity boundary.

### W9A-041 - Global wiring test rejected the canonical Venue Match pane

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run `npm test` after adding the `campo` pane to the
  authoritative Match navigation.
- Impact: the product build and focused Wave 9A suite passed, but the global
  rendered-source contract still required exactly the four pre-Wave panes and
  failed on the intentional fifth canonical pane.
- Correction and regression: the exact type union plus the administrator and
  player pane arrays now include `campo`; the latter still excludes `admin`.
  The complete rendered HTML test file passes `9/9` before the global rerun.

### W9A-042 - Core UX test omitted the requester Reservations utility

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run the complete TS/TSX suite after adding the
  contextual `/reservas` destination to the shared player tools.
- Impact: the product contract correctly exposed a requester read/action
  surface without granting organizer authority, but the older exact player
  destination list still expected only Team, Ranking and Notifications.
- Correction and regression: the exact player list includes `reservations`;
  its negative checks still reject Control Center and organizer access. The
  focused Core UX and Wave 8B run passes with the corrected contract.

### W9A-043 - Wave 8B test treated its closing ledger as the repository ceiling

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run the complete TS/TSX suite with the eight Wave 9A
  migrations present after ledger 212.
- Impact: the Wave 8B regression asserted that the whole migration directory
  must forever contain exactly 212 files and that its own files remain the
  final eight. It failed at the valid Wave 9A ledger 220.
- Correction and regression: Wave 8B is now anchored at zero-based index 204
  and its exact eight-file slice is verified through index 211, allowing only
  later forward migrations after its boundary. The focused pair passes `23/23`.

### W9A-044 - Ephemeral Supabase branch inherited an incomplete migration ledger

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: create the isolated branch
  `wave9a-venue-operations-20260830` from project `Pachangas` and read
  `supabase_migrations.schema_migrations` before applying Wave 9A.
- Impact: the branch contained only `10` versions, ending at
  `20260728191429`, rather than the required production baseline of `212`.
  Applying migrations 213-220 directly would certify the feature against an
  invalid schema and could hide missing dependencies.
- Required correction: rebuild the isolated branch deterministically through
  the repository baseline plus migrations 11-212, confirm exact ledger and
  required relation digests, and only then apply the eight Wave 9A migrations.
  The baseline was applied transactionally, all 36 absorbed versions were
  reconciled and migrations 37-212 completed. Direct PostgreSQL readback
  reports ledger `212`, last version `20260829221312`, and the required Team,
  CanonicalMatch, referee and command authorities are present.

### W9A-045 - Branch inspection emitted ephemeral credentials to local tool output

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: request full CLI details for the Wave 9A Supabase branch
  while filtering only lower-case secret field names.
- Impact: the CLI used upper-case environment names and emitted ephemeral
  branch credentials to the private local tool channel. No value was written
  to Git, files, reports, screenshots, browser bundles or user-visible output;
  Production credentials were not involved.
- Required correction: never print the branch environment again, consume it
  directly into a process environment, run repository and bundle secret scans,
  and destroy the entire ephemeral branch after staging so all emitted values
  cease to authenticate. Every affected branch was destroyed with deletion
  readback, no development branch remains active, and the 53-file pre-commit
  scan found zero external database, Supabase, JWT or Stripe secrets.

### W9A-046 - Transaction pooler rejected the staging migration session

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: run the exact 11-212 migration push through the branch
  transaction pooler on port `6543`.
- Impact: PgBouncer reused a prepared statement name and PostgreSQL returned
  `prepared statement already exists` before the migration batch started. No
  schema or ledger change was recorded.
- Required correction: use the IPv4 session pooler on port `5432`, verify the
  branch ledger is still 10 before retrying, then require exact ledger 212 and
  schema dependency readback. The session-pooler retry completed all
  incremental migrations and the independent ledger/dependency readback passed.

### W9A-047 - Supabase CLI could not persist its optional pg-delta cache

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: complete the 37-212 staging push from a temporary
  workdir whose generated `.temp/pgdelta` certificate path is absent.
- Impact: all SQL migrations completed, but the CLI warned that it could not
  export its optional migration catalog cache. No repository artifact or
  product schema depends on that cache.
- Required correction: verify ledger 212 and required schema objects directly
  in PostgreSQL, keep no generated cache, and use database readback rather than
  the failed local optimization as release evidence. The temporary directory
  was deleted and PostgreSQL independently confirmed ledger 212 plus all
  dependencies required by Wave 9A.

### W9A-048 - Local fixture ordering violated the remote Club owner guard

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: load `tests/venue-operations-v1-fixture.sql` on the
  isolated Supabase branch after ledger 220.
- Impact: the fixture inserts its synthetic Club before inserting the primary
  owner membership. The current production guard correctly rejects that
  intermediate state with `CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED`; the local
  database suite did not expose the guard timing difference.
- Required correction: add a staging-only transactional bootstrap that bypasses
  product guards solely while importing deterministic dependencies, restore
  normal trigger execution before tests, and separately create a Club through
  the real authenticated Club RPC. The transactional bootstrap and canonical
  DB suite both produced PASS markers; the exact dataset then created two more
  Clubs through the real RPC.

### W9A-049 - Failed pre-wrapper staging seed left a partial synthetic graph

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: retry the transactional staging wrapper on the first
  branch after the earlier unwrapped fixture stopped at the Club owner guard.
- Impact: inherited fixture rows preceding the failing statement had already
  committed, so the retry met duplicate synthetic Auth IDs. No real entity or
  Production row was involved.
- Required correction: destroy the contaminated ephemeral branch instead of
  manually editing a partially known graph, recreate a clean branch, and run
  the new single-transaction bootstrap exactly once. The regression requires
  both bootstrap and canonical DB PASS markers with no partial retry. The
  contaminated branches were destroyed and the clean certification branch
  passed both markers on its first seed execution.

### W9A-050 - Remote DB harness dropped its temporary reference in autocommit

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: execute `tests/venue-operations-v1-db.sql` on staging
  without the local runner's `--single-transaction` option.
- Impact: `venue_operations_v1_test_refs` is declared `ON COMMIT DROP`; psql
  autocommit removed it before the following insert. Canonical operations before
  that point committed with fixed idempotency keys, but no product invariant
  failed.
- Required correction: execute the remote DB suite in one transaction, replay
  the prior operation IDs, require the canonical PASS marker, and encode
  one transaction in the permanent staging wrapper. The remote run reached
  `VENUE_OPERATIONS_V1_DB_PASS`, including the temporary-reference negatives.

### W9A-051 - Partial remote suite could not be replayed as a born-OFF test

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: rerun the DB suite transactionally after the autocommit
  execution had already activated Venue flags and committed its receipts.
- Impact: the first invariant correctly rejected the branch because flags no
  longer appeared born OFF. Deleting receipts or rewriting revisions would
  invalidate the very authority being tested.
- Required correction: destroy the partial branch and execute the complete
  staging sequence once on a new branch, with bootstrap and DB suite each
  transactional from the outset. No receipt or flag row was repaired; the clean
  branch certified born-OFF before its authoritative activation receipt.

### W9A-052 - Staging topology omitted the Club Foundation dependency window

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: apply the exact 3-Club/6-Team staging topology after the
  Venue DB suite while canonical Club Foundation flags remain OFF.
- Impact: the real Club RPC rejected the first synthetic Club with
  `CLUB_FOUNDATION_DISABLED`; the dataset transaction rolled back completely.
- Required correction: enable only the five required Club Foundation flags
  through `command_pachanga_club_platform_v1` on the isolated branch before
  Club creation, retain its receipt and revision, and rerun the exact-count
  assertion. The RPC activation and exact 3-Club count passed; Production flags
  remain untouched.

### W9A-053 - Synthetic Tournament filler hit an intentionally disabled beta guard

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: insert the single Tournament required by the Wave 9A
  staging topology while League/Tournament product flags remain OFF.
- Impact: the Competition trigger rejected the filler with
  `LEAGUE_PRIVATE_BETA_CREATION_DISABLED`; the complete dataset transaction
  rolled back. Wave 9A does not authorize activating Tournament product flags.
- Required correction: keep Tournament features OFF and bypass product guards
  only for the synthetic Competition/CanonicalMatch filler rows inside the
  isolated dataset transaction. Restore trigger authority before assertions
  and continue to exercise Venue operations through real RPCs. The final exact
  1-League/1-Tournament/20-Match assertion passed and product flags stayed OFF.

### W9A-054 - Authenticated staging mutation did not reach the Realtime listener

- Classification: `TESTABILITY_GAP`
- Status: `fix pending regression`
- Original reproducer: subscribe device B to Club-scoped Venue invalidations,
  wait for `SUBSCRIBED`, update a Venue from device A and await one insert.
- Impact: the command confirmed and persisted, but the listener timed out after
  20 seconds. The current evidence does not yet distinguish an incorrect test
  filter/audience from a publication or RLS delivery defect.
- Required correction: inspect the persisted invalidation, its audience, the
  publication membership and Realtime logs; then correct only the proven layer
  and rerun subscription, refetch and reconnect with two Auth sessions. The
  persisted Club and Public invalidations, RLS-enabled table, publication
  membership and active replication stream were confirmed. The staging test
  now mirrors the production clients by subscribing to the RLS-protected table
  without a server-side filter and selecting the expected entity/audience in
  its callback; it also proves an authenticated Club member can read the
  invalidation surface before awaiting delivery.

### W9A-055 - Venue invalidation RLS called a non-executable authority helper

- Classification: `PRODUCT_BUG`
- Status: `fix pending staging regression`
- Original reproducer: as an authenticated active Club Venue manager, select
  the Club-scoped row from `pachanga_venue_invalidations` before subscribing to
  Realtime.
- Impact: PostgreSQL returned `42501 permission denied for function
  pachanga_club_can_v1`. Venue commands and event persistence remained
  authoritative, but authenticated readback and Realtime policy evaluation
  could not expose the invalidation that tells a permitted client to refetch.
- Required correction: route the authenticated invalidation policy through a
  purpose-built, non-impersonable RLS helper that derives `auth.uid()` inside
  the function, grant only that helper to `authenticated`, keep the generic
  three-argument Club authority helper revoked, and prove permitted/outsider
  row visibility plus Realtime delivery with two authenticated clients. Fresh
  and upgraded local databases now prove the permission matrix and keep the
  generic helper closed; remote Realtime remains pending on a clean branch.

### W9A-056 - Reconstructed staging branch retained a failed control-plane status

- Classification: `ENVIRONMENT_ISSUE`
- Status: `open`
- Original reproducer: after reconstructing and certifying ledger `220`, inspect
  the Supabase branch state and subscribe an authenticated client to Postgres
  Changes.
- Impact: PostgreSQL was healthy and the channel reported `SUBSCRIBED`, but the
  branch remained `MIGRATIONS_FAILED`; Realtime logs showed its database tenant
  stopped without a subsequent replication-supervisor start, so no WAL event
  reached the listener.
- Required correction: independently read back exact ledger/schema health,
  update only the ephemeral branch control-plane status to the certified state,
  and require a fresh Realtime tenant start plus authenticated event delivery.
  Production and its branch status must remain untouched. The failed branch
  could not transition to a healthy state through the branch API and was
  destroyed with deletion readback; the regression will use a new branch built
  from the exact published Git SHA instead of preserving repaired control-plane
  state.

### W9A-057 - Owner transfer and reservation acceptance both won a race

- Classification: `SIMULATION_BUG`
- Status: `fixed + regression_verified`
- Original reproducer: run the Wave 9A concurrency scenario labelled `owner
  transfer vs Club acceptance` after the RLS regression update.
- Impact: ownership moved to the successor while the former owner also accepted
  a pending reservation; both commands committed. The operations target
  different aggregate revisions, so the one-winner assertion may be stricter
  than the product contract, but accepting with authority that has just been
  revoked would be a real authorization defect if the Club transition was
  already canonical at the command lock point.
- Required correction: inspect transaction lock order and command-time authority
  checks, decide whether this cross-aggregate pair is allowed to serialize as
  two valid operations, and either enforce the missing Club authority fence or
  replace the invalid one-winner assertion with an explicit allowed-outcome
  invariant. Inspection found the fixture owner also held `platform_admin`, so
  losing the Club role could not remove authority. The corrected scenario
  withdraws only that synthetic override immediately before the race and keeps
  the delayed acceptance as the original interleaving regression. The complete
  twelve-race suite then returned twelve canonical winners, twelve explicit
  stale/conflict/forbidden outcomes, zero double bookings and one active
  CanonicalMatch binding.

### W9A-058 - Secret scan classified loopback fixtures as remote credentials

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: scan every modified/new file for a PostgreSQL URL that
  embeds a password without distinguishing the destination host.
- Impact: the scan flagged the standard disposable local URL
  `postgres:postgres@127.0.0.1` in the concurrency and scale harnesses. No
  Supabase, Stripe, JWT or external database secret was found or printed.
- Required correction: retain strict remote credential patterns while allowing
  only explicit loopback hosts used by isolated disposable databases, rerun all
  five secret classes, and require zero external findings before commit. The
  corrected 53-file scan allowed loopback fixtures only and returned zero
  external findings.

### W9A-059 - Branch creation CLI prefixed its JSON response with human text

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: create the final branch with CLI JSON output and pipe it
  directly to a strict JSON parser used to redact credential fields.
- Impact: the CLI wrote `Created preview branch:` before the JSON document, so
  the parser exited after creation. Its input was not echoed and no credential
  reached terminal output, Git, reports or logs.
- Required correction: discover the created branch through the safe branch-list
  API, expose only id/name/ref/status, and consume any later environment response
  entirely in process memory. Do not repeat branch creation.
  The safe branch-list API recovered exactly one new branch, exposed no
  credential field, and the contaminated branch was later destroyed.

### W9A-060 - Healthy Git-linked branch did not apply unmerged Wave migrations

- Classification: `ENVIRONMENT_ISSUE`
- Status: `open`
- Original reproducer: create a Supabase branch linked to the published Wave 9A
  Git branch, wait for `FUNCTIONS_DEPLOYED`, then read
  `private.pachanga_venue_settings`.
- Impact: the branch control plane was healthy but contained only the production
  migration frontier; the Venue settings relation did not exist. No Wave flag
  or product write could run and Production was unchanged.
- Required correction: read back the exact base ledger, apply only the eight
  forward Wave 9A migrations through Supabase migration authority, and require
  exact ledger `220`, migration names/digests, flags born OFF and helper/schema
  presence before loading synthetic fixtures.

### W9A-061 - Generic db push advanced staging history without Venue schema

- Classification: `ENVIRONMENT_ISSUE`
- Status: `open`
- Original reproducer: on the clean ten-version branch, apply the canonical
  baseline, repair the 26 absorbed versions and run generic `supabase db push
  --include-all`, then require the Venue settings relation.
- Impact: the final readback found no `private.pachanga_venue_settings_v1` even
  though the CLI command exited successfully. The branch must be treated as
  contaminated because migration history and schema no longer prove each other.
  No fixture, Auth account, flag activation or Production write followed.
- Required correction: inspect the ledger statement payloads, destroy the
  contaminated branch, and replace generic push with an explicit transactional
  application of every post-baseline migration plus atomic ledger recording.
  The replacement must compare exact file count/names and fresh schema hash
  before staging data is allowed. Dry-run evidence showed the repository's
  canonical `config.toml` intentionally reports `Skipping migrations because
  it is disabled`; the replacement harness now creates an isolated temporary
  config with migrations enabled, links the exact migration directory and
  removes the temporary workdir in `finally`.

## Canonical regression evidence

All incidents marked `fixed + regression_verified` are covered by the same
transactional database suite and were re-executed together after the final
fixture correction:

- command: `node tests/venue-operations-v1-db-runner.mjs`;
- exact upgrade path: ledger `212 -> 220`;
- fresh bootstrap ledger: `220`;
- migration count: `8`;
- normalized schema equivalence: `PASS`;
- schema SHA-256: `83c1142de712cdbcb6528794ccf511d9fabf127caecf2c3e27ac2e735e2ee135`;
- flags born OFF: `PASS`;
- canonical lifecycle, RLS, privacy, DST, R4D and ledger: `PASS`;
- concurrency: `12` races, `12` canonical winners, `12` explicit stale/conflict
  outcomes, `0` double bookings and `1` active CanonicalMatch binding;
- scale corpus: `1,000` Venues, `5,000` Pitches, `50,000` availability
  records, `100,000` requests, `50,000` reservations and `100,000`
  invalidations;
- measured paths: directory, availability, request submit, hold, accept,
  conflict detection, reservation desk, Match binding, health and Control
  Center, with at least `20` samples per path and valid p50/p95 ordering;
- scale write samples rolled back: `PASS`; full corpus rollback: `PASS`;
- scale database and temporary infrastructure dump cleanup: `PASS`;
- ephemeral database cleanup: `PASS`.
