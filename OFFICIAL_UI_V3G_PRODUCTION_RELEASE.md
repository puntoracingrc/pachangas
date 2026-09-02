# OFFICIAL UI V3G PRODUCTION RELEASE

## Release state

`PENDING_RELEASE`

This file is intentionally present before merge so the release evidence has a
stable canonical location. It must not be interpreted as evidence of staging,
merge, migration or production deployment until the sections below contain
their final readbacks.

## Immutable inputs

- Initial main: `8ce3dec994c16e32fd9cae5a05f51e37f4537b6f`
- Functional PR: #256
- Branch: `codex/official-ui-v3g-social-inbox`
- Initial migration ledger: 233
- Planned final ledger: 234
- Migration: `20260902064632_social_inbox_authority_v1.sql`
- Migration SHA-256: `4ade702f4ae82b4fbbabbf79d0cb3ee037b11d9345ee9dd8ab1853c36165460b`
- Supabase production project: `Pachangas` (`qonbngfrnrqgmxbdfbea`)
- Pre-release remote ledger: 233 exact local/remote pairs through `20260901214527`; only `20260902064632` is pending remotely

## Pending evidence

- Supabase staging branch and authenticated two-device QA;
- synthetic staging cleanup readback at zero;
- final branch SHA and merged main SHA;
- production migration ledger/readback;
- exact Vercel deployment ID, SHA and READY state;
- production desktop, portrait, landscape and PWA smoke;
- production canary rollback/readback at zero;
- manifest, Service Worker, logs and redirect checks;
- final report merge and worktree cleanup.

## Fixed safety boundaries

- no real users, Teams, players or notifications;
- no push, email, SMS or WhatsApp delivery;
- no Stripe calls or payments;
- no advanced platform notifications in the social Inbox;
- no domain action executed by the Inbox;
- no physical-device QA claim without a real device;
- Wave 9C paused and V3H not started.
