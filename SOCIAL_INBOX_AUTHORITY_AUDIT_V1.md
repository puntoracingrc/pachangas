# SOCIAL INBOX AUTHORITY AUDIT V1

## Audit checkpoint

- Date: 2026-09-02 08:42:34 CEST
- Base: `origin/main`
- Initial SHA: `8ce3dec994c16e32fd9cae5a05f51e37f4537b6f`
- Branch: `codex/official-ui-v3g-social-inbox`
- Initial migration ledger: 233 local migration files
- Initial worktree: clean
- Scope: local repository only; no Supabase, Vercel, Stripe, push, email or production writes

## Executive decision

Pachangas IQ already has one reusable canonical notification authority:
`public.pachanga_user_notifications`. V3G must not create a second notification
table, another outbox or another event store.

The existing authority is sufficient for recipient ownership, stable identity,
deduplication, read state, revision, server sequence, timestamps, preferences,
Realtime invalidation and disabled secondary delivery. It is not sufficient for
the V3G product contract because it lacks archive state, mark-unread,
mark-all-read, a social-only projection, canonical attention state, stable
cursor pagination and server-built allowlisted deep links.

One minimal forward-only migration is therefore justified. It will extend the
existing notification row with archive state and add a social read RPC plus one
idempotent command RPC. It will not create notifications, alter any sports
authority or enable push/email.

## Classification legend

- `CANONICAL`: authoritative active source used by production flows.
- `REUSABLE`: valid existing component to consume without replacement.
- `DOMAIN-SPECIFIC`: canonical inside a sports/social domain, not Inbox authority.
- `ADVANCED-ONLY`: valid platform/competition surface excluded from social Inbox.
- `LEGACY`: active or retained implementation superseded by V3G.
- `PARTIAL`: useful implementation missing part of the required contract.
- `MISSING`: no implementation located.

## Authority inventory

| Piece | Classification | Evidence | V3G decision |
| --- | --- | --- | --- |
| `public.pachanga_user_notifications` | CANONICAL | `20260803190301_match_guest_invitations_notifications.sql` | Reuse as the only persisted Inbox source. |
| `recipient_user_id` plus own-row RLS | CANONICAL | Same migration; policy compares `auth.uid()` | Preserve. A user, team admin and platform owner only read their own rows. |
| `dedupe_key` unique | CANONICAL | Same table and `private.pachanga_notify_v1` upsert | Preserve. Replayed source event keeps one row. |
| `revision` | CANONICAL | Same table and read command | Reuse for item commands and stale detection. |
| `server_sequence` plus `id` | CANONICAL | Same table and existing read order | Reuse for ordering and cursor pagination. Never paginate only by time. |
| `read_at` | CANONICAL | Same table | Reuse as read state. |
| `archived_at` | MISSING | No column or side table located | Add minimally to the canonical row. |
| `private.pachanga_notification_operation_receipts` | PARTIAL | Original notification migration | Existing receipt only models mark-read; retain for legacy replay, add a V3G command receipt for all actions. |
| `private.pachanga_notify_v1` | CANONICAL | Notification foundation and later policy replacements | Keep as the sole notification writer. V3G does not call it to duplicate domain events. |
| `public.pachanga_notification_preferences` | CANONICAL | `20260804144819_notification_foundation.sql` | Reuse unchanged. |
| `get_pachanga_notification_preferences_v1` | CANONICAL | Same migration | Reuse unchanged under `/ajustes/notificaciones`. |
| `update_pachanga_notification_preferences_v1` | CANONICAL | Same migration; revision, advisory lock and receipt | Reuse unchanged. No offline queue or optimistic success. |
| `private.pachanga_notification_delivery_outbox` | CANONICAL | Notification foundation | Preserve. Push and email channels remain disabled. |
| `get_pachanga_notification_center_v1` | LEGACY | Original migration, later replaced by notification foundation | Retain for compatibility but stop invoking from V3G. It returns raw payload/context, mixes advanced domains and loads up to 120 rows without cursor. |
| `mark_pachanga_notification_read_v1` | LEGACY | Original notification migration | Retain for compatibility. V3G uses the new generic command RPC. |
| global `NotificationCenter` popover | LEGACY | `app/notification-center.tsx`, mounted from `app/layout.tsx` | Remove from active layout. It executes attendance, invitation, request and conduct commands directly from the Inbox. |
| shell bell | PARTIAL | `app/_components/official-product-shell-v2.tsx` | Point to `/avisos`; add canonical pending badge and informational dot. |
| notification preferences page | PARTIAL | `app/perfil/avisos/page.tsx` | Move to `/ajustes/notificaciones`; make legacy route a redirect. |
| Realtime publication | REUSABLE | Notification table uses replica identity full and is in `supabase_realtime` | Subscribe per recipient and use events only to invalidate/refetch. |
| Service Worker | PARTIAL | `app/service-worker-source.ts` | Cache new route shells/assets only; never cache private RPC responses. |
| private Inbox cache | MISSING | No V3G cache located | Add a versioned, user-namespaced IndexedDB read cache with sanitized read-model items only. |

## Domain event inventory

### Social Inbox eligible

