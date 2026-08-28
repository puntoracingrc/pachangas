# Tournament Knockout V1 Production Release

## Identidad del release

- Base inicial: `659511e41cbab57440ba23124f8e339110aed9c5`.
- Rama: `codex/tournament-knockout-bracket-champion-v1`.
- PR funcional: #209.
- PR de compatibilidad post-activación: #210.
- Supabase producción esperado antes de R6C: ledger 169.
- Objetivo: seis migraciones funcionales hasta ledger 175 y un hotfix
  forward-only de compatibilidad en ledger 176, con activación invite-only
  posterior al deployment del mismo SHA.

## Migraciones exactas

| Versión | Archivo | SHA-256 |
| --- | --- | --- |
| 170 | `20260827205347_tournament_knockout_bracket_authority_v1.sql` | `3ff4d3aabefe0ef3d65511e601405038dc507830aaeaff5f3c94bb7b445f1bb4` |
| 171 | `20260827205351_tournament_knockout_progression_results_v1.sql` | `f273c6273bf47f64bed7cecd34be3a6c259d8cab524fc9ca6b2b16eb1213ca32` |
| 172 | `20260827205356_tournament_knockout_canonical_match_adapter_v1.sql` | `08330a45d19257a672c3df5c6dcaa4b5d2b11666cd6c5b3a5f099810afd1cdcf` |
| 173 | `20260827205359_tournament_knockout_read_models_hub_v1.sql` | `1038d252af1525a2c411e9cb53c43a293bb1f5084374709dd71f1ae9fa2f4c4d` |
| 174 | `20260827205403_tournament_knockout_access_realtime_v1.sql` | `876f68ed7117628ff426c0dd0e58ba391e74caac77b0b8bf36211e81925d0cc6` |
| 175 | `20260827205409_tournament_knockout_hardening_flags_v1.sql` | `27b4c59a4b171a515a5457e60d40af2842b4d86ccad943ada18d5ca36aff1653` |
| 176 | `20260828045324_tournament_knockout_flag_authority_compatibility_v1.sql` | `df6c601489dcad556c8fd475559f99f4aaf799c4982f274a4304bc196a560aec` |

Paquete funcional: 5.918 líneas. Hotfix de compatibilidad: 272 líneas.
`lock_timeout = 5s`; `statement_timeout = 120s`. Las 175 migraciones
anteriores no se reescriben.

## Gate local confirmado

- Fresh bootstrap, upgrade 169->176 y schema equivalence: PASS.
- Schema hash: `3f813724b1e65e21d66ba345131d42a0ca7f42bee3b294d58e8dcd8b03ed6eb7`.
- Build y typecheck: PASS.
- Tests: 20/20 Node + 552/552 TS/TSX = 572/572.
- Lint focalizado: PASS.
- Lint global: 40 incidencias preexistentes fuera del diff R6C.
- `git diff --check`: PASS.
- Concurrencia, negativos, formatos, escala y performance: PASS.
- Demo World simulate/verify: determinista, 0 remote writes.
- QA visual: ocho viewports, 0 root overflow, 0 imágenes rotas, 0 errores
  consola/hidratación; PWA local controlada, offline y reconexión PASS.
- PWA instalada física, Android físico e iPhone físico: PENDING, no se presentan
  como PASS y no bloquean este release.

## Gates remotos

Esta sección se actualiza antes del cierre final. No interpretar los estados
pendientes como release completado.

