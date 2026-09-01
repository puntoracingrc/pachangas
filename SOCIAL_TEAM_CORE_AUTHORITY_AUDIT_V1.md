# Pachangas IQ Social Team Core Authority Audit V1

## Checkpoint

- Audit date: 2026-09-01 23:42:35 CEST.
- Branch: `codex/official-ui-v3f-social-team-core`.
- Audited commit: `bb95b056a018ab8868d1b80d3479873a630b832b`.
- Base: `origin/main` at the same commit.
- Initial worktree status: clean.
- Migration ledger represented in Git: 228 forward migrations.
- Runtime: Node `v24.16.0`, npm `11.13.0`, Supabase CLI `2.107.0`.
- Baseline: Node `20/20`; TS/TSX `747/747`; total `767/767`; skipped/todo/cancelled `0/0/0`.
- Sources: local application, migrations and tests. `supabase migration list --linked` was not available from this new isolated worktree because it intentionally had no linked project ref; no remote state was inferred from that failure.

## Classification

- `CANONICAL`: active server authority with a reachable product path.
- `LEGACY`: older implementation retained for compatibility.
- `PARTIAL`: server-backed, but missing one or more required V3F guarantees.
- `UNSAFE`: reachable behavior that violates the V3F authority or privacy contract.
- `UI_ONLY`: interface or local state without a confirmed server write.
- `MISSING`: no suitable authority exists.

## Consolidated inventory

| Area | Classification | Existing authority | Active path | V3F decision |
| --- | --- | --- | --- | --- |
| Auth user | CANONICAL | Supabase Auth and `auth.uid()` | Google/Auth session | Reuse; actor is always resolved server-side |
| Universal player sport profile | CANONICAL | `pachanga_player_profiles` | Profile, Rating V2, card, Market | Preserve unchanged as sporting authority |
| Independent social identity | MISSING | None | V3E local draft only | Add a minimal global social identity authority |
| Rating V2 | CANONICAL | Rating V2 tables, commands and snapshots | Assessment, cards and peer reviews | Read allowed projections only; never write or recalculate |
| Card/cosmetics | CANONICAL | Player card and cosmetics authorities | `/personalizar-carta` | Preserve and keep optional |
| Avatar | PARTIAL | `pachanga_player_profiles.avatar` plus cosmetics/avatar flows | Profile tied to sporting profile | Social identity stores only a safe avatar reference; sporting profile wins for its own card |
| Market publication | CANONICAL | Market profile/state and authoritative Market RPCs | Explicit publish/pause/unpublish | Reuse; profile/team creation never publishes automatically |
| Team | CANONICAL | `pachanga_groups` | Main product payload and team selectors | Reuse as the team aggregate |
| Membership | CANONICAL | `pachanga_group_members` | Direct canonical reads and role checks | Reuse; all new writes only through V3F commands |
| Owner | PARTIAL | `pachanga_groups.owner_id` plus owner membership | Existing teams | Preserve dual invariant; V3F creates both atomically |
| Admin | CANONICAL | membership `role=admin` | Existing capability checks | Preserve; no extra owner/billing/platform authority |
| Team code | PARTIAL | `pachanga_groups.team_code` | Member reads and selector | Keep as identifier; add reduced lookup; never grant membership |
| Legacy group invite token | UNSAFE | `pachanga_groups.invite_token` | `join_pachanga_team` | Remove from V3F reads; close or delegate membership grant |
| Ordinary player invitation | LEGACY / UNSAFE | raw group UUID token | `join_pachanga_team` | Replace with hashed, expiring, revisioned V2 invitation |
| Admin invitation | CANONICAL | `pachanga_admin_invites` and `accept_pachanga_admin_invite_authoritative_v1` | Explicit confirmation | Preserve as separate admin-only authority |
| Team creation | MISSING | RLS allows an owner group insert, but product has no atomic command | V3E button is fail-closed | Add one transactional `team.create` command |
| Initial shield | CANONICAL / PARTIAL | Team Shield Cosmetics V1 | Existing team identity editor | Validate a free/granted V1 selection, then initialize in the same transaction |
| Team operational state | CANONICAL | Wave 8B private operational tables and guards | Team state/control center | Initialize `ACTIVE/CLEAR`; enforce membership scope |
| Group payload | CANONICAL for legacy sporting read model | `pachanga_groups.payload` + revision | Match/team application | Create only a minimal valid empty payload; never use it as social identity authority |
| Operation receipts | PARTIAL | existing group receipts plus subsystem-specific private receipts | Several authoritative RPCs | Add immutable V3F receipts with request fingerprint and replay |
| Events | PARTIAL | group events and subsystem ledgers | Several group actions | Add V3F events without secrets or unnecessary Auth identity |
| Invalidations | PARTIAL | subsystem invalidation streams | Realtime refetch patterns | Add scoped profile/team/roster/invitation invalidations |
| Notifications | CANONICAL / PARTIAL | `pachanga_user_notifications` and private notifier | Membership trigger and product notifications | Reuse internal notifications; no external delivery in QA and no token in payload |
| Realtime | CANONICAL pattern | `postgres_changes` then canonical refetch | Profile, groups and other products | Subscribe only to scoped invalidations and refetch read models |
| Team selector | PARTIAL | direct membership/group query; first membership fallback | Main page shell | Consume canonical `MyTeams`; preserve an authorized selected team |
| Local cache | CANONICAL only as derived cache | localStorage read caches/drafts | Profile, main app and PWA | Keep bounded snapshots and drafts; never confirm writes offline |
| V3E profile flow | UI_ONLY | onboarding draft in React/localStorage | `?social=profile` | Wire save to social profile command and canonical readback |
| V3E create flow | UI_ONLY / fail-closed | `TEAM_CREATION_AUTHORITY.available=false` | `?social=create` | Wire to `team.create`; no optimistic team |
| V3E ordinary join | LEGACY / PARTIAL | `join_pachanga_team` | explicit click after link | Replace with invitation V2 accept command |
| `/equipo` | UI_ONLY redirect | redirects to `/?mobile=equipo` | Product route | Replace with a real team home and separate roster/invitation surfaces |

