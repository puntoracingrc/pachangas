# Reconciliación del backlog histórico: issues #179 y #180

## 1. Resumen ejecutivo

Esta revisión documental concluye que los dos issues abiertos quedaron superados por releases posteriores ya fusionadas, migradas, activadas y verificadas en producción:

- [#179](https://github.com/puntoracingrc/pachangas/issues/179) se clasifica como `COMPLETED_BY_SUBSEQUENT_RELEASE`. Referee Assignments & Match Officiating Private Beta V1 entregó el ciclo autoritativo que faltaba y continúa limitado a su beta privada.
- [#180](https://github.com/puntoracingrc/pachangas/issues/180) se clasifica como `COMPLETED_BY_SUBSEQUENT_RELEASE`. Competition Discipline V1 entregó eventos/tarjetas, contadores, sanciones, cumplimiento, elegibilidad y apelaciones bajo autoridad privada. La disciplina pública continúa deliberadamente desactivada.

Esta tarea no implementa producto. Su único cambio persistente es este informe Markdown. No modifica runtime, SQL, migraciones, flags, RLS, datos, Stripe ni Supabase.

## 2. SHA base

| Campo | Valor |
| --- | --- |
| Repositorio | `puntoracingrc/pachangas` |
| Base esperada | `ddb22efda0304c01a2371ce62e140cb1b76c1982` |
| Base real auditada | `ddb22efda0304c01a2371ce62e140cb1b76c1982` |
| Rama | `codex/reconcile-superseded-issues-179-180` |
| Entorno | macOS, Node `v24.16.0`, worktree aislado |
| Auditoría | 2026-09-05 04:23:58 CEST (+0200) |

El checkout compartido no se utilizó para editar. Se preservaron sus cambios locales, sus directorios sin seguimiento y todos los worktrees ajenos.

## 3. Estado actual de main

`origin/main` coincidía con el checkpoint esperado y contenía el merge de [#277](https://github.com/puntoracingrc/pachangas/pull/277). Los dos archivos de ese fix no se modificaron. El historial local y remoto de migraciones coincidía en `237/237`; la última versión era `20260904184204_r4b_interactive_schedule_capacity_v1`.

El estado inicial del worktree fue limpio. El único cambio final previsto es este documento.

## 4. Open issues antes

La consulta a GitHub confirmó exactamente estos issues abiertos al iniciar la reconciliación:

| Issue | Alcance |
| --- | --- |
| [#167](https://github.com/puntoracingrc/pachangas/issues/167) | QA física Android |
| [#168](https://github.com/puntoracingrc/pachangas/issues/168) | QA física iPhone |
| [#169](https://github.com/puntoracingrc/pachangas/issues/169) | QA física PWA instalada |
| [#178](https://github.com/puntoracingrc/pachangas/issues/178) | Profile Reports V1 |
| [#179](https://github.com/puntoracingrc/pachangas/issues/179) | Referee Assignments pendiente |
| [#180](https://github.com/puntoracingrc/pachangas/issues/180) | Competition Discipline pendiente |
| [#181](https://github.com/puntoracingrc/pachangas/issues/181) | Tarifas y pagos arbitrales |

No se modificaron `#167`, `#168`, `#169`, `#178` ni `#181`.

## 5. Cronología

| Fecha/hito | Estado histórico verificable |
| --- | --- |
| Clubs & Referees Beta V1 | Fundación arbitral, perfiles, marketplace y relaciones Club-árbitro activos; Assignments todavía OFF; disciplina no disponible. |
| 2026-08-24 | Se abren `#179` y `#180` describiendo los alcances entonces pendientes. |
| R5 / PR [#191](https://github.com/puntoracingrc/pachangas/pull/191) | Competition Discipline V1 implementa la autoridad privada. |
| PR [#192](https://github.com/puntoracingrc/pachangas/pull/192) | Demo V2.1 y cierre de accounting de cumplimiento/apelación. |
| PR [#193](https://github.com/puntoracingrc/pachangas/pull/193) | Integración disciplinaria pertinente en calendario público, sin activar datos públicos privados. |
| PR [#194](https://github.com/puntoracingrc/pachangas/pull/194) | Hardening de ACL y políticas privadas R5. |
| PR [#195](https://github.com/puntoracingrc/pachangas/pull/195) | Cierre documental de Competition Discipline V1. |
| Wave 4 / PR [#197](https://github.com/puntoracingrc/pachangas/pull/197) | Referee Assignments & Match Officiating Private Beta V1 completa la productización. |
| PR [#198](https://github.com/puntoracingrc/pachangas/pull/198) | Cierre documental y evidencia productiva de Referee Assignments. |
| 2026-09-05 | Readback actual confirma ambas autoridades privadas y sus migraciones; los issues históricos seguían abiertos por falta de conciliación documental. |

## 6. Clubs & Referees Beta original

El informe histórico [`CLUBS_REFEREES_BETA_V1_PRODUCTION_RELEASE.md`](CLUBS_REFEREES_BETA_V1_PRODUCTION_RELEASE.md) es correcto para su fecha: activó Foundation, self-service, perfiles públicos, marketplace y relaciones Club-árbitro, pero mantuvo Referee Assignments OFF y presentó `disciplineStatsStatus = NOT_AVAILABLE`.

Los informes [`REFEREE_PLATFORM_V1_REPORT.md`](REFEREE_PLATFORM_V1_REPORT.md), [`REFEREE_ASSIGNMENTS_V1_REPORT.md`](REFEREE_ASSIGNMENTS_V1_REPORT.md), [`REFEREE_PROFILES_AND_MARKETPLACE_V1_REPORT.md`](REFEREE_PROFILES_AND_MARKETPLACE_V1_REPORT.md) y [`CLUB_REFEREE_RELATIONSHIPS_V1_REPORT.md`](CLUB_REFEREE_RELATIONSHIPS_V1_REPORT.md) documentan esa fundación, no el estado productivo final. No se reescriben: forman parte de la cronología legítima.

## 7. Issue #179 original

`#179` se creó el 2026-08-24T16:11:57Z. Reconocía una base canónica existente, pero exigía mantener `referee_assignments_enabled` desactivado durante aquella estabilización. Dejaba para una productización posterior propuestas, aceptación, sustituciones, permisos, Realtime y QA multidispositivo.

El issue no incluía pagos arbitrales, disciplina pública ni exposición general de Assignments. Su timeline solo contenía una referencia cruzada posterior; no contenía comentarios ni cambios de estado que reconciliaran la release posterior.

## 8. Releases posteriores de Referee Assignments

[`REFEREE_ASSIGNMENTS_PRIVATE_BETA_V1_REPORT.md`](REFEREE_ASSIGNMENTS_PRIVATE_BETA_V1_REPORT.md) y [`REFEREE_ASSIGNMENTS_PRIVATE_BETA_V1_PRODUCTION_RELEASE.md`](REFEREE_ASSIGNMENTS_PRIVATE_BETA_V1_PRODUCTION_RELEASE.md) prueban la entrega completa del alcance pendiente. [#197](https://github.com/puntoracingrc/pachangas/pull/197) fusionó el código con merge `f6b1686d84552962f34ed218fe0b1ddd96fda32b`; [#198](https://github.com/puntoracingrc/pachangas/pull/198) fusionó el cierre documental con merge `fca8a26b928b8a119490f2b0610f919c48267915`.

Migraciones verificadas localmente y en el ledger remoto:

1. `20260826014905_referee_assignment_private_beta_schema_v1`
2. `20260826014910_referee_assignment_private_beta_authority_v1`
3. `20260826014916_referee_match_officiating_commands_v1`
4. `20260826014920_referee_assignment_private_beta_access_v1`
5. `20260826105132_referee_assignment_fk_index_hardening_v1`

Demo World V2.2 conserva paridad mediante [`DEMO_WORLD_V2_2_REFEREE_ASSIGNMENTS_PARITY_REPORT.md`](DEMO_WORLD_V2_2_REFEREE_ASSIGNMENTS_PARITY_REPORT.md), sin convertir datos demo en autoridad ni escribir en producción.

## 9. Matriz requisito por requisito de #179

| Requisito histórico | Evidencia actual | Resultado |
| --- | --- | --- |
| Propose | Comando canónico, revisión y receipt | ENTREGADO |
| Accept / decline | Transiciones server-side y permisos del árbitro | ENTREGADO |
| Confirm / cancel | Lifecycle canónico y estado terminal | ENTREGADO |
| Replace | Sustitución versionada; activación solo tras confirmación | ENTREGADO |
| Reconfirmación R4D | Cambio horario invalida/requiere reconfirmación | ENTREGADO |
| Actor server-side | Derivado de sesión autenticada; no aceptado del cliente | ENTREGADO |
| `operationId` | UUID obligatorio e idempotencia persistida | ENTREGADO |
| `expectedRevision` | Conflicto stale explícito, sin last-write-wins silencioso | ENTREGADO |
| Receipt e historial | Recibos idempotentes y revisiones inmutables | ENTREGADO |
| Lifecycle | proposed, accepted, declined, confirmed, cancelled, expired, replaced y completed | ENTREGADO |
| Conflictos horarios | Exclusión de solapes para árbitro principal | ENTREGADO |
| Disponibilidad | Validación de ventana, excepción, modalidad y área en servidor | ENTREGADO |
| Máximo activo | Un único `MAIN_REFEREE` activo por partido canónico | ENTREGADO |
| Términos privados | Persistidos aparte y cerrados a lectura directa de clientes | ENTREGADO |
| Privacidad | Proyecciones por actor y sin términos privados en superficies públicas | ENTREGADO |
| Permisos Team/Club/árbitro | Capabilities resueltas por PostgreSQL | ENTREGADO |
| Realtime | Invalidación acotada; WAL no se usa como snapshot | ENTREGADO |
| Canonical refetch | Relectura al suscribirse, invalidarse y reconectar | ENTREGADO |
| Offline fail-closed | Escrituras clasificadas por el bridge; nunca éxito ficticio ni cola deportiva | ENTREGADO |
| UI privada | Mis asignaciones, Assignment Desk e integración contextual presentes | ENTREGADO |
| Staging autenticado | Evidencia de dos actores/dispositivos y concurrencia | ENTREGADO |
| Producción | Migraciones, activación privada, smoke transaccional y deployment documentados | ENTREGADO |
| Rollback / cleanup | Smoke con `ROLLBACK` y residuo sintético cero | ENTREGADO |

## 10. Readback productivo de #179

Consultas agregadas y estrictamente de lectura confirmaron:

| Evidencia | Estado actual |
| --- | --- |
| Referee Foundation | ON |
| Referee self-service | ON |
| Perfiles públicos arbitrales | ON |
| Referee marketplace | ON |
| Relaciones Club-árbitro | ON |
| Referee Assignment Private Beta | ON |
| `referee_assignments_enabled` | ON |
| Revisión / secuencia de flags | `6 / 54` |
| Assignments totales / activos | `0 / 0` |
| Revisiones / términos privados | `0 / 0` |
| Recibos agregados | `23`; de ellos, `2` de activación de flags de Assignments |
| Invalidaciones agregadas | `29`, correspondientes a actividad histórica permitida de perfiles, flags y relaciones |
| Tablas y funciones requeridas | PRESENTES |
| RLS | ACTIVO en las tres tablas públicas relevantes |
| DML directo anon/auth | `0` rutas concedidas |
| RPC de comando/officiating | EXECUTE autenticado y autoridad interna |
| Realtime | Tabla de invalidaciones publicada |
| Índices de hardening | `13/13`, válidos y listos |
| Objetos de autoridad de pagos arbitrales | `0` |
| Canonical backfill | No inicializado; `0` eventos |

No se consultaron ni publicaron identidades, términos, disponibilidad, contactos, partidos o IDs.

## 11. Clasificación final de #179

**`COMPLETED_BY_SUBSEQUENT_RELEASE`**.

El issue fue creado antes de la productización posterior. Referee Assignments & Match Officiating Private Beta V1 implementó y activó de forma privada el lifecycle autoritativo originalmente pendiente. El acceso continúa limitado a la beta, los pagos permanecen fuera de alcance y la QA física continúa pendiente. No existe divergencia productiva que justifique mantener abierto el alcance original.

## 12. Issue #180 original

`#180` se creó el 2026-08-24T16:11:58Z. Registró como pendientes Competition Discipline, tarjetas, sanciones, autoridad, privacidad, revisión y apelación. En la beta anterior los read models mostraban correctamente `disciplineStatsStatus = NOT_AVAILABLE`.

El issue no contenía comentarios ni eventos posteriores de reconciliación. No era un issue de conducta social, Profile Reports, Rating, Rewards o billing.

## 13. Releases posteriores de Competition Discipline

[`COMPETITION_DISCIPLINE_V1_REPORT.md`](COMPETITION_DISCIPLINE_V1_REPORT.md) y [`COMPETITION_DISCIPLINE_V1_PRODUCTION_RELEASE.md`](COMPETITION_DISCIPLINE_V1_PRODUCTION_RELEASE.md) documentan R5. Los merges relevantes fueron:

- [#191](https://github.com/puntoracingrc/pachangas/pull/191), autoridad inicial, merge `00dc908be0cb87ed0814becdc7ec06c48ec8102b`.
- [#192](https://github.com/puntoracingrc/pachangas/pull/192), Demo V2.1 y accounting de cumplimiento/apelación, merge `f96b49d06d43725abdec8ef4fc6b1a0d9e69be0d`.
- [#193](https://github.com/puntoracingrc/pachangas/pull/193), integración de calendario pertinente, merge `30a4fef063e99c2757ab7c676c033d05ffb36dda`.
- [#194](https://github.com/puntoracingrc/pachangas/pull/194), hardening de ACL, merge `0401a127ebd910ccad799b466ad3327782067b37`.
- [#195](https://github.com/puntoracingrc/pachangas/pull/195), cierre documental, merge `b3fc733700186bdc7d77cfab2ff304bef24f3448`.

Migraciones verificadas localmente y en producción:

1. `20260825165834_competition_discipline_schema_v1`
2. `20260825165838_competition_discipline_commands_v1`
3. `20260825165843_competition_discipline_access_v1`
4. `20260825165849_competition_discipline_hardening_v1`
5. `20260825203500_competition_discipline_appeal_service_accounting_v1`
6. `20260825211825_competition_discipline_private_policy_revoke_v1`

[`DEMO_WORLD_V2_1_DISCIPLINE_PARITY_REPORT.md`](DEMO_WORLD_V2_1_DISCIPLINE_PARITY_REPORT.md) conserva una proyección determinista y sanitizada, no una segunda autoridad.

## 14. Matriz requisito por requisito de #180

| Requisito histórico | Evidencia actual | Resultado |
| --- | --- | --- |
| Eventos/tarjetas | Eventos disciplinarios append-only vinculados a Competition y CanonicalMatch | ENTREGADO |
| Counters | Reconstrucción canónica por RuleRevision y ciclo | ENTREGADO |
| Sanciones | Decisión versionada y propuesta separada de autoridad | ENTREGADO |
| Cumplimiento | Unidades de servicio y reversión auditable | ENTREGADO |
| Elegibilidad | Estado derivado de sanción y cumplimiento | ENTREGADO |
| Apelaciones | Submit, transición, retirada y revisiones inmutables | ENTREGADO |
| Revisión/corrección | Correct/annul sin reescribir evidencia histórica | ENTREGADO |
| Autoridad | Actor server-side, `operationId`, `expectedRevision`, locks y receipts | ENTREGADO |
| Privacidad | Separación de vistas privadas/públicas y evidencia privada | ENTREGADO |
| RLS y grants | DML directo cerrado; comandos autenticados acotados | ENTREGADO |
| Realtime/refetch | Invalidaciones canónicas y relectura, sin autoridad WAL | ENTREGADO |
| Offline | Escritura fail-closed y sin confirmación optimista | ENTREGADO |
| Match Hub / mesa privada | Superficies canónicas presentes | ENTREGADO |
| Perfil de jugador | Read model privado disciplinario presente | ENTREGADO |
| Control Center | Gestión privada y flags fail-closed | ENTREGADO |
| Read model público | Proyección minimizada y protegida por flag público | ENTREGADO |
| Producción | R5 migrado y beta privada activa | ENTREGADO |
| Rollback / cleanup | Smoke productivo transaccional y residuo cero | ENTREGADO |

## 15. Readback productivo de #180

| Evidencia | Estado actual |
| --- | --- |
| `competition_discipline_foundation_enabled` | ON |
| `competition_disciplinary_events_enabled` | ON |
| `competition_disciplinary_counters_enabled` | ON |
| `competition_sanctions_enabled` | ON |
| `competition_sanction_service_enabled` | ON |
| `competition_discipline_appeals_enabled` | ON |
| `competition_public_discipline_enabled` | OFF |
| Revisión / secuencia de flags | `21 / 2614` |
| Catálogos de reglas | `4`, incremento histórico legítimo respecto al release inicial |
| Ciclos/eventos/counters | `0 / 0 / 0` |
| Sanciones/servicio/apelaciones | `0 / 0 / 0` |
| Estados de jugador/evidencia privada | `0 / 0` |
| Recibos de activación disciplinaria | `1` |
| Invalidaciones disciplinarias | `1`, de cambio de flags |
| Tablas requeridas | PRESENTES; las 12 públicas relevantes tienen RLS |
| DML directo anon/auth | `0` rutas concedidas |
| RPC de comando | EXECUTE autenticado, un único overload |
| Helper de política privada accesible al cliente | `0` rutas |
| Triggers disciplinarios | `13` activos, `0` deshabilitados |
| Realtime | Invalidaciones de competición publicadas |
| Ledger | `237/237`; las seis migraciones R5 presentes |

El readback no creó pruebas productivas ni extrajo jugadores, árbitros, competiciones, eventos, sanciones, apelaciones, descripciones, notas, evidencia o IDs.

## 16. Separación private/public discipline

La disciplina privada de competición y la exposición pública son capacidades distintas. R5 mantiene activa la primera y apagada la segunda:

- Privado: eventos/tarjetas, counters, sanciones, cumplimiento, elegibilidad, apelaciones y correcciones están disponibles para actores autorizados.
- Público: `competition_public_discipline_enabled = false`; no se publican sanciones ni evidencia. Las superficies públicas continúan minimizadas o con estado no disponible.
- Conducta social: es un dominio independiente y no modifica Competition Discipline.
- Profile Reports: corresponde a `#178` y no modifica Competition Discipline.

Por tanto, mantener disciplina pública OFF es una decisión vigente de privacidad/activación, no una carencia del motor privado requerido por `#180`.

## 17. Clasificación final de #180

**`COMPLETED_BY_SUBSEQUENT_RELEASE`**.

El issue fue creado antes de R5. Competition Discipline V1 implementó posteriormente tarjetas, contadores, sanciones, cumplimiento y apelaciones bajo autoridad privada. La beta privada está activa y la disciplina pública continúa deliberadamente desactivada. No existe divergencia productiva en el alcance original.

## 18. Alcances que continúan deliberadamente OFF

| Alcance | Estado | Relación con esta reconciliación |
| --- | --- | --- |
| Referee Assignments pública/general | OFF / no declarada | La release está limitada a beta privada. |
| Disciplina pública | OFF | Separada de la autoridad privada ya entregada. |
| Pagos arbitrales | NOT_IMPLEMENTED | Issue independiente `#181`; no formaba parte de `#179`. |
| Profile Reports | No iniciado aquí | Issue independiente `#178`. |
| QA física Android/iPhone/PWA | PENDING | Issues independientes `#167`-`#169`. |
| Canonical backfill arbitral | No inicializado | No impide el lifecycle privado desplegado. |
| Wave 9C | NO DEFINIDA / NO REANUDADA | Fuera de alcance. |

## 19. Issue #178

[#178](https://github.com/puntoracingrc/pachangas/issues/178) continúa `OPEN` y se clasifica aquí únicamente como `BLOCKED_PRODUCT_LEGAL`. Profile Reports no se confunde con disciplina de competición. No se modificaron su cuerpo, etiquetas, comentarios ni estado.

## 20. Issue #181

[#181](https://github.com/puntoracingrc/pachangas/issues/181) continúa `OPEN` y se clasifica aquí únicamente como `BUSINESS_LEGAL_DECISION_REQUIRED`. Tarifas y pagos arbitrales siguen fuera de Referee Assignments Private Beta. No hubo llamadas a Stripe ni cambios de billing.

## 21. Issues físicos #167-169

[#167](https://github.com/puntoracingrc/pachangas/issues/167), [#168](https://github.com/puntoracingrc/pachangas/issues/168) y [#169](https://github.com/puntoracingrc/pachangas/issues/169) continúan `OPEN`. Android físico, iPhone físico y PWA instalada física siguen `PENDING`; esta tarea no ejecuta ni afirma QA física.

## 22. Tests

| Gate | Resultado |
| --- | --- |
| `npm ci` | PASS; lockfile respetado, sin edición |
| Referee Platform | `18/18 PASS` |
| Referee Platform UI | `10/10 PASS` |
| Referee Assignments | `15/15 PASS` |
| Referee Assignments DB/RLS/idempotencia | PASS |
| Referee Assignments concurrencia | PASS; 10 carreras con un ganador canónico y conflicto/replay esperado |
| Competition Discipline | `15/15 PASS` |
| Competition Discipline DB/RLS/idempotencia/adversarial | PASS |
| Competition Discipline concurrencia | PASS; 7 carreras |
| Demo World V2 | `20/20 PASS` |
| `npm test` Node | `20/20 PASS` |
| `npm test` TS/TSX | `857/857 PASS` |
| `npm test` total | `877/877 PASS` |
| Failed / skipped / todo / cancelled | `0 / 0 / 0 / 0` |
| `npm run typecheck` | PASS |
| `npm run build` | PASS; 78 páginas estáticas generadas |
| `npm run lint` | PASS; solo nota informativa de Babel por tamaño de `app/page.tsx` |
| `git diff --check` | PASS antes de redactar; se repite sobre el diff final |

El runner histórico `test:referee-platform:db` no es directamente reproducible sobre el esquema local posterior a Wave 4/R5: primero requiere activar una flag histórica y después choca con una restricción posterior de invitaciones Club. Ambos intentos permanecieron dentro de transacciones revertidas y el readback confirmó las flags locales en `false`. No se alteró el runner para forzar verde. La suite DB/RLS actual que sustituye ese alcance, `test:referee-assignments:db`, sí pasó completa.

## 23. Seguridad

- Los endpoints de escritura aceptan intención semántica, exigen sesión, `operationId` y `expectedRevision`, y devuelven respuestas `no-store`.
- PostgreSQL resuelve actor, permisos, estado, tiempo, conflictos, idempotencia y revisión.
- Realtime invalida; los clientes releen el read model canónico y no aplican el payload WAL como autoridad.
- El bridge PWA bloquea escrituras offline e incompatibles y no muestra éxito ficticio.
- RLS está activa, el DML directo de `anon`/`authenticated` está cerrado y las funciones privadas no son ejecutables por clientes.
- El readback fue agregado y read-only. No se usó `service_role` en navegador, no se conservaron resultados sensibles y no se efectuaron escrituras.

## 24. Datos

Durante la tarea se crearon exactamente cero usuarios, perfiles, árbitros, Clubs, Assignments, eventos disciplinarios, sanciones, apelaciones y notificaciones. Hubo cero cambios de flags, cero migraciones y cero llamadas a Stripe.

Los únicos accesos externos fueron metadata pública de GitHub y consultas agregadas read-only al proyecto Supabase correcto, identificado antes de consultar para no tocar otros proyectos.

## 25. Cambios realizados

| Tipo | Cantidad |
| --- | ---: |
| Markdown nuevos/modificados | 1 |
| Código ejecutable modificado | 0 |
| Tests modificados | 0 |
| SQL/migraciones/RPC/RLS/flags | 0 |
| `AGENTS.md` | 0 |
| Archivos del shell de #277 | 0 |
| `package.json` / `package-lock.json` | 0 / 0 |
| Assets/configuración/Service Worker | 0 |

## 26. Estado del backlog después

Tras fusionar este informe, comentar con la evidencia y cerrar manualmente `#179` y `#180`, el estado reconciliado es:

| Issue | Clasificación | Estado final |
| --- | --- | --- |
| #167 | PHYSICAL_QA | OPEN |
| #168 | PHYSICAL_QA | OPEN |
| #169 | PHYSICAL_QA | OPEN |
| #178 | BLOCKED_PRODUCT_LEGAL | OPEN |
| #179 | COMPLETED_BY_SUBSEQUENT_RELEASE | CLOSED |
| #180 | COMPLETED_BY_SUBSEQUENT_RELEASE | CLOSED |
| #181 | BUSINESS_LEGAL_DECISION_REQUIRED | OPEN |

No se abre ningún issue de sustitución. Los issues `#165`, `#166`, `#170` y `#173`; `SOCIAL-RC-001` a `SOCIAL-RC-012`; y `OFFICIAL-UI-V3I-001` a `OFFICIAL-UI-V3I-003` permanecen cerrados y congelados. El contrato de cierre exterior de menús de `#277` permanece desplegado y sin cambios.

## 27. Conclusión

Los cuerpos de `#179` y `#180` describen correctamente un momento histórico, pero ya no representan el producto actual. La autoridad privada, las migraciones, los permisos, las pruebas, los releases y el readback productivo sostienen el cierre de ambos como `COMPLETED_BY_SUBSEQUENT_RELEASE`.

El cierre no amplía acceso: Referee Assignments continúa en beta privada, Competition Discipline continúa en beta privada, disciplina pública permanece OFF, pagos arbitrales siguen fuera de alcance y la QA física continúa pendiente. El punto de parada es esta reconciliación documental; no se inicia Wave 9C ni ninguna implementación posterior.
