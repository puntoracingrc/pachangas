# Social Core RC Hotfix Batch 002 - Functional Report

## Release identity

- Repository: `puntoracingrc/pachangas`
- Base: `origin/main` at `fe6430a8f02dadf4300645d07713d91bcbc15cd0`
- Branch: `codex/social-core-rc-hotfix-002`
- Audited implementation commit: `f8ac0c765a53853e87fea9bbae4f993ad8468b6f`
- Reference production deployment: `dpl_49uSaxXrngooxXnSRNhGLdPWJjRk`
- Exact implementation Preview: `dpl_7URXe3jnpxkSXkgjan7C4hxPwB4L`
- Exact implementation Preview URL: <https://pachangas-8ei9kmh33-persianas-almar-web-s-projects.vercel.app>
- Preview metadata commit: `f8ac0c765a53853e87fea9bbae4f993ad8468b6f`
- Source field-review package: absent from `/tmp`; the seven reproductions were rebuilt against the known production deployment and the untouched base.

## Closed defects

| ID | Reproduction and cause | Minimal correction | Result |
| --- | --- | --- | --- |
| SOCIAL-RC-002 | Starting `Usuario nuevo` from Admin retained the previous context because the journey opened without first selecting its declared perspective. | Every review journey declares a perspective; first-time activation selects `free-agent` before opening and route restoration synchronizes perspective and dialogs. | FIXED / regression verified |
| SOCIAL-RC-003 | The text-labelled location action consumed a mobile grid column and left the query field impractically narrow. | The existing action is a named 44 x 44 icon target; the field keeps the flexible column and focus remains visible. | FIXED / regression verified |
| SOCIAL-RC-005 | First-time and Social Inbox surfaces exposed internal V3/V3H wording. | Only rendered product copy was replaced; technical identifiers and Service Worker versions remain unchanged. | FIXED / regression verified |
| SOCIAL-RC-007 | Challenge detail gave primary visual weight to accept, counter, reject/cancel and perspective switching. | One state-dependent primary action, one secondary proposal action, destructive actions under `Mas acciones`, and perspective switching in a separate review area. A synchronous local lock prevents duplicate mutations. | FIXED / regression verified |
| SOCIAL-RC-009 | `Ver proximo partido` opened the general Partidos calendar. | The action sorts projected scheduled matches by date and opens the exact canonical Demo match ID; the existing general fallback remains. | FIXED / regression verified |
| SOCIAL-RC-011 | Desktop context copy shrank or ellipsized away role, detail, state and next action. | The shared selector builds a deduplicated full label from existing fields, exposes it accessibly and wraps desktop metadata while preserving compact mobile layouts. | FIXED / regression verified |
| SOCIAL-RC-012 | The horizontally scrollable guarantees strip had no keyboard entry point. | One named region and one tab stop support arrows, Home and End, visible focus and a thin scrollbar; Escape and focus return remain intact. | FIXED / regression verified |

No defect was classified as `NOT_REPRODUCED`. All seven IDs were reproduced twice before implementation, first against production and then against the untouched base. Detailed reproduction evidence and causes are recorded in `SOCIAL_CORE_RC_HOTFIX_002_PLAN.md`.

## Files and scope

The implementation commit changes 15 paths: 604 additions and 62 deletions. It contains the plan, one sanitized evidence image, seven focused regressions, compatibility assertion updates and the narrowly affected components/styles. This report is the sixteenth functional-PR path.

No path under `supabase/`, no migration, RPC, RLS policy, flag, authentication, Stripe, billing, Rating, result authority, reward, achievement, cosmetic, club, competition, manifest or Service Worker strategy was changed. `package-lock.json` and dependencies are unchanged.

## Automated verification

| Gate | Result |
| --- | --- |
| Clean install | PASS (`npm ci`) |
| Baseline | PASS: 835/835 (Node 20/20, TS/TSX 815/815) |
| Batch 002 focused tests | PASS: 10/10 |
| Official UI / Social Core compatibility group | PASS: 39/39 |
| Final full suite | PASS: 845/845 (Node 20/20, TS/TSX 825/825) |
| Failed / skipped / todo / cancelled | 0 / 0 / 0 / 0 |
| Typecheck | PASS |
| Production build | PASS, 78 static routes generated |
| Global lint | PASS; only the existing Babel size notice for `app/page.tsx` was emitted |
| Focused lint | PASS |
| `git diff --check` | PASS |
| Secret scan | PASS |
| Prohibited-path comparison | PASS |

