# OFFICIAL UI V3G PRODUCTION RELEASE

## Release state

`PRODUCTION_ACTIVE`

Official UI V3G is merged, deployed and verified on the production domain. The
only remaining repository operation is merging this final evidence update and
removing its own clean worktree.

## Immutable inputs

- Initial main: `8ce3dec994c16e32fd9cae5a05f51e37f4537b6f`
- Functional PR: #256
- Branch: `codex/official-ui-v3g-social-inbox`
- Final functional branch SHA: `6018a0e96a142fc473936e85061adfbd17c27747`
- Functional merge SHA: `62cccab2ae08319f0c06977a2cc7e70b3af8b1e6`
- Production deployment: `dpl_EdhzJ5hUyA5Xn8aM87MsBpiNTAHw` (`READY`)
- Production domain: `https://pachangasiq.com`
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

## Production verification

- completed physical backup recorded before DDL: `1548932346`;
- both additive migrations applied once, remote ledger 235 and final version/name exact;
- all three receipt indexes valid/ready and both foreign keys covered;
- production SQL/RLS/idempotency canary executed inside `ROLLBACK` and returned zero synthetic users, Teams, Challenges, notices and receipts;
- exact merge deployment `READY`, Service Worker version `2.0.0+sw.62cccab2ae08` and valid manifest;
- `/`, `/avisos`, `/ajustes/notificaciones`, `/perfil/avisos`, `/demo?tab=avisos`, `/admin/demo`, `/mercado` and `/equipo` passed at 1440x900, 390x844 and 844x390;
- zero horizontal overflow, broken images, overlays or browser warnings/errors;
- cached offline Inbox, reconnection and disposable standalone-mode emulation: PASS;
- Vercel runtime errors: zero; deployment logs: zero 4xx and zero 5xx;
- physical Android, iPhone and installed-PWA checks remain `PENDING`, not PASS.

The post-DDL performance Advisor no longer reports the V3G unindexed foreign
key. The two new indexes only have expected zero-use INFO notices because the
receipt table remains empty. The two authenticated `SECURITY DEFINER` warnings
are intentional RPC boundaries: each resolves `auth.uid()`, fixes
`search_path=pg_catalog`, denies `anon` and exposes no direct table privilege.
Reference: [unused index Advisor](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index),
[authenticated SECURITY DEFINER Advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

## Disposable environment cleanup

- branch-scoped Preview variables removed: 3/3; branch readback empty;
- isolated Supabase branch deleted; final branch inventory contains only `main`;
- no staging user, Team, session, notification or immutable evidence remains because the complete branch was destroyed;
- no task-owned browser viewport, offline network emulation or temporary page mutation remains.

## Repository closure pending

- merge this final report update;
- wait for the documentation-only `main` deployment;
- verify the final `main` ancestry and clean status;
- remove this task's own worktree and prune registered worktrees.

## Fixed safety boundaries

- no real users, Teams, players or notifications;
- no push, email, SMS or WhatsApp delivery;
- no Stripe calls or payments;
- no advanced platform notifications in the social Inbox;
- no domain action executed by the Inbox;
- no physical-device QA claim without a real device;
- Wave 9C paused and V3H not started.
