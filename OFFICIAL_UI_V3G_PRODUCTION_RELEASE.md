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

## Completed pre-production evidence

- isolated Supabase branch bootstrapped to the exact 234-version ledger;
- authenticated four-actor, two-Team staging dataset;
- two devices converged through Realtime invalidation and canonical refetch;
- direct writes, cross-user reads and stale/duplicate action effects denied;
- exact Preview bundle used only the ephemeral staging public project;
- no service-role value or token in browser code;
- 1440x900, 390x844, 844x390 and installed-mode Preview smoke: PASS;
- Service Worker control and cached offline Inbox shell: PASS;
- zero unexpected console errors, page errors, HTTP failures, overflow or broken images.

## Pending release evidence

- disposable staging branch destruction and branch-scoped Preview variable removal;
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