| Gate | Estado | Evidencia |
| --- | --- | --- |
| Staging efímero creado | PASS | Branch privada full-clone `zsqmpkmvrpeiesbwvbsu`; baseline heredado ledger 169 y autoridades R6B presentes. |
| Migraciones staging 170..175 | PASS | Dry-run exacto, aplicación única y readback independiente: ledger 175, hashes/nombres coincidentes. |
| QA autenticada / Realtime | PASS | Dos clientes GoTrue, una invalidación canónica por dispositivo, refetch convergente y escritura directa denegada. |
| Cleanup staging / branch eliminado | PASS | Datos, flags, grants, usuarios, probes y procesos QA a cero; branch R6C eliminado y `pwa-bridge-staging` preservado. |
| Backup producción recuperable | PASS | Full-clone con datos creado desde producción, abierto en PostgreSQL 17.6, validado con historias canónicas y retirado tras cleanup. |
| Baseline/ledger producción | PASS | 169 receipts, último `20260827105036`, 0 locks exclusivos, 54.693.011 bytes y relaciones R6C ausentes. |
| Migraciones producción 170..175 | PASS | Aplicación forward-only única; ledger 175 y seis nombres exactos confirmados por CLI y API. |
| Hotfix 176 local | PASS | Bootstrap y upgrade equivalentes; la regresión del RPC R6A conserva los siete flags R6C y el canario local revierte íntegramente. |
| Hotfix 176 producción | PASS | Aplicación forward-only única; ledger local/remoto 176 y definición funcional confirmada. El warning opcional de cache pg-delta apareció después del SQL y no se reintentó. |
| Flags nacen OFF | PASS | Siete flags R6C false; two-leg, double elimination y public discovery false; flags R6B preservados. |
| PR #209 fusionado | PASS | Merge `94edebf1d470b92fc57988696a144567d2dc9d38`, 2026-08-28 02:34:44Z. |
| PR #210 fusionado | PASS | Merge `41c8280b55bdabd201da4169fbf524561bc9ee24`, 2026-08-28 03:14:57Z. |
| Deployment Vercel SHA exacto READY | PASS | `pachangas-319jsjkrf-persianas-almar-web-s-projects.vercel.app`, deployment `dpl_AH3CJhTQ25tXQU5QjrbqdTb3t9Bv`, target production y alias `pachangasiq.com`. |
| Smoke productivo | PASS | `/`, Demo World V2.6 y `/torneos` responden; R6C permanece invite-only y no hay discovery público. |
| Activación Private Beta por RPC | PASS | Operación `83b2493b-5a54-4981-a4c0-620bc82686da`, actor `service_authority`, revision 17 / sequence 1853; siete flags R6C ON y formatos avanzados OFF. |
| Canario 4 equipos reversible | PASS | 1 bracket de 4, 3 nodes, 2 semifinales, 2 CanonicalMatches distintos, 0 resultados y Hub/bracket válidos dentro de una transacción terminada en rollback. |
| Readback y cleanup productivo | PASS | Revision 17 / sequence 1853; 0 usuarios, competiciones, receipts, eventos y filas R6C QA; protegidos 1 / 17 / 0 / 0. |
| Demo World V2.6 LIVE | PASS | Cuadro completo, ocho partidos, campeón único, lineage de corrección y `remoteWrites=0` visibles en producción. |
| Service Worker productivo | PASS | `2.0.0+sw.41c8280b55bd`, controlador activo, `no-store`, Demo disponible offline y reconexión convergente sin errores. |

## Certificación de staging

- El primer branch schema-only se descartó al comprobar que no heredaba el
  baseline real. Se creó después un full-clone privado y se mantuvo intacto el
  branch ajeno `pwa-bridge-staging`.
- El escenario `COPA QA` recorrió activación, cuatro cuartos, resultado normal,
  prórroga, penaltis, no-show, semifinales, corrección con invalidación y
  replacement, final, tercer puesto, campeón y completion.
- Readback de la historia: 8 nodes vigentes, 8 matches activos, 9 históricos,
  1 predecesor retirado, 1 invalidación y campeón único. No se emitieron
  rewards y Rating, Rewards, Conduct y Billing conservaron sus digests.
- RLS permanece habilitada en todas las tablas R6C. Los clientes no tienen
  grants de escritura directa y las tablas de autoridad no se publican por
  Realtime; solo se publica una vez el bus canónico de invalidaciones.
- El actor de equipo no puede ejecutar la RPC de plataforma. `anon` no puede
  ejecutar APIs R6C; `authenticated` solo accede a los entrypoints previstos,
  que vuelven a validar identidad, capacidad, revisión e idempotencia.
- Supabase Advisors devuelve 71 INFO de FK sin índice y 10 INFO de índices
  todavía sin uso en tablas nuevas, además de cuatro warnings de seguridad
  esperados para los entrypoints `SECURITY DEFINER`.
  Están protegidos por permisos internos y sin grant a `anon`; no son
  escrituras abiertas sobre tablas.
- Cleanup de datos confirmado: siete flags R6C OFF, bundle beta QA revocado,
  cero grants activos, cero usuarios temporales, cero probes, cero brackets
  activos y cero procesos de prueba. El branch efímero y su release copy local
  se retiraron; el worktree quedó relinkado a producción, todavía en ledger 169.

## Baseline de producción

- Recoverability: el full-clone privado con datos arrancó saludable desde el
  estado productivo, expuso ledger 169 y permitió ejecutar las historias
  canónicas antes de ser eliminado. Es una prueba real de restauración, no una
  mera comprobación de que exista un fichero de backup.
- PostgreSQL `17.6`, tamaño 54.693.011 bytes y cero locks exclusivos ajenos en
  el checkpoint previo.
- Foundation revision 16 / server sequence 1285. Foundation, Private Beta,
  Draw, Group Stage, Group Match Generation, Tracking, Standings,
  Qualification y Bracket Template estaban ON; Public Discovery estaba OFF.
- Baseline protegido: 1 Rating snapshot, 17 reward grants, 0 conduct reports y
  0 billing events. Se comparará de nuevo después de migrar y activar.
- Las tablas de brackets, nodes, advances y completion R6C no existían antes del
  release.
- La copia de release difiere del repositorio exclusivamente en
  `db.migrations.enabled = true`. `db push --dry-run` enumera exactamente los
  seis archivos 170..175 y ningún SQL adicional.

## Readback posterior a migraciones

