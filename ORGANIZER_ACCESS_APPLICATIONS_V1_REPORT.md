# Organizer Access Applications V1 Report

Date opened: 2026-08-29 CEST

## Initial audit

Wave 8A starts from the production `main` SHA
`e0cbf7bd45f8d38e4edc8bc7dc97fd1272ec355f` and repository ledger 197.
The existing canonical path is:

`OrganizerPlanCatalog -> OrganizerAccessGrant -> CompetitionEntitlementGrant -> Competition`

The missing product path is:

`OrganizerAccessApplication -> platform review -> explicit decision -> existing grant`

The implementation will add that missing path without introducing a second
permission model, a frontend organizer boolean or an application-owned
entitlement.

## Existing authorities to reuse

- Team ownership from `pachanga_groups.owner_id`.
- Club ownership and staff capability from the Club Foundation.
- Plans and plan revisions from the Organizer Plan Catalog.
- Access bundles and projected competition capabilities from Organizer
  Billing.
- Competition drafts, rules, league and tournament wizards from the existing
  competition engines.
- Platform roles and capabilities from Control Center.
- Existing notification, receipt, event, revision, sequence and invalidation
  patterns.

## Release boundary

Stripe resources, variables, routes and flags are not part of Wave 8A. Paid
plan interest may be reviewed, waitlisted or converted into an explicit
non-subscription grant, but never into a fictitious paid subscription.

Implementation and release evidence will be completed in this report before
the Wave 8A production release closes.
