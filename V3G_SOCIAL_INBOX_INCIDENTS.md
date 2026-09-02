# Official UI V3G Social Inbox incidents

## V3G-001 - Synthetic Team fixture referenced a non-canonical shield column

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: transactional Social Inbox SQL contract test.
- Original failure: `column "social_shield_key" of relation "pachanga_groups" does not exist`.
- Product impact: none. The transaction aborted and no local or remote data was persisted.
- Cause: the fixture mixed a UI shield key with the canonical `pachanga_groups` schema.
- Correction: create the synthetic Teams using only the social columns introduced by V3F.
- Regression: `npm run test:social-inbox:db` executes the complete V3F and V3G migration chain plus the synthetic Inbox scenario inside a rollback-only transaction.
- Regression verified: yes. The rollback-only SQL suite passes.

## V3G-002 - Inbox projection rejected canonical UUID values outside RFC version bits

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: unresolved Challenge notification projected through `get_my_pachanga_social_inbox_v1`.
- Original failure: the canonical Challenge existed and required a response, but the Inbox classified it as `RESOLVED / Ya no disponible`.
- Product impact: imported or deterministic UUID values accepted by PostgreSQL could lose their actionable projection.
- Cause: the defensive text-to-UUID helper required RFC version and variant bits even though the canonical columns use PostgreSQL `uuid`, whose accepted value space is broader.
- Correction: validate UUID syntax, then let PostgreSQL perform the authoritative cast without imposing extra version bits.
- Regression: the synthetic contract intentionally uses a canonical UUID without RFC version bits and requires the Challenge to remain `ACTION_REQUIRED`.
- Regression verified: yes. The rollback-only SQL suite passes.

## V3G-003 - Accepted guest match route was absent from the client allowlist

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: an accepted open-match request projects the canonical `/partido-invitado?acceso=...` deep link.
- Original failure: the server returned a safe internal destination, but `safeSocialInboxDeepLink` removed it because the client allowlist did not include `/partido-invitado`.
- Product impact: an accepted guest could see the resolved activity without the button that opens the match they may access.
- Cause: server and client allowlists were not reconciled after the accepted guest route was added to the projection.
- Correction: add the exact internal pathname to the client allowlist. Parameters remain server-built and external, protocol-relative, `javascript:` and `data:` destinations remain rejected.
- Regression: the focal test accepts `/partido-invitado?acceso=abc` and rejects external or administrative routes.
- Regression verified: yes. `npm run test:social-inbox` passes.

## V3G-004 - V3G focal tests were not included in the complete suite

- Classification: `TESTABILITY_GAP`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: release-gate reconciliation after adding the V3G source and SQL tests.
- Original failure: `npm run test:social-inbox` existed, but `npm test` did not invoke `tests/social-inbox-v1.test.ts`.
- Product impact: later global release runs could pass without exercising the new Inbox contract.
- Cause: the focal script was added before the complete-suite list was updated.
- Correction: include the V3G test file in the global TS/TSX suite while retaining the focused command.
- Regression: the focal test asserts that the complete test command contains its own V3G contract test.
- Regression verified: yes. `npm run test:social-inbox` passes.

## V3G-005 - Concurrent replay could collide after waiting for the actor lock

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: two devices submit the same Inbox `operationId` before either transaction has committed its receipt.
- Original failure: both transactions could miss the initial receipt lookup; after serializing on the actor lock, the second transaction continued and collided on the receipt primary key instead of replaying the confirmed response.
- Product impact: the canonical mutation remained single-application, but the retrying device could receive an error instead of converging on the exact server receipt.
- Cause: the receipt was checked before acquiring the advisory lock and not checked again after waiting.
- Correction: repeat the receipt and argument-conflict check immediately after acquiring the per-user transaction lock.
- Regression: the focal contract requires a post-lock receipt read, and the dedicated concurrency test holds the actor lock so two requests deterministically miss the first read before replaying the same operation.
- Regression verified: yes. `npm run test:social-inbox:concurrency` passed with two concurrent sessions, one mutation, one receipt and identical confirmed responses.

