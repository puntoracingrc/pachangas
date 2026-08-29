# Organizer Access Applications V1 Report

Date opened: 2026-08-29 CEST

Base `main`: `e0cbf7bd45f8d38e4edc8bc7dc97fd1272ec355f`

Migration baseline: 197

Wave 8A ledger after local bootstrap: 204

## Canonical authority

Wave 8A adds the missing acquisition path without creating a second permission
model:

`OrganizerPlanCatalog -> OrganizerAccessApplication -> review decision -> OrganizerAccessGrant -> CompetitionEntitlementGrant -> Competition`

`CompetitionEntitlementGrant` remains the final authorization. Applications,
decisions and onboarding never grant sporting access by themselves.

## Persistent model

- Private application aggregate keyed by `organizer_kind + organizer_id`.
- Immutable application revisions with content fingerprint and consent version.
- Private messages, immutable decisions, operation receipts and ordered events.
- Monotonic aggregate revision plus `server_sequence` for canonical ordering.
- One active equivalent application per organizer and plan.
- No duplicate Auth, Club, Team, billing or contact data.

The lifecycle implemented is:

`draft -> submitted -> under_review -> needs_information -> under_review -> approved`

Terminal alternatives are `approved_interest`, `rejected`, `withdrawn` and
`expired`. A terminal decision is immutable; reconsideration creates a linked
new application/revision rather than rewriting history.

## Ownership and privacy

- Team submission resolves the current owner from `pachanga_groups.owner_id`.
- Club submission resolves current owner/staff authority from Club Foundation.
- Ownership transfer is evaluated at command time under lock: the new owner can
  continue and the former owner loses implicit authority.
- Applicant read models omit private reviewer notes, Auth identifiers and
  internal moderation fields.
- Authority tables revoke direct `INSERT`, `UPDATE` and `DELETE` from `anon`
  and `authenticated`; writes enter only through versioned RPC/API commands.

## Commands and consistency

`command_pachanga_organizer_access_application_v1` accepts allowlisted actions,
`operationId`, `expectedRevision`, aggregate id and sanitized client metadata.
PostgreSQL resolves actor, organizer, owner, plan, eligibility, duplicate and
rate-limit checks, server time and sequence.

The client keeps read snapshots only. `SUBSCRIBED`, invalidation and reconnect
all trigger canonical refetch; WAL payloads are not applied as state. Offline
writes are blocked and never queued as completed operations.

## Plans

- `CLUB_PARTNER`: manual review may create `PARTNERSHIP` access.
- `CLUB_ORGANIZER`: records paid-plan interest while live Checkout is OFF.
- `TEAM_ORGANIZER_PRO`: records add-on interest while live Checkout is OFF.
- `PRIVATE_BETA`, `PROMOTION` and `PLATFORM_GRANT` require an explicit platform
  decision and are never represented as subscriptions.

`approved_interest` creates no subscription grant.

## Product surfaces

- `/planes-organizador` derives its CTA from the canonical availability model.
- `/organizacion/solicitar-acceso`
- `/organizacion/solicitudes`
- `/organizacion/solicitudes/[applicationId]`
- `/organizacion/onboarding`
- `/organizacion/empezar`
- `/admin/organizer-access`

Navigation exposes one role-aware `Organizar` path and links to the GET-only
Demo World practice surface.

## Local verification

- Organizer access source suite: 16/16 PASS.
- SQL/RLS/idempotency suite: PASS.
- Concurrency suite: 13/13 races PASS with cleanup PASS.
- Fresh PostgreSQL bootstrap: 204 migrations, PASS.
- Schema equivalence hash:
  `4793080d9ba7421e773be599e82753ad7af4bbbfedca75c1f62c849c777281a8`.
- Global product suite: 615/615 PASS; skip/todo/cancelled: 0/0/0.
- Typecheck and build: PASS.
- Focused lint: PASS. Global lint retains 40 pre-existing findings
  (22 errors, 18 warnings) and adds no Wave 8A error.
- `git diff --check`: PASS.
- Local security Advisor: 0 findings.
- Performance Advisor: two pre-existing duplicate-index observations, neither
  introduced by Wave 8A.

The contractual baseline written before implementation was 618, but the exact
runner on the checkpoint `main` plus this Wave reports 615 tests. The report
uses the executable runner total and does not present a subtotal as a total.

## Release boundary

Stripe resources, variables, routes and flags are untouched. Live prices,
Checkout and portal remain OFF. Preview, staging and production evidence is
recorded separately in the production release report.

## Staging verification

The authenticated staging run exercised six independent actors and two client
sessions. It confirmed one-winner stale-revision handling, canonical refetch
after a Realtime invalidation, private-note isolation, owner transfer, paid
interest without a grant, launcher cancellation, grant revocation and
notification deduplication.

That run found and permanently recorded W8A-018: the invalidation RLS policy
depended on a private predicate whose `EXECUTE` privilege had been revoked from
`authenticated`. The final migration grants only that predicate execution;
table writes remain denied. Owner/outsider SQL reads and an actual two-device
Realtime delivery now pass.