The final suite contains ten more TS/TSX tests than the 835-test baseline. No existing assertion was weakened: the one affected V3F expectation now checks the human-facing replacement copy.

## Functional and navigation QA

The exact implementation Preview was exercised with synthetic Demo data only:

- `Usuario nuevo` opened from Admin resolves immediately to `free-agent`; URL, selector, Back, Forward and reload remain coherent.
- `Ver proximo partido` opens `demo_match_121` with `matchView=detail`; Back returns to Inicio and Forward restores the exact match.
- Challenge detail exposes one primary action, a secondary counterproposal, an overflow menu for the destructive action and a separate perspective-review control. Player perspective is read-only.
- Mercado keeps a useful location-query field with both 44 px controls at 360 and 390 px widths; a long query creates no root overflow.
- No audited surface renders `V3`, `V3H`, `V3.5`, `Official UI`, `read model` or the known internal action labels.
- Context labels retain title, type, role, detail, status and next action at desktop widths and remain compact on mobile.
- The guarantees region scrolls to its end with End, returns with Home, displays focus and returns focus to `Revision rapida` after Escape.

## Batch 001 regressions

- SOCIAL-RC-001: route history and exact-match Back/Forward behavior remain correct; there is no parallel local history authority.
- SOCIAL-RC-004: offline Mercado shows cached read-only results rather than inventing a zero or a successful write.
- SOCIAL-RC-006: Avisos opens the exact attendance match; choosing `Voy` is local, increases the confirmed projection, reduces the badge from 3 to 2 and removes the duplicate pending action.
- SOCIAL-RC-008: Mercado detail remains a named dialog; Escape restores scroll and focus to the exact `Ver detalles` opener.
- SOCIAL-RC-010: the first request transitions to `Solicitud enviada`, the same action becomes disabled and the Demo explicitly identifies session-local state. Offline requests are disabled.

## Responsive and accessibility QA

Validated viewports: 1440 x 900, 1280 x 720, 1024 x 768, 390 x 844, 360 x 800 and 844 x 390. Dark/light, normal/reduced motion and standalone display-mode emulation were included.

- Root overflow introduced by this batch: 0.
- Broken images: 0.
- Cut primary controls: 0.
- Modified priority targets below 44 x 44: 0.
- Application console errors or warnings on a clean Preview load: 0.
- Unexpected local 4xx/5xx during the exercised routes: 0.
- New critical/serious Axe violations on modified mobile surfaces: 0.
- At 1024 px in the light context-selector case, Axe reports the same 26 pre-existing contrast nodes as production before the patch: delta 0. They were not changed opportunistically.

The sanitized before/after sheet is `SOCIAL_CORE_RC_HOTFIX_002_BEFORE_AFTER.png`; it contains only synthetic Demo data.

## PWA and offline

- Local production build: manifest HTTP 200 (`application/manifest+json`) and Service Worker HTTP 200 with `Cache-Control: no-store`.
- Exact Preview: active controlling worker, no waiting worker and one current cache: `pachangas-iq-pwa-2.0.0-sw.f8ac0c765a53`.
- Offline reload: PASS; the cached Demo remains readable and no mutation is presented as remotely confirmed.
- Reconnection and fresh reload: PASS; the update warning clears and the same Preview route reloads under the active worker.
- Background Sync added: no.
- Service Worker/manifest strategy changed: no.

Preview protection redirects anonymous direct asset requests to Vercel authentication as expected; PWA verification was performed in the authorized Preview session. Emulation does not replace physical-device testing.

- Physical Android QA: PENDING
- Physical iPhone QA: PENDING
- Physical installed-PWA QA: PENDING

## Authority and safety

All exercised mutations were Demo session-local. Observed guarantees remained:

- `remoteWrites = 0`
- `externalNotifications = 0`
- `pushSent = 0`
- `emailsSent = 0`
- `realEntities = 0`
- `StripeCalls = 0`

Real entities created: 0. Real notifications sent: 0. Supabase was not accessed or modified.

## Final functional status

The seven remaining field-review IDs are fixed and regression-verified. Together with the five Batch 001 regressions, the Social Core field review is functionally closed, subject only to the explicitly pending physical Android, iPhone and installed-PWA checks.

Official UI V3I was not started. Wave 9C was not resumed.
