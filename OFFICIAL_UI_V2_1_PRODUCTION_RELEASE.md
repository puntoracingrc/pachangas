# Official UI V2.1 Production Release

## Release Decision

The product owner authorized an immediate production release and accepted the
following waivers for this release:

- visual approval: `APPROVED FOR IMMEDIATE PRODUCTION REVIEW`;
- physical Android QA: `PENDING / WAIVED FOR RELEASE`;
- physical iPhone QA: `PENDING / WAIVED FOR RELEASE`;
- installed physical PWA: `PENDING / WAIVED FOR RELEASE`;
- Rating V2 onboarding blocker: known pre-existing debt, not a release blocker;
- Preview Google Places selection blocker: known pre-existing debt, not a
  release blocker.

## Source And Merge

| Item | Value |
| --- | --- |
| Previous production `main` | `a4f2468d9b779db6a4391df7cec4cc34e4162fbe` |
| PR | `#163` |
| Authorized functional HEAD | `f25063f9490221b88e8f84edd1fad07cf4671cf5` |
| Merge method | Squash |
| Merge SHA / resulting `main` | `0045ec6f0a4098b93573c01766769f70c1005bce` |
| Merged at | `2026-08-23T16:57:22Z` |

No new Supabase path, migration, RPC or RLS change was present in PR #163.
Rating V2, rewards, Conduct, billing and R4A were not modified by this release.

## Final Validation

Validation ran against the exact authorized PR HEAD before merge:

| Gate | Result |
| --- | --- |
| `npm ci` | PASS; 21 inherited audit findings, dependency graph unchanged |
| Node runner | 20/20 PASS |
| TSX runner | 354/354 PASS |
| Canonical total | 374/374 PASS |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Focused rendered HTML | 9/9 PASS |
| Focused Official UI/OAuth/PWA/Demo/R3 | 64/64 PASS |
| Typecheck | PASS |
| Production build | PASS |
| `git diff --check` | PASS |
| Secret-value scan | 0 findings |
| Supabase paths in PR | 0 |
| RPC/RLS definition changes in PR | 0 |

## Rollback Checkpoint

Captured before the merge at `2026-08-23T16:56:20Z`:

| Item | Value |
| --- | --- |
| Previous deployment | `dpl_5sZieHebWq3Si4jz3ydPbRk2Xj6R` |
| Previous immutable URL | `pachangas-8bl6wbxg0-persianas-almar-web-s-projects.vercel.app` |
| Previous Service Worker SHA-256 | `30b584522668edf320e8cf852018bee8b771c3935d8ae267848364baa9247eef` |
| Production aliases | `pachangasiq.com`, `www.pachangasiq.com` |

## Production Deployment

| Item | Value |
| --- | --- |
| Deployment | `dpl_BzAYfgWZueQsqo9w83xWWhGxsDWk` |
| Immutable URL | `pachangas-6ziw1ti5z-persianas-almar-web-s-projects.vercel.app` |
| State | `READY` |
| Target | `production` |
| Created at | `2026-08-23T16:57:25Z` |
| New Service Worker SHA-256 | `1465fc516f7cbfc1c724feaf8c4f4e34b356933897fdc8fdc8b7a78fcb5f5be1` |
| Service Worker changed | YES |
| Service Worker cache policy | `no-cache, no-store, must-revalidate` |

Both production aliases resolve to the new deployment. The application root,
Market, Ranking, manifest, Service Worker, Official UI laboratory, Demo World,
Card, Shield, Alerts and Control Center return HTTP 200 on their canonical
routes.

## Production QA

Read-only QA covered desktop `1440x900`, portrait `390x844` and landscape
`844x390`.

| Surface | Result |
| --- | --- |
| Authenticated Home | PASS; shield protagonist, one primary action, metrics, agenda, activity, integrated selector and secondary card access |
| Match / Next / Lineup / Result / Admin | PASS |
| Market sections | PASS |
| Ranking | PASS |
| Alerts | PASS |
| Player card | PASS |
| Team shield | PASS |
| Demo World | PASS |
| Control Center authenticated | PASS |
| Mobile portrait | PASS; no horizontal overflow |
| Mobile Game Landscape | PASS; side HUD, single navigation, usable lineup, no desktop compression |
| Portrait -> landscape -> portrait | PASS; Lineup state retained |
| Broken images | 0 |
| Console runtime errors in tested surfaces | 0 |

The QA did not submit forms or execute destructive sporting writes.

## Known Debt

1. Rating V2 initial onboarding order blocks a genuinely profile-less owner.
2. Google Places produced no selectable prediction in the protected Preview
   fixture flow.
3. Physical Android QA remains pending.
4. Physical iPhone QA remains pending.
5. A real installed physical PWA pass remains pending.
6. Ranking `CRON_SECRET` remains a separate operational debt.

These items were explicitly waived for this release and were not repaired in
PR #163.

## Rollback Decision

Rollback: **NO**.

No white screen, global login failure, data leak, unusable primary navigation,
broken Match flow, PWA loop, generalized runtime error or exposed private
permission was observed. Minor visual preferences remain eligible for later
hotfixes without rolling back this release.

## Final State

- Official UI V2.1: `LIVE / ACTIVE`.
- Production deployment: `READY`.
- Supabase production: unchanged by Phase A.
- R4A: not modified by Phase A.
- Canonical backfill: not executed.