- Ledger: 176 receipts; último `20260828045324` con nombre y hash
  `df6c601489dcad556c8fd475559f99f4aaf799c4982f274a4304bc196a560aec`.
  El warning opcional de cache pg-delta apareció después de la aplicación; el
  comando salió con código 0, el readback independiente confirmó la migración y
  no se reintentó ningún SQL.
- Las trece relaciones R6C existen, tienen RLS, están vacías y no conceden
  `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `TRIGGER` ni `REFERENCES` a `anon`
  o `authenticated`.
- Realtime publica una vez `pachanga_tournament_invalidations` y cero tablas de
  autoridad R6C. El cliente recibe invalidación y relee el snapshot canónico.
- Los siete flags R6C nacieron OFF en foundation revision 16 / sequence 1285;
  todos los flags R6B previos permanecen ON y los formatos avanzados/discovery
  siguen OFF.
- Baseline protegido sin cambios: 1 Rating snapshot, 17 reward grants,
  0 conduct reports y 0 billing events. Locks exclusivos ajenos: 0.
- Security Advisor sobre el alcance exacto R6C: 13 INFO `RLS enabled/no policy`,
  intencionales como deny-all sobre tablas, y 5 WARN en los entrypoints
  `SECURITY DEFINER` (command, plataforma, lectura del cuadro, Hub y control de
  plataforma). Revocan `anon`, comprueban identidad/capacidad dentro de la
  función y son el API previsto. Remediación de referencia:
  https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- Performance Advisor sobre las 13 tablas exactas R6C: 71 INFO de FK sin índice
  y 3 INFO de índices todavía no usados por estar las tablas vacías. No es un
  stop condition: el scale gate de 10.000 brackets / 100.000 nodes y las
  latencias certificadas pasan. Se registra como deuda explícita sin reescribir
  una migración aplicada. Remediación de referencia:
  https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

## Compatibilidad post-activación

- La activación R6C quedó confirmada en foundation revision 17 / sequence 1853.
- El primer canario productivo se revirtió antes de crear el torneo QA porque
  el RPC R6A de flags intentaba escribir agregados incompatibles con R6C activo.
- La migración 176 no abre tablas, no concede permisos y no cambia datos:
  restaura el marcador transaccional de autoridad y obliga a los escritores
  R6A/R6B a preservar los siete flags propiedad de R6C.
- El probe productivo del RPC legado avanzó solo dentro de la transacción hasta
  revision 18, mantuvo todos los flags R6C y volvió por rollback a revision 17 /
  sequence 1853 con cero receipts/events.
- `R6C-PRODUCT-084`: `FIXED / REGRESSION_VERIFIED` después de ese probe y del
  canario productivo completo.

## Canario, PWA y smoke final

- Canario productivo: 1 bracket, 3 nodes, 2 semifinales, 1 final, 2
  CanonicalMatches distintos, 0 resultados deportivos/oficiales y snapshots Hub
  y bracket válidos; transacción finalizada con `ROLLBACK`.
- Readback independiente: 13 relaciones R6C, 0 filas totales; cero usuarios
  `r6a-fixture-*`, competición `r6a-concurrency-fixture`, receipts y eventos.
- Protegidos sin cambios: 1 Rating snapshot, 17 Reward grants, 0 Conduct reports
  y 0 Billing events.
- Responsive en producción: 1440x900, 390x844 y 844x390 con 0 overflow
  raíz/cuerpo, 0 imágenes rotas y 0 warnings/errors de consola.
- Demo World V2.6 muestra campeón Marina Fosca, 8 partidos y 1 predecesor
  retirado en los tres viewports.
- Manifest installable fullscreen; Service Worker activo
  `2.0.0+sw.41c8280b55bd`, respuesta `no-cache, no-store, must-revalidate`, carga
  offline completa y reconexión al snapshot canónico.
- Logs posteriores al canario: sin nuevos errores PostgreSQL, API o Realtime.
  El único ERROR en el intervalo corresponde al readback inválido ya registrado
  y cerrado como `R6C-SIMULATION-086`.

## Flags objetivo

ON al finalizar: Foundation, Draw, Group Stage, Group Match Generation,
Qualification, Knockout Foundation invite-only, Knockout Match Generation,
Bracket Progression, Extra Time, Penalty Shootout, Completion y Third Place
cuando la RuleRevision lo configure.

OFF: Two-leg, Double elimination, Public Discovery y Payments.

Los flags se modifican solo mediante la RPC de plataforma, nunca por `UPDATE`
directo.

## Rollback

- Antes de activar: migraciones aditivas + flags OFF; rollback funcional por
  kill switch/flags.
- Después de activar: mantenimiento temporal o roll-forward antes que reabrir
  escrituras antiguas.
- El canario no registra resultados y debe terminar con 0 torneos, brackets,
  nodes, matches, resultados, assignments y grants QA activos.
- Ninguna reversión convierte payload local en fuente de verdad.

## Estado actual

`R6C_INVITE_ONLY_ACTIVE / LEDGER_176 / PRODUCTION_CANARY_PASS / DEMO_WORLD_V2_6_LIVE / SERVICE_WORKER_PASS`.
