# Official UI V2.1 Deep Demo Parity Report

## Release State

- Base: `origin/main` `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Branch: `codex/official-ui-v2-1-deep-demo-parity`.
- Starting HEAD for this gate:
  `a1b6f5223f6d2ec70e390073aa2a030755732b28`.
- Closing code HEAD: `d1b44b4490f943a0e4f0792a392e0380ef845589`.
- Draft PR: [#163](https://github.com/puntoracingrc/pachangas/pull/163).
- Merge: NO.
- Production and Supabase production: not modified.
- R4A PR #162: not modified.

## Product Story

Official Home follows the accepted Demo World hierarchy without importing demo
authority: canonical team identity, `TeamShieldView`, one primary sporting
action, compact metrics, upcoming matches and season activity. The player's own
card remains secondary. Team selection stays integrated and private Team Access
lives in its permission-guarded drawer.

Match remains one hub with Proximo, Alineacion, Resultado and Admin. Market,
Ranking, Notifications, Card and Shield retain their existing read models,
permissions and server-backed writes.

## Demo World Boundary

Demo World received no data, fixture, authority or redesign changes. It did
receive one bounded responsive hotfix in
`app/demo-world/demo-world.module.css`: the Mobile Game Landscape identity band
changed from `min-height: 100%` to
`min-height: calc(100dvh - var(--game-nav-height, 48px))`. The regression lives
in `tests/demo-world-v1.test.ts`.

The A/B/C contact sheet keeps the curated Demo baseline for structural
comparison. It must not be read as a fresh canonical staging readback or as a
claim that Demo World was wholly untouched.

## Canonical Staging QA

The stable Preview uses staging OAuth and Supabase project
`iozcjirlfytryzrcmrnq`. Canonical readback confirms:

- user without team/profile: PASS;
- owner with team and no profile: PASS;
- base shield revision 0: PASS;
- configured shield revision 1: PASS;
- long team name: PASS;
- 12-player QA roster created through the official UI: PASS.

Several upcoming and closed matches remain
`BLOCKED_PREVIEW_GOOGLE_PLACES_SELECTION`. The official create-field form
accepted the QA search text but returned no selectable Google Places prediction,
so `Guardar campo` and then `Guardar partido` stayed disabled. No direct API,
table or local-payload fixture was used to manufacture this state.

Owner with profile is `BLOCKED_EXISTING_RATING_V2_ONBOARDING`: the current SQL
orders profile creation before inserting the initial assessment while the
profile gate requires that assessment. No Rating code or database state was
changed to hide the blocker. Normal-player QA is PASS: a second Google actor
completed device verification and the official invitation flow returned role
`Jugador`. No direct membership write or role override was used.

## Canonical Navigation Defect Closed

Preview QA reproduced two related menu defects:

1. desktop `Perfil` opened a mobile account sheet hidden by the desktop shell;
2. portrait shell destinations became static links and bypassed the in-app
   navigation callback after the first transition.

Commit `d1b44b4490f943a0e4f0792a392e0380ef845589` applies the minimal fix and
adds regression coverage. No palette, density or navigation model was
redesigned.

## Visual Evidence

The prior canonical no-team set contains nine sanitized captures. The owner and
shield pass adds nine more, and the real normal-player pass adds three at
`1440x900`, `390x844` and `844x390`, for 21 canonical staging captures total.
The current authenticated contact sheet separates these rows from the
explicitly labelled fixture owner/player/offline row.

The new owner/shield images show no horizontal overflow or broken shield image.
The pre-existing exhaustive fixture matrix still covers 16 product surfaces and
seven viewports with zero recorded violations.

## PWA And Orientation

- Manifest and Service Worker: PASS.
- Cached shell under simulated offline: PASS.
- Reconnect and canonical refresh: PASS.
- Installed standalone Preview: PENDING.
- Physical Android/iPhone: PENDING.
- Product state-retention and no duplicate sporting write on rotation:
  regression PASS.

Emulation is not reported as installed or physical QA.

## Engineering Gates

- `npm ci`: PASS.
- Complete `npm test`: 374/374 PASS (20 Node + 354 TSX).
- Typecheck: PASS.
- Production build: PASS.
- Focused lint: PASS.
- Global inherited lint baseline: 22 errors and 18 warnings.
- `git diff --check`: PASS at the recorded gate and repeated after final
  evidence edits.

The reconciled test inventory is in
`OFFICIAL_UI_V2_1_TEST_COUNT_RECONCILIATION.md`.

## Evidence Hygiene

The retained set consists of final contact sheets, compact machine-readable
matrices and representative captures. No email, personal name, cookie, token,
invitation URL, service key or internal group identifier is committed.

The invitation was consumed by the official flow. The QA team, its 12 QA
players and normal-player membership were then removed through the official
owner delete action. A canonical reload showed no team selector, owner role or
QA team, and both temporary sessions were signed out. No direct database
deletion was used.

## Gate

PR #163 stays OPEN and DRAFT. The owner/shield and normal-player slices are
ready for human review. Owner-with-profile remains blocked by the existing
Rating V2 onboarding order; installed PWA and physical devices remain pending.
Merge and production deployment are not authorized.
