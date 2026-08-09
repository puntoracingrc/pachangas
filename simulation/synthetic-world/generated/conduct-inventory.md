# Conduct, reports and no-show inventory

Generated from local product SQL, UI and DB tests. Absence of a general report route is reported as absence, not simulated as product.

| Capability | Classification | Evidence |
| --- | --- | --- |
| General player reports | not_implemented | No canonical table/RPC/UI located; guest withdrawal review is deliberately narrower. |
| Guest voluntary withdrawal | implemented | leave_pachanga_guest_match_v1 revokes access, frees the place and creates one review. |
| Guest withdrawal admin review | implemented | Admin confirms or dismisses; idempotent, revisioned, private identities, affectsSportRating=false. |
| Canonical no-show distinction | not_implemented | Product records status changes and guest withdrawal, but no attended/no-show fact distinct from cancellation. |
| Attendance joined notification | implemented | Only transition into voy notifies; retries do not duplicate. |
| Attendance cancellation notification | implemented | Only voy to no notifies; direct no does not imply misconduct or notify. |
| Injury and recovery notifications | implemented | Profile injured transition emits unavailable/available without medical detail. |
| Notification preferences | implemented | Six categories; in-app, push and email preferences are revisioned through RPC. |
| Mandatory administrative notices | implemented | Security/warning/sanction kinds are mandatory in-app even when a category is disabled. |
| Warnings and sanctions engine | partially_implemented | Delivery policy reserves security/warning/sanction kinds, but no canonical decision/history/restriction engine was located. |
| Independent-source weighting and report abuse defense | not_implemented | No general reports exist, so source-team independence, coordinated false-report detection and appeals are not product capabilities. |
| Conduct effect isolation from Rating V2 | partially_implemented | The one existing withdrawal review explicitly cannot alter sport rating. |

## Decision boundary

- A normal cancellation is not misconduct.
- Guest withdrawal review is not a no-show detector and creates no automatic sanction.
- General player reporting, independent-source weighting, restrictions and appeals remain product decisions.
- Notification transport can carry mandatory future warnings/sanctions, but that does not mean a sanction engine exists.
