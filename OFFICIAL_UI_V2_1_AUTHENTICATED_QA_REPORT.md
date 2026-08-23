# Official UI V2.1 Authenticated QA Report

## Checkpoint

- Base: `origin/main` at `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Branch: `codex/official-ui-v2-1-deep-demo-parity`.
- Actual starting HEAD: `c6733f6cb39c950ff70c590c5a6072e562554ea7`.
- PR: [#163](https://github.com/puntoracingrc/pachangas/pull/163), OPEN and DRAFT.
- Final HEAD: the final `headRefOid` recorded in PR #163 after the closing push.
- Production: not modified.
- R4A PR #162: not modified.

## OAuth Audit

The application uses flow B:

```text
Google -> stable Preview /auth/google -> Supabase signInWithIdToken -> original route
```

The old Google client did not authorize this exact callback:

`https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app/auth/google`

That caused `redirect_uri_mismatch`. The fix uses a separate OAuth client named
`Pachangas IQ Preview Staging` with:

- public client ID:
  `539843550578-tr4f8l63bcgl0aheubteq55lpagbsent.apps.googleusercontent.com`;
- authorized JavaScript origin:
  `https://pachangas-git-codex-offic-85e5c1-persianas-almar-web-s-projects.vercel.app`;
- authorized redirect URI: the same origin plus `/auth/google`.

Supabase staging project `iozcjirlfytryzrcmrnq` has that staging client enabled
for Google login. Skip nonce checks remain disabled and users without email
remain disabled. No secret, token, cookie or account identity is stored in the
repository or evidence.

Branch-scoped Vercel Preview overrides are limited to:

- `NEXT_PUBLIC_GOOGLE_CLIENT_ID`;
- `NEXT_PUBLIC_SUPABASE_URL`;
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.

Production Vercel variables, production Supabase Auth and the productive Google
client were not changed.

## Isolation

| Check | Result |
| --- | --- |
| Login against stable Preview | PASS |
| Supabase project after login | staging `iozcjirlfytryzrcmrnq` |
| Production project in active bundle | absent |
| Token in final URL | absent |
| Token in logs/evidence | absent |
| Logout | PASS |
| OAuth loop | none |
| Service-role key in browser | absent |

A manual Preview deployment initially inherited the general Preview environment
instead of branch overrides. The client mismatch was detected at the Google
boundary, the stable alias was restored immediately, and no authentication or
write completed through that artifact. All subsequent validation uses a local
prebuild generated from the branch-specific Preview environment.

## Deep-Link Return

| Entry route | Result |
| --- | --- |
| `/` | PASS |
| `/?mobile=partido` | PASS; valid query retained |
| `/mercado` | public route; no login gate, route retained |
| `/ranking` | public route; no login gate, route retained |
| `/equipo/identidad` | PASS; returns to exact protected route |
| `/personalizar-carta?slot=frame` | PASS; protected route and query retained |

The return helper accepts only same-origin paths and rejects external targets or
the OAuth callback itself.

## Canonical Staging Cases

| Case | Status | Evidence |
| --- | --- | --- |
| Authorized authenticated user without team/profile | PASS | real staging readback, 9 captures |
| Owner with team and no profile | PENDING_SECOND_IDENTITY | fixture/source regression only |
| Owner with team and profile | PENDING_SECOND_IDENTITY | fixture/source regression only |
| Normal player | PENDING_SECOND_IDENTITY | fixture/source regression only |
| Configured team shield | PENDING_SECOND_IDENTITY | canonical component/source plus fixture |
| Base team shield | PENDING_SECOND_IDENTITY | canonical component/source plus fixture |
| Long team name, wide roster, several matches | PENDING_SECOND_IDENTITY | exhaustive visual fixture matrix |

The second authorized Google actor reached device verification twice, but both
requests expired before human approval. No password was guessed, no synthetic
membership was altered and no staging data was created to manufacture a PASS.

## Authenticated Defects Closed

1. Signed-out protected Card and Shield routes had no direct login action and
   therefore could not return to the original route.
2. A user without `PlayerProfile` saw the server message `Player profile
   required`; the product now shows `Tu carta aún no está creada` with the sole
   action `Crear mi ficha`.
3. The first deep-link implementation dropped `?slot=frame`; browser QA
   reproduced it and the final implementation preserves the current valid
   query.
4. The missing-profile state no longer remains in an indefinite busy state.

All changes are minimal and covered by `tests/official-ui-v2-1.test.ts`.

## Visual Matrix

Canonical staging evidence contains 9 captures. Result: 0 document overflow,
0 broken images, 0 console warnings/errors and 0 technical error leaks. It
covers Home at `1440x900`, `390x844`, `844x390`, plus Team Identity, Card,
Ranking, Notification Preferences and empty Notifications.

The final contact sheet explicitly labels owner/player/offline frames as
`fixture visual`; they are not presented as canonical authenticated readbacks.

## Theme And Orientation

- Authenticated user without an explicit preference: dark default PASS.
- Explicit light/dark persistence: source and regression PASS; canonical second
  identity pending.
- Portrait -> landscape -> portrait: visual matrix and rotation regression PASS.
- No duplicate sports write was issued during QA.
- No local preview was presented as server confirmation.

## PWA

| Check | Result |
| --- | --- |
| Manifest | PASS, `/manifest.webmanifest` |
| Service Worker controller | PASS |
| Cached shell under simulated network offline | PASS |
| Sports operation shown as confirmed offline | NO |
| Reconnect and canonical refresh | PASS |
| Exact installed standalone Preview | PENDING |
| Physical Android | PENDING |
| Physical iPhone | PENDING |

Browser emulation does not substitute an installed PWA or a physical device, so
those states remain pending.

## Data Boundary

- Supabase Auth staging configuration: modified only for the separate Google
  staging client.
- Supabase schema paths in Git diff: 0.
- Migrations: 0.
- SQL/RPC/RLS changes: 0.
- Staging product rows created/updated/deleted: 0.
- Supabase production: not modified.
- Vercel production: not modified.

## Closing Gates

- `npm ci`: PASS.
- `npm test`: PASS, 354/354 tests; includes the production build.
- `npm run typecheck`: PASS.
- Focused ESLint for the new helper, protected routes, regression suite and
  evidence generator: PASS.
- Source-only global ESLint: inherited baseline remains at 22 errors and 18
  warnings; no out-of-scope lint debt was changed.
- `git diff --check`: PASS.

## Evidence

- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_AUTHENTICATED_FINAL_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/captures/authenticated-staging-final/matrix.md`
- `docs/official-ui-v2-1/captures/authenticated-staging-final/results.json`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_EVIDENCE_INVENTORY.md`

All committed screenshots were reviewed for PII before inclusion.
