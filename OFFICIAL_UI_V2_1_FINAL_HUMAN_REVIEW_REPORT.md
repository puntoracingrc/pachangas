# Official UI V2.1 Final Human Review Report

## Decision Gate

PR [#163](https://github.com/puntoracingrc/pachangas/pull/163) remains OPEN
and DRAFT. The product code and deployed visual fixtures are ready for Alberto's
final visual review. This report does not authorize merge or production.

Exact Preview:
`https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app`

## What To Review

1. Home immediately reads as team + shield + next action + season.
2. The shield, not a roster player's card, is the protagonist for team users.
3. `Mi carta` remains compact and secondary.
4. The team selector is integrated in identity controls.
5. Team code, role, invite and destructive actions remain inside the drawer.
6. Desktop, portrait and landscape retain one navigation and no document-level
   horizontal overflow.
7. Market and Match retain their existing product structure.
8. Explicit light/dark/system preferences still win over the authenticated dark
   fallback.

## Evidence Status

| Area | Status | Evidence |
| --- | --- | --- |
| Product implementation | PASS | committed checkpoint `65577f21ba838c52e4b36fa3af849011936951d3` |
| Local visual matrix | PASS | 112 captures; 0 navigation errors, console errors, warnings, failed requests, broken images, overflow or viewport/game violations |
| Exact deployed Preview fixtures | PASS | 33 captures; 11 surfaces x 3 viewports; 0 broken images and 0 overflow |
| Preview console check | PASS | 0 warnings and 0 errors during the final fixture pass |
| Rotation state | PASS | Market `Retos` and Match `Alineacion` retained portrait -> landscape -> portrait with one navigation |
| Authenticated canonical Preview | BLOCKED | Google `Error 400: redirect_uri_mismatch` on the exact Preview callback |
| Installed PWA on exact Preview | PENDING | no authenticated installed Preview session was available |
| Physical Android | PENDING | no real-device claim made |
| Physical iPhone | PENDING | no real-device claim made |

## Authentication Blocker

The rejected callback is:

`https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app/auth/google`

The blocker prevented a real canonical readback of owner/player sessions, long
team names, wide rosters, configured/unconfigured shields and an owner without a
player profile. No auth, Supabase or production setting was changed to bypass it.
Lab fixtures cover the visual hierarchy only.

## Contact Sheets

- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_AUTHENTICATED_FINAL_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_HOME_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MOBILE_GAME_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_DEMO_OFFICIAL_COMPARISON.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MATCH_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MARKET_PARITY_CONTACT_SHEET.png`

## Requested Delivery Matrix

| # | Item | Result |
| ---: | --- | --- |
| 1 | `origin/main` | `a4f2468d9b779db6a4391df7cec4cc34e4162fbe` |
| 2 | Initial HEAD | `7e02e1111fb1617534f06e5f2b2e5fb2f82e6ac3`; contract checkpoint was `b78ac9695a896fcad8842198b4a285d4e9124acf` |
| 3 | Final HEAD | PR #163 exact `headRefOid` after the closing push |
| 4 | Exact Preview | URL above |
| 5 | Shield protagonist | PASS |
| 6 | `TeamShieldView` reused | PASS |
| 7 | Owner without profile | source/regression PASS; canonical Preview BLOCKED |
| 8 | User without team | source/regression PASS; canonical Preview BLOCKED |
| 9 | Secondary card | PASS |
| 10 | Team selector integrated | PASS |
| 11 | Team Access drawer | PASS |
| 12 | Context not duplicated | PASS |
| 13 | Preview dark default | PASS |
| 14 | Explicit light respected | PASS |
| 15 | Explicit dark respected | PASS |
| 16 | Authenticated owner Home | visual fixture PASS; canonical login BLOCKED |
| 17 | Player Home | visual fixture PASS; canonical login BLOCKED |
| 18 | No-team Home | visual fixture PASS; canonical login BLOCKED |
| 19 | Match | PASS visual/source |
| 20 | Market | PASS visual/source |
| 21 | Portrait | PASS visual |
| 22 | Landscape | PASS visual |
| 23 | Rotation | PASS |
| 24 | Long canonical data | lab visual PASS; canonical login BLOCKED |
| 25 | Authenticated contact sheet | CREATED and explicitly blocker-labelled |
| 26 | Demo / production / V2.1 comparison | UPDATED |
| 27 | Tests | PASS, 372 total |
| 28 | Typecheck | PASS |
| 29 | Build | PASS, 39 static pages |
| 30 | Focused lint | PASS on changed clean modules/tests; inherited `app/page.tsx` and `app/mercado/page.tsx` debt documented |
| 31 | Visual QA | local and deployed fixture passes above |
| 32 | Supabase modified | NO |
| 33 | Production modified | NO |
| 34 | Merge | NO |
| 35 | R4A modified | NO |
| 36 | Worktree | preserved while the PR is unmerged; must be clean at handoff |

## Approval Boundary

The valid next human action is visual approval or a concrete reproducible defect
report. Authenticated canonical and physical-device limitations remain visible;
they must not be silently converted into PASS.
