# Rating V2 initial assessment onboarding release

## Checkpoint

- Audit date: 2026-09-05 11:38:55 CEST.
- Repository: `puntoracingrc/pachangas`.
- Initial SHA: `6baf4445514faa8546810917a4adf97d0498b425`.
- Branch: `codex/restore-initial-assessment-onboarding`.
- Isolated worktree: `/Users/macbookpro14/.codex/worktrees/pachangas-restore-initial-assessment-onboarding`.
- Shared checkout initial state: pre-existing edits in the player-rating laboratory plus untracked `.codex-worktrees/` and `supabase/.temp/`; none were absorbed or modified.
- Isolated worktree initial state: clean.
- Remote migration ledger before release: synchronized through `20260905061857`; `20260905084509` remains local until the release gate.
- Commit: pending.
- Pull request: pending.
- Preview deployment: pending.
- Merge SHA: pending.
- Production deployment: pending.

## Reproduction before the change

| Flow | Previous behavior | Classification |
| --- | --- | --- |
| A. Registered, social profile, no sports profile, no team | `/perfil` showed the missing card but `Crear mi carta` opened `/personalizar-carta`; the cosmetic guard returned toward profile/home and `startPlayerAssessment("initial")` stopped at `!hasRealTeam`. | Confirmed by active UI and call graph |
| B. Registered, member of a team, no sports profile | The assessment existed behind contextual paths, but the permanent profile CTA still opened cosmetics first. | Confirmed by active UI and call graph |
| C. Registered from invitation or match link, no sports profile | The assessment could appear indirectly while joining, claiming a player or trying a match action; there was no permanent direct profile entry. | Confirmed by active UI and call graph |
| D. Initial assessment completed | The canonical profile and card existed and cosmetics could load them. | Confirmed by code, SQL and existing tests |
| E. Initial and advanced assessments completed | Both canonical assessments were preserved and Rating V2 continued from them. | Confirmed by code, SQL and existing tests |

Previous call graph:

```text
/perfil -> Crear mi carta -> /personalizar-carta
  -> missing profile guard -> profile/home
  -> startPlayerAssessment("initial")
  -> !hasRealTeam return
```

The old assessment API also required client-provided `groupId` and `playerId`. This made the existing engine unreachable as universal onboarding for a player without a team.

## Implemented product flow

Current call graph:

```text
/perfil
  -> Hacer test inicial y crear mi carta
  -> /perfil/test-inicial
  -> existing 15-step questionnaire and unchanged shared Rating engine
  -> POST /api/ratings/assessment
  -> authenticated actor + canonicalized answers + server calculation
  -> group authority when membership exists
     or universal-profile authority when it does not
  -> one PostgreSQL transaction
  -> canonical profile + assessment + Rating V2 snapshot + receipt + event
  -> canonical response
  -> Ficha creada con test inicial
  -> Realtime invalidation triggers a canonical refetch on other clients
```

The dedicated screen includes the existing modes, position, experience, elapsed time, frequency and ten technical questions. The optional advanced assessment remains available only after the initial assessment under `Mejorar precisión de mi ficha`.

`/personalizar-carta` now routes a missing sports profile directly to the initial assessment. Once the initial assessment exists, the cosmetic editor remains unchanged and cannot modify sports ratings.

## Authority and persistence

- The browser submits only assessment answers/context, `operationId`, expected revision and allowlisted client metadata.
- The API derives the actor from the authenticated session, resolves current membership/player context and canonicalizes every answer.
- Client timestamps and unknown fields are discarded before calculation or persistence.
- The existing `calculateSharedAssessmentResult` and Rating V2 formula are unchanged.
- No-team writes use `persist_pachanga_player_assessment_self_authoritative_v1`, callable only by `service_role` through the server API.
- The transaction creates at most one universal profile and one assessment of each kind, increments the profile revision, recalculates Rating V2, writes immutable receipt/event evidence and returns the canonical snapshot.
- Advisory locking, expected revisions and payload-bound idempotency cover retries and concurrent devices.
- Direct authenticated DML to profiles/assessments remains denied.
- Realtime events are invalidation signals only. Clients always refetch the canonical snapshot.
- `localStorage` contains only an unconfirmed resumable draft; it is removed only after a successful canonical response.
- Offline completion fails closed and never displays success.
- The PWA caches the test route, not assessment API responses or confirmed writes.

## Compatibility

- Existing group onboarding continues through `persist_pachanga_player_assessment_authoritative_v2`.
- A player without a team receives a universal profile with no fabricated group or player source.
- Canonical social display name and avatar are copied when available.
- Existing initial and advanced assessments remain unique and are not rerun.
- Rating V2 snapshots, later peer assessments, shared-match windows, facets and reliability continue through existing authorities.
- No Rating V2 formula, scale, facet, reward, competition, Stripe, result, challenge or market rule was changed.

## Verification

Local application checks:

- `npm test`: PASS. Build PASS; Node `20/20`; TS/TSX `867/867`; total `887/887`; skipped/todo/cancelled `0/0/0`.
- `npm run typecheck`: PASS.
- `npm run lint`: PASS. Only Babel's informational large-file message for the pre-existing `app/page.tsx`.
- Focused onboarding, Rating V2, Official UI and PWA tests: PASS.
- `git diff --check`: PASS.

Disposable PostgreSQL checks:

- Applied the complete pending migration chain to a disposable local database.
- New SQL/RLS assessment test: PASS.
- New identical and competing two-client concurrency test: PASS.
- Existing group assessment SQL/RLS test: PASS.
- Existing group assessment concurrency matrix: PASS.
- Exact retry returns one identical response and one profile/assessment/snapshot/receipt/event.
- A second operation cannot create another active initial assessment.
- Advanced assessment cannot replace or precede the initial assessment.
- Stale revision and invalid result both roll back fully.
- Direct client execution and private evidence access are denied.
- Synthetic rows, disposable database and diagnostic files were removed after the checks.

Database lint found no issue in the new authority. It still reports ten pre-existing findings in unrelated venue, Stripe, reward and standings functions; they were not changed in this release.

## Remote release gates

Pending before merge or production:

1. Preview/staging with the forward-only migration.
2. Authenticated browser QA for flows A-E, hard reload, sign-out/in and two-client convergence.
3. Responsive QA at desktop, portrait mobile and landscape mobile/PWA.
4. Exact Preview SHA verification and console/overflow/image checks.
5. Coordinated additive migration and frontend deployment, followed by canonical production smoke with synthetic data and complete cleanup.

Production has not been modified at this checkpoint.
