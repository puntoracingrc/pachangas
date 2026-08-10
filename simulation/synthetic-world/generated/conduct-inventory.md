# Conduct, reports and no-show inventory

Generated from local product SQL, UI and DB tests. Feature availability is classified from canonical routes, not inferred from Synthetic World labels.

| Capability | Classification | Evidence |
| --- | --- | --- |
| General player reports | implemented | Context-bound, idempotent reports create clustered moderation cases without automatic sanctions. |
| Guest voluntary withdrawal | implemented | leave_pachanga_guest_match_v1 revokes access, frees the place and creates one review. |
| Guest withdrawal admin review | implemented | Admin confirms or dismisses; idempotent, revisioned, private identities, affectsSportRating=false. |
| Canonical no-show distinction | partially_implemented | A complete post-match roster closure distinguishes played, excused absence, late cancellation and unexcused no-show. |
| Attendance joined notification | implemented | Only transition into voy notifies; retries do not duplicate. |
| Attendance cancellation notification | implemented | Only voy to no notifies; direct no does not imply misconduct or notify. |
| Injury and recovery notifications | implemented | Profile injured transition emits unavailable/available without medical detail. |
| Notification preferences | implemented | Six categories; in-app, push and email preferences are revisioned through RPC. |
| Mandatory administrative notices | implemented | Security/warning/sanction kinds are mandatory in-app even when a category is disabled. |
| Warnings and sanctions engine | implemented | Warnings, explicit moderator restrictions, expiry and appeals are canonical; social restrictions remain independently flag-gated. |
| Independent-source weighting and report abuse defense | partially_implemented | Reports share source clusters by team/context while different teams increase independent-source count. |
| Conduct effect isolation from Rating V2 | partially_implemented | Guest withdrawal and Conduct V1 responses explicitly return affectsSportRating=false; no conduct path writes sport tables. |

## Decision boundary

- A normal cancellation is not misconduct.
- Guest withdrawal review remains narrower than post-match attendance closure.
- Reports create reviewable cases; no report imposes a sanction automatically.
- Warnings and restrictions require an internal moderator, and social restrictions have an independent feature flag.
- Conduct and attendance never alter Rating V2, Season Score, TOPS, achievements or reward boxes.
