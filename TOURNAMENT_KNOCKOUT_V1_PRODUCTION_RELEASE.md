# Tournament Knockout V1 Production Release

## Identidad del release

- Base inicial: `659511e41cbab57440ba23124f8e339110aed9c5`.
- Rama: `codex/tournament-knockout-bracket-champion-v1`.
- PR: #209 (Draft durante gates).
- Supabase producción esperado antes de R6C: ledger 169.
- Objetivo: ledger 175, flags naciendo OFF y activación invite-only posterior
  al deployment del mismo SHA.

## Migraciones exactas

| Versión | Archivo | SHA-256 |
| --- | --- | --- |
| 170 | `20260827205347_tournament_knockout_bracket_authority_v1.sql` | `3ff4d3aabefe0ef3d65511e601405038dc507830aaeaff5f3c94bb7b445f1bb4` |
| 171 | `20260827205351_tournament_knockout_progression_results_v1.sql` | `f273c6273bf47f64bed7cecd34be3a6c259d8cab524fc9ca6b2b16eb1213ca32` |
| 172 | `20260827205356_tournament_knockout_canonical_match_adapter_v1.sql` | `08330a45d19257a672c3df5c6dcaa4b5d2b11666cd6c5b3a5f099810afd1cdcf` |
| 173 | `20260827205359_tournament_knockout_read_models_hub_v1.sql` | `1038d252af1525a2c411e9cb53c43a293bb1f5084374709dd71f1ae9fa2f4c4d` |
| 174 | `20260827205403_tournament_knockout_access_realtime_v1.sql` | `876f68ed7117628ff426c0dd0e58ba391e74caac77b0b8bf36211e81925d0cc6` |
| 175 | `20260827205409_tournament_knockout_hardening_flags_v1.sql` | `27b4c59a4b171a515a5457e60d40af2842b4d86ccad943ada18d5ca36aff1653` |

Total SQL: 5.918 líneas. `lock_timeout = 5s`; `statement_timeout = 120s`.
Las 169 migraciones anteriores no se modifican.

## Gate local confirmado

- Fresh bootstrap, upgrade 169->175 y schema equivalence: PASS.
- Schema hash: `c75464ec12235e07a3e2c02a40a26b6f7ee04f88b7c6b7a310d3a8d42150ee0f`.
- Build y typecheck: PASS.
- Tests: 20/20 Node + 551/551 TS/TSX = 571/571.
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
| Migraciones producción 170..175 | PENDING | - |
| Flags nacen OFF | PENDING | - |
| PR #209 fusionado | PENDING | - |
| Deployment Vercel SHA exacto READY | PENDING | - |
| Smoke inactivo | PENDING | - |
| Activación Private Beta por RPC | PENDING | - |
| Canario 4 equipos reversible | PENDING | - |
| Readback y cleanup productivo | PENDING | - |
| Demo World V2.6 LIVE | PENDING | - |
| Service Worker productivo | PENDING | - |

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
- Supabase Advisors devuelve cero hallazgos de rendimiento R6C y cuatro
  warnings de seguridad esperados para los entrypoints `SECURITY DEFINER`.
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

`STAGING_CERTIFIED_AND_RETIRED / PRODUCTION_BASELINE_LEDGER_169 / PRODUCTION_GATES_PENDING`.
