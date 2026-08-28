# Demo World V2.7 - Public Competition Parity Report

## Estado

`GENERATED / VERIFIED / REMOTE WRITES 0`

Demo World preserva V2.1 a V2.6 y añade V2.7 con los renderers productivos de
Public Competitions.

## Escenarios

- una Liga publica con inscripcion abierta, plazas, calendario y standings;
- un Torneo publico/en curso con grupos, bracket y campeon;
- una Competition unlisted accesible por enlace y noindex;
- una Competition private visible solo desde perspectiva autorizada;
- Team A accepted;
- Team B waitlisted;
- Team C rejected;
- Team D withdrawn.

Accepted crea la Entry canonica simulada; waitlisted, rejected y withdrawn no
la crean. Los estados se generan con el mismo contrato de operaciones que el
producto y se verifican contra sus invariantes.

## Privacidad

Los snapshots publicos no contienen mensajes privados, motivos internos,
owner UUID, emails, telefonos, roster, Attendance, lesiones, fees ni evidencia.
Private y unlisted no aparecen en el directorio; unlisted conserva noindex.

## Evidencia determinista

| Evidencia | Valor |
| --- | --- |
| Snapshot hash | `e4830ff25db5318a169e0e8da5cf7ffb8820beee8616cc6e88e8cf6a05a2b7dd` |
| Authority hash | `eedee3d55d597dfc0c9037192c22ccb41b7667d0a797c03` |
| Remote writes | `0` |
| Demo tests | PASS |
| Liga/Torneo publicos | PASS |
| Private/unlisted isolation | PASS |
| Calendar/standings/bracket canonicos | PASS |

Rating, Rewards, Conduct y Billing se comprobaron sin mutaciones. V2.7 no
activa pagos, disciplina publica, autoaccept, ida y vuelta ni doble eliminacion.

## UI

La Demo añade Directorio, Liga publica, Torneo publico, solicitud, waitlist,
pagina no listada y perspectivas de organizador/participante. Reutiliza los
componentes productivos y mantiene navegacion responsive en desktop, portrait,
landscape y PWA.

