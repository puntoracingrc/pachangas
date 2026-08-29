# Organizer Partnership Review V1 Report

Date: 2026-08-29 CEST

## Review authority

Platform review is a server-authoritative extension of Control Center. The
platform route requires `organizer_access.read`; each mutation additionally
checks the exact capability for support, review, approval or rate override.

- Platform owner and explicitly capable platform admin may review.
- Support may inspect, request information and escalate, but cannot grant.
- Finance receives no implicit partnership approval capability.
- Applicant, Team admin and Club member cannot invoke review commands.

## Decisions

Review supports start, request information, approve, reject, expire and
reconsider. Every accepted command persists a receipt, event, revision and
server sequence in one transaction.

An approval records public-safe applicant text separately from an optional
private note. Applicant RPCs never return the private note. The Control Center
read model can expose it only to an authorized platform reviewer.

## Grant bridge

- `CLUB_PARTNER + APPROVED + PARTNERSHIP` atomically creates one existing
  organizer access grant and projects one `CompetitionEntitlementGrant`.
- Paid interest produces `APPROVED_INTEREST` and no grant.
- Private beta, promotion and platform grant require explicit source, duration,
  limits and capabilities.
- `SUBSCRIPTION` cannot be synthesized by this flow.
- Application approval races safely with legacy/manual grant creation under a
  shared organizer/plan lock and converges on one canonical grant.

## Queue and health

`/admin/organizer-access` provides status, plan, organizer kind, competition
type, area, date and reviewer filters. Its health read model reports pending,
unassigned, needs-information, approvals, rejections, grants, inconsistent
decision/grant pairs, duplicate blocks and errors without promising a public
SLA.

## Notifications

Mandatory, deduplicated notifications cover submission, review start,
information request/response, approval, rejection, access grant and expiry.
Only the owner/authorized actor and necessary platform reviewers receive them;
the Club or Team roster is not broadcast.

The expiry worker is service-only, idempotent, uses row locks with
`SKIP LOCKED`, and is invoked by the existing billing expiration and
reconciliation jobs.

## Verification

SQL tests cover capability boundaries, private-note isolation, direct-table
denial, decision/grant consistency and notification recipients. Concurrency
tests cover approve-vs-withdraw, approve-vs-reject,
request-information-vs-approve, approval-vs-manual-grant and duplicate expiry
reminders. All pass locally.

## Production verification

- Review and partnership approval were enabled separately through the audited
  platform settings RPC at monotonic revisions 4 and 5.
- The ephemeral production canary exercised `review.start`,
  `review.request_information` and `review.approve` with the real platform
  authority. The approval created exactly one temporary `PRIVATE_BETA` grant.
- The grant was revoked and the surrounding transaction rolled back. Final
  readback reports zero applications, decisions and application-created grants.
- Seven mandatory notifications and seven ordered application events were
  observed before rollback; no roster-wide disclosure or private-note leakage
  occurred.
- Production logs contain only explicitly recorded harness/readback errors;
  API, Auth, Realtime and Vercel show no unrecorded release error.

Full migration, deployment and cleanup evidence is recorded in
`ORGANIZER_ACCESS_ONBOARDING_V1_PRODUCTION_RELEASE.md`.
