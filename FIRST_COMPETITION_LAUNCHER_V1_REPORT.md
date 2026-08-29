# First Competition Launcher V1 Report

Date: 2026-08-29 CEST

## Product contract

`/organizacion/empezar` is a guided entry into the existing Competition
engines. It does not introduce a second League or Tournament wizard.

The owner selects the organizer and confirms:

- League or Tournament;
- canonical preset/modality;
- proposed name and area;
- dates;
- expected team count.

Defaults may come from the approved application, but the user confirms them
before the server command.

## Server authority

`competition.launch` requires an active onboarding workspace, active canonical
entitlement, `operationId` and `expectedRevision`. PostgreSQL locks the
workspace and entitlement, rejects stale/expired access and creates exactly one
canonical draft.

- League delegates to League Wizard V2 and its presets.
- Tournament delegates to Tournament Foundation/Wizard.
- Configuration Center and RuleRevision remain canonical.
- The launcher never publishes automatically.

The response contains the updated workspace plus the canonical handoff URL.
Retry returns the same receipt and draft id.

## Concurrency and expiry

Tests cover two simultaneous launches and entitlement-expiry-vs-launch. The
result is one canonical winner plus an idempotent or stale outcome; there are
no duplicate competitions. A manual cancellation remains in the existing
competition engine rather than adding launcher-specific deletion authority.

## Navigation

The onboarding next action links to the launcher only when the server returns
`CREATE_FIRST_COMPETITION`. After creation, it links to the existing League or
Tournament workspace. The practice action opens Demo World V3.0 and creates no
data in the real account.
