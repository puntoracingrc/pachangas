# Official / Demo V3.2 parity audit

Baseline: `origin/main` at `a3e5abe7ab37d21f4b3f10edcb6de7d5504979bd`.

The Demo is a composition reference and a read-only synthetic review surface.
The official product remains authoritative for permissions, mutations, private
data, and server-confirmed state.

| Surface | Demo World V3.2 | Official product | Wave 8D objective |
| --- | --- | --- | --- |
| Inicio | Strong team identity, two competing actions, fixed player-oriented metrics | Team dashboard already derives the next match and role-sensitive action | One primary action, role label, canonical context, and no admin tools as player hero |
| Partido | Rich upcoming/lineup/result/admin panes | Server-authoritative match state and role checks | Preserve authority; expose only valid pane and one current match context |
| Próximo partido | Compact synthetic agenda and attendance preview | Canonical attendance RPCs and current snapshot | Same hierarchy; offline is confirmed read-only, never optimistic success |
| Alineación | Game layout with local-only Demo interactions | Canonical lineup and revision controls | Keep game layout, keyboard alternative, stale-revision feedback |
| Resultado | Synthetic result and scorers | Canonical finalization and result dispute flows | One result action, clear finalized/locked states, no client authority |
| Administración de equipo | Demo admin tools gated by synthetic role | Owner/admin server permissions | Contextual destination, not a permanent player destination |
| Perfil de equipo | Hero shield and team history | Team identity and operational read models | Unified team context and operational status |
| Carta de jugador | Synthetic ratings/cosmetics | Rating V2 canonical snapshots | Shared card presentation; Rating formula and evidence unchanged |
| Personalización | Local Demo inventory | Server-authoritative cosmetic ownership | Shared visual controls; no Demo grant becomes product ownership |
| Mercado | Players, teams and matches in one synthetic view | Real public read models and server commands | One Market shell, stable tab deep links, compact responsive cards |
| Retos | Synthetic challenge history | Canonical social/challenge flows | Discoverable under Competir/Market context without duplicating authority |
| Clubs | Synthetic public Club profiles | Clubs public beta read models | Context-aware public/profile/management states |
| Árbitros | Synthetic profiles and assignments | Referee marketplace and private assignments | Arbitrar appears only for relevant capability; public privacy preserved |
| Ligas | Full synthetic season, rounds, standings | League Hub read models and commands | `Competir` entry with contextual rounds/matches/standings rail |
| Torneos | Groups, bracket and champion | Tournament Hub read models and commands | `Competir` entry with rounds/bracket/match context |
| Competiciones públicas | Sanitized league/tournament directory | Public discovery APIs | Public visitor path, stable filters and no private identifiers |
| Organización | Synthetic application/grant/onboarding | Organizer access and configuration clients | Role-context action, not a player hero or global technical tab |
| Planes | Seven synthetic billing states, Stripe disabled | Organizer billing read models | Contextual settings; no live checkout activation |
| Estado operativo | Seven canonical synthetic scenarios | Team Operational State | Shared status language and valid next action |
| Notificaciones | Synthetic feed and local read state | Server-authoritative notification center/preferences | One badge/feed, mandatory notices cannot be hidden |
| Control Center | Synthetic reviewer concepts spread across modules | Platform-admin routes | Reviewer/admin-only contextual navigation and canonical queues |
| Demo World | Nine perspectives and nine immutable checkpoints | Product routes remain separate | V3.3 guided review reuses the same snapshots, components, and vocabulary |

## Baseline navigation

- Product shell: Inicio, Partido, Mercado, Equipo, Perfil.
- Desktop utilities: Ligas, Torneos, Organizar, Ranking, Avisos.
- Demo secondary row: 12 always-visible technical/domain destinations.
- Portrait: five fixed destinations, but no `Competir` concept.
- Landscape: five primary cells plus a separate horizontally clipped domain row.

## Legitimate divergences

- Demo attendance, cosmetics, and tour progress are local presentation state.
- Official writes require actor, operation ID, expected revision, server time, and
  a canonical response.
- Demo may explain unavailable future capabilities; it must not manufacture
  permission, entitlement, payment, or sporting results.
- Public directories remain sanitized and do not expose private context options.

## Wave 8D closure

| Contract | Result |
| --- | --- |
| Product navigation | Six canonical destinations on desktop/landscape; five on portrait |
| Role tools | Derived from perspective for discovery only; server capability remains authoritative |
| Context | One selector contract carrying type, identity, role, state, and next action |
| Demo domain navigation | Contextual grouped menu instead of a second permanent global bar |
| Official/Demo vocabulary | `Competir`, role perspectives, canonical states, and next-action language aligned |
| Demo authority | V3.2 hash `763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1` preserved |
| Remote Demo writes | 0 |
| Sporting/Rating/Billing authority changes | 0 |

The remaining differences are intentional data and permission boundaries, not
visual or navigation forks.
