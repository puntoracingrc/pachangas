# First-time player card onboarding V1 production release

## Checkpoint

- Audit and implementation date: `2026-09-05 17:46:02 CEST`.
- Repository: `puntoracingrc/pachangas`.
- Initial `origin/main`: `b0a94edd62050967af9188299018151ac0a3a0a0`.
- Branch: `codex/first-time-onboarding-gate`.
- Isolated worktree: `/Users/macbookpro14/.codex/worktrees/pachangas-first-time-onboarding-gate`.
- Shared checkout: left untouched, including its pre-existing local changes.
- Functional commit: pending.
- Pull request: pending.
- Preview deployment: pending.
- Merge SHA: pending.
- Production deployment: pending.
- Supabase migrations: none.

## Product behavior

A registered player without a canonical initial assessment is now held inside one mandatory three-step journey:

1. Complete the existing basic player profile.
2. Select a city or town through Google Places and choose preferred playing days.
3. Complete the existing initial Rating V2 assessment to create the universal player card.

Until the server confirms the initial assessment, the regular product shell is not rendered. The user cannot see the dashboard, match agenda, team data, primary navigation, mobile bottom navigation or legal footer. The gate cannot be dismissed. Once the canonical card exists, the normal application becomes available and the advanced assessment remains optional.

The visible location language is `Ciudad o población`; the previous `zona general` wording is not used. The existing server field remains compatible and stores only the selected general-area text, not a precise address or device coordinates. `Días habituales` is presented as `Días preferidos`.

## Server authority

- The gate is decided from `pachanga_player_assessments.initial.completed_at` returned by `GET /api/ratings/assessment` with `Cache-Control: no-store`.
- Browser storage remains only a resumable, unconfirmed profile or questionnaire draft.
- Initial assessment submission still uses the existing authenticated, idempotent, revisioned Rating V2 authority.
- The API now verifies the canonical social profile and city/town before accepting an initial assessment, so a direct URL or forged browser sequence cannot bypass steps 1 and 2.
- The authenticated actor is derived from the session. The browser cannot author the result, score, facets, reliability or server revision.
- Realtime remains an invalidation signal. On `rating_profile`, each client refetches the canonical assessment snapshot.
- Offline and server errors fail closed and never expose a confirmed card or the product shell.
- Existing profiles, initial and advanced assessments, teams, cosmetics and later Rating V2 evolution remain compatible.

No Rating V2 question, formula, scale, facet, reliability rule, assessment engine or persistence RPC was changed. No migration or production data mutation is part of this release.

## Regression coverage

- Canonical gate distinguishes a completed initial assessment from missing or malformed local data.
- First-card profile readiness requires a server-confirmed city or town.
- Step 2 uses the existing Google Places integration with city-only suggestions.
- Step 3 opens the real initial assessment and cannot be reached as a confirmed flow from an incomplete profile.
- The API independently enforces the profile prerequisite.
- The assessment route has no product navigation until the card is confirmed.
- `/perfil` still opens the real assessment when the card is absent.
- `/personalizar-carta` still redirects a player without a sports profile to the assessment.
- Existing social onboarding, invitations, team creation, no-team entry, PWA cache and Rating V2 tests remain green.

## Local verification

- `npm test`: PASS. Build PASS; Node `20/20`; TS/TSX `874/874`; total `894/894`; skipped/todo/cancelled `0/0/0`.
- `npm run typecheck`: PASS.
- `npm run build`: PASS; `79/79` static pages generated.
- Focused onboarding, Google Places, V3E and V3F tests: PASS, `53/53`.
- `npm run lint`: PASS with `0` errors and one pre-existing `react-hooks/exhaustive-deps` warning in `app/page.tsx`.
- `git diff --check`: PASS.
- Secret scan of the diff: no credential or server secret found.

## Responsive QA

- Desktop `1440x900`: all three steps fit without horizontal overflow; short states remain centered.
- Portrait `390x844`: the complete flow is vertically reachable; no product navigation or footer is mounted.
- Landscape `844x390`: a real clipping defect caused by unsafe vertical centering was reproduced and corrected with safe alignment. Steps 1, 2 and 3 now start inside the viewport and their final actions remain reachable through contained vertical scrolling.
- Broken images: zero in the local flow.
- Runtime console errors: zero in the local flow.

The local layout and Places callback contract passed. A real Google Places selection cannot be certified locally because Vercel redacts the sensitive Preview value when pulling environment variables; it remains an explicit exact-Preview gate.

## Remote release gates

- Exact-SHA Vercel Preview: pending.
- Real Google Places city/town selection in Preview: pending.
- Authenticated first-time user with no team: pending.
- Canonical card creation, hard reload, fresh session and Realtime convergence: pending.
- Production deployment and smoke: pending.
- Synthetic QA residue readback: pending.
- Physical Android, iPhone and installed-PWA checks: not part of this browser release and remain `PENDING` unless performed on real devices.
