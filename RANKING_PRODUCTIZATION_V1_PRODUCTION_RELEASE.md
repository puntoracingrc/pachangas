# Ranking Productization V1 Production Release

Estado: PRODUCCIÓN ACTIVA PARA BARCELONA. SEASON SCORE ON, RANKING PROVINCIAL ON, AWARDS OFF.

## Identidad de release

| Campo | Valor |
| --- | --- |
| `main` inicial | `cce6d5e68a34b10c3ae6cb2f8bbdb1d567465aeb` |
| Rama | `codex/ranking-productization-v1` |
| PR | [#145](https://github.com/puntoracingrc/pachangas/pull/145), fusionado |
| Commit inicial | `b6d91cc` |
| Commit RC | `d97c0719317f7dd0755f271238158af0d291e2fe` antes de incorporar esta evidencia |
| Fórmula | `season_score_v3` V1 |
| Formula checksum | `e7b1788fa2d6d7ce2c37cd00f8fa55d78a87539bfa68c76a383bb3500ac388a4` |
| Provincia piloto | Barcelona `08` |
| Premios | OFF por constraint |
| Merge R1-R6 | `989d645ac57d80c9cd180259ba733c2b22865577` |
| Hotfix vacío | [#146](https://github.com/puntoracingrc/pachangas/pull/146), merge `c241e005f35d391c54af64caead7013ff746e167` |
| Deployment funcional | `dpl_ptQ4ke3jCQ8xqVoYKBPteMJWHvXn`, `READY` |
| Fix salud inactiva | [#148](https://github.com/puntoracingrc/pachangas/pull/148), commit `e4fc1f82ccfc06606f280c6d0dd10eb40f5ade69`, merge `9a12bf1665cbcd0f2e3201e6108235959518a460` |
| Deployment R8 | `dpl_ixGi2ASmg31sMRgWhPjWA5MQWtxg`, `READY` |
| URL productiva | `https://pachangasiq.com` |

## Estado de gates

| Gate | Estado | Evidencia |
| --- | --- | --- |
| Fresh install | PASS local | baseline + 98 migraciones |
| Upgrade remoto | PASS staging | R1-R8, ledger sincronizado |
| SQL/RLS | PASS local + staging | `RANKING_PRODUCTIZATION_V1_DB_OK`, grants legacy cerrados |
| Concurrencia | PASS local + staging | replay, `PT409`, lifecycle, `SKIP LOCKED` |
| Escala | PASS local | 10k jugadores, 1k equipos, 3 provincias |
| App tests | PASS | 252/252 |
| Typecheck | PASS | TypeScript sin errores |
| Build | PASS | Next 16.2.6 Turbopack, 31/31 rutas estáticas |
| Lint focalizado | PASS | archivos nuevos y data layer |
| Lint global | DEUDA PREEXISTENTE | 23 errores, 20 warnings; ninguno focalizado nuevo |
| Preview visual | PASS | cinco viewports, sin overflow/error/imagen rota |
| PWA instalada | PASS | aplicación Chrome instalada real, ventana standalone y `/ranking` canónico revisión 2 |
| Staging autenticado | PASS | owner x2, usuario, outsider, anónimo y Realtime |
| Backup producción | PASS | backup físico Supabase disponible + dump lógico restaurado íntegramente en instancia aislada |
| Producción | PASS | R1-R8, rebuild/publicación R2, flags `true / true / false`, health `OK` |

## Migraciones forward-only

Aplicar exactamente en este orden:

1. `20260820075321_ranking_productization_r1_contract_persistence.sql`
2. `20260820075323_ranking_productization_r2_refresh_read_model.sql`
3. `20260820075324_ranking_productization_r3_integrity_eligibility.sql`
4. `20260820075326_ranking_productization_r4_provincial_product.sql`
5. `20260820182038_ranking_productization_r5_http_conflicts.sql`
6. `20260820184126_ranking_productization_r6_legacy_surface_hardening.sql`
7. `20260820204159_ranking_productization_r7_empty_publication.sql`
8. `20260820213930_ranking_productization_r8_idle_health.sql`

Cada migración configura `lock_timeout = 5s` y `statement_timeout = 5min`. No reescribir ni reparar silenciosamente versiones existentes. Antes de aplicar, comparar `supabase migration list --linked` con el repositorio; cualquier divergencia del ledger es un blocker hasta sincronizarla explícitamente.

## Incidencias de activación registradas

`PRODUCT_BUG`: el 20 de agosto de 2026, el primer rebuild real de producción produjo correctamente cero candidatos y checksum determinista `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`. La publicación quedó auditada con cero grants, rewards y notificaciones, pero R4 solo creaba filas territoriales desde entradas existentes. Un piloto legítimo con cero jugadores no obtenía fila de publicación para Barcelona y el health gate permanecía `false`.

Estado: `fixed + regression_verified` en local, staging y producción. R7 hace que cada territorio habilitado reciba una publicación canónica, incluso con cero entradas. Producción devuelve Barcelona disponible, revisión 2, lista vacía y checksum determinista `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`. No se añadieron datos sintéticos ni se forzó el health gate.

`PRODUCT_BUG`: después de la activación, una temporada abierta y correctamente publicada pasaba a `WARNING / RANKING_REFRESH_STALE` tras quince minutos sin nueva evidencia. La regla R4 miraba únicamente la edad de `last_refresh_at`, aunque la cola estuviera vacía. Esto convertía una inactividad legítima en una alerta permanente.

Estado: `fixed + regression_verified` en local, staging y producción. R8 exige trabajo `queued` de la propia temporada activa para declarar stale. La regresión SQL prueba cola vacía y cola pendiente; staging la ejecutó en una transacción revertida. Producción pasó de `WARNING` a `OK` con la misma revisión 2, checksum, publicación y flags, cola 0 y sin recalcular el ranking.

## Runbook de staging

1. Confirmar proyecto/`project_ref`, rama y entorno. No asumir que la pestaña abierta corresponde a Pachangas IQ.
2. Capturar ledger, versión PostgreSQL, tamaño de tablas relevantes, locks y CPU iniciales.
3. Verificar que el frontend de staging contiene las RPC y rutas V1 de ranking.
4. Aplicar las ocho migraciones forward-only con flags aún `false / false / false`.
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

Resultado ejecutado: PASS. La PWA se instaló desde el Preview exacto, abrió en una ventana standalone y mostró la publicación canónica de Barcelona con siete entradas y revisión 2. La E2E autenticada confirma permisos, posición propia, `PT409`, idempotencia, Realtime y refetch canónico.

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

Evidencia capturada antes de migrar:

```text
backup_timestamp: 2026-08-20T20:09:32Z
managed_physical_backup: 2026-08-20T00:19:36Z, Supabase Dashboard, estado Physical/Restore disponible
backup_reference: roles.sql + schema.sql + data.sql, dump oficial Supabase CLI
backup_sha256_roles: 168a95a9c745af5ed4679751f90419ac9dc434240a213b03e32a06d5664c2308
backup_sha256_schema: 212cd31291aeec488e1b7050054762569298954cdfa7b4f9ea800e4547f222b2
backup_sha256_data: b13cc3c2f4693bf768670c4563da1674daa84f67a795f9dab5a2f06fd945e81b
restore_verified: PASS, Supabase local aislado PostgreSQL 17.6 con versiones remotas Auth 2.195.0 / REST 14.5 / Storage 1.70.4
production_ledger_before: 90 versiones remotas coinciden con las 90 primeras locales; solo R1-R6 pendientes
production_schema_checksum_before_columns: 4af306f0335dacf2c7b3ab9239ba6951
production_schema_checksum_before_constraints: 2984d75cb2b5a648d3cb9ac97509e20d
production_schema_checksum_before_indexes: 8fe4766b0a37424ff0c95d32ef356ea5
production_schema_checksum_before_functions: 17b08ad4a7db874544cc86f12eece28c
production_schema_checksum_before_policies: 8c9f7b40e17abc3755275d193e1e9ff5
production_flags_before: Attendance ON, Conduct ON, triage shadow, social restrictions OFF, Player Cosmetics ON, Team Cosmetics ON, Team Rewards ON; tablas/flags Ranking aún ausentes
```

La primera restauración local se revirtió completa porque el contenedor local de Auth no coincidía con producción. La repetición utilizó las versiones exactas declaradas por el proyecto remoto y restauró, en una sola transacción, roles, esquema y datos. Los recuentos exactos de todas las tablas `public`, `auth` y `storage`, los cinco checksums de esquema y los checksums de Rating, assessments, Conduct, rewards y Team Cosmetics coincidieron con producción.

## Despliegue coordinado de producción

1. Poner la release en ventana controlada; evitar cambios sociales simultáneos.
2. Aplicar schema/RPC de Ranking con flags OFF.
3. Readback: siete versiones presentes, fórmula/checksum exactos, awards false.
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

Estado final confirmado:

```text
season_score_product_enabled = true
provincial_rankings_product_enabled = true
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
staging_url: https://pachangas-nl50tlf5g-persianas-almar-web-s-projects.vercel.app
staging_qa: PASS, incluida PWA instalada real
staging_r7: PASS, ledger 20260820204159 y regresión transaccional sin residuos
staging_r8: PASS, ledger 20260820213930, salud idle/queued y rollback sin residuos
hotfix_preview: https://pachangas-8bmk0kh4r-persianas-almar-web-s-projects.vercel.app
production_backup: PASS, backup físico disponible y restore lógico aislado verificado
pilot_season_id: 20bad54c-7b29-4a88-9a7e-a1f80f8ef8eb
pilot_period: 2026-08-20T20:40:00Z -> 2026-12-31T23:59:59Z
initial_snapshot_checksum: no hay snapshots individuales; conjunto vacío SHA-256 4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945
initial_rebuild_checksum: 4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945
published_rebuild_id: d227df1b-9db0-4112-995c-cf9cb4c4e97f
published_rebuild_checksum: 7da7104898f9628072e23b1e3971980e5b991e3c414288100955bd0e6a39ce85
eligible_real_players: 0
pending_integrity_real_players: 0
ranking_grants_created: 0
ranking_sanctions_created: 0
production_deployment: dpl_ixGi2ASmg31sMRgWhPjWA5MQWtxg
production_main_sha: 9a12bf1665cbcd0f2e3201e6108235959518a460
pachangasiq.com_smoke: PASS, ranking desktop/portrait/landscape y rutas /, /mercado, /admin/rankings
runtime_errors: 0
broken_images: 0
horizontal_overflow: 0
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

## Huellas protegidas de producción

La misma consulta determinista se ejecutó inmediatamente antes de R7 y después de rebuild, publicación y activación. Los cinco resultados son idénticos:

| Sistema | Tablas | Filas | Checksum |
| --- | ---: | ---: | --- |
| Rating / assessments | 14 | 3 | `b683a4e04daa90d6abb6eaca24692f5c` |
| Conduct / Attendance | 16 | 9 | `2f73b1228d0618db1ab2e2ea505d1f3b` |
| Notifications | 6 | 34 | `0b6feb65ed17140469430afc0a68e3e7` |
| Rewards / cosmetics | 42 | 735 | `572e138afbf8b68b71a4cb00fd19038f` |
| Billing | 1 | 0 | `43e4837531a6231f35f06665c16ffbd9` |

El ledger remoto incluye R1-R8. Las funciones privadas de publicación y salud continúan sin `EXECUTE` para `authenticated`. El CLI emitió un warning posterior al apply al intentar actualizar su caché `pg-delta` sin certificado temporal; ambas migraciones afectadas devolvieron éxito, aparecen en el ledger y el readback funcional confirma su código fuente.

## Smoke productivo final

- `/ranking`: Barcelona, temporada piloto, fórmula `55 / 30 / 15`, revisión 2 y 0 jugadores reales; no muestra estado inactivo.
- Viewports `1440x900`, `390x844` y `844x390`: sin overflow horizontal, imágenes rotas ni logs de consola.
- `/` y `/mercado`: desktop, portrait y landscape sin overflow ni imágenes rotas.
- `/admin/rankings` sin sesión: guard correcto, sin fuga de datos administrativos.
- PWA: manifest `fullscreen` y Service Worker versionado por build; el smoke funcional R8 sirvió `2.0.0+sw.9a12bf1665cb`. La instalación standalone se validó previamente en staging.
- Vercel: deployment exacto `dpl_ixGi2ASmg31sMRgWhPjWA5MQWtxg` `READY`, SHA `9a12bf1665cbcd0f2e3201e6108235959518a460`, aliases `pachangasiq.com` y `www.pachangasiq.com`, cero runtime errors en la ventana de release.
