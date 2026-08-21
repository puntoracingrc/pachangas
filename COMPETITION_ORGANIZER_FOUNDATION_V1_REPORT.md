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

## Incidencias encontradas durante validacion

| ID | Clasificacion | Escenario original | Estado | Regresion |
| --- | --- | --- | --- | --- |
| R1-VAL-001 | `PRODUCT_BUG` | El read model de plataforma recalculaba la salud de 10.000 fuentes canónicas en cada lectura; 100 lecturas superaban varios minutos. | `fixed` mediante snapshot materializado, invalidacion explicita y refresco tras comandos canónicos. | `regression_verified`: 10.000 bindings, read admin p95 `12.920 ms`; ciclo stale/refresco comprobado. |
| R1-VAL-002 | `SIMULATION_BUG` | El ensayo de escala intentaba medir el indice de bindings como rol `authenticated`, aunque la tabla esta correctamente revocada a clientes. | `fixed` separando la medicion interna bajo rol de base de datos. | `regression_verified`: lookup interno p95 `0.433 ms` y acceso cliente permanece revocado. |
| R1-VAL-003 | `SIMULATION_BUG` | El fixture declaraba revisiones `validated` sin `effective_from` y la RPC de publicacion las rechazaba como no publicables. | `fixed` completando la vigencia requerida en el fixture, sin relajar la validacion de producto. | `regression_verified`: 100 publicaciones, p95 `2.046 ms`, 100 eventos y 100 receipts. |
| R1-VAL-004 | `PRODUCT_BUG` | En portrait, el disparador global de Avisos se superponia a los formularios del laboratorio interno. | `fixed` ocultando ese disparador solo cuando el laboratorio R1 es la superficie activa. | Pendiente de recaptura responsive. |
| R1-VAL-005 | `PRODUCT_BUG` | Control Center consumia claves inexistentes (`activeBindings`, `reviewsOpen`) y mostraria cero pese a existir bindings o revisiones. | `fixed` usando el contrato canónico exacto y una cuadricula explicita de salud. | Pendiente de test focalizado y Preview. |
| R1-VAL-006 | `PRODUCT_BUG` | `canonical.bind` usaba variables `source_kind`, `source_group_id` y `source_id` ambiguas frente a columnas SQL; el linter local detecto la ruta. | `fixed` con nombres de variables inequívocos `target_source_*`. | Pendiente de bootstrap y regresion SQL directa. |
