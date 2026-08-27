# Tournament Foundation V1 Report

## Estado

`LOCAL RELEASE CANDIDATE / STAGING PENDING`

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
| Incidencias | `R6A-001` a `R6A-006`, corregidas y con regresion |

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

## Gate local

| Gate | Resultado |
| --- | --- |
| Contrato TS/TSX | `14/14 PASS` |
| SQL/RLS/idempotencia | `PASS` |
| Concurrencia | `10/10 PASS` |
| Scale | `10k plans / 20k revisions / 100k placements / PASS` |
| Performance | `260 muestras / solver acotado a 128 intentos / PASS` |
| Demo World V2.4 | `14/14 + reconstruccion identica PASS` |
| Typecheck | `PASS` |
| Build | `PASS`, 53 paginas |
| Lint focalizado | `PASS` |
| Lint global | deuda previa: `22 errores / 18 warnings` |
| Bateria global | `540/540 PASS` (`20 Node + 520 TS/TSX`) |
| Tournament matches | `0` |

Las suites que restauran infraestructura Supabase se ejecutan en serie porque
los catalogos de roles son compartidos por el cluster PostgreSQL local. La
repeticion serializada confirma `158 -> 163 PASS` y concurrencia `10/10 PASS`;
la colision inicial queda trazada como `R6A-007 ENVIRONMENT_ISSUE`.

## Pendiente de cierre

- rama Supabase efimera y cinco migraciones exactas;
- E2E autenticado Team + Club, dos dispositivos y Realtime;
- Preview/PWA instalada;
- Advisors remotos;
- merge, migracion y smoke productivo;
- readback final y retirada del worktree.
