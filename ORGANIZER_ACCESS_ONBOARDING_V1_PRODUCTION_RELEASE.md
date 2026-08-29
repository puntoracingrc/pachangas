# Organizer Access and Onboarding V1 Production Release

Closed: 2026-08-29 CEST

## Release checkpoint

- Initial `main`: `e0cbf7bd45f8d38e4edc8bc7dc97fd1272ec355f`.
- Implementation commit: `c941294f93ab282aa5dfd23f9c0cce55161258ff`.
- Final implementation branch commit: `08a3b9286766d140424ab7d3c743076ad7f5ac33`.
- PR #223: merged.
- PR #223 merge SHA: `be8dab63dfedbc2abf34a9b48b0ec619cfc94536`.
- Hydration hotfix commit: `7d701f968d436d4cb0c75a441abfc26d36c8be6c`.
- PR #224: merged.
- Final functional production SHA before this report-only merge:
  `b9c21ae57e0e7cec0cff3647561d7f92e20e6493`.
- Production deployment: `dpl_9j39rC8vUfBu1en2M4ZQLTDHYWBE`, `READY`.
- Production URL: `https://pachangasiq.com`.
- Stripe touched: NO.
- Real charges: 0.
- Next Wave started: NO.

## Exact migrations

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20260829152223` | `organizer_access_applications_revisions_v1` | `33f8afe66ac0d70bd360cb8ad742a0e6176e81ad513ee143e8265442b0096c97` |
| `20260829152228` | `organizer_access_review_decisions_messages_v1` | `b8d20bc87f00f1a1c642d3c97282fa45c35aaab089839e73c3e9836ba4947d7c` |
| `20260829152232` | `organizer_access_entitlement_bridge_authority_v1` | `b2d212040a132d32bc5bf3bcbe65b7d76c0ce578660f118780ee302ee1c7fcc7` |
| `20260829152237` | `organizer_guided_onboarding_workspace_v1` | `aec76c43df08f4650b1d2e87d8e38dd2844fde1ec8b0c4686016c9f1ea13a0d3` |
| `20260829152241` | `organizer_access_read_models_control_center_v1` | `dc96f902d1e497a4b46036e6b22ce60a6c3e649103a6f73f0e1d1207a7e4e475` |
| `20260829152246` | `organizer_access_rls_realtime_notifications_v1` | `e9b39a21e8fce0adda1bf07b3d2fcd50c6b99e1817fa6095a06126bdbe2b2568` |
| `20260829152250` | `organizer_access_hardening_indexes_flags_v1` | `b34cb55b2883951da3df557728740e6cbc8e9a7b996609ce2aebbe255060afe1` |

All seven are forward-only. The 197 previous versions were not rewritten.
Direct SQL readback from `supabase_migrations.schema_migrations` confirms 204
remote versions and the seven exact Wave 8A names above.

## Recovery checkpoint

- Physical Supabase backup ID `1509546398`, status `COMPLETED`, created
  `2026-08-29T00:16:58.120Z` in `eu-west-1`.
- WAL-G backup support was available. PITR was not enabled.
- Redacted logical role, schema and data dumps were generated locally with
  mode `0600` and verified before migrations.
- Temporary logical dumps were removed after final production readback; the
  physical backup remains the durable recovery point.

## Validation gates

| Gate | Result |
| --- | --- |
| Organizer access focused suite | 17/17 PASS after hotfix |
| SQL/RLS/idempotency | PASS |
| Concurrency | 13/13 PASS, cleanup PASS |
| Fresh PostgreSQL bootstrap | 204 migrations PASS |
| Global product tests | 616/616 PASS after hotfix |
| Skip/todo/cancelled | 0/0/0 |
| Typecheck | PASS |
| Build | PASS |
| Focused lint | PASS |
| Global lint | 40 pre-existing findings; no Wave 8A finding |
| `git diff --check` | PASS |
| Secret scan | PASS |
| Local Security Advisor | 0 findings |
| Production Performance Advisor | 1 global pre-existing finding; 0 Wave 8A |

The production Security Advisor retains 411 global notices, primarily its
generic treatment of authenticated `SECURITY DEFINER` RPCs and anonymous-signin
RLS heuristics. Wave 8A SQL tests confirm exact ACLs, ownership checks and no
direct authority-table writes by `anon` or `authenticated`.

## Staging

- Disposable Supabase branch `iozcjirlfytryzrcmrnq` was reconciled to the
  canonical 197-version baseline and then advanced to ledger 204.
- Six authenticated application stories, two simultaneous clients, ownership
  transfer, private-note isolation, paid interest without grant, launcher,
  cancellation, grant revocation, mandatory notification deduplication and
  Realtime invalidation plus canonical refetch passed.
- RLS regression W8A-018 was found in staging, recorded, fixed with the minimum
  predicate `EXECUTE` privilege and covered by SQL plus authenticated E2E.
- The disposable branch was deleted after production verification. Branch
  readback now lists only `main`.
- The five branch-scoped Preview variables were removed. Variables belonging
  to other branches and shared environments were not touched.

## Controlled activation

All writes used `command_pachanga_organizer_access_application_v1` with an
idempotent operation ID and expected revision. No direct `UPDATE` was used.

| Revision | Activated capability |
| --- | --- |
| 1 -> 2 | Organizer Access Applications |
| 2 -> 3 | Submission |
| 3 -> 4 | Partnership Review |
| 4 -> 5 | Partnership Approval |
| 5 -> 6 | Guided Onboarding |
| 6 -> 7 | First Competition Launcher and Demo World V3.0 |

Final readback at revision 7 reports all seven Wave 8A flags `true`.

Commercial safety readback remains:

- pre-existing Stripe Sandbox: `true`;
- Stripe TEST Checkout: `false`;
- Stripe TEST Portal: `false`;
- LIVE Checkout: `false`;
- LIVE prices approved: `false`;
- production portal: `false`.

## Production canary

One ephemeral, transactional canary exercised the real canonical RPC chain:

`draft -> submit -> start review -> request information -> respond -> approve`

It then created a temporary `PRIVATE_BETA` grant, launched one canonical League
draft, cancelled that wizard and revoked the grant. Replaying the first
operation returned the same receipt. Every command enforced the expected
revision. Seven ordered events and seven mandatory notifications were visible
inside the transaction.

The complete transaction was rolled back. Independent readback confirmed zero
canary groups, memberships, applications, grants, entitlements, workspaces,
invalidations, wizards, competitions and operation receipts. Global final
Wave 8A state contains:

- 0 applications;
- 0 decisions;
- 0 application-created grants;
- 0 onboarding workspaces;
- 0 invalidations;
- 6 platform activation receipts;
- 1 idempotent expiry-notification worker receipt.

## Web, Realtime and PWA smoke

- Public and authenticated product routes return `200` on the exact production
  deployment.
- Control Center reload shows 7/7 active flags, zero overflow, zero broken
  images and no fresh console entries.
- The React hydration timezone defect was fixed in PR #224 and did not recur.
- Vercel runtime logs for the deployment show 0 errors, 0 warnings, 0 4xx and
  0 5xx in the inspected release window.
- Supabase API sample: 100 events, 94 HTTP 200 plus 6 Realtime upgrades 101,
  with no 4xx/5xx. Auth and Realtime logs show no error signal.
- PostgreSQL errors in the release window are the six recorded, rolled-back
  canary harness incidents W8A-025 and W8A-031 through W8A-035 plus the
  read-only naming mistake W8A-041. The corrected final readbacks pass and no
  unrecorded database error remains.
- Service Worker is active and controls `https://pachangasiq.com/`.
- Offline proof blocked a non-cacheable API request before and after navigation;
  the Demo document and eleven V3 fragments were served with
  `fromServiceWorker=true` and local cache. Online reconnection then returned a
  fresh non-cacheable `200` and preserved the canonical Demo route.

