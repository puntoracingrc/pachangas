# Synthetic Season Fault Injection V1

Cada carrera produce un ganador canonico y un segundo resultado explicitamente
`STALE`, `REJECTED` o `IDEMPOTENT`. No existe last-write-wins silencioso.

| Caso | Ganador canonico | Segundo resultado |
| --- | --- | --- |
| replay `operationId` | `receipt_original` | IDEMPOTENT |
| `expectedRevision` obsoleta | `revision_19` | STALE |
| dos actores por ultima plaza | `registration_request_a` | STALE |
| cambio de horario vs confirmacion arbitral | `schedule_revision_7` | STALE |
| sancion vs cierre de squad | `sanction_revision_4` | REJECTED |
| correccion vs rebuild de standings | `official_decision_31` | STALE |
| correccion de cuartos vs semifinal | `quarterfinal_revision_5` | STALE |
| suspension Team vs aceptacion | `team_state_revision_9` | REJECTED |
| owner transfer vs solicitud organizador | `ownership_revision_3` | STALE |
| cierre Torneo vs correccion final | `final_correction_revision_6` | STALE |
| reconexion Realtime | `canonical_refetch_sequence_128` | IDEMPOTENT |
| escritura PWA offline | `server_confirmation_required` | REJECTED |

Las suites SQL adicionales revalidan concurrencia real en Organizer Access,
R4A, R4B, R4C, R4D, R5, Referee Assignments, R6A, R6B, R6C, Public
Competitions, Configuration Center, League Private Beta y Team Operational
State. Los runners historicos se fijan a su frontera de migracion; el ledger
global permanece en 212.
