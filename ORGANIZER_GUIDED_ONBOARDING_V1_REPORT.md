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