Physical Android, iPhone and installed-device PWA QA remain `PENDING`. They are
not represented as PASS.

## Demo World V3.0

- Manifest version: 3.
- Seed: `pachangas-iq-demo-world-v3-0-2026-27`.
- Hash: `f641bc1c787b08102ed14b2c15f58adcab86ad0fc031df360bd78593984bac1c`.
- Organizer access scenarios: 6.
- Public competitions: 4.
- Remote writes: 0.

## Residual product decision

W8A-005 remains open: Team has no canonical operational suspension status. No
synthetic boolean or billing state was reused as a sanction. Club suspension
and actor authority are enforced; a future cross-product Team status contract
is required for that one case.

## Cleanup

- Supabase staging branch `63ed59d3-7ace-4bda-acd3-21035a12ae31`: deleted.
- Branch-scoped Preview variables removed: 5/5.
- Owned Preview deployments for the implementation and hotfix branches:
  removed 5/5. The production deployment remains `READY` and aliased.
- `/private/tmp/pachangas-wave8a*`: empty after cleanup, including temporary
  credentials, fixtures, dumps, logs and migration push directories.
- Local development server on port 3090 and its child process: stopped.
- QA network override: restored online. QA viewport: reset. Agent-created
  Browser and Chrome tabs: closed.
- No Stripe resource or production secret was created, changed or removed.
