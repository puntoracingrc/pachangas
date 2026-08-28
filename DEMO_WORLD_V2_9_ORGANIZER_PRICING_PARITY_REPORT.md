# Demo World V2.9 Organizer Pricing Parity Report

Date: 2026-08-29 CEST

## Snapshot

- Version: 2.9
- Seed: `pachangas-iq-demo-world-v2-9-2026-28`
- Manifest hash: `300c5490d8e1ff64dd6e9238228d57628bfbae5e70a0cde0f089c04c3adb7e74`
- Authority proof hash: `b9ee4eee8398d338891771eed13c6573deca1d532c01229b668e495fbd10f36a`
- Historical V2.1 through V2.8 snapshots remain immutable; V2.8 is archived
  under `public/demo-world/v2-8/`.

## Canonical scenarios

1. Club A on `CLUB_PARTNER`.
2. Club B on active monthly `CLUB_ORGANIZER`.
3. Club C on active annual `CLUB_ORGANIZER`.
4. Team D on active `TEAM_ORGANIZER_PRO` while its base plan stays separate.
5. Team E with Checkout pending and no entitlement from its redirect.
6. Team F in `past_due` with bounded grace.
7. Club G canceled with read continuity and no new creation entitlement.

The simulator applies the 196-migration product schema in a disposable
PostgreSQL database, drives the real internal billing processors and destroys
the database after export. It never calls Stripe remotely.

## Authority proof

- TEST Price mappings: 4.
- LIVE Price mappings: 0.
- Canonical Stripe events: 7.
- Operation receipts: 22.
- TEST runtime ready: true.
- Remote writes: 0.

No Product, Price, Customer, subscription, invoice, webhook or signing-secret
identifier is present. The snapshot contains no cards, tax data, email or real
payment instrument.

## Verification

The deterministic V2.9 generate/verify cycle and the 17-test Demo World suite
pass. Missing or changed Organizer Billing chunks fail verification. Immutable
hash checks for historical V2.1 through V2.8 remain active.

Final production manifest, Service Worker and responsive smoke are recorded in
`ORGANIZER_LIVE_CHECKOUT_V1_PRODUCTION_RELEASE.md`.
