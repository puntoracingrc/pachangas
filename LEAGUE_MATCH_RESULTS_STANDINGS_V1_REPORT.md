# League Match Results & Standings V1 Report

## Estado

`DRAFT / IMPLEMENTATION IN PROGRESS`

Este informe acompana R4C desde el primer checkpoint. Se actualizara con la
implementacion, validacion, staging y, solo si pasan todos los gates, la release
productiva inactiva.

## Trazabilidad inicial

| Dato | Valor |
| --- | --- |
| Fecha de inicio | `2026-08-24T18:55:04+02:00` |
| `origin/main` | `57fe285daf4eb57f400c313f20841cff2dff4962` |
| Rama | `codex/league-match-results-standings-v1` |
| Worktree | `/Users/macbookpro14/.codex/worktrees/pachangas-league-match-results-standings-v1` |
| Estado inicial | limpio, basado directamente en `origin/main` |
| Node | `v24.16.0` |
| npm | `11.13.0` |
| Supabase CLI | `2.107.0` |
| Ledger productivo conocido | `127`, pendiente de readback antes del primer SQL |

## Autoridades heredadas auditadas

R4C se construye sobre las autoridades existentes y no introduce una identidad
paralela de partido:

| Dominio | Autoridad existente | Uso en R4C |
| --- | --- | --- |
| Partido | `pachanga_canonical_matches` | Identidad deportiva unica |
| Contexto | `pachanga_competition_match_contexts` | Liga, edicion, fase, jornada, equipos y reglas |
| Fixture | `pachanga_competition_schedule_items` | Origen publicado, nunca resultado |
| Participacion | entries, stage memberships, rosters y roster revisions R4A | Elegibilidad y autoridad de equipo |
| Asistencia | autoridad de participantes/asistencia existente | Adaptacion canonica, sin segunda fuente de verdad |
| Alineacion | autoridad de alineacion existente y squad competitivo versionado | Integracion por adapter y revision |
| Goleadores | autoridad existente de goleadores y patron versionado de resultados externos | Integracion por lado, sin aceptar goleadores rivales |
| Reglas | `pachanga_competition_rule_revisions` | Scoring, desempates, squad y confirmacion congelados |
| Orden | `private.pachanga_competition_sequence` | Secuencia del servidor para comandos y evidencias |

## Limites no negociables

- Solo `LEAGUE`; `TOURNAMENT` falla cerrado con `FEATURE_NOT_AVAILABLE`.
- PostgreSQL decide actor, permisos, regla, revision, tiempo y secuencia.
- Toda escritura usa `operationId` y `expectedRevision`.
- No existe `LeagueMatch`, payload local autoritativo ni last-write-wins.
- La clasificacion consume exclusivamente la decision oficial activa.
- Rating V2, Season Score, rewards, Conduct, billing y disciplina no cambian.
- Referee Assignments y Club Competition Organizer permanecen apagados.
- Las ocho flags R4C nacen y terminan en `false`.
- No se ejecuta `canonical.backfill`.

## Estado de release

| Gate | Estado |
| --- | --- |
| Auditoria de base R1-R4B | En curso |
| Esquema y comandos R4C | Pendiente |
| SQL/RLS/idempotencia/concurrencia | Pendiente |
| UI, Realtime y PWA | Pendiente |
| Staging autenticado | Pendiente |
| Produccion | No modificada |