| Domain | Existing evidence | Classification | Notes |
| --- | --- | --- | --- |
| Match attendance | `match_attendance_joined`, `match_attendance_cancelled` | CANONICAL | Informational group activity. A direct `no` without previous `voy` intentionally creates no cancellation notice. |
| Player availability | `player_availability_unavailable`, `player_availability_available` | CANONICAL | Safe text excludes medical details. |
| Match invitations | `match_invitation`, response/cancel/access/withdrawal kinds | DOMAIN-SPECIFIC | Inbox deep-links to V3B/V3D; response stays in match authority. |
| Open match requests | `open_match_request` and status variants | DOMAIN-SPECIFIC | Admin/player projection exists. Review remains in market/match authority. |
| Team challenges | `team_challenge_<event_type>` and expiry | DOMAIN-SPECIFIC | Deep-link to V3C. Challenge status is the attention authority. |
| Team membership | join/leave/remove kinds | CANONICAL | Informational or resolved social activity. |
| Team player invitation response | accepted/declined kinds | PARTIAL | Admin response notification exists. The invitee token invitation is not tied to a recipient until acceptance, so no pending personal Inbox row can be invented. |
| Team creation | Canonical V3F team command/read model | DOMAIN-SPECIFIC | No separate notification is required for the actor who just created it. |
| Match result and lineup changes | Existing match/result notifications | DOMAIN-SPECIFIC | Include only kinds explicitly allowlisted as social. Domain state decides pending/resolved. |

### Excluded from normal social Inbox

The shared table also receives achievements/rewards, conduct/security,
platform announcements, Clubs, referees, competitions, leagues, tournaments,
venues, organizer access and Billing events. Later migrations broaden
`private.pachanga_notification_policy_v1`, sometimes mapping advanced events to
the same broad `match`, `market` or `group` categories.

Those categories cannot be used as the V3G boundary. The new projection must
use an explicit server-side social kind classifier. Unknown and advanced kinds
return no social item and remain available to their existing administrative or
specialized surfaces.

## Existing behavior that must stop being invoked

`app/notification-center.tsx` currently calls domain RPCs for:

- match invitation acceptance/rejection;
- public-place request acceptance/rejection;
- withdrawal/conduct review;
- post-match attendance agreement/dispute.

It also follows persisted `action_url` values directly. This makes the legacy
popover both a domain command surface and an open-ended navigation surface.
V3G removes it from the global layout. The new Inbox only executes read/archive
commands and receives a server-built allowlisted relative deep link.

## Missing V3G authority

| Requirement | Current state | Required implementation |
| --- | --- | --- |
| Social-only projection | MISSING | Explicit server classifier and safe read RPC. |
| `ACTION_REQUIRED` / `INFORMATIONAL` / `RESOLVED` | MISSING | Derive from current canonical aggregate state, never from read state. |
| Safe deep link | PARTIAL | Build from allowlisted domain and canonical identifiers; never expose arbitrary stored URL. |
| Pending/unread counts | PARTIAL | Server projection returns both independently. |
| Stable pagination | MISSING | Cursor is `(server_sequence, id)`. |
| Mark unread | MISSING | Add to generic command RPC. |
| Mark all read | MISSING | Bound by the caller's confirmed snapshot sequence so concurrent new notices remain unread. |
| Archive | MISSING | Add canonical timestamp and idempotent command. Archive never resolves a domain action. |
| Command audit/idempotency | PARTIAL | Add private receipts for the generic V3G command. |
| Home convergence | MISSING | Home consumes the same provider/read model and shows at most one Inbox action. |
| User-switch isolation | MISSING | Provider aborts stale requests and clears/changes cache namespace. |

## Deep-link allowlist contract

Only relative product routes built by the server are valid:

- Match: `/?mobile=partido&p=<canonical-match-id>`
- Accepted guest match: `/partido-invitado?acceso=<canonical-access-id>`
- Challenge: `/retos?view=active&reto=<canonical-challenge-id>`
- Market request/invitation: `/mercado?tab=partidos` or the canonical match route
- Team: `/equipo` or `/equipo/invitaciones?team=<canonical-group-id>`

The projection rejects `javascript:`, `data:`, protocol-relative URLs,
external hosts, arbitrary return targets and tokens. Raw `action_url` and raw
payload are not returned to the V3G client.

## Data and privacy boundary

The V3G read model may return only stable notification ID, social domain, kind,
display title/summary/context, occurred time, priority, attention/read/archive
state, revision, sequence and safe relative link. It must not return recipient
UUID, Auth IDs, emails, phones, invitation tokens, private locations, prices,
notes, Stripe IDs, service-role material or full source payloads.

Authenticated clients keep zero direct INSERT/UPDATE/DELETE privilege on the
notification table. All V3G writes pass through the command RPC. `anon` has
zero private reads and writes.

## Migration decision

Create exactly one additive migration containing:

1. `archived_at` on `public.pachanga_user_notifications`;
2. a partial recipient/order index for active social reads if query planning
   requires it;
3. a private idempotency receipt table for V3G commands;
4. a private explicit social-kind classifier;
5. `get_my_pachanga_social_inbox_v1`;
6. `command_pachanga_social_inbox_v1`;
7. minimum grants and pinned `search_path`.

No new event table, notification table, outbox, trigger fan-out, feature flag,
push channel or email channel is introduced.

## Validation required before release

- bootstrap and 233-to-235 upgrade paths;
- RLS and direct-write denial;
- own-user and platform-owner privacy;
- advanced-kind exclusion;
- idempotent read/unread/archive/all-read commands;
- stale revisions and concurrent command outcomes;
- same-timestamp ordering via sequence plus ID;
- Realtime invalidation followed by canonical refetch;
- offline fail-closed commands and namespaced cache;
- no service-role or private payload in browser bundles;
- synthetic staging/canary cleanup with zero residual entities.
