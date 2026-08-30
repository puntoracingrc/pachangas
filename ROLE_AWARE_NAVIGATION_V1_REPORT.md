# Role-Aware Navigation V1

## Before and after

| Area | Before Wave 8D | Final contract |
| --- | --- | --- |
| Desktop | Five primary destinations plus permanent technical utilities | Six product destinations; role tools contextual |
| Portrait | Five destinations without a competition domain | Inicio, Partido, Competir, Mercado, Perfil |
| Landscape | Product row plus a clipped domain strip | Six-destination game rail plus bounded contextual tools |
| Demo | Twelve always-visible domain links | Same primary product navigation plus grouped domain menu |
| Context | Separate selectors and labels | One selector contract for team, Club, competition, platform, and Demo perspective |

## Primary destinations

| Destination | Canonical route |
| --- | --- |
| Inicio | `/?mobile=inicio` |
| Partido | `/?mobile=partido` |
| Competir | `/competiciones` |
| Mercado | `/mercado` |
| Equipo | `/?mobile=equipo` |
| Perfil | `/?mobile=perfil` |

Portrait intentionally omits the standalone `Equipo` tab. The team remains
reachable from player context and role tools.

## Perspective matrix

| Perspective | Priority tools |
| --- | --- |
| Player | Equipo, Ranking, Avisos |
| Team admin / owner | Player tools, Organizar, Estado operativo |
| Club organizer | Organizar, Club, Ligas, Torneos, Avisos |
| League organizer | Organizar, Club, Ligas, Torneos, Avisos |
| Tournament organizer | Organizar, Club, Ligas, Torneos, Avisos |
| Referee | Ficha arbitral, Asignaciones, Avisos |
| Free agent / public visitor | Buscar equipo, Competiciones, Avisos |
| Platform reviewer / admin | Control Center, Avisos |

These links are discovery and prioritization only. They do not grant a role,
capability, entitlement, or write permission.

## Context and next action

The selector shows context type, name, role, status, and next action. The
official Home consumes existing canonical data and presents one primary action.
It does not introduce a second next-action engine. Demo contexts remain local
and synthetic.

## Deep links

The release preserves market tab, competition, checkpoint/week, surface/view,
perspective, tour, and tour-step parameters. Mercado now hydrates from a stable
server/client baseline and restores URL state after mount. `pushState`, browser
back/forward, reload, and rotation were verified without hydration warnings.

Referee routes were corrected to the existing canonical paths:

- `/perfil/arbitro`
- `/mis-asignaciones-arbitrales`

## Verification

- Navigation contract regression: six desktop/landscape and five portrait.
- Role matrix and referee paths: exact assertions.
- All competition clients: `active="competir"`.
- Browser QA at 1440x900, 1920x1080, 390x844, 360x800, 667x375,
  740x360, 844x390, and 932x430.
- No duplicate primary navigation, root overflow, clipped essential control,
  broken image, or fresh console error observed.
