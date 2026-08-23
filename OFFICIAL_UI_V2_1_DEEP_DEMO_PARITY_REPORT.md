# Official UI V2.1 Deep Demo Parity Report

## Release State

- Base: `origin/main` `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Branch: `codex/official-ui-v2-1-deep-demo-parity`.
- Starting HEAD for the authenticated gate:
  `c6733f6cb39c950ff70c590c5a6072e562554ea7`.
- Draft PR: [#163](https://github.com/puntoracingrc/pachangas/pull/163).
- Final HEAD: PR #163 `headRefOid` after the closing push.
- Merge: NO.
- Production: not modified.
- R4A PR #162: not modified.

## Product Story

Official Home follows the accepted Demo World hierarchy without importing demo
authority:

1. canonical team identity and `TeamShieldView`;
2. one primary sporting action and compact real metrics;
3. upcoming matches;
4. real season activity.

The player's own card is secondary. A team owner without a personal profile
never inherits another roster member's card. Team selection is integrated in
identity controls and detailed Team Access stays in a permission-guarded drawer.

Match remains one hub with Proximo, Alineacion, Resultado and Admin. Market,
Ranking, Notifications, Card and Shield retain their existing read models,
permissions and server-backed writes. Demo World remains isolated.

## OAuth And Authenticated QA

The Preview now uses a separate staging Google client and exact stable callback.
Login, logout, staging isolation and deep-link return pass for a real authorized
staging account without team/profile. Browser QA found and closed three concrete
defects: missing protected-route login, a leaked technical no-profile error and
loss of the Card query during OAuth return.

Canonical owner/player sessions remain pending because the second authorized
Google actor's device verification expired. Fixture coverage remains clearly
labelled and is not promoted to canonical evidence. Full detail is in
`OFFICIAL_UI_V2_1_AUTHENTICATED_QA_REPORT.md`.

## Visual QA

The pre-existing exhaustive V2.1 matrix covers 16 surfaces across seven
viewports, including `667x375`, `740x360`, `844x390`, `932x430` and PWA-emulated
portrait. Its recorded result remains 0 navigation errors, console issues,
failed requests, broken images, document overflow, viewport violations and game
chrome violations.

The new canonical staging pass adds nine PII-free captures:

| Captures | Console warnings/errors | Broken images | Overflow X | Technical leaks |
| ---: | ---: | ---: | ---: | ---: |
| 9 | 0 | 0 | 0 | 0 |

It covers Home desktop/portrait/landscape, no-team identity, no-profile Card,
Ranking, Notification Preferences and empty Notifications.

## PWA And Orientation

- Manifest: PASS.
- Service Worker controlled: PASS.
- Cached shell under simulated network offline: PASS.
- Reconnect and canonical state: PASS.
- Installed standalone Preview: PENDING.
- Physical Android/iPhone: PENDING.
- Market and Match rotation state: regression PASS with one navigation and no
  duplicate sporting write.

## Evidence Hygiene

Before hygiene, the PR contained 249 V2.1 evidence files and 19,372,386 bytes,
including 243 raw captures. The cleanup removed 179 raw files and 9,400,725
bytes while retaining all final contact sheets, Markdown/JSON matrices,
representative viewport evidence and canonical staging captures.

After hygiene:

- 82 evidence files;
- 9,978,764 bytes total;
- 75 capture/matrix files;
- 6,199,773 capture bytes;
- six contact sheets;
- nine canonical staging screenshots.

See `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_EVIDENCE_INVENTORY.md`.

## Engineering Gates

The closing run completed `npm ci`, the complete test suite, typecheck,
production build, focused lint and `git diff --check` after all
report/evidence changes. Results: 354/354 tests PASS (including the production
build), typecheck PASS, focused lint PASS and diff check PASS. Source-only
global lint still reports the documented out-of-scope baseline of 40 problems
(22 errors and 18 warnings); the generated Vercel output is excluded from that
baseline. The authoritative final HEAD/deployment is recorded in PR #163 and
the final handoff.

The focused OAuth/V2.1 suite passes 10/10. No Supabase, migration, SQL, RPC, RLS
or `app/api` path was added by this gate.

## Evidence

- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_AUTHENTICATED_FINAL_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_HOME_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MATCH_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MARKET_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MOBILE_GAME_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_DEMO_OFFICIAL_COMPARISON.png`

## Gate

PR #163 stays OPEN and DRAFT. OAuth staging and the no-team canonical case pass.
The PR must not be described as fully authenticated until the owner/player
second-identity rows are completed or Alberto explicitly accepts that limitation.
No merge or production deployment is authorized by this report.