## Existing canonical relationships

```text
auth.users
  1 -> 0..1 pachanga_player_profiles (sporting identity, Rating/card/Market)
  1 -> 0..n pachanga_group_members -> pachanga_groups

pachanga_groups.owner_id
  must match exactly one active owner membership for the same user

pachanga_groups.payload
  legacy sporting aggregate/read model; not a source for independent social identity
```

`pachanga_player_profiles` is global by `user_id`, but it is not a safe V3F social identity container. Its creation/upsert path is team-scoped, it projects into group payloads, and it contains Rating, facets, assessments, Market state, private phone data and sporting state. Adding independent onboarding writes there would couple first access to Rating V2 and could overwrite a real sporting profile.

## Required new authority

The audit therefore permits one new bounded subsystem, rather than a duplicate team or player model:

```text
pachanga_social_player_profiles
private.pachanga_social_operation_receipts_v1
private.pachanga_social_events_v1
pachanga_social_invalidations_v1

pachanga_team_player_invitations_v2
private.pachanga_team_player_invitation_secrets_v2
```

`pachanga_groups` and `pachanga_group_members` remain the only team and membership authorities. No `LocalTeam`, onboarding membership or second team table is permitted.

## Data precedence

| Final datum | Initial source | Sources allowed to modify it | Order | Merge rule | Reconstructible |
| --- | --- | --- | --- | --- | --- |
| Auth identity | Supabase Auth | Auth provider/account controls | Auth only | Replace by authenticated account state | Yes |
| Social display name | Social profile command | User's social profile command | Social identity | Last confirmed revision | Yes, from revisions/events |
| Team roster display name | Membership projection | Membership command/admin role-safe command | Membership, then social fallback | Explicit team label overrides social name only inside that team | Yes |
| Sporting profile name/avatar/position | `pachanga_player_profiles` | Existing authoritative profile commands | Sporting profile | Never overwritten by V3F social onboarding | Yes |
| Card/GRL/facets | Rating V2 | Rating V2 events only | Rating V2 | Server-calculated | Yes |
| Public card | Card/cosmetics projection | Existing card/cosmetics authorities | Card authority | Social identity can provide a fallback label/avatar only | Yes |
| Market state | Market authority | Existing publish/pause/unpublish commands | Market authority | Explicit, never inferred from profile/team | Yes |
| Team owner | Atomic team create or existing role authority | Existing owner transfer authority only | Team aggregate + owner membership | Exact invariant, not a client-selected field | Yes |
| Team role | Membership authority | Invitation/admin/role commands | Membership revision | Server command result | Yes |
| Selected team | Authorized `MyTeams` read model | User navigation | Client preference constrained by server list | Keep if still authorized; otherwise deterministic allowed fallback | Yes from preference plus memberships |
| Team code | Team create | No client write | Server generated | Lookup only | Yes |
| Invitation access | V2 secret hash + invitation state | Create/revoke/accept/decline commands | Latest invitation revision and use count | Token equality by hash; no code fallback | Yes without raw token |

