# Official UI V2.1 Final Human Review Report

## Decision Gate

PR [#163](https://github.com/puntoracingrc/pachangas/pull/163) remains OPEN and
DRAFT. Merge and production are not authorized.

Stable OAuth Preview:
`https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app`

The exact immutable Preview and final `headRefOid` are recorded in the PR body
after the closing push.

## Review Focus

1. Home reads as team identity, shield, next action and season.
2. `Mi carta` remains secondary.
3. Team selector is integrated and Team Access stays in its drawer.
4. Match and Market use one navigation and retain context.
5. Desktop, portrait and landscape have no document overflow.
6. Empty/no-profile states use product language and one next action.
7. Explicit theme choices continue to override dark default.

## Current Gate Status

| Area | Status |
| --- | --- |
| Separate Google OAuth staging client | PASS |
| Login/logout and staging isolation | PASS |
| Protected deep-link return and query | PASS |
| Canonical no-team/no-profile user | PASS |
| Canonical owner without profile | PENDING_SECOND_IDENTITY |
| Canonical owner with profile | PENDING_SECOND_IDENTITY |
| Canonical normal player | PENDING_SECOND_IDENTITY |
| Canonical configured/base shield | PENDING_SECOND_IDENTITY |
| Local exhaustive visual matrix | PASS |
| Canonical staging visual matrix | PASS, 9 captures and 0 issues |
| Manifest/Service Worker/offline/reconnect | PASS |
| Exact installed standalone Preview | PENDING |
| Physical Android | PENDING |
| Physical iPhone | PENDING |

The pending identity is a human Google device-verification dependency, not an
OAuth configuration failure. It is not silently converted into PASS.

## Requested Delivery Matrix

| # | Item | Result |
| ---: | --- | --- |
| 1 | `origin/main` | `a4f2468d9b779db6a4391df7cec4cc34e4162fbe` |
| 2 | Initial HEAD | `c6733f6cb39c950ff70c590c5a6072e562554ea7` |
| 3 | Final HEAD | PR #163 `headRefOid` after final push |
| 4 | Mismatch cause | old Google client lacked exact stable Preview `/auth/google` callback |
| 5 | URI sent to Google | exact stable alias plus `/auth/google` |
| 6 | OAuth client | `Pachangas IQ Preview Staging` |
| 7 | Google staging config | exact origin and redirect only |
| 8 | Supabase Auth staging | staging client enabled; nonce checks retained |
| 9 | Vercel Preview vars | three branch-scoped public variables |
| 10 | Production OAuth modified | NO |
| 11 | Login Preview | PASS |
| 12 | Logout Preview | PASS |
| 13 | Deep-link return | PASS, including Card query |
| 14 | Supabase staging ref | `iozcjirlfytryzrcmrnq` |
| 15 | Owner without profile | fixture PASS; canonical PENDING_SECOND_IDENTITY |
| 16 | Owner with profile | fixture PASS; canonical PENDING_SECOND_IDENTITY |
| 17 | Player | fixture PASS; canonical PENDING_SECOND_IDENTITY |
| 18 | User without team | canonical PASS |
| 19 | Configured shield | component/fixture PASS; canonical PENDING_SECOND_IDENTITY |
| 20 | Base shield | component/fixture PASS; canonical PENDING_SECOND_IDENTITY |
| 21 | Secondary card | PASS |
| 22 | Integrated selector | PASS regression |
| 23 | Team Access drawer | PASS regression |
| 24 | Dark default | PASS |
| 25 | Light preference | PASS regression; canonical actor pending |
| 26 | Dark preference | PASS regression; canonical actor pending |
| 27 | Authenticated Home desktop | no-team canonical PASS |
| 28 | Home portrait | canonical PASS |
| 29 | Home landscape | canonical PASS |
| 30 | Match | exhaustive fixture/regression PASS |
| 31 | Lineup | exhaustive fixture/regression PASS |
| 32 | Result | exhaustive fixture/regression PASS |
| 33 | Market | public/runtime and regression PASS |
| 34 | Ranking | canonical PASS |
| 35 | Notifications | canonical empty/preferences PASS |
| 36 | Card | canonical no-profile PASS |
| 37 | Shield | canonical no-team PASS |
| 38 | Rotation | regression PASS |
| 39 | PWA | manifest/SW/offline PASS; installed standalone PENDING |
| 40 | Physical Android | PENDING |
| 41 | Physical iPhone | PENDING |
| 42 | Evidence size | 19,372,386 -> 9,978,764 bytes |
| 43 | Evidence removed | 179 raw files / 9,400,725 bytes |
| 44 | Authenticated contact sheet | UPDATED, canonical vs fixture labelled |
| 45 | Stable Preview | URL above |
| 46 | Exact deployment | PR body after closing deployment |
| 47 | PR body | updated after closing push |
| 48 | Tests | PASS, 354/354 |
| 49 | Typecheck | PASS |
| 50 | Build | PASS, included in complete test run |
| 51 | Focused lint | PASS; global inherited baseline 22 errors / 18 warnings |
| 52 | Visual QA | canonical 9 captures: 0 issues |
| 53 | Supabase schema modified | NO |
| 54 | Supabase production modified | NO |
| 55 | Vercel production modified | NO |
| 56 | Merge | NO |
| 57 | R4A modified | NO |
| 58 | Worktree | retained while PR remains unmerged; clean at handoff |

## Approval Boundary

Alberto may review the visual RC now. Full authenticated approval still requires
the owner/player second identity or an explicit human waiver of that canonical
coverage. Physical-device claims remain pending independently.
