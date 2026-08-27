# Tournament Foundation V1 Report

## Estado

`PRODUCTION ACTIVE / PRIVATE BETA`

R6A crea la primera autoridad privada de Tournament sobre las entidades
canonicas de Competition. No crea partidos, resultados, standings, calendario,
progresion de bracket, pagos ni inscripcion publica.

## Trazabilidad

| Dato | Valor |
| --- | --- |
| Fecha | `2026-08-27` |
| Base | `31d83d5014d19bb6a94960019038f1fa0038bba3` |
| Rama funcional | `codex/tournament-foundation-draw-engine-v1` |
| PR funcional | `#204 MERGED` |
| Main funcional | `68dc360acf5dcce6cd7ffb6be4fa4b4d14d20cd7` |
| Ledger base | `158` |
| Migraciones R6A | `5` |
| Ledger productivo | `163` |
| Node | `v24.16.0` |
| Incidencias | `R6A-001` a `R6A-041`, registradas antes de corregir |

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

## Gates locales, staging y produccion

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

La rama Supabase final fue reconstruida desde el ledger productivo exacto y
las mismas cinco migraciones se aplicaron despues en produccion:

- pre-R6A: `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693`;
- post-R6A: `163 / 20260826195040 / 53b5456c21933e614752179568576d18`;
- schema hash local: `ed02a2dccac26791336c7dd8d044af8636556e300040e5c535d5379ca527aed4`;
- cinco migraciones exactas, once flags nacidos OFF y cero Tournament match
  contexts.

El E2E autenticado completo paso Team y Club, determinismo, concurrencia de
publicacion `1 winner / 1 stale`, modo automatico, manual, HYBRID, knockout con
byes, restricciones imposibles, retirada que invalida el freeze, 17 negativos
de seguridad/producto y Realtime con refetch canonico. Tras la prueba quedaron
los flags OFF, cero grants activos y cero Tournament match contexts; las filas
  QA vivieron solo en la rama efimera, retirada al cerrar la release.

Security Advisor no encontro errores. Los 18 hallazgos de foreign keys R6A
quedaron resueltos con indices de cobertura. Performance Advisor solo conserva
un warning heredado de indices duplicados en snapshots de Rating, ajeno a R6A.
Los logs remotos no contienen 5xx; los 4xx corresponden a negativos esperados.

La Preview Git `dpl_CcoXgisaJH6jQ68vpRcgcU3SaGNR` esta `READY` en el commit
exacto `5cd821c55a009bf4a74e020d60a7228edbb8a2c0`. El escaneo de sus 12 chunks
encuentra el ref de staging y cero apariciones de los refs de produccion,
staging ajeno o del valor exacto de service role. Las seis rutas protegidas
responden 200. Desktop `1440x900`, portrait `390x844` y landscape `844x390`
presentan cero overflow raiz, imagenes rotas, overlays o errores de consola.
La produccion quedo desplegada en `dpl_2CHjktZiXEmimN5AXGeKrdrUFZh7`, READY y
asociada al SHA exacto `68dc360acf5dcce6cd7ffb6be4fa4b4d14d20cd7`.
Las cinco migraciones avanzaron el ledger remoto de `158` a `163`, con digest
`53b5456c21933e614752179568576d18`.

La activacion se ejecuto por `command_pachanga_tournament_platform_v1`, revision
de settings `11` y secuencia de servidor `1136`. Quedaron ON Foundation,
Private Beta, Creation, Draw, Automatic, Manual, Hybrid y Publish. Public
Discovery, Match Generation y Bracket Progression siguen OFF. La repeticion
del mismo `operationId` produjo un unico evento/receipt y ninguna segunda
aplicacion.

El canary productivo `R6A-PROD-4784A46F4233` se ejecuto en una transaccion con
`ROLLBACK`: creo el bundle y participantes efimeros, completo HYBRID con dos
locks, valido el audit canonico y cancelo/revoco antes del rollback. El readback
independiente confirmo cero Tournaments, plans, placements, grants y Tournament
match contexts QA persistentes, ademas de cero sesiones Auth creadas.

El smoke productivo cubrio `/torneos`, `/torneos/crear`,
`/laboratorio-tournament-draw` y `/demo?demo=1&world=tournament` en `1440x900`,
`390x844` y `844x390`: cero overflow raiz no intencional, imagenes rotas,
errores de consola o warnings de hidratacion. Manifest, Service Worker,
controlador activo, cache offline de Demo y reconexion pasaron en navegador.
La PWA instalada fisica, Android fisico e iPhone fisico quedan pendientes y no
se presentan como pasados.

## Cierre

- rama Supabase R6A eliminada; `pwa-bridge-staging` conservada intacta;
- tres variables Vercel limitadas a la rama R6A eliminadas;
- contenedor de restauracion, dumps, credenciales y temporales R6A eliminados;
- worktree conservado solo hasta fusionar este informe y retirado despues segun
  la politica del repositorio;
- R6B, generacion de partidos, progresion, resultados, pagos y discovery no se
  iniciaron.
