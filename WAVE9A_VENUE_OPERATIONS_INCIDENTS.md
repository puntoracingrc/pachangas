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

## Canonical regression evidence

All incidents marked `fixed + regression_verified` are covered by the same
transactional database suite and were re-executed together after the final
fixture correction:

- command: `node tests/venue-operations-v1-db-runner.mjs`;
- exact upgrade path: ledger `212 -> 220`;
- fresh bootstrap ledger: `220`;
- migration count: `8`;
- normalized schema equivalence: `PASS`;
- schema SHA-256: `90fe290261f0cd23ad7401ea968fd053d71eb55979a1db839da6f6e79548b4f8`;
- flags born OFF: `PASS`;
- canonical lifecycle, RLS, privacy, DST, R4D and ledger: `PASS`;
- concurrency: `12` races, `12` canonical winners, `12` explicit stale/conflict
  outcomes, `0` double bookings and `1` active CanonicalMatch binding;
- scale corpus: `1,000` Venues, `5,000` Pitches, `50,000` availability
  records, `100,000` requests, `50,000` reservations and `100,000`
  invalidations;
- measured paths: directory, availability, request submit, hold, accept,
  conflict detection, reservation desk, Match binding and health, with at least
  `20` samples per path and valid p50/p95 ordering;
- scale write samples rolled back: `PASS`; full corpus rollback: `PASS`;
- scale database and temporary infrastructure dump cleanup: `PASS`;
- ephemeral database cleanup: `PASS`.