## Security findings

1. `join_pachanga_team(uuid,text)` grants player membership from `pachanga_groups.invite_token` without operation ID, expected revision, expiry, revocation state, use limit, request fingerprint or Team Operational membership guard. It is `UNSAFE` for V3F.
2. The legacy raw `invite_token` is selected with normal team data in `app/page.tsx`. V3F read models must not return it.
3. Authenticated clients still retain direct `INSERT` privileges on `pachanga_groups` and direct `INSERT/UPDATE` privileges on `pachanga_group_members` from early migrations. RLS narrows some paths, but V3F must revoke direct writes and expose command RPCs only.
4. Existing admin invitation acceptance is versioned, idempotent and explicit. It must remain isolated from player invitations so a player token can never grant `admin` or `owner`.
5. Existing profile reads expose only the caller's universal profile under RLS, but the table mixes private and sporting fields. A reduced social read model is required.
6. Existing Realtime use correctly treats events as invalidation signals and refetches canonical rows. V3F should follow that pattern, not apply WAL payloads as authority.

## Team creation contract

The V3F command must hold a user-scoped advisory transaction lock and create, in one transaction:

1. one `pachanga_groups` row with server-generated ID/code and a minimal valid payload;
2. one owner membership matching `owner_id`;
3. one Wave 8B state initialized as `ACTIVE/CLEAR`;
4. one allowed initial shield state or the canonical free default;
5. social settings/read projection as needed;
6. one receipt, event and scoped invalidation.

Any failure rolls the transaction back. A replay with the same actor, operation ID and request fingerprint returns the same response. Reusing the operation ID with another payload fails.

## Invitation V2 contract

- The raw secret is generated by PostgreSQL and returned only from `team.invitation.create`.
- Only its cryptographic hash is persisted.
- It expires, is revocable, revisioned and single-use in V3F.
- Lookup is reduced and does not grant membership.
- Acceptance locks both invitation and team, verifies Wave 8B membership administration, creates at most one player membership, consumes one use and returns canonical team/read-model revisions.
- Events, receipts, notifications, invalidations, logs, Demo and Realtime never contain the raw secret.
- Team code is not accepted by the membership command.

## Read model boundaries

- `MySocialProfile`: caller's safe profile fields, revision, sequence and timestamps.
- `MyTeams`: team ID, code, name, safe shield, modality, general area, role, safe operational status, member count and next-match summary.
- `SocialTeamHome`: safe identity, caller capabilities, one primary action, next match, roster summary and recent social activity.
- `SocialTeamRoster`: reduced members and roles; no email, phone, Auth ID, token or private operational reason.
- `SocialTeamInvitationList`: owner/admin-only metadata, never raw token/hash.
- `SocialTeamInvitationLookup`: reduced team preview plus invitation revision/expiry/state for the authenticated holder of a raw secret.

## Legacy reconciliation decision

V3F will use only the new V2 commands. `join_pachanga_team` and the older `join_pachanga_group` must stop granting membership to authenticated clients once the V3F UI is deployed. Compatibility is provided by explicit update-required behavior, not by keeping a second divergent membership authority. The admin invitation RPC remains active and separate.

## Audit result

The required V3F scope is implementable without modifying Rating V2, card formulas, Market publication semantics, Clubs, competitions, billing or Stripe. The safe path is:

```text
Auth
  -> independent social profile command
  -> atomic team create OR player invitation V2 accept
  -> canonical group membership
  -> reduced team home/roster read models
  -> V3B first match
```

No production or staging data was changed during this audit.