## V3G-006 - Demo Profile exposed a second obsolete notification center

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: navigating to Demo Profile after V3G added the canonical Social Inbox tab and bell.
- Original failure: Profile still offered a separate `Avisos` pane backed by the old generic read-state array.
- Product impact: the Demo presented two competing Inbox concepts with different counters and state.
- Cause: the V3G navigation was added without removing the replaced Demo-only pane.
- Correction: Profile keeps `Ficha` and `Recompensas`; all social notices now enter through the bell and `Avisos`, while channel preferences remain in Ajustes on the real product.
- Regression: the focal test isolates `ProfileView` and rejects the obsolete `Avisos` pane and its old center heading.
- Regression verified: yes. `npm run test:social-inbox` passes and rejects the obsolete Demo Profile notification pane.

## V3G-007 - Inbox commands bypassed the PWA client-version write bridge

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: marking or archiving an Inbox item through Supabase in browser or installed PWA mode.
- Original failure: `command_pachanga_social_inbox_v1` was not in the known write RPC classifier, so the shared Supabase fetch transport did not attach bridge metadata or enforce incompatible/offline write blocking.
- Product impact: an obsolete PWA could attempt this new write without the permanent client-version guard and telemetry path.
- Cause: the RPC was introduced after the classifier inventory was last updated.
- Correction: register the exact V3G command RPC as a V2 client write. The read-model RPC remains deliberately unclassified and available for reads.
- Regression: the focal test classifies the exact PostgREST endpoint as `rpc:command_pachanga_social_inbox_v1`.
- Regression verified: yes. `npm run test:social-inbox` and the complete PWA bridge test classify the command as a write and leave the read RPC unclassified.

## V3G-008 - Concurrency fixture used a non-canonical notification category

