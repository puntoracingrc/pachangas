# Official UI V2.1 Authenticated QA Report

## Checkpoint

- Base: `origin/main` at `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Branch: `codex/official-ui-v2-1-deep-demo-parity`.
- Starting HEAD for this gate: `a1b6f5223f6d2ec70e390073aa2a030755732b28`.
- Closing code HEAD: `d1b44b4490f943a0e4f0792a392e0380ef845589`.
- PR: [#163](https://github.com/puntoracingrc/pachangas/pull/163), OPEN and DRAFT.
- Stable OAuth Preview:
  `https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app`.
- Exact validated deployment:
  `https://pachangas-6r1p3rqn6-persianas-almar-web-s-projects.vercel.app`
  (`dpl_A4QJjWdzm6e21dwC3kC7dYnDrdNE`).
- Production: not modified.
- R4A PR #162: not modified.

The final evidence-only commit is recorded in PR #163 after the closing push;
the report cannot embed the SHA of the commit that contains itself.

## OAuth Audit

The application uses the following flow:

```text
Google -> stable Preview /auth/google -> Supabase signInWithIdToken -> original route
```

The separate staging OAuth client authorizes only the stable Preview origin and
its `/auth/google` callback. Supabase staging project `iozcjirlfytryzrcmrnq`
has that staging client enabled. No password was guessed and no account
identity, cookie, token or OAuth client secret is stored in Git or evidence.

The branch-scoped Vercel Preview environment contains the three public staging
variables plus one server-only `SUPABASE_SERVICE_ROLE_KEY` required by the
authenticated assessment API. The key value was streamed directly from the
staging CLI to Vercel, was not printed or written to disk, and is absent from
the browser bundle. Production variables were not changed.

| Isolation check | Result |
| --- | --- |
| Login/logout against stable Preview | PASS |
| Supabase project after login | staging `iozcjirlfytryzrcmrnq` |
| Production project in active bundle | absent |
| Token in final URL, logs or evidence | absent |
| Service-role key in browser | absent |
| OAuth loop | none |

## Deep-Link And Menu Return

| Entry or action | Result |
| --- | --- |
| `/` | PASS |
| `/?mobile=partido` | PASS; valid query retained |
| `/mercado` and `/ranking` | PASS; public route retained |
| `/equipo/identidad` | PASS; protected route restored after login |
| `/personalizar-carta?slot=frame` | PASS; route and query restored |
| Desktop `Perfil` | PASS; opens the own profile flow |
| Portrait `Inicio`, `Partido`, `Equipo`, `Perfil` | PASS; invoke in-app navigation |
| Portrait `Mercado` | PASS; remains the explicit `/mercado` route |

The final menu regression is covered in `tests/official-ui-v2-1.test.ts`.

## Canonical Staging Cases

| Case | Status | Evidence |
| --- | --- | --- |
| Authorized user without team/profile | PASS | 9 prior canonical captures |
| Owner with team and no profile | PASS | desktop, portrait and landscape |
| Base team shield | PASS | canonical snapshot revision 0; three viewports |
| Configured team shield | PASS | canonical snapshot revision 1; three viewports |
| Owner with profile | BLOCKED_EXISTING_RATING_V2_ONBOARDING | server rejected the first assessment before profile creation |
| Normal player | PASS | second Google actor joined through the official invitation flow and read back as `Jugador` |
| Long team name | PASS | canonical owner Home |
| Wide roster | PASS | 12 QA player rows created through the official UI |
| Several upcoming/closed matches | BLOCKED_PREVIEW_GOOGLE_PLACES_SELECTION | official venue form returned no selectable prediction, so save remained disabled; no direct fixture write used |

The configured shield was saved through the existing authoritative product
flow and read back from the server. No reward, inventory or production cosmetic
was granted. The Home keeps `TeamShieldView` as the protagonist and does not
substitute a `PlayerCardView` for the team shield.

## Existing Rating V2 Blocker

The owner assessment reached the staging server and returned:

```text
Complete the initial player assessment before creating a new profile
```

This is not an Official UI V2.1 visual defect. The existing Rating V2 function
`persist_pachanga_player_assessment_v2` invokes
`upsert_pachanga_own_player_profile` before inserting the initial assessment.
The profile upsert simultaneously requires that initial assessment to exist
when neither a global profile nor selected player exists. A genuinely
profile-less user therefore cannot complete the first assessment through the
current ordering.

No SQL, migration, Rating formula, assessment row or direct database workaround
was introduced in this gate. No partial assessment was persisted. The owner
with-profile row remains blocked until Rating V2 is corrected in its own scope.

## Role Boundary

- Owner controls and private Team Access: canonical PASS.
- Owner shield editing: canonical PASS.
- Second Google identity and normal-player membership: canonical PASS.
- The OAuth return completed the existing invitation through the official
  product path; canonical readback reported `Jugador`, never owner/admin.
