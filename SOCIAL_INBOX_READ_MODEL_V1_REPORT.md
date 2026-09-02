# SOCIAL INBOX READ MODEL V1 REPORT

## Checkpoint

- Date: 2026-09-02 10:39:54 CEST
- Base: `8ce3dec994c16e32fd9cae5a05f51e37f4537b6f`
- Branch: `codex/official-ui-v3g-social-inbox`
- Migration frontier: 235 local files
- V3G authority migration SHA-256: `4ade702f4ae82b4fbbabbf79d0cb3ee037b11d9345ee9dd8ab1853c36165460b`
- V3G FK-index migration SHA-256: `3cbc006045c326737faf66210bc92753d7adf1ffd23dc0510958c24efcc51067`
- Status: local, authenticated staging and isolated Preview certified; authority migration applied in production and FK-index migration pending

## Authority

`public.pachanga_user_notifications` remains the only persisted notification
source. V3G adds no notification table, outbox, event store, delivery channel or
domain command. The read RPC derives a safe social projection at read time and
rechecks the current Match, Challenge, Market or Team aggregate where a
canonical aggregate exists.

The projection is recipient-bound through `auth.uid()`. A group admin or
`platform_owner` receives no social privilege to inspect another user's Inbox.
Unknown, advanced, platform, competition, Club, referee, venue and Billing
kinds are excluded by an explicit server-side allowlist.

## Response contract

`get_my_pachanga_social_inbox_v1` returns:

- `pendingCount` independently from read state;
- `unreadCount` independently from attention state;
- a maximum of 25 items by default and 50 by contract;
- `MATCH`, `CHALLENGE`, `MARKET` and `TEAM` filters;
- `hasMore` and a stable `nextCursor`;
- `fetchedAt` and the highest confirmed `serverSequence`.

Each item contains only:

- stable notification ID;
- social domain, kind and source ID;
- bounded title, summary and display context;
- priority and display status;
- `ACTION_REQUIRED`, `INFORMATIONAL` or `RESOLVED`;
- `UNREAD` or `READ`;
- `ACTIVE` or `ARCHIVED`;
- revision, sequence and server timestamps;
- one server-built allowlisted relative deep link and CTA label.

It never returns the recipient ID, raw payload, raw `action_url`, email,
telephone, invitation token, private location, private price, Stripe data,
service-role material or arbitrary redirect targets.

## Ordering and pagination

The authoritative order is:

1. server-derived `sortRank`;
2. `server_sequence DESC`;
3. stable notification `id DESC`.

The cursor contains all three fields. No query selects the latest item by
`created_at` alone. `mark_all_read` is bounded to the snapshot sequence supplied
by the client, so a notification created concurrently remains unread.

## Source coverage

| Product domain | Canonical coverage | State derivation |
| --- | --- | --- |
| Match | attendance changes, availability changes, revoked guest access and guest withdrawal | informational or resolved; opens V3B/V3F match surfaces |
| Challenge | challenge lifecycle and external result lifecycle | canonical challenge/result state decides pending or resolved; opens V3C |
| Market | match invitation and open-place request lifecycle | invitation/request/access rows decide pending or resolved; opens V3D or accepted guest match |
| Team | membership changes, invitation responses and shield updates | canonical notification state; opens V3F |

Two intentional limits remain:

- a token-only Team invitation has no recipient before the invited person opens
  it, so V3G does not invent a private Inbox row;
- pre-match attendance selection continues to use the existing V3B Match
  authority when no canonical personal notification exists. Demo can explain
  that journey locally, but production does not persist a fictitious event.

## Cache, Realtime and user switching

The client stores only the sanitized first confirmed page in IndexedDB database
`pachangas-iq-private-read-models`, namespaced by user and schema version.
Sign-out clears that user's namespace and an in-flight response is discarded
when the actor changes.

Realtime subscribes to the current recipient's notification rows. WAL payloads
are never applied as state: `SUBSCRIBED`, reconnect and row events debounce a
canonical RPC refetch. The Service Worker caches route shells and assets, never
Supabase private RPC responses.

## Verification

- focused source contract: 17/17;
- SQL/RLS rollback suite: PASS;
- deterministic two-session replay: one mutation, one receipt, revision 2;
- global suite: Node 20/20 plus TS/TSX 798/798, total 818/818;
- typecheck, build, focused lint, global lint and `git diff --check`: PASS.

## Remote staging and Preview

An isolated Supabase branch was bootstrapped from the signed 234-migration
baseline, then advanced to the forward-only 235-migration FK-index correction.
It exposed the exact V3G RPC signatures. Four synthetic `.test`
actors exercised two Teams, one Match, one Challenge, one open-place request,
one Match invitation and one Team invitation.

The authenticated two-device run passed:

- own-user privacy, foreign-user denial and direct-write denial;
- actual Challenge deep-link resolution;
- one receipt for concurrent idempotent replay;
- stable cursor pagination and session-switch isolation;
- offline write rejection with no optimistic confirmation;
- Realtime `UPDATE` invalidation followed by canonical RPC refetch.

The exact Preview bundle contained only the isolated staging project ref and no
service-role credential. Remote browser QA passed signed-out Inbox, settings,
Demo Inbox, domain filtering, Service Worker control, cached offline shell and
installed-mode emulation at 1440x900, 390x844 and 844x390 with zero horizontal
overflow, broken images or unexpected browser/network errors.

No external push, email or domain side effect was emitted. The disposable
branch and its branch-scoped Preview variables remain only until the release is
complete; branch destruction is the canonical cleanup because immutable
operational evidence must not be bypassed.
