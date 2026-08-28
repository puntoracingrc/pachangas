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
| Staging efímero creado | PENDING | - |
| Migraciones staging 170..175 | PENDING | - |
| QA autenticada / Realtime | PENDING | - |
| Cleanup staging / branch eliminado | PENDING | - |
| Backup producción recuperable | PENDING | - |
| Baseline/ledger producción | PENDING | - |
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

`LOCAL_RELEASE_CANDIDATE_COMPLETE / REMOTE_GATES_PENDING`.
