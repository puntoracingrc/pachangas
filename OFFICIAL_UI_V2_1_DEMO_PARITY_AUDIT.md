# Official UI V2.1 Demo Parity Audit

## Checkpoint

- Date: 2026-08-22 (CEST).
- Initial main: `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Branch: `codex/official-ui-v2-1-deep-demo-parity`.
- Draft PR: [#163](https://github.com/puntoracingrc/pachangas/pull/163).
- Initial branch checkpoint: `4381563af4149236d79c3adf2faf53f5aa40bcfc`.
- Sources: local code, local Demo World, the Official UI V2 visual evidence already tracked in `docs/official-ui-v2`, and local browser inspection. No production or Supabase data was written.

## Finding

Official UI V2 established a shared shell, palette and responsive modes, but the authenticated home still mounts the legacy hero, eight peer actions and a permanent Team Access band before the actual sporting content. Demo World instead establishes one hierarchy: identity, one next action, the team object, compact metrics, upcoming matches and recent activity.

The remaining gap is therefore structural rather than chromatic. Match, Market, Ranking, Notifications and the cosmetic editors already have more of the target language, but they still need a common hierarchy and density pass.

## A / B / C Comparison

| Dimension | A. Demo World | B. Current official | C. V2.1 migration |
| --- | --- | --- | --- |
| Data authority | Isolated fixtures | Canonical read models, RPC and Realtime | Keep official authority unchanged |
| First viewport | Identity, next action, object and metrics | Brand hero, many actions and Team Access metadata | Identity band, one CTA, player card or shield and real metrics |
| Navigation | One global shell plus contextual side navigation | Shared shell plus legacy content navigation | Keep shell; make contextual navigation part of each game hub |
| Actions | One dominant action | Manual, session, profile, team, identity, Market, Create and Settings compete | One state-derived action; secondary operations in compact menus |
| Matches | Horizontal agenda and compact history | A narrow match/history panel beside a large manager | Home rails plus one persistent Match Hub |
| Objects | Shield/card are protagonists | Card and shield often sit inside long forms | Object stage plus compact controls |
| Landscape | Purpose-built manager composition | Correct shell with several compressed legacy panels | Preserve shell, reduce inner panels and whole-page scrolling |
| Empty states | One next step | Several generic empty copies | One valid CTA without invented metrics |

## Surface Matrix

| Surface | Demo structure | Current official structure | Duplicated or over-visible | Primary action | Protagonist | Desktop gap | Portrait gap | Landscape gap | Proposed migration |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Home | Identity band, shield, 4 metrics, agenda rail, activity and results | Legacy hero, 8 actions, permanent Team Access, match list and manager | Team name, role, status, group ID and level | State-dependent next step | Shield or own player card | Sporting content starts too low | Hero and metadata consume several screens | Legacy blocks compete inside the HUD | New real-data Home dashboard; Team Access becomes selector plus drawer |
| Match hub | Persistent side subnav and one match context | Side subnav, context, match list, main panel and lineup panel | Match state and mode appear in several headers | Depends on pane/state | Match context and active pane | Match list steals width from active task | Long stacked panels | Too many independently scrolling areas | Extract one hub header; keep existing handlers and read models |
| Next match | Scoreboard/facts, attendance, roster | Settings/main panel, roster states, payment and weather | Date/place/status recur | Attendance or admin next step | Attendance and confirmed roster | Secondary administration appears early | Player rows are tall | Vertical manager compressed horizontally | Prioritize facts, attendance and roster; secondary data remains available |
| Lineup | Pitch occupies workspace | Pitch plus titles, balance, actions, two team lists and result controls | Lineup controls repeat in side tools and panel | Prepare/close lineup | Interactive pitch | Pitch is one block among several | Pitch competes with lists | Extra controls reduce field area | Keep `MatchPitch`; group tools once and make field the visual stage |
| Result | Large score plus scorers | Result inputs, photo, scorers and finalization inside lineup panel | Result labels and team scores repeat | Finalize/confirm | Scoreboard | Secondary upload dominates before score | Long stacked form | Score and scorers lack clear split | Promote score and scorer list; keep exact callbacks and guards |
| Match admin | Grouped operations | Many forms and action grids | State repeated in every operation block | Save current operation | Admin purpose group | Indifferent visual weight | Very long | Dense unprioritized grid | Group Configuration, Market, Guests, Privacy and Danger |
| Market | Side modes, compact filter, scannable results | Correct side modes and filters, but no stable list/detail hierarchy | Title and context repeat in shell and page | Search or item action | Result collection | Cards are still form-like | Filters consume vertical space | Feels like rotated desktop in dense states | Keep RPCs; compact context/filter and define list/detail workspace |
| Ranking | Own position first, table later | Product route and canonical snapshot; own rank lives inside board | Season and territory repeat | Understand eligibility | Own position | Top status bars delay own result | Formula metadata is too prominent | Table density needs a stable viewport | Keep ranking authority; place own rank and eligibility before table |
| Notifications | Priority, category and action | Notification center plus separate preferences route | Profile/notification headings repeat | Resolve required item | Highest-priority notification | Preferences, not actionable inbox, dominate route | Toggles are clear but long | No compact priority workspace | Preserve events/preferences; emphasize mandatory/actionable/history |
| Player card | Card stage plus collection controls | Real cosmetic editor already follows this pattern | Route and editor headings repeat | Save card | `PlayerCosmeticCard` | Minor hierarchy cleanup | Mostly aligned | Mostly aligned | Retain editor authority; compact duplicate route chrome |
| Team shield | Shield stage plus collection/progression | Real identity route already uses `TeamShieldView` and editor | Identity/team headings repeat | Save shield or open reward | `TeamShieldView` | Minor hierarchy cleanup | Mostly aligned | Progression can crowd object | Retain authority; keep shield stage first |
| Team room | Ranking/plantilla/logros/escudo contextual modes | Internal ranking and gallery mixed into home page state | Team/Ranking labels recur | Open own player or ranking | Own rank/team collection | No single room hierarchy | Long internal page | Manager mode varies by pane | Extract presentation progressively; no new team state |
| Referee profile | Dedicated product card | R3 official card and read model | Low duplication | Contextual referee action | Referee card | Already close | Already close | Needs density-only verification | Visual QA only unless a concrete defect is found |
| Control Center | Not a game surface | `PLATFORM_ADMIN` tables and diagnostic shell | None relevant | Operational task | Data table | Correct | Correct | Not applicable | Keep unchanged |

## Responsive Findings

### Desktop

- The shared header and context bar are stable.
- Home fails first-viewport parity because legacy account and create controls precede the match agenda.
- Match functionality is complete, but the match list, active task and lineup compete for equal visual weight.

### Portrait

- The single bottom navigation is correct.
- The legacy hero and Team Access create avoidable vertical travel.
- Match and Market remain functional, but filter/form density delays the sporting object or result list.

### Mobile Game Landscape

- `OfficialProductShellV2` already provides the correct single HUD and preserves children across orientation changes.
- Inner legacy panels still introduce whole-workspace scroll and reduce the pitch, scoreboard and scannable lists.
- The work must change composition, not duplicate the tree for landscape.

## Authority Boundary

V2.1 may transform presentation only. It must not change RPC names, payloads, revision checks, idempotency, RLS, Realtime subscriptions, rating calculations, match state transitions, notification persistence, Market queries, ranking publication, cosmetic inventory or permissions. New components receive already-derived values and existing callbacks.

## Implementation Order

1. Home identity, one next action, compact metrics, upcoming and activity rails.
2. Compact Team Access selector and administrative drawer.
3. Match Hub header and pane hierarchy while preserving current controls.
4. Market, Ranking, Notifications and object-editor density pass.
5. Light/dark and responsive verification, then A/B/C evidence.

## Known Limits At Audit Time

- The clean local worktree has no private environment file, so authenticated local state is validated through official source/read-model branches and tracked Official UI V2 captures. Authenticated Preview QA will use the Vercel environment without performing destructive actions.
- Reward activity is not duplicated into `app/page.tsx`; Home must not invent pending rewards if the canonical read model is unavailable there.
- Demo World remains untouched in data, fixtures and authority and is never
  used as an authority adapter. A later bounded CSS hotfix corrects only the
  Mobile Game Landscape identity-band height.

## Post-implementation Verification

- Home now exposes one `data-primary-action`, one identity band, four compact metrics, an upcoming rail, an activity rail and compact Team Access.
- Match now exposes one persistent contextual navigation and one persistent match context. The existing lineup, result and administration bodies keep their original callbacks and guards.
- Market now has one navigation and one compact context/filter/results workspace. Existing Market queries, feature flags and mutations remain in `app/mercado/page.tsx`.
- Ranking renders the canonical own-position result before the public table without changing its contract or formula.
- Demo World received no data, fixture, authority or redesign change. Its only
  source change is the responsive `identityBand` height fix from `100%` to
  `calc(100dvh - var(--game-nav-height, 48px))`, covered by
  `tests/demo-world-v1.test.ts`. Control Center received no source changes.
- The visual lab is explicitly noindex/nofollow and imports no Demo fixtures, Supabase client, RPC, localStorage or IndexedDB.
- The final local matrix covered 279 surface/viewport combinations: 144 V2.1 proposal combinations and 135 product/Demo regression combinations. All automated violation counters finished at zero.
- A same-page browser rotation test retained the selected Market tab and Match pane through portrait -> landscape -> portrait, with one contextual navigation after each change.

The clean worktree still contains no private local environment. Canonical
authenticated readback was therefore performed only against the isolated
staging Preview: owner without profile, base shield and configured shield now
have sanitized canonical evidence. Owner with profile is blocked by the
pre-existing Rating V2 assessment/profile ordering, and normal-player readback
remains pending a second authenticated identity. No local fixture is presented
as proof of server behavior.