- Player invitation, deletion, match administration, Market configuration and
  shield editing controls: absent. Team selector, role and read-only shield:
  present.
- No direct membership write or synthetic role override was used.

## Defects Closed In This Gate

1. Signed-out protected Card and Shield routes lacked a direct login action.
2. The no-profile state leaked a technical server message and could remain busy.
3. The Card OAuth return dropped `?slot=frame`.
4. Desktop `Perfil` opened a mobile account sheet hidden by the desktop shell.
5. Portrait shell destinations became static links and bypassed the internal
   product navigation callback after the first transition.

The two menu defects were reproduced on the canonical Preview, fixed minimally
in commit `d1b44b4490f943a0e4f0792a392e0380ef845589`, and covered by regression.

## Visual Evidence

There are 21 canonical staging captures in total: nine prior no-team/no-profile
captures, nine owner/shield captures and three normal-player captures. The role
sets have exact dimensions `1440x900`, `390x844` and `844x390`, no observed
horizontal overflow and no broken shield image. The earlier nine-capture set
retained its recorded zero console/error result. Console counters were not
re-invented for screenshots where a separate console audit was not repeated.

The authenticated contact sheet labels canonical staging separately from the
owner/player/offline fixture row. Fixture images are never presented as server
readback.

## Match, Market, Theme And Orientation

- Match and Market exhaustive fixture/regression matrices: PASS.
- Normal-player canonical Match: Proximo, Alineacion and Resultado PASS; Admin
  absent; result mutation controls remain disabled.
- Owner canonical Match: Admin and match-save controls present as expected.
- Normal-player canonical Market: Jugadores, Partidos, Retos and Equipos PASS;
  admin configuration and Referees absent.
- Owner Market remains in its public sections because there is no saved active
  match to configure. The canonical match fixture could not be created while
  the Preview Places selector returned no selectable prediction.
- Default dark theme for the canonical actor: PASS.
- Explicit light/dark persistence: regression PASS. The canonical actors have
  no PlayerProfile because of the documented Rating V2 onboarding blocker, so
  the profile-scoped theme control cannot be replayed without bypassing it.
- Portrait, landscape and portrait layouts: canonical viewport captures PASS;
  the second actor retained Market Partidos plus the selected day and modality.
- Same-page state retention and absence of duplicate sporting writes:
  regression PASS.

No sporting write was presented as confirmed while offline.

## PWA

| Check | Result |
| --- | --- |
| Manifest and Service Worker | PASS |
| Cached shell under simulated network offline | PASS |
| Reconnect and canonical refresh | PASS |
| Exact installed standalone Preview | PENDING |
| Physical Android | PENDING |
| Physical iPhone | PENDING |

Browser emulation is not reported as an installed PWA or a physical device.

## Data And Cleanup Boundary

- Supabase production, Vercel production and production OAuth: not modified.
- Supabase schema, migration, SQL, RPC and RLS paths changed by this gate: 0.
- Staging product fixture used for QA: one clearly named QA team, 12 QA players
  and shield revision 1, all created through product flows and removed at the
  end of the gate.
- Rating, rewards, Conduct and billing fixture mutations: 0.
- Pending invitation: none; it was consumed by the official second-identity
  flow.
- QA team cleanup: PASS through the official owner delete action. The post-delete
  canonical reload showed no team selector, owner role, delete control or QA
  team. Both temporary sessions were signed out.
- Pending sporting/offline operations: 0.
- Remaining QA team/player fixture rows in staging: 0 after owner deletion.

The wide-match row is not presented as a product PASS. The official create-field
surface accepted the QA search text but never produced a selectable Google
Places prediction; `Guardar campo` stayed disabled, which also prevented a
canonical saved match. No RPC, table or local payload was used to bypass this
guard.

## Closing Gates

- `npm ci`: PASS.
- `npm test`: PASS, **374/374** total (**20 Node + 354 TSX**).
- `npm run typecheck`: PASS.
- `npm run build`: PASS.
- Focused Official UI/OAuth/PWA/Demo/R3/rendered HTML suite: PASS.
- Focused ESLint: PASS.
- Global lint baseline: 22 inherited errors and 18 inherited warnings.
- `git diff --check`: PASS at the recorded gate; repeated after final evidence.

See `OFFICIAL_UI_V2_1_TEST_COUNT_RECONCILIATION.md` for the runner inventory.

## Evidence

- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_AUTHENTICATED_FINAL_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/captures/authenticated-staging-final/matrix.md`
- `docs/official-ui-v2-1/captures/canonical-role-final/matrix.md`
- `docs/official-ui-v2-1/captures/canonical-role-final/results.json`

All committed evidence is sanitized: no email, personal name, invitation token,
cookie, service key or internal group identifier is included.
