# Organizer Billing Control Center V2 Report

Date: 2026-08-28 CEST

## Capabilities

The existing Platform Control Center gains one bounded Organizer Billing surface:

- health and aggregate counts;
- feature-flag activation through the canonical platform RPC;
- one flag change per expected revision;
- organizer-specific approved Price mapping;
- tax-health state;
- manual partnership, promotion, private-beta and platform grants;
- revoke and renew operations;
- dedicated reconciliation requests;
- redacted account, subscription, invoice, delivery and drift queues.

## Security

- Every mutation requires `platform_admin`; live Price approval and live Checkout require `platform_owner`.
- The API derives actor and authority from the authenticated server session.
- Direct table writes are revoked from browser roles.
- Unknown actions and payload keys fail closed.
- Manual grants require organizer identity, plan compatibility, reason, expected revision and idempotent operation ID.
- `CLUB_PARTNER` additionally requires the partnership gate.
- Full Stripe identifiers, webhook payloads, signatures, Auth identities and private receipts never enter the ordinary UI response.

## Activation Dependencies

The settings row enforces the dependency graph. In particular, live Checkout requires foundation, catalog, accounts, webhook ingest, Portal, approved live Prices and `tax_health=LIVE_READY`. It cannot be activated by toggling a browser control out of order.

Recommended V1 activation order:

1. Foundation.
2. Plan catalog.
3. Billing accounts.
4. Partner grants.
5. Organizer UI.
6. Webhook ingest and reconciliation.
7. Stripe sandbox.
8. Portal only after its remote path is validated.
9. Demo World V2.8.

Live Prices and live Checkout remain OFF.

## QA

The dedicated reconciliation branch, expected-revision contract, role split and redaction are covered by focused tests, SQL/RLS tests and concurrency races. No Control Center operation trusts a client-calculated entitlement.
