# SOCIAL INBOX ACTION STATE V1 REPORT

## Decision

Reading, attention and archive are three independent dimensions:

| Dimension | Values | Authority |
| --- | --- | --- |
| Read | `UNREAD`, `READ` | notification `read_at` |
| Attention | `ACTION_REQUIRED`, `INFORMATIONAL`, `RESOLVED` | current domain aggregate plus server classifier |
| Archive | `ACTIVE`, `ARCHIVED` | notification `archived_at` |

A read notification may still require action. Archiving never accepts a
challenge, confirms attendance, reviews a place request, joins a Team or changes
a result. An archived item that remains canonically actionable continues to
appear in `Pendientes`; it disappears only from the normal `Todos` activity
view.

## Command authority

`command_pachanga_social_inbox_v1` accepts exactly:

- `inbox.mark_read`;
- `inbox.mark_unread`;
- `inbox.mark_all_read`;
- `inbox.archive`.

The client supplies semantic action, notification ID where applicable,
`operationId`, expected item revision or expected snapshot sequence. The server
resolves actor, ownership, server time, sequence, receipt and resulting Inbox.
There is no direct authenticated `INSERT`, `UPDATE` or `DELETE` grant on the
notification table.

The command uses a per-user transaction lock, a five-second lock timeout and a
post-lock receipt read. Replaying the same envelope returns the same confirmed
receipt; reusing its operation ID with different arguments fails explicitly.

## Domain-state matrix

| Source | `ACTION_REQUIRED` | `RESOLVED` | Action location |
| --- | --- | --- | --- |
| Challenge | proposal or counterproposal awaiting the recipient Team admin | accepted, rejected or cancelled | `/retos` V3C |
| External result | rival response or scorer correction pending for recipient Team | confirmed, auto-confirmed, disputed, annulled or cancelled | `/retos` V3C result surface |
| Match invitation | pending and current user is invitee | accepted, rejected or cancelled | `/mercado` V3D |
| Open place request | pending and current user is source Team admin | accepted, rejected or cancelled | Match/Market V3B/V3D |
| Match activity | ordinary attendance or availability change | access revoked or guest left | Match V3B |
| Team activity | informational membership/shield change | leave, removal or invitation response | Team V3F |

If the referenced aggregate is absent or no longer accessible, the item becomes
`RESOLVED / Ya no disponible`; it never remains as a stale action.

## Concurrency outcomes

- Same `operationId`, same command from two sessions: one write, one receipt,
  identical confirmed state.
- Same operation ID with a different envelope: `OPERATION_ID_CONFLICT`.
- Stale item revision: no write and canonical refetch.
- `mark_all_read` versus a later notification: only rows at or below the
  confirmed snapshot sequence are changed.
- Realtime versus pagination: invalidation refetches page one and preserves the
  selected view/filter; WAL is not authority.
- Sign-out versus command/refetch: late UI effects are ignored for the next
  actor and busy state is always released.

## Error contract

Raw PostgreSQL/PostgREST details are converted into product messages for
authentication, missing/foreign item, stale revision, offline, timeout,
unavailable service and unknown error. `operationId`, SQLSTATE, stack and raw
payload are not displayed.

## Verification

- own-user privacy, foreign-user denial and direct-write denial: PASS;
- advanced-kind exclusion: PASS;
- read/unread/archive/all-read idempotency: PASS;
- pending independent from unread: PASS;
- archived pending remains pending: PASS;
- same-timestamp ordering via sequence and ID: PASS;
- concurrent replay and receipt uniqueness: PASS;
- no Match, Challenge, Market or Team command exists in the Inbox RPC: PASS.
