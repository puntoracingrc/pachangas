# Tournament Completion V1

## Snapshot canónico

`TournamentCompletionSnapshot` persiste:

- competición y edición;
- revisión exacta de bracket;
- campeón y subcampeón;
- tercer y cuarto puesto opcionales;
- final `CanonicalMatch`;
- checksum;
- revisión y secuencia;
- hora del servidor.

El snapshot es reconstruible desde el bracket y las AdvanceDecision vigentes.
Rebuilds concurrentes generan una única revisión efectiva.

## Preconditions

`tournament.complete` exige:

- final oficial y AdvanceDecision vigente;
- cero nodes pendientes;
- cero disputas;
- cero partidos aplazados o suspendidos;
- bracket health válido;
- snapshot actual;
- RuleRevision exacta;
- flags/grant y expected revision válidos.

Lifecycle: `active -> completed -> locked`. No existe `completed -> active` ni
edición posterior a `locked`.

## Podio

- Campeón: ganador vigente de la final.
- Subcampeón: perdedor vigente de la final.
- Tercer/cuarto puesto: resultado oficial del node opcional de tercer puesto.
- Sin tercer puesto configurado, ambos campos permanecen nulos; no se inventa
  clasificación.

Una corrección de final invalida el snapshot anterior. `complete` contra una
corrección concurrente produce un ganador y un conflicto, nunca dos campeones.

## Sin economía automática

R6C no concede cajas, cosméticos, premios, dinero, Season Score o Ranking.
`Reward grants = 0`. Los eventos futuros no alteran propiedad ni balances.

## Read models y UI

- Hub: Resumen, Jornadas, Partidos, Clasificación, Equipos, Disciplina,
  Árbitros, Incidencias, Reglamento y Cuadro.
- Cuadro vivo: selector de ronda, node detail, resultado, ET, penalties,
  ganador, partido y Organizer Desk.
- Team Journey: fase, path, próximo rival/fuente, eliminación y posición final.
- Celebration opcional; `prefers-reduced-motion` muestra el resultado directo.
- PWA offline solo lee campeón y cuadro previamente cacheados.

## Verificación

| Gate | Resultado |
| --- | --- |
| Completion rebuild | idempotente y revisionado |
| Dos rebuilds | 1 winner / 1 conflict |
| Complete vs corrección final | 1 winner / 1 conflict |
| Completion scale | 10.000 snapshots con rollback |
| Completion p50/p95 | 54,72 / 58,61 ms |
| Demo | 1 campeón, 1 subcampeón, 1 tercero, bracket bloqueado |
| Sistemas protegidos | Rating, Rewards, Conduct y Billing intactos |

La activación remota y el canario reversible se documentan en el informe de
release.
