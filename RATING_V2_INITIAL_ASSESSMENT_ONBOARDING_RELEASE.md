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
- Initial implementation commit: `2149ddea4d73e17c6f079e1bcfa54c5b339865ee`.
- Pull request: `#281`, merged.
- Initial Preview deployment: `dpl_8pBvR3yeZaXcL6786h9RdUtSB63j`, READY for commit `2149ddea4d73e17c6f079e1bcfa54c5b339865ee`.
- Staging-certified Preview before the final responsive fix: `https://pachangas-ihya1cqqc-persianas-almar-web-s-projects.vercel.app`, READY for commit `8f0807a4a4ed10215b67aa398ced7961324bdb11`.
- Final staging Preview: `dpl_4fzXFzvpaqaJ2J92HZZKHy2NzEES`, READY at `https://pachangas-l4yfkx6ei-persianas-almar-web-s-projects.vercel.app` for commit `0ebf84b2ade29faa924414e551c0bca71c71e119`.
- Merge SHA: `db7f72b28183075535ffafebd15acb1d34b9f3cf`.
- Production deployment: `dpl_4brkngMSiU7kLVruy9MjjoXCaqba`, READY and assigned to `pachangasiq.com` for the exact merge SHA.

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
- Universal-profile writes emit a user-scoped `rating_profile` invalidation through the existing published social invalidation stream. Group-context clients also listen to the existing group event stream.
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

- `npm test`: PASS. Build PASS; Node `20/20`; TS/TSX `869/869`; total `889/889`; skipped/todo/cancelled `0/0/0`.
- `npm run typecheck`: PASS.
- `npm run lint`: PASS. Only Babel's informational large-file message for the pre-existing `app/page.tsx`.
- Focused onboarding, Rating V2, Official UI and PWA tests: PASS.
- `git diff --check`: PASS.

Responsive browser QA:

- Desktop `1440x900`: the initial flow and completed-card state fit without horizontal overflow, clipped controls or broken images.
- Portrait `390x844`: all 15 steps are reachable by normal vertical scrolling; the final submit clears the fixed mobile navigation and the completed state exposes both allowed follow-up actions.
- Landscape `844x390`: QA first reproduced a real defect where the card and actions were cut because the compact layout depended on `pointer: coarse`, while the game shell did not. The fix now keys the compact assessment layout to landscape height, gives the flow a contained vertical fallback and assigns stable grid positions to its title and close control.
- After the fix, step `15/15`, `Crear ficha`, the completed card, `Personalizar mi carta` and `Mejorar precisión de mi ficha` are all fully visible at `844x390` with zero horizontal overflow.
- Browser console: zero runtime errors during the assessment traversal.
- Broken images: zero in every checked viewport.
- The development-only visual fixture used for these checks was removed before validation and is not part of the release diff.

Staging transport incident:

- Classification: `ENVIRONMENT_ISSUE`.
- Reproduction: two final-SHA staging runs reached Vercel through the authenticated `vercel curl` beta transport and failed with `LibreSSL SSL_connect: SSL_ERROR_SYSCALL`, first on `/sw.js` and then on `/api/ratings/assessment`.
- Scope: transport failed before an HTTP response; it was not tied to one product route, RPC or Supabase operation.
- Correction: the staging harness retries at most three times only for an explicit allowlist of transient network errors. HTTP statuses, invalid JSON and product assertions remain fail-closed and are never retried as success.
- Regression verification: PASS. The exact-SHA staging run completed every product assertion after the bounded retry was added.

Account-deletion compatibility incident:

- Classification: `PRODUCT_BUG`, found during the pre-production synthetic cleanup check.
- Reproduction: deleting a staging Auth account that had completed the assessment failed with SQLSTATE `55000` and `PLAYER_ASSESSMENT_EVIDENCE_IMMUTABLE`.
- Root cause: the evidence tables declared `ON DELETE CASCADE` from `auth.users`, but their immutable trigger rejected that declared cascade as if it were a direct evidence deletion.
- Correction: forward-only migration `20260905105747_allow_rating_evidence_auth_user_cascade_v1.sql` permits a delete only when it is nested inside the Auth foreign-key cascade and the parent Auth row is already absent. Direct receipt/event deletion and every update remain immutable.
- Regression: PASS locally and in staging. SQL exercises direct-delete rejection and complete Auth cascade cleanup in the same transaction.
- A complete Auth-account deletion then reached a separate pre-existing Rating V2 constraint: `pachanga_player_rating_snapshots_player_profile_id_fkey` rejects deletion of a canonical player profile that has snapshots. That wider account-erasure graph predates this release and is not changed here; synthetic production cleanup therefore uses an explicit, UUID-scoped administrative transaction and must finish with a zero-row readback.
- Hotfix verification: build, `889/889` tests, typecheck, global lint, focused SQL/RLS, two-client concurrency and `git diff --check` all pass. Supabase Advisors attributes no security finding to the migration; the only related notice is the expected `unused_index` info for an empty staging evidence table.

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
- Synthetic rows were rolled back by the SQL tests. The disposable database and local diagnostics remain isolated until the release gate completes, then will be removed.

Database lint found no issue in the new authority. It still reports ten pre-existing findings in unrelated venue, Stripe, reward and standings functions; they were not changed in this release.

## Remote staging

- Ephemeral Supabase branch: `rating-onboarding-v1` (`jtfugdbnvjnxhodispji`), separate from production.
- Migration ledger: `239` entries through `20260905084509`.
- New self-assessment RPC grants: `service_role` only; `anon` and `authenticated` denied.
- Authenticated synthetic flows A-E: PASS.
- Two clients racing the same operation: one canonical profile and identical confirmed response.
- Hard reload and a fresh login recover the same initial assessment and universal profile.
- Advanced assessment remains optional, requires the initial assessment and rejects a stale revision.
- Direct profile/assessment DML and direct client execution of the server-only RPC: denied.
- Offline attempt: fails closed with no persisted change.
- Realtime between two devices: PASS through a scoped invalidation followed by canonical refetch.
- Final exact-SHA certification: PASS for commit `0ebf84b2ade29faa924414e551c0bca71c71e119` and all flows A-E.

The first remote run found that `pachanga_player_profiles` and `pachanga_player_assessments` were not members of the Realtime publication even though the UI subscribed to them. The fix does not publish private rating tables: it reuses the existing RLS-protected invalidation table and adds the explicit `rating_profile` entity type. A regression now exercises the actual Realtime event.

## Production release

- Migration `20260905084509_restore_initial_assessment_profile_onboarding_v1.sql` was applied forward-only before the frontend deployment.
- Linked migration history is synchronized at 239 versions through `20260905084509`.
- Readback confirms zero production self-assessment receipts/events before canary, seven valid indexes, the public wrapper executable only by `service_role`, private functions unreachable by client roles and the `rating_profile` invalidation constraint active.
- PR `#281` merged as `db7f72b28183075535ffafebd15acb1d34b9f3cf`.
- Vercel production deployment `dpl_4brkngMSiU7kLVruy9MjjoXCaqba` is READY and aliases both `pachangasiq.com` and `www.pachangasiq.com` to that exact merge SHA.

Pending before final closure:

1. Merge and apply the account-cascade compatibility migration documented above.
2. Run the canonical production smoke with synthetic data and explicit zero-row cleanup readback.
3. Remove the ephemeral staging branch, branch-scoped Preview variables, disposable local database and this worktree.