- Classification: `SIMULATION_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: setup for the deterministic two-session Inbox replay test.
- Original failure: PostgreSQL rejected the synthetic `team` category through `pachanga_user_notifications_category_check`.
- Product impact: none. Setup aborted before the concurrent command and the cleanup removed the synthetic user.
- Cause: V3G exposes the product domain as `TEAM`, but the existing notification table deliberately retains the canonical storage category `group`.
- Correction: the fixture now stores `group`; the projection remains responsible for returning `sourceDomain = TEAM`.
- Regression: rerun the full two-session concurrency script with the canonical category.
- Regression verified: yes. `npm run test:social-inbox:concurrency` passes with the canonical `group` storage category projected as `TEAM`.

## V3G-009 - An in-flight Inbox command could update the next signed-in session

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: user A starts a read/archive command and signs out or changes to user B before the RPC resolves.
- Original failure: Inbox reads rejected stale responses by actor and request generation, but the command path did not capture its initiating actor and did not use `try/finally`. A late response could refresh the next session or leave the busy indicator stuck after a transport exception.
- Product impact: no cross-user database write is possible because the RPC resolves `auth.uid()` and enforces recipient ownership, but the browser could display stale command feedback or refresh the wrong user session.
- Cause: command lifecycle isolation lagged behind the already protected read lifecycle.
- Correction: bind every command to its initiating actor, ignore late UI effects after an actor change, clear command state during reconnect, serialize commands in the provider and always release the busy state in `finally`.
- Regression: the focal source contract requires actor capture, stale-session rejection, reconnect cleanup and guarded `finally` release.
- Regression verified: yes. `npm run test:social-inbox` passes 17/17, including the stale-session command lifecycle contract.

## V3G-010 - PWA regression inventory omitted the new match-invitation read RPC

- Classification: `TESTABILITY_GAP`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: the complete PWA bridge test inventories every RPC invoked by browser product surfaces and separates reads from writes.
- Original failure: `get_my_pachanga_match_invitation_action_v1` was absent from the explicit read list, so the test expected it to be protected as a write even though the write classifier correctly returned `null`.
- Product impact: none at runtime. The failure prevented release and exposed an incomplete regression inventory.
- Cause: Mercado gained a new server read model after the bridge test's read allowlist was last updated.
- Correction: register the exact RPC as read-only in the bridge regression while retaining `respond_pachanga_match_invitation_v1` and the Social Inbox command as classified writes.
- Regression: the complete PWA bridge inventory must classify the read RPC as `null` and every adjacent mutation as a known write.
- Regression verified: yes. `npx tsx --test tests/pwa-client-version-bridge.test.ts` passes 10/10 with zero skips, todos or cancellations.

## V3G-011 - Provider lifecycle violated focused React lint contracts

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: focused ESLint over every V3G TypeScript and TSX route.
- Original failure: the disabled-provider branch called React setters synchronously inside an effect, and `runCommand` read the complete `snapshot` while declaring only `snapshot.serverSequence` as a memo dependency.
- Product impact: avoidable cascading renders on excluded routes and a React Compiler optimization skip caused by an imprecise callback dependency.
- Cause: provider reset and command code were added incrementally without a final React lifecycle pass.
- Correction: schedule guarded provider reset outside the effect body and read the current sequence through `snapshotRef`, keeping the command callback independent of the snapshot object.
- Regression: focused ESLint plus V3G and typecheck.
- Regression verified: yes. Focused ESLint, `npm run test:social-inbox` and `npm run typecheck` pass.

## V3G-012 - Seven cross-slice tests still asserted the superseded notification UI

- Classification: `TESTABILITY_GAP`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: complete `npm test` after replacing the mounted notification popover with the canonical Social Inbox and extending the Demo session schema.
- Original failures: seven tests still required one or more superseded details: `/perfil/avisos`, mounted `NotificationCenter`, preferences rendered at the legacy route, the old four-entry Demo tab set, a Demo session shape without per-perspective Inbox state, or the old challenge-only Home action selector.
- Product impact: no runtime failure was demonstrated, but the release suite failed and no longer described the intended product contract.
- Cause: V3G focal coverage was added before reconciling older cross-feature source-contract assertions.
- Correction: update the seven assertions to require `/avisos`, `/ajustes/notificaciones`, `SocialInboxProvider`, the versioned Demo Inbox state and the generalized one-action Home projection. Guest request review is asserted in its real admin surface and player invitation response remains in Mercado. Guest, preferences, V3B and V3C authority checks remain intact.
- Regression: rerun the isolated seven-file suite, then the complete suite.
- Regression verified: yes. The isolated suite passes 77/77 and the complete suite passes Node 20/20 plus TS/TSX 798/798, total 818/818, with zero failures, skips, todos or cancellations.

## V3G-013 - Disposable database URL was not restored after the desktop restart

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: rerunning the rollback-only SQL/RLS gate after ChatGPT Desktop had closed and resumed the task.
- Original failure: `SOCIAL_INBOX_DATABASE_URL` was absent from the resumed shell, so `psql` tried the default local socket on port 5432 and exited before executing SQL.
- Product impact: none. No migration, fixture or assertion ran and no database was modified.
- Cause: the disposable local PostgreSQL connection was session-scoped and was not exported into the resumed process environment.
- Correction: verified the disposable instance on `127.0.0.1:55322` and passed its URL explicitly to the rollback-only database and concurrency commands.
- Regression: complete both SQL/RLS and concurrent replay gates against the disposable database, then confirm their cleanup/readback.
- Regression verified: yes. The SQL/RLS suite completed inside `BEGIN`/`ROLLBACK`, and the deterministic two-session replay returned one receipt at revision 2 with both clients converged.

## V3G-014 - Demo Inbox used dark-only surfaces under the light product theme

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: local browser QA of Demo Social Inbox at 1440x900 with the product's current light theme.
- Original failure: cards, selected state, detail pane, toolbar and proof panel used hard-coded dark backgrounds while their text inherited the light-theme dark ink variables.
- Product impact: titles, summaries and detail text were difficult or impossible to read despite the DOM remaining structurally valid.
- Cause: the new CSS module assumed the old always-dark Demo palette and did not use the existing theme-aware panel variables.
- Correction: replace dark-only surfaces with `--demo-panel` and `--demo-panel-soft`, and use theme-aware text variables for notices and metadata.
- Regression: visual and computed-style checks in light and dark themes across desktop, portrait and landscape.
- Regression verified: yes. The clean production build is readable with the light theme, retains the intended dark treatment, and the final eight-viewport matrix reports zero overflow, zero broken images and fully visible Inbox actions.

## V3G-015 - The 26-step Demo proof reused a React key

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: opening Demo Social Inbox and inspecting the browser console.
- Original failure: React reported two children with key `Volver` because the proof list used the human-readable step as its key and that label occurs twice.
- Product impact: development console error and unsupported child identity if the list is updated.
- Cause: a non-unique display string was used as the list identity.
- Correction: include the deterministic step index in the local proof key.
- Regression: reopen the Inbox, inspect the complete proof list and require zero console errors.
- Regression verified: yes. The complete 26-step proof renders and the clean production build reports zero browser console errors.

## V3G-016 - Demo onboarding launcher occupied the Inbox action area in landscape

- Classification: `PRODUCT_BUG`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: production-build browser QA at 844x390 in Demo Social Inbox.
- Original failure: the global fixed `Primeros pasos` launcher remained visible over the lower-right Inbox detail area while that pane had its own canonical CTA and vertical scroll.
- Product impact: the unrelated onboarding control consumed the only compact action corner and made the Inbox detail action less discoverable.
- Cause: the landscape launcher was rendered for every Demo tab, including the new focused Inbox workspace.
- Correction: suppress only the global launcher while `activeTab === "avisos"`; the 26-step Inbox proof and all other Demo onboarding entry points remain available. The focused detail typography and CTA spacing were compacted without removing any Inbox action.
- Regression: require the launcher guard in the focal contract and recheck all landscape viewports for visible action collisions.
- Regression verified: yes. At 667x375, 740x360, 844x390 and 932x430 the global launcher is absent, the canonical Inbox CTA is fully visible, and there is no horizontal overflow or broken image. The 844x390 readback places the CTA entirely inside the viewport at y=191..229.

## V3G-017 - Isolated worktree did not inherit the linked Supabase project ref

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: release-ledger reconciliation with `supabase migration list --linked`.
- Original failure: CLI 2.107.0 returned `Cannot find project ref` because the ignored `supabase/.temp/project-ref` is not copied into an isolated Git worktree.
- Product impact: none. The command stopped before connecting to a database and no migration or data operation ran.
- Cause: task isolation correctly excludes ignored machine-local Supabase link state.
- Correction: link only this task worktree to the independently verified `Pachangas` project ref `qonbngfrnrqgmxbdfbea`, rerun the read-only migration ledger and require all other Supabase projects to remain untouched.
- Regression: exact local/remote migration list plus project inventory and final task-local link cleanup.
- Regression verified: yes. CLI 2.107.0 reports 233 exact local/remote pairs through `20260901214527` and only the V3G migration `20260902064632` as local pending. The project inventory still contains the three pre-existing projects and no command targeted the two non-Pachangas refs.

## V3G-018 - QA filter selector matched both the filter and mobile navigation

- Classification: `TESTABILITY_GAP`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: browser QA of the `Retos` Social Inbox filter at 390x844.
- Original failure: an unscoped accessible-name selector matched the `Retos` filter button and the `Retos` mobile-navigation button, so strict mode rejected the click before any UI action.
- Product impact: none. Both controls were visible, distinct and functional; only the QA selector was ambiguous.
- Cause: the automated step ignored the existing `Filtrar por tipo` accessible container.
- Correction: scope the control lookup to the labelled filter group before selecting `Retos`.
- Regression: the scoped filter returns only the four Challenge-related Inbox cards and does not navigate away from `/avisos`.
- Regression verified: yes. The filtered titles are `Tienes una contrapropuesta`, `Reto aceptado`, `Contrapropuesta recibida` and `Resultado confirmado`.

## V3G-019 - New files carried an extra blank line at EOF

- Classification: `TESTABILITY_GAP`
- Status: `fixed`
- Detected: 2026-09-02
- Scenario: first staged `git diff --cached --check` over the complete V3G path set.
- Original failure: six newly tracked files ended with an additional blank line and failed the release whitespace gate.
- Product impact: none at runtime; the release gate correctly stopped the commit.
- Cause: the earlier unstaged diff check could not inspect untracked file contents.
- Correction: remove only the redundant trailing blank lines, restage the six paths and rerun the staged and unstaged diff checks.
- Regression: both `git diff --cached --check` and `git diff --check` must return no output.
- Regression verified: yes. Both staged and unstaged diff checks return no output.
