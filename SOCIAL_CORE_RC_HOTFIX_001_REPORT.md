# Social Core RC Hotfix 001 - Verification Report

## Release identity

- Initial `origin/main`: `c762948cad6fc80579189c4e6f33b41de13820a4`.
- Functional branch: `codex/social-core-rc-hotfix-001`.
- Functional commit: `4199852f63308631c6e29219cc63f5dfeae96316`.
- Functional PR: [#260](https://github.com/puntoracingrc/pachangas/pull/260).
- Exact Preview deployment: `dpl_Emq9YRnsfvbF2eN7mhPi6xMJ2hKF`.
- Exact Preview URL: <https://pachangas-9plwfqtq3-persianas-almar-web-s-projects.vercel.app>.
- Preview status: `READY`; the Vercel success check is attached to functional HEAD `4199852f63308631c6e29219cc63f5dfeae96316`.
- Source audit: `/tmp/pachangas-social-core-field-review-v1/SOCIAL_CORE_FIELD_REVIEW_V1.md`.
- Source audit SHA-256: `296ff621313ff07e9feb351d36b2c5fcf1058b4a25da6b5d823abfbd21226979`.
- Source package reviewed: 91 evidence files. They were not copied into Git.

## Scope result

All five selected defects were reproduced twice against the previous production release and are closed in both local QA and the exact Preview.

| ID | Severity | Initial reproduction | Confirmed cause | Minimal correction | Regression result |
| --- | --- | --- | --- | --- | --- |
| `SOCIAL-RC-006` | P1 | `2/2` | The attendance action selected the right match, but the match view only exposed attendance controls to the `player` perspective and lost the Avisos return context. | Authorize the current Demo actor by team membership for player/admin perspectives, open the exact match and preserve browser history. | Avisos `3 -> 2`, `Voy/Duda/No voy` visible, own response selected, return to Avisos, `Remote writes: 0`. |
| `SOCIAL-RC-008` | P2 | `2/2` in this pass, `3/3` in the source audit | The shared sheet used `aside[role=dialog]` without focus entry, trap, Escape, inert background, scroll lock or focus restoration. | Use a named modal `div`, safe initial focus, Tab containment, Escape, inert background, scroll lock and exact focus restoration. | Player, team and match dialogs pass repeated open/close; corrected dialog has zero Axe violations. |
| `SOCIAL-RC-001` | P2 | `2/2` | Primary Demo navigation replaced one history entry and had no shell `popstate` restoration. | Push real internal entries, restore state from URL on `popstate`, retain replace semantics for the current filter entry and seed one safe Inicio fallback for deep links. | Back follows Mercado -> Partidos -> Inicio; Forward restores; direct deep links do not leave Demo on the first Back. |
| `SOCIAL-RC-004` | P2 | `2/2` in this pass, `3/3` in the source audit | Empty arrays were rendered as a result count before an authenticated authoritative query existed. | Add explicit `IDLE`, `LOADING`, `LIVE`, `CACHED` and `UNAVAILABLE` query phases; expose counts only for live/cached responses. | Signed-out Preview shows `Sin consultar` and the login CTA, never `0 partidos encontrados`. A real live empty response may still show zero. |
| `SOCIAL-RC-010` | P2 | `2/2` | The covered card and the open match sheet did not derive their labels from the same request state. | Share one request presentation, add a single-submit `sending -> pending` transition and keep confirmation in both card and detail. | Detail shows `Solicitud enviada`, blocks duplicates, survives close/reopen, acceptance shows `Plaza confirmada`, and offline remains disabled with explicit copy. |

Defects not reproduced: `0`.

## Tests and build gates

- Clean install: `npm ci` PASS, 525 packages installed.
- Dependency audit output: 19 existing dependency findings (1 low, 4 moderate, 14 high). No dependency upgrade was attempted inside this defect-only hotfix.
- Focused new regression file: 10/10 PASS.
- Focused compatibility set (`official-ui-v2-1` plus Batch 001): 23/23 PASS.
- Full Node suite: 20/20 PASS.
- Full TS/TSX suite: 815/815 PASS.
- Full total: 835/835 PASS.
- Failed / skipped / todo / cancelled: `0 / 0 / 0 / 0`.
- `npm run typecheck`: PASS.
- `npm run build`: PASS.
- `npm run lint`: PASS, 0 errors and 0 warnings. Babel emitted only its existing large-file deoptimization note for `app/page.tsx`.
- `git diff --check`: PASS.

The suite total increased from the audited 825 to 835 exclusively through the ten Batch 001 regressions.

## Browser and responsive QA

The affected surfaces were checked locally and again in the exact Preview.

| Viewport | Theme / motion | Surface | Result |
| --- | --- | --- | --- |
| `1440x900` | dark / normal | Demo Mercado and Back/Forward | PASS |
| `390x844` | dark / normal | Avisos, attendance match, Market dialogs, request detail, public Mercado | PASS |
| `360x800` | light / reduced | public Mercado | PASS |
| `844x390` | light / reduced | Demo match and attendance controls | PASS |
| `390x844` | standalone emulated | Demo Mercado with active Service Worker | PASS |

Across this matrix: 0 root overflow, 0 broken images, 0 clipped target CTA, 0 hydration warnings and 0 console errors/warnings. Physical Android, iPhone and installed-PWA QA remain `PENDING`; emulation is not reported as physical approval.

## Accessibility

- Keyboard: initial focus enters the dialog, Tab and Shift+Tab wrap, Escape closes, the background is inert, body scroll is restored and focus returns to the exact opener.
- Axe local corrected dialog: 0 violations.
- Axe local Demo Mercado, Avisos and attendance match: 0 critical or serious violations.
- Axe exact Preview corrected detail: 0 violations.
- Public Mercado still reports `select-name` (critical) and `region` (moderate). The same nodes and severities exist in the audited production baseline, so Batch 001 introduced 0 critical or serious violations. This pre-existing issue is not silently fixed outside the selected IDs.

## PWA and cache

- Manifest route: available through the Preview application.
- Service Worker: registered, active and controlling the Preview.
- Exact worker version: `2.0.0+sw.4199852f6330`.
- Worker response: HTTP 200 with `no-cache, no-store, must-revalidate`.
- Active Pachangas cache keys after update: exactly one, `pachangas-iq-pwa-2.0.0-sw.4199852f6330`.
- `registration.update()`: completed with no waiting or installing worker left behind.
- Reload with an existing cache: same exact worker version, 0 overflow, 0 broken images and 0 console errors.
- No Background Sync, offline sporting queue or Service Worker strategy change was introduced.
- Demo offline request: disabled and explicitly unconfirmed; reconnect restores normal controls.

## Authority and security

- Supabase modified: NO.
- Migrations: 0.
- RPC, RLS or feature flags modified: NO.
- Stripe touched: NO.
- Real entities used: 0.
- Real notifications sent: 0.
- Demo mutations remain session-local and explicitly expose `Remote writes = 0`.
- Local cache remains a derived read, never a competing source of truth.
- No cookies, tokens, Auth UUIDs, emails, secrets or private headers are present in the committed evidence.

## Before and after

The sanitized comparison is stored in `SOCIAL_CORE_RC_HOTFIX_001_BEFORE_AFTER.png`. It contains one prior-production and one corrected capture for each selected ID, using a desktop reproduction for `SOCIAL-RC-001` and `390x844` mobile reproductions for the other four defects.

## Remaining documented backlog

These seven source-audit defects remain `DOCUMENTED / NOT FIXED IN BATCH 001`:

| ID | Severity | Title | Reason for exclusion |
| --- | --- | --- | --- |
| `SOCIAL-RC-002` | P2 | Usuario nuevo conserva la perspectiva anterior | Outside the approved top-five batch. |
| `SOCIAL-RC-003` | P3 | El botón de ubicación comprime el buscador | Outside the approved top-five batch. |
| `SOCIAL-RC-005` | P3 | La interfaz muestra nombres internos de versiones | Outside the approved top-five batch. |
| `SOCIAL-RC-007` | P2 | Cuatro acciones equivalentes en el detalle de un reto | Outside the approved top-five batch. |
| `SOCIAL-RC-009` | P2 | Ver próximo partido abre el calendario | Outside the approved top-five batch. |
| `SOCIAL-RC-011` | P3 | El selector de contexto pierde información en desktop | Outside the approved top-five batch. |
| `SOCIAL-RC-012` | P2 | La franja de garantías no es accesible con teclado | Outside the approved top-five batch. |

The field-review audit is therefore not described as completely resolved.

## Release state

- Functional PR ready/merge: pending final PR documentation commit.
- Production deployment and smoke: pending.
- Documentary PR: pending after production readback.
- Batch 002 started: NO.
- Official UI V3I started: NO.
- Wave 9C resumed: NO.
