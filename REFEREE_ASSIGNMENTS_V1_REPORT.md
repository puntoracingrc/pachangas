# Referee Assignments V1 Report

Estado: `READY FOR REVIEW`

## Autoridad de partido

Una `RefereeAssignment` nunca apunta a una copia local del partido. Requiere un
`pachanga_canonical_matches.id` y un binding exacto y vigente desde una fuente
soportada (`group_match`, `open_match`, `external_match` o `team_challenge`).
Un partido sin binding canonico falla `REFEREE_CANONICAL_MATCH_REQUIRED`.

La propuesta toma del servidor:

- canonical match y source binding;
- inicio, final y timezone;
- revision de horario de la fuente;
- requester Team o Club y su autoridad;
- actor autenticado;
- secuencia y fecha de servidor.

El navegador no puede imponer un horario, revision, identidad del arbitro,
Club, Team, competencia o permiso mediante snapshots propios.

## Alcance de roles

Solo `MAIN_REFEREE` esta habilitado funcionalmente en R3. El schema reserva
assistant, cronometrador y mesa para fases posteriores, pero los flujos R3 no
los presentan como operativos.

Requester puede ser Team o Club. Team usa owner/admin del grupo; Club usa owner,
admin o `club_referee_manager`. El adaptador de Competition usa exclusivamente
el contexto canonico y staff autorizado, sin activar League/Tournament Engine.

## Lifecycle

| Accion | Resultado |
| --- | --- |
| Proponer | `proposed`, con deadline y snapshot de horario |
| Aceptar | `accepted`; valida perfil activo y ausencia de solapamiento |
| Rechazar | `declined` |
| Confirmar | `confirmed`; valida slot unico y revision de horario |
| Cancelar | `cancelled`, con reason code/text acotados |
| Reemplazar | nueva propuesta enlazada; la anterior solo cambia al confirmar el reemplazo |
| Reconciliar | `completed` al finalizar el partido canonico |

Si cambia el horario despues de la propuesta, confirmar con snapshot obsoleto
falla; el requester debe reconciliar o volver a proponer con la revision nueva.
No existe last-write-wins silencioso.

## Concurrencia e idempotencia

PostgreSQL usa transaccion, revision, unique slot, advisory locks y chequeo de
solapamiento. Las pruebas cubren:

- dos respuestas simultaneas a la misma propuesta;
- confirmacion contra cancelacion;
- dos arbitros para el mismo slot MAIN_REFEREE;
- dos partidos solapados para el mismo arbitro;
- reemplazos concurrentes;
- reconciliacion concurrente al finalizar;
- replay identico y operationId reutilizado con payload distinto.

En cada carrera hay un unico estado final y todos los clientes convergen tras
invalidacion + snapshot canonico.

## Reemplazo

La propuesta de reemplazo referencia `replaces_assignment_id`. La asignacion
original conserva autoridad hasta que el nuevo arbitro acepta y el requester
confirma. Solo entonces se enlazan `replaced_by_assignment_id` y el estado
`replaced`; un rechazo o expiracion no deja el partido sin la asignacion previa.

## Finalizacion y estadisticas

La finalizacion deportiva sigue perteneciendo al motor canonico existente. R3
solo reconcilia una asignacion confirmada cuando la fuente informa partido
finalizado. La reconciliacion incrementa una sola vez el snapshot estadistico y
es idempotente.

Estadisticas derivadas:

- propuestas recibidas;
- aceptadas, rechazadas y confirmadas;
- partidos concluidos;
- partidos individuales y de Competition;
- Clubs activos;
- ultima finalizacion.

`incremental` y `full_rebuild` producen el mismo documento/checksum. El arbitro
no puede escribir contadores. Anular administrativamente una reconciliacion
reconstruye desde evidencia canonica.

## Disciplina

No existe motor canonico de tarjetas en R3. El snapshot fija:

- `discipline_stats_status = NOT_AVAILABLE`;
- `yellow_cards_shown = null`;
- `red_cards_shown = null`;
- `blue_cards_shown = null`.

Ninguna UI o RPC permite registrar tarjetas, sanciones o informes arbitrales.

## QA y escala

El E2E staging cubrio propuesta individual, accept, decline, confirm, cancel,
replace, cambio de horario, binding ausente, conflicto de slot, solapamiento,
finalizacion, reconcile, rebuild, checksum y dos dispositivos con Realtime.

La carga representativa usa `100.000` asignaciones. El chequeo de conflicto
alcanzo p95 `0.164 ms`; la query de rebuild p95 `0.050 ms`. EXPLAIN confirma el
indice de solapamiento y el slot activo unico. Tras la limpieza de staging
quedaron `0` asignaciones activas fixture.

R3 no modifica resultado, goleadores, alineacion, asistencia, Rating, Conduct,
rewards, Billing, Season Score ni rankings del partido.
