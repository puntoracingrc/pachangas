# Core Social Flows Closure V1

## Scope and safeguards

- Base: PR #119, commit `93361fe0f22cafb8bd31fbde65fa055774ac0ca4`.
- Branch: `codex/core-social-flows-closure-v1`.
- Runtime used: local repository, local PostgreSQL/Supabase-compatible database and an isolated disposable PostgreSQL clone.
- Remote Supabase and production: not accessed or modified.
- Synthetic World V1 source preserved: `3df9494d-3b8c-4447-96e8-d5244892af78`, revision `313`, server sequence `69458`.
- Conduct remains in shadow mode. TOPS V1 and its flags remain unchanged. No cosmetic system was changed.

## Audit inventory

| Capability before this branch | Initial classification | Closure result | Canonical authority |
| --- | --- | --- | --- |
| Player/admin leaves a group | NOT_IMPLEMENTED | IMPLEMENTED | `leave_pachanga_group_authoritative_v1` |
| Owner transfer before leaving | NOT_IMPLEMENTED | IMPLEMENTED | `transfer_pachanga_group_ownership_authoritative_v1` |
| Admin removes a member | PARTIAL | IMPLEMENTED | `remove_pachanga_group_member_authoritative_v1` |
| Leave and later rejoin | PARTIAL | IMPLEMENTED | leave RPC + existing `join_pachanga_team` reactivation |
| Challenge expiry | NOT_IMPLEMENTED | IMPLEMENTED | server-time reconciliation + guard + service-role batch hook |
| Admin invitation | PARTIAL | IMPLEMENTED | existing creation + authoritative acceptance |
| Public match market | PARTIAL | IMPLEMENTED | existing V2 RPCs wrapped with lifecycle reconciliation |
| Guest leaves accepted place | IMPLEMENTED_BUT_NOT_SYNTHETIC_COVERED | IMPLEMENTED_AND_COVERED | `leave_pachanga_guest_match_v1` |
| Lineup and reserves | IMPLEMENTED_BUT_NOT_SYNTHETIC_COVERED | IMPLEMENTED_AND_COVERED | existing attendance and lineup V2 RPCs |

The generated capability matrix is in `simulation/synthetic-world/generated/product-inventory.md`. It now separates active browser routes from server-side lifecycle activation.

## Membership lifecycle

All new membership mutations require an authenticated actor, an `operation_id` and the expected group payload revision. They acquire a transaction-scoped advisory lock, fail on stale revisions, increment the canonical group revision, store an operation receipt and append an auditable group event.

- Player or non-owner admin may leave without administrator intervention.
- Owner may not leave until ownership is explicitly transferred. No successor is inferred automatically.
- Transfer promotes one current member to owner and keeps the previous owner as admin.
- Owner/admin may remove members according to the existing role boundary; an ordinary admin cannot remove an owner or another admin.
- Departure removes only future, unfinished participation, team placement, scorers and payer references. Historical matches stay unchanged.
- The group read model marks the linked local player inactive. Rejoining through the existing team code reactivates that same player identity.
- Universal profile, Rating V2, facetas, achievements, reward boxes, historical statistics, Conduct history/restrictions and ranking evidence are not modified.
- The group receives the noncritical `group_member_left` notification for voluntary departures.

## Challenge lifecycle

Pending `proposed` and `changes_proposed` challenges become `expired` when their scheduled deadline plus configured grace has passed. Accepted, rejected and cancelled challenges do not expire.

- Server clock is authoritative.
- Default grace is zero and configurable in a private singleton table.
- No inactivity TTL was invented. `proposal_ttl` remains a product decision.
- A deadline trigger prevents late acceptance/counterproposal.
- Snapshot reads perform lazy server-side reconciliation; an explicit authenticated reconciliation RPC and a service-role batch hook also exist.
- Repeated reconciliation produces one transition, one event and one notification set.
- Expired challenges stay in history as `Caducado` and create no match, known opponent, Season Score evidence, Rating evidence, achievement or reward.
- The accept/expire race converges to exactly one final transition.

## Admin invitations

The existing creation flow is retained. Acceptance now has revision, operation receipt and server sequence semantics.

- Resulting role is admin, never owner.
- Retry from the same operation and replay from another device do not duplicate membership or events.
- Foreign-user reuse and expired tokens fail.
- An existing owner remains owner.
- Explicit invitation revocation is not implemented; expiry is currently the only invalidation mechanism and remains `NEEDS_PRODUCT_DECISION`.

## Public market

