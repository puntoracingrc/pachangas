# Official UI V2.1 Deep Demo Parity Report

## Release State

- Initial `origin/main`: `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Branch: `codex/official-ui-v2-1-deep-demo-parity`.
- Draft PR: [#163](https://github.com/puntoracingrc/pachangas/pull/163).
- Contract checkpoint: `b78ac9695a896fcad8842198b4a285d4e9124acf`.
- Actual branch HEAD when this closure resumed: `7e02e1111fb1617534f06e5f2b2e5fb2f82e6ac3`.
- Final product checkpoint: `65577f21ba838c52e4b36fa3af849011936951d3`.
- Final report/evidence HEAD: the exact `headRefOid` of PR #163 after the closing push.
- Production modified: NO.
- Supabase modified: NO.
- Migrations, SQL, RPC or RLS changes: 0.
- Merge: NO.
- R4A modified: NO.

## Final Product Story

The authenticated Home now tells the same story as Demo World while retaining
real product authority:

1. team identity and canonical shield;
2. one primary sporting action and compact metrics;
3. upcoming matches;
4. real season activity.

Administrative metadata no longer interrupts that sequence. Team selection is
integrated into the identity controls and detailed Team Access data remains in
a bounded drawer.

## Canonical Identity Hierarchy

| Context | Protagonist | Result |
| --- | --- | --- |
| User with a team | canonical `TeamShieldView` | IMPLEMENTED |
| Team without configured cosmetics | canonical base team shield | IMPLEMENTED |
| Owner/admin without own player profile | team shield, never the first roster player | IMPLEMENTED |
| User without team and with own profile | own player card | IMPLEMENTED |
| User without team and without profile | stable Pachangas IQ placeholder | IMPLEMENTED |

The Home reads the existing
`get_pachanga_team_shield_snapshot_v1` snapshot. A versioned local read cache is
derived from that response and Realtime invalidates/refetches it. No new shield
renderer, fixture authority, write path or sports state was introduced.

The player's card remains available through the compact `Mi carta` secondary
action and does not compete with the team shield.

## Team Selector And Access

- The standalone Team Access row was removed.
- Team selection is available inside the identity controls for registered users
  who have teams.
- Role, code, level, roster, synchronization, invite and destructive controls
  remain permission guarded inside one details drawer.
- Team name, role, connection state, level and selector each have one visual
  owner instead of being repeated across the product shell and Home.

## Authenticated Theme Default

`AuthenticatedThemeDefault` selects dark only when the authenticated user has
no saved preference. It does not persist that fallback.

| Saved preference | Result |
| --- | --- |
| none | dark |
| `light` | light |
| `dark` | dark |
| explicit `system` | system |

Manual changes persist and remain authoritative. The theme is not changed by
orientation. Public landing behavior and Control Center preference handling
were not replaced.

## Scope Preserved

- Match keeps its single navigation, persistent context, pitch, result and
  grouped Admin composition.
- Market keeps its single navigation, compact filters and current functional
  panels.
- Ranking, Clubs, Referee Platform, Rating V2, Demo World and Control Center are
  unchanged in authority.
- No attendance, lineup, result, Market, ranking, rating or cosmetics write
  contract was replaced.

## Automated Visual QA

### Local exhaustive matrix

The focused V2.1 matrix covers 16 surfaces across 7 viewports, including low
landscape and PWA-emulated portrait.

| Captures | Navigation errors | Console errors | Warnings | Failed requests | Broken images | Overflow X | Viewport violations | Game chrome violations |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 112 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Theme coverage is 105 dark captures and 7 explicit light captures.

Low-landscape checks include `667x375`, `740x360`, `844x390` and `932x430`.
The final composition keeps the shield visible, the primary action reachable,
one navigation, no footer and no document-level horizontal overflow.

### Exact deployed Preview

Preview:
`https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app`

The exact deployed Preview was captured on 11 representative surfaces at
`1440x900`, `390x844` and `844x390`.

| Captures | Broken images | Overflow X | Console warnings/errors | Theme |
| ---: | ---: | ---: | ---: | --- |
| 33 | 0 | 0 | 0 | dark |

Surfaces: Home owner, Home player, Home without team, Home offline, Match next,
Lineup, Result, Market, Ranking, Card and Shield.

These are deployed visual fixtures, not a substitute for an authenticated
canonical staging readback.

## Orientation

The deployed Preview retained the selected `Retos` Market tab through portrait
-> landscape -> portrait with one Market navigation. It also retained the
selected `Alineacion` pane through the same rotation with one Match navigation.
No sporting write was issued.

## Authenticated Preview Blocker

An authorized Google sign-in was attempted on the exact Preview. Google rejected
the callback with `Error 400: redirect_uri_mismatch` for:

`https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app/auth/google`

No Google Cloud, Supabase Auth or production configuration was changed because
that is outside this visual-only release. Consequently these canonical staging
cases remain BLOCKED, not passed:

- real owner and player sessions;
- long real team name and wide real roster;
- configured and unconfigured canonical shields;
- owner with a team and no player profile;
- authenticated offline/read-only state;
- exact installed-PWA session.

The lab fixtures exercise the layout and hierarchy for those cases, but they are
reported only as visual/source evidence.

## Evidence

- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_HOME_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MATCH_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MARKET_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MOBILE_GAME_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_DEMO_OFFICIAL_COMPARISON.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_AUTHENTICATED_FINAL_CONTACT_SHEET.png`

The last sheet is intentionally labelled as a final Preview review with the
authentication blocker; it does not claim that canonical authentication passed.
Its 33 source captures and machine-readable results are under
`docs/official-ui-v2-1/captures/authenticated-final`.

## Engineering Validation

| Gate | Result |
| --- | --- |
| `npm test` | PASS: production build plus 372 tests (20 bootstrap/HTML and 352 functional) |
| `npm run typecheck` | PASS |
| Production build | PASS: 39 static pages, including the isolated V2.1 lab |
| Focused lint | PASS on changed clean modules and tests |
| Legacy monolith lint | inherited debt only: `app/page.tsx` has 13 errors/17 warnings and `app/mercado/page.tsx` has 2 errors/1 warning; combined 15/18 |
| `git diff --check` | PASS |
| Supabase/SQL paths in diff | 0 |

The final commands are repeated after documentation/evidence is committed. Any
updated count or gate result must be taken from that closing run.

## Human Review Gate

PR #163 remains OPEN and DRAFT. It is ready for Alberto's final visual review of
the exact Preview, with two explicit limitations:

- authenticated canonical Preview QA: BLOCKED by the OAuth redirect allowlist;
- physical Android/iPhone and installed-PWA QA: PENDING.

No merge or production deployment is authorized by this report.
