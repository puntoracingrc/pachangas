# Demo World V2.8 Organizer Plans Parity Report

Date: 2026-08-28 CEST

## Snapshot

- Version: 2.8
- Seed: `pachangas-iq-demo-world-v2-8-2026-27`
- Manifest hash: `aae6c0c04a6049537fccbd4ffc8b45f811b9b50f7686b69ae1cd2e3205208640`
- Historical V2.1 through V2.7 chunks remain immutable; V2.7 is archived under `public/demo-world/v2-7/`.

## Scenarios

1. Audited Club partnership with active access and no charge.
2. Active Team Organizer Pro add-on while the Team base plan remains separate.
3. Active Club Organizer subscription.
4. `past_due` account inside bounded grace.
5. Canceled subscription preserving read continuity without allowing new creations.

## Safety

- Demo requests are GET-only and `remoteWrites=0`.
- No Stripe customer, subscription, Product or Price identifier is present.
- No PII, webhook payload, payment instrument or real price is present.
- Live Checkout is explicitly false.
- Session interaction is local and resettable; it cannot grant a real entitlement.
- The Service Worker caches immutable Demo chunks for offline reading and never queues a write.

## Visual QA

Desktop, portrait and game-landscape layouts were exercised. Scenario navigation, catalog cards, add-on labeling, price-pending copy and continuity states remain readable with no horizontal page overflow or console error. The internal horizontal tab rails and landscape content panel remain independently scrollable.

## Tests

Demo World V2: 17/17 focused tests, including deterministic hash, immutable history, privacy, GET-only behavior and warmed offline chunk reading.
