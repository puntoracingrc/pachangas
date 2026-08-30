# Team Competition Continuity V1 Report

Fecha: 2026-08-30 CEST

## Políticas canónicas

| Política | Efecto |
| --- | --- |
| `ALLOW_EXISTING_COMPETITIONS_TO_FINISH` | Bloquea actividad nueva según scope y permite completar la competición vigente. |
| `FREEZE_FUTURE_SPORTING_WRITES` | Conserva lectura/historia y detiene nuevas operaciones deportivas. |
| `PLATFORM_MANAGED_EXIT` | Exige una decisión administrativa por cada participación. |
| `HISTORY_ONLY` | Mantiene únicamente lectura histórica. |

La política forma parte de cada decisión; no se deduce de `SUSPENDED`, Billing,
Conduct ni una sanción de jugador.

## Invariantes

Aplicar, modificar, expirar, archivar o restaurar un estado Team no:

- elimina `CompetitionEntry`, roster, fixture, Assignment o resultado;
- cambia standings, goles, Rating, logros, cajas o cosméticos;
- crea no-show, derrota administrativa o forfeit;
- cancela retos ya finalizados;
- modifica evidencia deportiva histórica.

Una consecuencia deportiva requiere la autoridad administrativa de la
Competition y su propia revisión.

## Guards

`private.pachanga_assert_team_operational_scope_v1` serializa contra el Team y
resuelve el scope. Los contextos de competición consultan además la continuity
decision específica. `CompetitionRegistration`, aceptación y creación de
Entry se bloquean antes del commit cuando corresponde.

Carreras cubiertas:

- suspend vs Organizer Application submit/approve;
- suspend vs Registration submit/accept;
- suspend vs Challenge/Match/official result;
- continuity change vs sporting write;
- archive vs owner transfer;
- review close vs restriction apply.

Cada carrera termina con un resultado canónico y un stale/rejected o un commit
anterior reconciliado y marcado; nunca dos decisiones finales incompatibles.

## Demo y staging

Team C recibe `SOCIAL_ONLY`: Mercado y Retos se bloquean, la Liga continúa y
el cambio de standings procede exclusivamente del resultado oficial. Team D
recibe `NEW_ACTIVITY_ONLY`: no puede registrarse en una competición nueva,
pero conserva el resultado histórico y no recibe no-show/forfeit automático.

Staging confirmó historia JSON idéntica antes/después de la restricción,
`EXISTING_COMPETITION_OPERATIONS = true`, grants suspendidos en cero y
`TEAM_OPERATIONAL_STATE_V1_STAGING_PASS`.

## Resultado

La continuidad es explícita, versionada y auditable. El estado operativo del
Team gobierna capacidad futura sin reescribir el pasado deportivo.
