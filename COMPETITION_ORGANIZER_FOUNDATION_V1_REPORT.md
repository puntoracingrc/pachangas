# Competition & Organizer Foundation V1 Report

Estado: `IN PROGRESS - DRAFT PR`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Rama | `codex/competition-organizer-foundation-v1` |
| Base R1 | `0ea46f1cfa797a253678b68a3ffb8d7456856c81` |
| R0 | PR #152 fusionado en `main` |
| Inicio | `2026-08-21 07:39:27 CEST` |
| Produccion | No modificada |
| Merge R1 | No autorizado |

## Contratos

R1 implementa exclusivamente la fundacion definida por:

- `COMPETITION_RULES_RESEARCH_V1.md`;
- `COMPETITION_RULES_MATRIX_V1.md`;
- `COMPETITION_ENGINE_CONTRACT_V1.md`.

No implementa calendario, standings, plantillas, arbitros, disciplina, pagos,
League Engine ni Tournament Engine.

## Estado por bloque

| Bloque | Estado | Evidencia |
| --- | --- | --- |
| Auditoria de autoridades existentes | En curso | Repositorio local en la base R1 |
| Identidad canonica y bindings | Pendiente | `CANONICAL_MATCH_BINDING_V1_REPORT.md` |
| Competition y CompetitionEdition | Pendiente | Migraciones R1 |
| Reglamentos versionados | Pendiente | Migraciones y tests R1 |
| Stages, divisiones, grupos y grafo | Pendiente | Migraciones y tests R1 |
| Organizador, entitlements y staff | Pendiente | `COMPETITION_ENTITLEMENTS_V1_REPORT.md` |
| Receipts, eventos y read models | Pendiente | Migraciones y tests R1 |
| Laboratorio y Control Center | Pendiente | UI R1 |
| Local, Preview y staging | Pendiente | Evidencia de QA R1 |

## Limites de dominio

- PostgreSQL sera la unica autoridad para cada escritura R1.
- El cliente enviara intenciones con `operationId` y `expectedRevision`.
- Realtime solo invalidara el read model afectado y provocara un refetch.
- Los borradores offline no se mostraran como confirmados.
- Rating V2, resultados, participantes, Achievements, Rewards, Conduct, Billing,
  Ranking, Demo World y cosmeticos permanecen fuera del cambio.

## Registro de validacion

Se completara antes de marcar el PR como `READY FOR REVIEW` con los resultados
exactos de tests, typecheck, build, lint focalizado, SQL/RLS, bootstrap,
concurrencia, Synthetic World, rendimiento, Advisors, Preview y staging.

