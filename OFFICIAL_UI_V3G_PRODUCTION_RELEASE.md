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
- Final migration ledger: 235
- Authority migration: `20260902064632_social_inbox_authority_v1.sql`
- Authority migration SHA-256: `4ade702f4ae82b4fbbabbf79d0cb3ee037b11d9345ee9dd8ab1853c36165460b`
- FK-index migration: `20260902102800_social_inbox_receipt_notification_index_v1.sql`
- FK-index migration SHA-256: `3cbc006045c326737faf66210bc92753d7adf1ffd23dc0510958c24efcc51067`
- Supabase production project: `Pachangas` (`qonbngfrnrqgmxbdfbea`)
- Pre-release remote ledger: 233 exact local/remote pairs through `20260901214527`.
- Authority migration applied: ledger 234, exact version/name and canonical readback PASS.
- FK-index correction: isolated staging certification PASS; production ledger/readback PASS.

## Completed pre-production evidence

- isolated Supabase branch bootstrapped to the authority ledger and advanced to the exact 235-version corrected ledger;
- authenticated four-actor, two-Team staging dataset;
- two devices converged through Realtime invalidation and canonical refetch;
- direct writes, cross-user reads and stale/duplicate action effects denied;
- exact Preview bundle used only the ephemeral staging public project;
- no service-role value or token in browser code;
- 1440x900, 390x844, 844x390 and installed-mode Preview smoke: PASS;
- Service Worker control and cached offline Inbox shell: PASS;
- zero unexpected console errors, page errors, HTTP failures, overflow or broken images.
- production contains both exact V3G migration receipts, all three receipt indexes are valid/ready and both receipt foreign keys are covered;
- the V3G `unindexed_foreign_keys` Advisor finding is closed; only expected zero-use INFO notices remain for the new indexes;
- direct receipt-table access remains denied to `anon` and `authenticated`; the two self-authorizing RPCs remain authenticated-only.

## Pending release evidence

- disposable staging branch destruction and branch-scoped Preview variable removal;
- final branch SHA and merged main SHA;
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
