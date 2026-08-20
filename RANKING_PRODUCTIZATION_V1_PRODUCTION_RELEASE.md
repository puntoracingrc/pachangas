# Ranking Productization V1 Production Release

Estado: STAGING RC. Producción no modificada.

## Identidad de release

| Campo | Valor |
| --- | --- |
| `main` inicial | `cce6d5e68a34b10c3ae6cb2f8bbdb1d567465aeb` |
| Rama | `codex/ranking-productization-v1` |
| PR | [#145 draft](https://github.com/puntoracingrc/pachangas/pull/145) |
| Commit inicial | `b6d91cc` |
| Commit RC | Pendiente del cierre de esta ronda |
| Fórmula | `season_score_v3` V1 |
| Formula checksum | `e7b1788fa2d6d7ce2c37cd00f8fa55d78a87539bfa68c76a383bb3500ac388a4` |
| Provincia piloto | Barcelona `08` |
| Premios | OFF por constraint |

## Estado de gates

| Gate | Estado | Evidencia |
| --- | --- | --- |
| Fresh install | PASS local | baseline + 96 migraciones |
| Upgrade remoto | PASS staging | R1-R6, ledger sincronizado |
| SQL/RLS | PASS local + staging | `RANKING_PRODUCTIZATION_V1_DB_OK`, grants legacy cerrados |
| Concurrencia | PASS local + staging | replay, `PT409`, lifecycle, `SKIP LOCKED` |
| Escala | PASS local | 10k jugadores, 1k equipos, 3 provincias |
| App tests | PASS | 250/250 |
| Typecheck | PASS | TypeScript sin errores |
| Build | PASS | Next 16.2.6 Turbopack, 31/31 rutas estáticas |
| Lint focalizado | PASS | archivos nuevos y data layer |
| Lint global | DEUDA PREEXISTENTE | 23 errores, 20 warnings; ninguno focalizado nuevo |
| Preview visual | PASS | cinco viewports, sin overflow/error/imagen rota |
| PWA instalada | PENDING | contrato y Service Worker PASS; falta prueba instalada real |
| Staging autenticado | PASS | owner x2, usuario, outsider, anónimo y Realtime |
| Backup producción | PENDING | obligatorio antes de migrar |
| Producción | NOT TOUCHED | no se ha aplicado nada remoto |

## Migraciones forward-only

Aplicar exactamente en este orden:

1. `20260820075321_ranking_productization_r1_contract_persistence.sql`
2. `20260820075323_ranking_productization_r2_refresh_read_model.sql`
3. `20260820075324_ranking_productization_r3_integrity_eligibility.sql`
4. `20260820075326_ranking_productization_r4_provincial_product.sql`
5. `20260820182038_ranking_productization_r5_http_conflicts.sql`
6. `20260820184126_ranking_productization_r6_legacy_surface_hardening.sql`

Cada migración configura `lock_timeout = 5s` y `statement_timeout = 5min`. No reescribir ni reparar silenciosamente versiones existentes. Antes de aplicar, comparar `supabase migration list --linked` con el repositorio; cualquier divergencia del ledger es un blocker hasta sincronizarla explícitamente.

## Runbook de staging

1. Confirmar proyecto/`project_ref`, rama y entorno. No asumir que la pestaña abierta corresponde a Pachangas IQ.
2. Capturar ledger, versión PostgreSQL, tamaño de tablas relevantes, locks y CPU iniciales.
3. Verificar que el frontend de staging contiene las RPC y rutas V1 de ranking.
4. Aplicar las seis migraciones forward-only con flags aún `false / false / false`.
5. Verificar readback del checksum de fórmula y settings.
6. Desplegar frontend/backend RC; configurar `CRON_SECRET` únicamente en servidor.
7. Crear temporada de QA explícita y mappings de campos de prueba.
8. Abrir temporada y ejecutar el dataset canónico de staging: elegible, no elegible, near-cut, empate, corrección, inactividad, reliability baja, confidence baja, rival lógico duplicado, red cerrada e integrity pending.
9. Ejecutar incremental y full rebuild; exigir checksum idéntico.
10. Validar que un rebuild distinto queda en candidato y no se publica solo.
11. Publicar con checksum y revisión esperados.
12. Activar primero Season Score en staging; smoke.
13. Activar ranking provincial para `08`; smoke y Realtime.
14. Mantener awards OFF.
15. Recorrer lifecycle completo en una temporada descartable: `draft -> open -> frozen -> closed -> archived`.
16. Probar corrección dentro de temporada y rechazo tras `closed`.
17. Ejecutar QA autenticada con platform owner, usuario normal, elegible, no elegible y pending.
18. Validar `/ranking`, `/admin/rankings`, posición propia, mensajes seguros y ausencia de UUID/risk/graph.
19. Ejecutar viewports `1440x900`, `1920x1080`, `390x844`, `360x800`, `844x390` y PWA standalone; revisar light/dark y reduced motion.
20. Confirmar 0 errores runtime, imágenes rotas, overflow y recálculo cliente.

Resultado ejecutado: PASS salvo la apertura en una PWA realmente instalada, que sigue siendo gate previo a producción. El Preview público muestra la publicación canónica de Barcelona con siete entradas y revisión 2. La E2E autenticada confirma permisos, posición propia, `PT409`, idempotencia, Realtime y refetch canónico.

## Criterios de parada en staging

Detener antes de producción si ocurre cualquiera:

- ledger remoto diferente al repositorio;
- fórmula/checksum distintos;
- migración supera `statement_timeout` o deja locks esperando;
- salud `CRITICAL` o `UNKNOWN` con flags activados;
- incremental y rebuild no convergen;
- snapshot duplicado o revisión no monotónica;
- fuga de UUID, risk, graph, evidence o datos personales;
- Rating V2, Conduct, rewards, cosmetics o billing cambian;
- grants, sanciones o notificaciones masivas inesperadas;
- Realtime mezcla revisiones o la caché muestra una revisión distinta;
- PWA interpreta un error como escritura confirmada.

## Backup de producción

Antes de cualquier migración productiva:

1. Crear backup físico recuperable del proyecto correcto.
2. Registrar timestamp UTC, ID/ubicación del backup y responsable.
3. Exportar y guardar ledger de migraciones.
4. Registrar schema checksum y versión PostgreSQL.
5. Leer y registrar flags actuales.
6. Verificar restauración en un entorno aislado; un archivo existente sin restore test no cuenta como backup validado.

Campos pendientes:

```text
backup_timestamp: PENDING
backup_reference: PENDING
restore_verified: PENDING
production_ledger_before: PENDING
production_schema_checksum_before: PENDING
production_flags_before: PENDING
```

## Despliegue coordinado de producción

1. Poner la release en ventana controlada; evitar cambios sociales simultáneos.
2. Aplicar schema/RPC de Ranking con flags OFF.
3. Readback: seis versiones presentes, fórmula/checksum exactos, awards false.
4. Desplegar backend/frontend Vercel compatible.
5. Smoke preactivación de Rating, Retos, Attendance, Conduct, Rewards, Billing, PWA y Control Center.
6. Crear temporada piloto explícita, no retroactiva globalmente.
7. Mapear únicamente campos canónicos del piloto Barcelona.
8. Abrir temporada y ejecutar initial rebuild sobre su ventana.
9. Comparar candidato, contadores y checksum; exigir 0 grants y 0 sanciones.
10. Publicar candidato validado.
11. Activar `season_score_product_enabled` y hacer smoke.
12. Activar `provincial_rankings_product_enabled` para allowlist `08` y hacer smoke.
13. Confirmar `provincial_awards_enabled = false`.
14. Verificar Realtime, Top 10, posición propia, Control Center y health.
15. Monitorizar cola, refresh, rebuilds, integridad, logs Vercel/Supabase y efectos colaterales.

La release de frontend y migraciones debe coordinarse. Un frontend anterior no conoce el ranking; el nuevo frontend falla de forma segura mientras no existan sus RPC, pero no debe promoverse como release completa hasta que el schema esté presente.

## Activación y fail-closed

Estado inicial de migración:

```text
season_score_product_enabled = false
provincial_rankings_product_enabled = false
provincial_awards_enabled = false
pilot_province_codes = ['08']
```

El ranking público permanece no disponible si falta fórmula, temporada, territorio, publicación o salud canónica. El Control Center devuelve `OK`, `WARNING`, `CRITICAL` o `UNKNOWN` y códigos operativos.

## Rollback

Orden de reversión:

1. Desactivar `provincial_rankings_product_enabled` mediante RPC versionada.
2. Desactivar `season_score_product_enabled` si el problema afecta al motor/refresh.
3. Pausar cron/worker si la cola es la fuente de la incidencia.
4. Mantener snapshots, candidatos, eventos y recibos para auditoría.
5. Preferir roll-forward. No ejecutar down migrations ni borrar evidencia.
6. Solo restaurar backup ante corrupción real, siguiendo procedimiento revisado.

Un rollback nunca reactiva premios, reabre escrituras V1 ni convierte caché/localStorage en autoridad.

## Monitorización posterior

Confirmar durante la ventana inmediata:

```text
unexpected ranking grants       0
unexpected ranking sanctions    0
unexpected mass notifications   0
Rating changes from ranking     0
Conduct changes from ranking    0
Billing changes from ranking    0
refresh errors                  0
rebuild mismatch                0
```

Registrar tras release:

```text
staging_url: https://pachangas-5215gr27e-persianas-almar-web-s-projects.vercel.app
staging_qa: PASS, pendiente únicamente PWA instalada real
production_backup: PENDING
pilot_season_id: PENDING
pilot_period: PENDING
initial_snapshot_checksum: PENDING
initial_rebuild_checksum: PENDING
eligible_real_players: PENDING
pending_integrity_real_players: PENDING
production_deployment: PENDING
production_main_sha: PENDING
pachangasiq.com_smoke: PENDING
```

## Invariantes de release

- Rating V2: intacto.
- Conduct/Attendance: intactos.
- Achievements/Rewards/Player Cosmetics/Team Cosmetics/Team Rewards: intactos.
- Billing: intacto.
- Premium Ball: OFF.
- Comunidad autónoma: LAB.
- España: LAB.
- Grants creados por ranking: 0.
- Sanciones creadas por ranking: 0.
