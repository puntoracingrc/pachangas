# Ranking Productization V1 Report

Estado: STAGING RELEASE CANDIDATE. Producción pendiente.

Actualizado: 2026-08-20 21:05 CEST.

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Base real | `origin/main` `cce6d5e68a34b10c3ae6cb2f8bbdb1d567465aeb` |
| Rama | `codex/ranking-productization-v1` |
| Commit inicial | `b6d91cc` |
| PR draft | [#145](https://github.com/puntoracingrc/pachangas/pull/145) |
| Worktree | `/private/tmp/pachangas-ranking-productization-v1` |
| Fórmula | `season_score_v3` V1 |
| Checksum | `e7b1788fa2d6d7ce2c37cd00f8fa55d78a87539bfa68c76a383bb3500ac388a4` |
| Piloto | Barcelona, `08` |
| Rutas del cambio | 26 antes del commit final |
| Supabase staging | `iozcjirlfytryzrcmrnq` |
| Preview Vercel | `pachangas-5215gr27e-persianas-almar-web-s-projects.vercel.app` |

Se han aplicado y verificado las seis migraciones exclusivamente en Supabase staging. El Preview de la rama usa ese proyecto. Producción no se ha modificado.

## Resultado por fase

### R1: contrato y persistencia

- Registro inmutable de fórmula con checksum determinista.
- Settings con flags separados y `provincial_awards_enabled` bloqueado en `false`.
- Territorios y mappings de campo versionados.
- Temporadas canónicas con lifecycle y revisión monotónica.
- Snapshots de grafo y Season Score append-only.
- Recibos idempotentes, eventos auditables y secuencia de servidor.
- `lock_timeout = 5s` y `statement_timeout = 5min` en todas las migraciones.

### R2: refresh y read model candidato

- Selector SQL de evidencia canónica de Retos externos.
- Season Score V3 exacto `55 / 30 / 15`, `recent_30`.
- Match confidence, opponent independence, rivales lógicos y network diversity.
- Cola durable con `FOR UPDATE SKIP LOCKED`.
- Refresh incremental por jugador/temporada.
- Rebuild completo con candidato, diff y checksum semántico.
- Igualdad incremental/full tras normalización.
- Selección estable del último snapshot; no depende solo de `created_at`.

### R3: integridad y elegibilidad

- Ranking: 15 Retos, 6 rivales, reliability 0.45, actividad 12 semanas.
- Trophy readiness: 25/10, confidence 0.72, network 0.68, reliability 0.55 y actividad 12 semanas.
- Estrategia B+C: exclusión de evidencia y hold de certificación.
- Queue de revisión privada con referencia opaca y resolución versionada.
- Cero score penalties, sanciones, Conduct cases o restricciones sociales.

### R4: producto provincial

- Read model persistido por temporada, provincia y revisión.
- Publicación compare-and-publish con revisión y checksum esperados.
- RPC Top 10 pública minimizada y RPC autenticada de posición propia.
- IDs opacos; tablas internas, evidence, graph, risk y lineage cerrados.
- `/ranking` con caché derivada versionada y Realtime de invalidación.
- `/admin/rankings` con lifecycle, rebuild, publicación, mappings, cola e integridad.
- Salud operativa `OK / WARNING / CRITICAL / UNKNOWN` con reason codes para fórmula, temporada, refresh, backlog, rebuild, publicación e integridad.
- Cron server-only cada cinco minutos; requiere `CRON_SECRET`.

### R5: conflictos HTTP seguros

- Sustituye `40001`, reservado para rollbacks serializables reintentables, por `PT409` en los conflictos de revisión de Ranking.
- Evita que PostgREST reintente una intención obsoleta que solo puede resolverse recargando el snapshot canónico.
- Conserva la misma transacción, revisión esperada, receipt e idempotencia.

### R6: cierre de superficie legacy

- Revoca `EXECUTE` de las implementaciones pre-Ranking de flags a `public`, `anon`, `authenticated` y `service_role`.
- Mantiene como única superficie cliente la RPC versionada que valida actor, revisión, `operationId` y motivo.
- Incluye verificación SQL y llamada autenticada negativa contra staging.

## Objetos principales

### Migraciones

1. `20260820075321_ranking_productization_r1_contract_persistence.sql`
2. `20260820075323_ranking_productization_r2_refresh_read_model.sql`
3. `20260820075324_ranking_productization_r3_integrity_eligibility.sql`
4. `20260820075326_ranking_productization_r4_provincial_product.sql`
5. `20260820182038_ranking_productization_r5_http_conflicts.sql`
6. `20260820184126_ranking_productization_r6_legacy_surface_hardening.sql`

Son forward-only y posteriores a las 90 migraciones existentes. No se ha reescrito ninguna migración ya desplegada.

### Lecturas públicas

- `get_pachanga_provincial_ranking_v1`
- `get_my_pachanga_provincial_rank_v1`
- Realtime sobre `pachanga_provincial_ranking_publications` exclusivamente.

### Operaciones administrativas

- crear temporada;
- transición `draft -> open -> frozen -> closed -> archived`;
- mapear un `placeId` a provincia;
- procesar cola;
- rebuild completo;
- publicar candidato validado;
- resolver revisión de integridad;
- activar flags con revisión esperada.

Todas resuelven actor en servidor, exigen `operationId`, reason y revisión esperada cuando corresponde, y registran recibo/evento.

## Privacidad y RLS

| Actor | Top publicado | Posición propia | Snapshot/lineage | Riesgo/grafo | Operaciones admin |
| --- | ---: | ---: | ---: | ---: | ---: |
| Anónimo | Sí, si flags y publicación sanos | No | No | No | No |
| Usuario autenticado | Sí | Sí | No | No | No |
| Admin de equipo | Igual que usuario | Sí | No | No | No |
| Platform admin/owner | Sí | Sí | Mediante Control Center | Resumen privado | Según capability |
| Service role | Sí | N/A | Sí | Sí | Worker interno |

El read model directo no tiene `SELECT` para `anon` ni `authenticated`. Las RPC públicas no devuelven profile UUID, email, ubicación personal, raw risk, network graph ni evidence lineage.

## Pruebas locales

| Gate | Resultado |
| --- | --- |
| Fresh bootstrap | PASS, baseline + 96 migraciones |
| Upgrade local | PASS, 94 -> 96 |
| SQL/RLS/ACL | PASS, `RANKING_PRODUCTIZATION_V1_DB_OK` |
| Test estático focalizado | PASS, 8/8 |
| Concurrencia | PASS, un lifecycle winner, replay convergente, stale revision rechazada, cola `SKIP LOCKED` |
| Volumen | PASS, 10.000 jugadores, 1.000 equipos, 3 provincias |
| Typecheck | PASS |
| Build oficial Turbopack | PASS, 31 páginas; última ejecución compile 3,7 s y TypeScript 8,2 s |
| Batería global | PASS, 250/250 |
| Lint focalizado nuevo | PASS |
| Lint global heredado | 43 incidencias: 23 errores y 20 warnings; ninguna en los archivos nuevos focalizados |
| `git diff --check` | PASS antes de actualizar informes; se repite al cierre |
| Visual Preview | PASS: 1920x1080, 1440x900, 390x844, 360x800 y 844x390; sin overflow, imágenes rotas ni errores de consola |
| PWA | Contrato, manifest, Service Worker y regresiones PASS; validación instalada real aún pendiente |

El primer build dentro del sandbox quedó esperando resolución de Google Fonts. Repetido con acceso de red, el build oficial pasó. Un diagnóstico alternativo con Webpack señaló dos selectores CSS globales heredados; Vercel/Next usa el build Turbopack que pasa.

## Rendimiento local representativo

Dataset transaccional y reversible:

```text
10.000 perfiles
1.000 equipos
3 provincias
10.000 snapshots
10.000 candidatos
10.000 filas publicadas
```

Última ejecución sobre bootstrap limpio de 96 migraciones:

| Medida | Resultado |
| --- | ---: |
| Finalizar candidato + publicar | 1.233,641 ms |
| 100 lecturas Top 10 | 55,08 ms total |
| Consulta Top 10 indexada | 0,021 ms |
| Filas devueltas | 10 |
| Índices de snapshots/candidatos/read model | 8.282.112 bytes |

El plan usa `pachanga_provincial_ranking_position_idx`. La CTE de ordenación está materializada una sola vez; antes de esa corrección el mismo flujo tardaba aproximadamente 149 segundos.

## Supabase lint y advisors

- Ranking Productization: sin errores SQL propios tras el fresh bootstrap final.
- Advisors de staging: R6 cerró los grants legacy detectados. Los avisos `SECURITY DEFINER` restantes corresponden a RPC expuestas intencionadamente con autorización interna explícita; la matriz de actor se ha probado. Los índices FK sugeridos para Ranking son informativos y las rutas de producto usan los índices verificados por escala.
- El warning global de índice duplicado de Rating V2 es preexistente y queda fuera de alcance.
- Lint global heredado: tres errores anteriores en Rating/rewards (`normalized_name`, `target_group_id`, `cosmetic_key`) y warnings anteriores. No se modifican por estar fuera de alcance.
- CLI local 2.107.0 sobre PostgreSQL 17; la CLI informa 2.115.0 disponible.

## Invariantes demostrados

- Rating V2 checksum/facetas/reliability: sin cambios causados por Ranking.
- Conduct reports/cases/restrictions/warnings: 0 creados por Ranking.
- Achievements/boxes/points/cosmetics/Team Rewards: 0 creados por Ranking.
- Billing: 0 mutaciones.
- Awards de ranking: 0 y flag no activable en V1.
- Incremental y full rebuild: checksum semántico idéntico para el mismo dataset.
- Retry con mismo `operationId`: mismo resultado.
- Revisión obsoleta: `PT409` explícito, nunca retry ciego ni last-write-wins.

## Staging remoto

- Ledger remoto sincronizado con R1-R6.
- Fórmula leída con checksum exacto `e7b1788fa2d6d7ce2c37cd00f8fa55d78a87539bfa68c76a383bb3500ac388a4`.
- Temporada sintética activa final: `f73f8a4e-000d-4781-bc7c-742eabe317d0`, publicación canónica 2.
- E2E autenticada con owner en dos clientes, usuario normal, outsider y anónimo: PASS.
- Concurrencia real: un único ganador y el cliente obsoleto recibe `PT409`.
- Realtime: la publicación invalida y el cliente recupera después la revisión canónica.
- Cola durable: enqueue duplicado converge al mismo ID, un solo procesamiento, `attempts = 1`, cero fallos.
- Publicación visible: siete jugadores en Barcelona, revisión 2; premios y rewards creados: 0.
- La lectura legacy de flags y su escritura directa quedan denegadas incluso al owner autenticado.
- Los tres intentos sintéticos incompletos anteriores se eliminaron únicamente en staging tras verificar que no contenían snapshots, eventos, receipts, entradas ni publicaciones. Las ejecuciones completas posteriores se archivan mediante el lifecycle autoritativo.
- `TESTABILITY_GAP` detectado y corregido: la primera versión de la E2E comparaba dos propiedades de revisión inexistentes. La regresión exige ahora `publication.revision === publishedRevision`, ambas enteras y monotónicas; `fixed + regression_verified` contra staging con revisión 2.

## Pendiente remoto

1. Confirmar en una PWA instalada real que `/ranking` conserva navegación, actualización y estado canónico.
2. Crear y restaurar un backup físico recuperable antes de producción.
3. Comparar el ledger de producción con las 96 versiones locales y detener ante cualquier divergencia.
4. Actualizar el PR con el commit final y esperar el Preview de ese SHA.
5. Release coordinada schema/backend/frontend, smoke con flags OFF, temporada piloto y activación gradual.

No se declarará producción completada hasta registrar esos resultados en `RANKING_PRODUCTIZATION_V1_PRODUCTION_RELEASE.md`.
