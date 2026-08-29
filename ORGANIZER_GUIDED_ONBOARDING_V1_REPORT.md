# Organizer Guided Onboarding V1 Report

Date: 2026-08-29 CEST

## Authority

`OrganizerOnboardingWorkspace` is derived from a valid existing access grant.
It never grants access. A unique active workspace belongs to the organizer,
not to the user who happened to create the original application.

## Canonical checklist

PostgreSQL derives and persists ten checkpoints:

1. Organizer identity.
2. Active Club or Team.
3. Current organizer access.
4. Public or private organizer profile.
5. First Competition draft.
6. Valid RuleRevision.
7. Participants or invitations.
8. Schedule or draw.
9. Publication, including valid private completion.
10. First match prepared.

Each refresh updates canonical checkpoints, revision, timestamp and server
sequence. The browser renders this snapshot and does not calculate completion.

## Next action

The server returns one of:

`COMPLETE_ORGANIZER_PROFILE`, `WAIT_FOR_REVIEW`, `RESPOND_INFORMATION`,
`ACCESS_APPROVED`, `CREATE_FIRST_COMPETITION`,
`CONTINUE_COMPETITION_DRAFT`, `INVITE_TEAMS`, `CONFIGURE_RULES`,
`GENERATE_SCHEDULE`, `PREPARE_DRAW`, `PUBLISH_COMPETITION`,
`PREPARE_FIRST_MATCH` or `ONBOARDING_COMPLETE`.

## Existing grants and ownership transfer

An idempotent grant trigger creates or refreshes onboarding for access granted
outside the application flow. Owner transfer does not reassign the workspace:
the organizer remains constant while command authorization follows the current
owner or explicit Club staff capability.

## Realtime, cache and PWA

The client caches only the read model. Realtime invalidations and reconnects
trigger canonical refetch. Offline may display cached checklist and draft text,
but cannot refresh, launch or complete onboarding and never reports fake
success.

## Verification

Local SQL tests cover grant prerequisites, checkpoint derivation, one next
action, private competition completion, idempotent refresh and transfer of
owner authority. Demo World V3.0 contains complete, interest-only,
needs-information, rejected, withdrawn and transferred-owner workspaces without
PII.

Authenticated staging additionally confirmed that two sessions converge on
the same canonical workspace revision after an invalidation. The Realtime row
is never consumed as workspace state, and an unrelated authenticated user
cannot read the organizer's invalidation.

## Production verification

- Guided Onboarding was enabled through the settings RPC at revision 6.
- Approval in the transactional canary created the canonical workspace and the
  server returned the launcher next action; no browser-computed completion was
  accepted.
- Launcher cancellation and grant revocation were reflected before the full
  transaction rollback. Final readback contains zero onboarding workspaces and
  zero invalidations.
- The production Service Worker controls the origin. With network access
  blocked, the Demo onboarding page and all eleven V3 data fragments loaded
  from the worker cache while a non-cacheable control request continued to
  fail. After reconnection, a fresh control request returned `200` and the
  canonical route remained intact.
- Browser-level Service Worker and reconnection QA pass. Physical Android,
  iPhone and installed-device PWA QA remain explicitly `PENDING`.
