# Tournament Foundation V1 Report

## Estado

`STAGING CERTIFIED / RELEASE CANDIDATE`

R6A crea la primera autoridad privada de Tournament sobre las entidades
canonicas de Competition. No crea partidos, resultados, standings, calendario,
progresion de bracket, pagos ni inscripcion publica.

## Trazabilidad

| Dato | Valor |
| --- | --- |
| Fecha | `2026-08-27` |
| Base | `31d83d5014d19bb6a94960019038f1fa0038bba3` |
| Rama | `codex/tournament-foundation-draw-engine-v1` |
| PR | `#204` draft |
| Ledger base | `158` |
| Migraciones R6A | `5` |
| Ledger local | `163` |
| Node | `v24.16.0` |
| Incidencias | `R6A-001` a `R6A-031`, registradas antes de corregir |

## Autoridad

Toda mutacion entra por una de estas RPC versionadas:

- `command_pachanga_tournament_draw_v1` para Tournament, participantes y sorteo;
- `command_pachanga_tournament_platform_v1` para flags y grants.

El cliente envia `operationId`, agregado, revision esperada, accion y payload
semantico. PostgreSQL resuelve actor, permisos, tiempo, secuencia, seed,
checksums, placements, calidad y revision confirmada. Los receipts hacen la
operacion idempotente; el lock del agregado y `expectedRevision` impiden
last-write-wins silencioso.

## Modelo persistente

- flags Tournament privados, nacidos OFF;
- participant freezes inmutables;
- DrawPlan mutable por revision;
- DrawRevision, placements, byes y quality snapshots append-only;
- pots, constraints y manual locks normalizados;
- grants privados por Team o Club, con capacidad 4-64;
- eventos, receipts e invalidaciones Realtime ordenados por server sequence.

R6A reutiliza `Competition`, `Edition`, `RuleRevision`, `Stage`,
`CompetitionEntry`, `StageMembership`, Team, Club y notificaciones existentes.

## Seguridad

- `anon` y `authenticated` no escriben tablas Tournament directamente;
- el navegador no puede enviar actor, placement, resultado, calidad,
  algoritmo, checksum, fecha o secuencia;
- RLS limita invalidaciones y read models;
- el comando devuelve un snapshot filtrado por actor: participantes no ven
  invitaciones ajenas ni DrawPlans no publicados;
- el audit publicado oculta Auth IDs y motivos privados;
- service role no aparece en el cliente;
- Realtime solo invalida: cada cliente relee el snapshot canonico.

## Migraciones

1. `20260826195034_tournament_foundation_participant_freeze_v1.sql`
2. `20260826195036_tournament_draw_schema_revisions_v1.sql`
3. `20260826195037_tournament_draw_commands_engine_v1.sql`
4. `20260826195039_tournament_draw_access_read_models_v1.sql`
5. `20260826195040_tournament_draw_hardening_indexes_flags_v1.sql`

La reconstruccion temporal confirma `158 -> 163`, equivalencia de esquema y
flags OFF. No se modifica ninguna de las 158 migraciones anteriores.

## Gates locales y staging

| Gate | Resultado |
| --- | --- |
| Contrato TS/TSX | `17/17 PASS` |
| SQL/RLS/idempotencia | `PASS` |
| Concurrencia | `10/10 PASS` |
| Scale | `10k plans / 20k revisions / 100k placements / PASS` |
| Performance | `260 muestras / solver acotado a 128 intentos / PASS` |
| Demo World V2.4 | `14/14 + reconstruccion identica PASS` |
| Typecheck | `PASS` |
| Build | `PASS`, 53 paginas |
| Lint focalizado | `PASS` |
| Lint global | deuda previa: `22 errores / 18 warnings` |
| Bateria global | `543/543 PASS` (`20 Node + 523 TS/TSX`) |
| Tournament matches | `0` |

Las suites que restauran infraestructura Supabase se ejecutan en serie porque
los catalogos de roles son compartidos por el cluster PostgreSQL local. La
repeticion serializada confirma `158 -> 163 PASS` y concurrencia `10/10 PASS`;
la colision inicial queda trazada como `R6A-007 ENVIRONMENT_ISSUE`.

La rama Supabase final fue reconstruida desde el ledger productivo exacto:

- pre-R6A: `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693`;
- post-R6A: `163 / 20260826195040 / 53b5456c21933e614752179568576d18`;
- schema hash local: `ed02a2dccac26791336c7dd8d044af8636556e300040e5c535d5379ca527aed4`;
- cinco migraciones exactas, once flags OFF y cero Tournament match contexts.

El E2E autenticado completo paso Team y Club, determinismo, concurrencia de
publicacion `1 winner / 1 stale`, modo automatico, manual, HYBRID, knockout con
byes, restricciones imposibles, retirada que invalida el freeze, 17 negativos
de seguridad/producto y Realtime con refetch canonico. Tras la prueba quedaron
los flags OFF, cero grants activos y cero Tournament match contexts; las filas
QA viven solo en la rama efimera que se retirara al cerrar la release.

Security Advisor no encontro errores. Los 18 hallazgos de foreign keys R6A
quedaron resueltos con indices de cobertura. Performance Advisor solo conserva
un warning heredado de indices duplicados en snapshots de Rating, ajeno a R6A.
Los logs remotos no contienen 5xx; los 4xx corresponden a negativos esperados.

## Pendiente de cierre

- Preview Git exacta con variables de staging y escaneo de bundle;
- merge, cinco migraciones y deployment productivo;
- activacion Private Beta por RPC, canary y readback final;
- retirada de staging, variables Preview, temporales y worktree.
