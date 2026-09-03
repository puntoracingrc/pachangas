# Social Core RC Hotfix Batch 002 - Production Release

## Release identity

- Verification completed: `2026-09-03T09:46:21+02:00`
- Repository: `puntoracingrc/pachangas`
- Initial base: `fe6430a8f02dadf4300645d07713d91bcbc15cd0`
- Implementation commit: `f8ac0c765a53853e87fea9bbae4f993ad8468b6f`
- Functional PR final HEAD: `0e20d3d08f2f7b3d3fbbb12458b6633f5dc4eabc`
- Functional PR: [#262](https://github.com/puntoracingrc/pachangas/pull/262)
- Functional merge SHA: `b959bda37c63e1d3a87463e9af6c3acf0e2a1b97`
- Functional production deployment: `dpl_9g825itKuUgxSLuMZH9Qj7tVgNLJ`
- Immutable deployment URL: <https://pachangas-biw54jy7q-persianas-almar-web-s-projects.vercel.app>
- Public URL: <https://pachangasiq.com>
- Deployment state: `READY`
- Deployment metadata SHA: `b959bda37c63e1d3a87463e9af6c3acf0e2a1b97`
- Production Service Worker cache: `pachangas-iq-pwa-2.0.0-sw.b959bda37c63`

## Production smoke: Batch 002

| ID | Production evidence | Result |
| --- | --- | --- |
| SOCIAL-RC-002 | Starting `Usuario nuevo` from Admin immediately selected `Jugador sin equipo`, produced `perspective=free-agent`, and preserved coherent Back/Forward/reload state. | PASS |
| SOCIAL-RC-003 | At 390 x 844 the query retained 268 px and both location controls measured 44 x 44. At 360 x 800 the query retained 238 px. At 844 x 390 both controls remained 44 x 44. Root overflow was zero. | PASS |
| SOCIAL-RC-005 | No audited visible copy matched V3, V3H, V3.5, Official UI, read model or the known internal action labels. | PASS |
| SOCIAL-RC-007 | Admin challenge detail showed one primary accept action, one secondary counterproposal, the destructive reject action inside `Mas acciones`, and perspective review separately. Player view showed no mutation actions. | PASS |
| SOCIAL-RC-009 | `Ver proximo partido` opened `demo_match_121` with `matchView=detail`; Back returned to Inicio and Forward restored the exact match. | PASS |
| SOCIAL-RC-011 | At 1440 x 900 the context selector exposed title, type, role, detail, state and next action in its full accessible label, with zero root overflow. Compact variants remained intact in portrait and landscape. | PASS |
| SOCIAL-RC-012 | The named guarantees region accepted focus, End reached scrollLeft 301/301, Home returned to zero, focus outline was visible and Escape returned focus to `Revision rapida`. | PASS |

All seven IDs are `FIXED + REGRESSION_VERIFIED`. No ID remains `NOT_REPRODUCED`.

## Production smoke: Batch 001 regressions

| ID | Production evidence | Result |
| --- | --- | --- |
| SOCIAL-RC-001 | Inicio -> Partidos -> Mercado created real route entries; Back returned to Partidos and then Inicio; Forward restored Partidos without a loop. | PASS |
| SOCIAL-RC-004 | Public `/mercado` without a session settled on `Sin consultar` and requested sign-in; it did not expose a provisional zero as an authoritative result. | PASS |
| SOCIAL-RC-006 | Avisos opened `demo_match_121`; Voy, Duda and No voy were present. Selecting Voy remained session-local, reduced the pending badge from 3 to 2 and reported `Remote writes: 0`. | PASS |
| SOCIAL-RC-008 | Mercado detail opened as a named dialog with initial focus on Close; Escape closed it, restored scrolling and returned focus to the exact `Ver detalles` opener. | PASS |
| SOCIAL-RC-010 | The first Demo request became `Solicitud enviada`, its action disabled immediately and the card identified session-local state. Offline mode disabled remaining requests and did not create another success. | PASS |

## Automated gates

- Clean baseline: 835/835 (Node 20/20, TS/TSX 815/815).
- Final suite: 845/845 (Node 20/20, TS/TSX 825/825).
- Focused Batch 002: 10/10.
- Official UI / Social Core compatibility: 39/39.
- Failed / skipped / todo / cancelled: 0 / 0 / 0 / 0.
- Typecheck: PASS.
- Build: PASS, 78 static routes generated.
- Global lint: PASS; only the pre-existing Babel large-file informational notice was emitted.
- Focused lint: PASS.
- `git diff --check`: PASS.
- Secret scan: PASS.
- Prohibited-path comparison: PASS.

## Responsive and accessibility

Validated at 1440 x 900, 1280 x 720, 1024 x 768, 390 x 844, 360 x 800 and 844 x 390, plus light/dark, normal/reduced motion and standalone display-mode emulation.

- Root overflow introduced: 0.
- Broken images: 0.
- Cut primary controls: 0.
- Modified priority targets below 44 x 44: 0.
- Application console errors/warnings: 0.
- New critical or serious Axe violations on affected mobile surfaces: 0.
- The 26 pre-existing light-theme contrast nodes at the 1024 px context-selector baseline remain unchanged: delta 0.
- Keyboard order, modal focus containment, Escape and focus restoration: PASS.

The sanitized evidence is [SOCIAL_CORE_RC_HOTFIX_002_BEFORE_AFTER.png](./SOCIAL_CORE_RC_HOTFIX_002_BEFORE_AFTER.png).

## PWA and offline

- Manifest available: PASS.
- Service Worker active and controlling: PASS.
- Waiting worker: none.
- Current cache count: one.
- Exact functional cache: `pachangas-iq-pwa-2.0.0-sw.b959bda37c63`.
- Reload: PASS.
- Offline cached Demo: PASS.
- Reconnection and fresh canonical load: PASS.
- Real mutations offline: blocked.
- Fake remote success: none.
- New sports Background Sync: none.

Physical emulation was not represented as device evidence:

- Physical Android QA: PENDING
- Physical iPhone QA: PENDING
- Physical installed-PWA QA: PENDING

## Runtime and network readback

- Vercel runtime error clusters in the release window: 0.
- Fatal/error/warning runtime logs for `dpl_9g825itKuUgxSLuMZH9Qj7tVgNLJ`: 0.
- Deployment 4xx log count during the smoke window: 0.
- Deployment 5xx log count during the smoke window: 0.
- Browser-observed failed resources in the audited Demo route: 0 of 46 resources.
- Browser console warnings/errors in clean Demo and public Mercado tabs: 0.

## Authority and release boundaries

The smoke used only the read-only public product and synthetic, session-local Demo World. It created no real user, team, match, challenge, request, notification or payment.

- Supabase modified: NO.
- Migrations applied: 0.
- RPC/RLS/feature flags modified: NO.
- Stripe modified: NO.
- Real entities created: 0.
- Real notifications sent: 0.
- Demo remote writes: 0.
- Demo external notifications: 0.
- Demo push sent: 0.
- Demo emails sent: 0.
- Demo Stripe calls: 0.

No production backend operation was performed by this release.

## Final field-review status

The seven Batch 002 defects and the five Batch 001 regressions are closed in production. The Social Core field review is `CLOSED`, with physical Android, iPhone and installed-PWA QA still explicitly `PENDING`.

Official UI V3I was not started. Wave 9C was not resumed.

Functional detail: [SOCIAL_CORE_RC_HOTFIX_002_REPORT.md](./SOCIAL_CORE_RC_HOTFIX_002_REPORT.md).