The existing market is not redesigned. Its authoritative request, review, sync and search paths now reconcile lifecycle state before acting.

- Started, finalized, cancelled, missing, full or lineup-closed matches cannot continue accepting places.
- Closing the market also resolves remaining pending requests as rejected.
- Two concurrent acceptances for the last place produce one accepted request, one rejected request, one guest-access row and zero open slots.
- An accepted guest retains read access through the existing RLS contract and can leave through the existing canonical RPC.
- Reopening a past market is rejected.

## Lineups, reserves and guests

The branch does not replace the existing V2 lineup model. Regression coverage proves:

- attendance can enter playing or reserve state while the lineup is open;
- reserves may retain payment state;
- admins close the lineup through the canonical revisioned RPC;
- attendance and lineup mutation after closure are rejected;
- guests participate under the existing match-guest RLS boundary;
- unrelated users cannot edit another group's lineup or review its requests.

## Synthetic World V2

Core Social V2 clones the preserved V1 world and never mutates it. The primary clone is `47f2515f-c723-46e9-b707-4d1e58dc8c74`.

- 18 canonical flows covered.
- 10 linked stories per seed.
- 30 deterministic seeds.
- 540 flow passes and 960 new synthetic events.
- 300 generated stories.
- 0 failed seeds.

Required combined stories include:

1. Accepted challenge + guest + lineup change + finalized/disputed result.
2. Leave with an active public match + access withdrawal + later rejoin without a new identity.
3. Conduct state and person-bound restriction preserved through a team change; real restriction persistence is verified in SQL while Conduct stays in shadow.
4. Counterproposal immediately before expiry; one canonical transition wins.

The generated audit is `simulation/synthetic-world/generated/core-social-flows-v2-summary.json`.

## Adversarial and concurrency coverage

SQL/RLS rejects self-service attempts to remove another user, force ownership, expire an unrelated challenge, accept another team's market request, edit another lineup or reopen a past market. Private helpers are not executable by `authenticated`, and direct `DELETE` on memberships remains closed.

Concurrent regressions cover:

- self-leave versus admin removal;
- owner transfer versus owner leave;
- accept versus expire;
- two users competing for the final public place;
- same-operation retries and different-device replays.

## Preserved systems

- Rating V2 and facetas: unchanged.
- Conduct V1/V1.1 reports, no-shows, warnings and person-bound restrictions: preserved; no automatic sanction activation.
- Season Score and TOPS: unchanged, no reset on team change.
- Achievements and reward boxes: unchanged.
- Historical match evidence: unchanged.

## Permanent incidents

Core Social discoveries are recorded as `SW-0117` through `SW-0143` before correction. All product/simulation incidents in this range are fixed with regression evidence except:

- `SW-0134` (`ENVIRONMENT_ISSUE`): the historical migration chain is not independently bootstrappable from an empty database because older migrations expect `pachanga_admin_invites` from the consolidated `supabase/pachangas.sql` baseline. The new migration itself passed once in a disposable schema clone built from that baseline. Repairing historical bootstrap belongs to a separate maintenance change.

## Remaining product decisions

- `team.admin_invite.revoke`: explicit revocation of an unused admin invitation.
- `challenge.proposal_ttl`: optional inactivity expiry independent of the scheduled match deadline.

No parallel state or fictitious product route was added for either gap.

## Validation

Final closeout results:

- Focused Core Social TypeScript tests: 3/3 pass.
- Core Social SQL/RLS: pass.
- Core Social concurrency: pass.
- Team social SQL/concurrency: pass.
- Match guest SQL/concurrency: pass.
- Rating V2 SQL/concurrency: pass, including all eight established races.
- Conduct V1 and V1.1 SQL/concurrency: pass.
- Achievement Catalog V3 SQL/concurrency: pass.
- Main product suite: build + 196/196 tests pass.
- General Synthetic World suite: 26/26 tests pass, including a full season.
- Core Social V2 soak: 30/30 seeds, 540 flow passes, 0 failed seeds.
- Typecheck: pass.
- Production build: pass, 27 routes generated.
- Focused lint excluding the pre-existing monolithic `app/page.tsx` debt: 0 errors, 0 warnings.
- Global lint: 23 errors and 20 warnings, confined to the four pre-existing debt files `app/legal-data.tsx`, `app/mercado/page.tsx`, `app/page.tsx` and `app/theme-toggle.tsx`. No finding points to a newly added line.
- `git diff --check`: pass.

No migration was applied to staging or production as part of this branch.
