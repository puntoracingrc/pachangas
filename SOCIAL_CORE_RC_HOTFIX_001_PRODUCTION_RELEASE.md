# Social Core RC Hotfix 001 - Production Release

## Release identity

- Release date: `2026-09-03 01:23 CEST`.
- Initial `main`: `c762948cad6fc80579189c4e6f33b41de13820a4`.
- Functional commit: `4199852f63308631c6e29219cc63f5dfeae96316`.
- Verification commit: `052b5cc7a8f904d1d10b84f539bac963dbe41050`.
- Functional PR: [#260](https://github.com/puntoracingrc/pachangas/pull/260), merged.
- Production merge SHA: `32e9035d8f1a90ce2d3f3da19190f9bbfb584128`.
- Vercel deployment: `dpl_7MVNixr82mwNojHTQXv8Gp3g6CkZ`.
- Deployment URL: <https://pachangas-u99npsrbn-persianas-almar-web-s-projects.vercel.app>.
- Production URL: <https://pachangasiq.com>.
- Deployment state: `READY`.
- Vercel metadata commit SHA: `32e9035d8f1a90ce2d3f3da19190f9bbfb584128`.

## Delivered scope

Only the five defects authorized for Batch 001 were changed:

| ID | Production result |
| --- | --- |
| `SOCIAL-RC-006` | Attendance notice opens the exact match, exposes `Voy / Duda / No voy`, resolves locally and returns to Avisos. |
| `SOCIAL-RC-008` | Market detail is a keyboard-operable modal with initial focus, focus containment, Escape, inert background, scroll lock and focus restoration. |
| `SOCIAL-RC-001` | Demo primary navigation creates real internal history; Back and Forward remain inside Demo. |
| `SOCIAL-RC-004` | Signed-out public Market shows `Sin consultar` until an authoritative query exists and never presents a fabricated zero. |
| `SOCIAL-RC-010` | A Demo open-match request has one visible `sending -> pending` state in both card and detail, and duplicate submission is disabled. |

No other field-review defect was changed in this release.

## Pre-merge gates

- `npm ci`: PASS, 525 packages installed.
- Focused new regressions: 10/10 PASS.
- Focused compatibility suite: 23/23 PASS.
- Full Node suite: 20/20 PASS.
- Full TS/TSX suite: 815/815 PASS.
- Full total: 835/835 PASS.
- Failed / skipped / todo / cancelled: `0 / 0 / 0 / 0`.
- `npm run typecheck`: PASS.
- `npm run build`: PASS.
- `npm run lint`: PASS, 0 errors and 0 warnings.
- `git diff --check`: PASS.
- Vercel Preview checks on final PR HEAD: PASS.

The existing dependency audit output remains 19 findings (1 low, 4 moderate and 14 high). No dependency upgrade was folded into this defect-only hotfix.

## Production smoke

Production was checked without authentication, real entities, remote Demo writes or real notifications.

### `SOCIAL-RC-001`

1. Opened Demo Inicio as the player perspective.
2. Navigated to Partidos and then Mercado through the primary navigation.
3. Browser Back returned to Partidos.
4. A second Back returned to Inicio.
5. The browser remained under `/demo` throughout.

Result: PASS.

### `SOCIAL-RC-006`

1. Opened Avisos with three pending actions.
2. Selected `Confirma si juegas`.
3. The exact match `demo_match_121` opened.
4. `Voy`, `Duda` and `No voy` were visible.
5. Selecting `Voy` produced `Asistencia confirmada solo en esta sesión Demo. Remote writes: 0.`.
6. Returning to Avisos showed two pending actions and removed the resolved attendance action.

Result: PASS.

### `SOCIAL-RC-008`

1. Opened a player detail from Demo Market.
2. Initial focus moved to `Cerrar jugador demo Guillem Ferrer`.
3. The dialog had an accessible name, the background was inert and body scrolling was locked.
4. Escape closed the dialog.
5. Focus returned to the exact `Ver perfil` opener.

Result: PASS.

### `SOCIAL-RC-004`

- Signed-out `/mercado` displayed `Sin consultar` and the authentication call to action.
- `0 partidos encontrados` was absent before an authoritative query.

Result: PASS.

### `SOCIAL-RC-010`

1. Opened `demo_match_128` from Demo Market.
2. Selected `Solicitar plaza` in the detail.
3. The detail displayed `Solicitud enviada` and `Registrada en esta sesión Demo. Remote writes = 0.`.
4. The card and dialog action both became disabled `Solicitud enviada` controls.
5. The state remained visible without a duplicate request path.

Result: PASS.

## Responsive and visual readback

| Viewport | Surface | Result |
| --- | --- | --- |
| `1440x900` | Public Market | No root overflow or broken images; authoritative idle state visible. |
| `390x844` | All five corrected flows | No clipped target controls, root overflow or broken images. |
| `360x800` | Public Market | `Sin consultar` visible, no fake zero, no root overflow or broken images. |
| `844x390` | Demo match/calendar | No root overflow or broken images. |

- Production browser console errors/warnings during the isolated smoke: `0 / 0`.
- Physical Android QA: `PENDING`.
- Physical iPhone QA: `PENDING`.
- Physical installed-PWA QA: `PENDING`.

Emulated and browser QA are not presented as physical-device approval.

## PWA readback

- Manifest: HTTP available.
- Name: `Pachangas IQ`.
- Display mode: `fullscreen`.
- Start URL: `/`.
- Manifest icons: `5`.
- Service Worker: HTTP `200`.
- Service Worker version: `2.0.0+sw.32e9035d8f1a`.
- Service Worker cache policy: `no-cache, no-store, must-revalidate`.
- Service Worker scope header: `service-worker-allowed: /`.

No Service Worker strategy, background sporting queue or offline authority was introduced.

## Runtime readback

- Vercel grouped runtime errors, last 30 minutes after release: none.
- Deployment-specific `4xx` logs during the release smoke: none.
- Deployment-specific `5xx` logs during the release smoke: none.
- Observed successful response groups included `200` and `304`.
- Broken production images on checked surfaces: `0`.

## Authority and release boundaries

- Supabase modified: NO.
- Database migrations: `0`.
- RPC, RLS or feature flags modified: NO.
- Stripe modified: NO.
- Real entities created: `0`.
- Real notifications sent: `0`.
- Demo remote writes: `0`.
- Batch 002 started: NO.
- Official UI V3I started: NO.
- Wave 9C resumed: NO.

## Remaining field-review backlog

The following defects remain documented and intentionally unfixed:

| ID | Severity | State |
| --- | --- | --- |
| `SOCIAL-RC-002` | P2 | DOCUMENTED / NOT FIXED IN BATCH 001 |
| `SOCIAL-RC-003` | P3 | DOCUMENTED / NOT FIXED IN BATCH 001 |
| `SOCIAL-RC-005` | P3 | DOCUMENTED / NOT FIXED IN BATCH 001 |
| `SOCIAL-RC-007` | P2 | DOCUMENTED / NOT FIXED IN BATCH 001 |
| `SOCIAL-RC-009` | P2 | DOCUMENTED / NOT FIXED IN BATCH 001 |
| `SOCIAL-RC-011` | P3 | DOCUMENTED / NOT FIXED IN BATCH 001 |
| `SOCIAL-RC-012` | P2 | DOCUMENTED / NOT FIXED IN BATCH 001 |

## Final release state

- Social Core RC Hotfix Batch 001: `RELEASED / PRODUCTION VERIFIED`.
- Functional PR #260: `MERGED`.
- Production deployment: `READY`.
- Production rollback candidate: available in Vercel deployment history.
- Scope expansion: none.
