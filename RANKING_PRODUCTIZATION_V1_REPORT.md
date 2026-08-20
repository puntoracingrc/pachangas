# Ranking Productization V1 Report

Estado: LOCAL RELEASE CANDIDATE. Staging y producción pendientes.

Actualizado: 2026-08-20 11:44 CEST.

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
| Rutas del cambio | 23 antes del commit final |

No se ha tocado Supabase remoto, Vercel staging ni producción en la fase local.

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

## Objetos principales

### Migraciones

1. `20260820075321_ranking_productization_r1_contract_persistence.sql`
2. `20260820075323_ranking_productization_r2_refresh_read_model.sql`
3. `20260820075324_ranking_productization_r3_integrity_eligibility.sql`
4. `20260820075326_ranking_productization_r4_provincial_product.sql`

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
| Fresh bootstrap | PASS, baseline + 94 migraciones |
| SQL/RLS/ACL | PASS, `RANKING_PRODUCTIZATION_V1_DB_OK` |
| Test estático focalizado | PASS, 7/7 |
| Concurrencia | PASS, un lifecycle winner, replay convergente, stale revision rechazada, cola `SKIP LOCKED` |
| Volumen | PASS, 10.000 jugadores, 1.000 equipos, 3 provincias |
| Typecheck | PASS |
| Build oficial Turbopack | PASS, 31 páginas; última ejecución compile 4,3 s y TypeScript 8,0 s |
| Batería global | PASS, 249/249 |
| Lint focalizado nuevo | PASS |
| Lint de `app/page.tsx` heredado | 13 errores y 19 warnings preexistentes; los dos enlaces añadidos no coinciden con ninguna incidencia |
| `git diff --check` | Pendiente del commit final |
| Visual/PWA | Pendiente de Preview/staging |

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

Última ejecución:

| Medida | Resultado |
| --- | ---: |
| Finalizar candidato + publicar | 1.185,120 ms |
| 100 lecturas Top 10 | 54,17 ms total |
| Consulta Top 10 indexada | 0,023 ms |
| Filas devueltas | 10 |
| Índices de snapshots/candidatos/read model | 8.265.728 bytes |

El plan usa `pachanga_provincial_ranking_position_idx`. La CTE de ordenación está materializada una sola vez; antes de esa corrección el mismo flujo tardaba aproximadamente 149 segundos.

## Supabase lint y advisors

- Ranking Productization: sin errores ni warnings propios tras el fresh bootstrap final.
- Advisors: ningún índice ausente de Ranking; permanecen dos índices duplicados preexistentes ajenos.
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
- Revisión obsoleta: error serializable, nunca last-write-wins.

## Pendiente remoto

1. Actualizar el PR con el commit final local.
2. Confirmar que `origin/main` no ha introducido conflicto.
3. Desplegar Preview/staging con flags OFF.
4. Aplicar las cuatro migraciones solo en staging y verificar ledger.
5. Ejecutar dataset canónico, lifecycle, corrección, incremental/rebuild, Realtime, PWA y QA visual.
6. Crear backup físico recuperable antes de producción.
7. Release coordinada schema/backend/frontend, smoke con flags OFF, temporada piloto y activación gradual.

No se declarará producción completada hasta registrar esos resultados en `RANKING_PRODUCTIZATION_V1_PRODUCTION_RELEASE.md`.
