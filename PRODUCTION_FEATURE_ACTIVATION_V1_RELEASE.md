# Production Feature Activation V1 Release

Estado: `RELEASE PRODUCTIVA VERIFICADA`.

## Identidad del release

| Dato | Valor |
| --- | --- |
| Base inicial auditada | `97fb945850b0b843050cd5b4288e24d7397a339b` |
| Rama funcional | `codex/production-feature-activation-audit-v1` |
| PR funcional | [#142](https://github.com/puntoracingrc/pachangas/pull/142) |
| Merge de `main` | `3ef0322cf4bb20ae1e8750b96dee4da47e147927` |
| Deployment Vercel | `dpl_6u6MVL18K2wd6dmZPLvqTeEKSsSj` |
| URL productiva | [pachangasiq.com](https://pachangasiq.com) |
| Proyecto Supabase | `qonbngfrnrqgmxbdfbea` (`Pachangas`) |
| Migracion | `20260812062731_production_feature_activation_v1` |

La rama documental que contiene este informe se publicara y fusionara separadamente. No contiene codigo, migraciones ni cambios de datos.

## Backup y migracion

- Backup fisico recuperable mas reciente antes de activar: `2026-08-12T00:16:24Z`, con accion Restore disponible en Supabase Dashboard.
- PITR no esta habilitado; la base es Pro y el backup incluye la ultima mutacion aplicativa previa, de `2026-08-11T20:43:10.337474Z`.
- Historial remoto antes: 89 migraciones. Despues: 90.
- Ultima version remota: `20260812062731 production_feature_activation_v1`.
- Hash MD5 del SQL remoto y local: `b74207ab78ad026618c5a1a235b33eb1`.
- La migracion se instalo con Attendance, Conduct y Social Restrictions OFF, Triage OFF y shadow ON. No proceso historia.

## Activacion autoritativa

Ambos cambios pasaron por `set_pachanga_platform_flag_v1` con actor autenticado, revision esperada, `operationId`, motivo, fecha y secuencia del servidor. No se uso un `UPDATE` manual para cambiar flags.

| Paso | Operation ID | Revision | Server sequence | Frontera efectiva | Resultado |
| --- | --- | --- | ---: | --- | --- |
| Attendance ON | `a8121000-0000-4000-8000-000000000001` | 1 -> 2 | 2 | `2026-08-12T07:53:14.023506Z` | confirmado |
| Conduct ON | `a8121000-0000-4000-8000-000000000002` | 2 -> 3 | 3 | `2026-08-12T07:56:33.639969Z` | confirmado |

Motivos persistidos:

```text
Production Feature Activation Audit V1 - Attendance activation
Production Feature Activation Audit V1 - Conduct activation
```

El ledger conserva actor `platform_owner`, valor anterior, valor nuevo, revision, operation ID, server sequence y timestamp para ambas operaciones.

## Estado final de los 35 gates

| # | Gate | Valor final | Clasificacion final |
| ---: | --- | --- | --- |
| 1 | Attendance | ON, revision global 3 | `ACTIVE_PRODUCT` |
| 2 | Conduct/report intake | ON, revision global 3 | `ACTIVE_PRODUCT` |
| 3 | Social Restrictions | OFF | `READY_WITH_GUARDS` |
| 4 | Conduct Triage authority | OFF | `SHADOW_ONLY` |
| 5 | Conduct Triage shadow | ON | `SHADOW_ONLY` |
| 6 | Player Cosmetics | ON, revision 1 | `ACTIVE_PRODUCT` |
| 7 | Team Cosmetics | ON, revision 1 | `ACTIVE_PRODUCT` |
| 8 | Team Cosmetic Rewards | ON, revision 1 | `ACTIVE_PRODUCT` |
| 9 | Season Score V3 | LAB | `NEEDS_PRODUCTIZATION` |
| 10 | Ranking provincial | LAB | `NEEDS_PRODUCTIZATION` |
| 11 | Premios provinciales | OFF | `BLOCKED` |
| 12 | Premium Ball | OFF/ausente | `BLOCKED` |
| 13 | Canal push | OFF | `NEEDS_PRODUCTIZATION` |
| 14 | Canal email | OFF | `NEEDS_PRODUCTIZATION` |
| 15 | Minimum supported client | `2.0.0` | `ACTIVE_PRODUCT` |
| 16 | Client/SW release | `2.0.0+sw.3ef0322cf4bb` | `ACTIVE_PRODUCT` |
| 17 | PWA runtime | ON | `ACTIVE_PRODUCT` |
| 18 | Synthetic World | OFF | `LAB_VALIDATED` |
| 19 | Synthetic admin | OFF | `LAB_VALIDATED` |
| 20 | Rating por grupo | 11/11 ON | `ACTIVE_PRODUCT` |
| 21 | Publicacion de jugador | 0/1 ON | `ACTIVE_PRODUCT` |
| 22 | Perfil de mercado activo | 0/1 ON | `ACTIVE_PRODUCT` |
| 23 | Acepta grupos | 1/1 ON, latente | `ACTIVE_PRODUCT` |
| 24 | Acepta invitados | 1/1 ON, latente | `ACTIVE_PRODUCT` |
| 25 | Equipo retable | 2/3 ON | `ACTIVE_PRODUCT` |
| 26 | Partido publico | 0/1 ON | `ACTIVE_PRODUCT` |
| 27 | Preferencia in-app | 0 overrides | `ACTIVE_PRODUCT` |
| 28 | Preferencia push | 0 overrides | `READY_WITH_GUARDS` |
| 29 | Preferencia email | 0 overrides | `READY_WITH_GUARDS` |
| 30 | Definiciones de logro | 106/222 ON | `ACTIVE_PRODUCT` |
| 31 | Reglas logro-caja | 156/156 ON | `ACTIVE_PRODUCT` |
| 32 | Catalogo de cajas | 5/5 ON | `ACTIVE_PRODUCT` |
| 33 | Pools de recompensa | 19/19 ON | `ACTIVE_PRODUCT` |
| 34 | Catalogo cosmetico | 89/89 ON | `ACTIVE_PRODUCT` |
| 35 | Team Reward mappings | 5/5 ON | `ACTIVE_PRODUCT` |

No se localizaron flags obsoletos ni duplicados destructivos. Los solapamientos documentados son guardas ortogonales o proyecciones derivadas.

## Cero backfill y cero burst

Los contadores se comprobaron antes, despues de Attendance y despues de Conduct:

```text
attendance closures/events/reviews/state = 0
attendance facts = 0
conduct reports/cases/events/warnings/restrictions/receipts = 0
active restrictions = 0
notifications = 32 -> 32 -> 32
billing webhook events = 0
```

No se generaron no-shows, cancelaciones tardias, reportes, casos, avisos ni sanciones a partir del historial. Las fronteras del servidor rechazan contextos anteriores. Un no-show sigue siendo un hecho revisable, no culpabilidad ni castigo automatico.

## Invariantes de datos

Todos estos pares `filas/hash` permanecieron identicos antes y despues de ambas activaciones:

| Sistema | Antes y despues |
| --- | --- |
| Rating snapshots | `1/ce838b082d476871c05aa6df5cdf589c` |
| Rating evidence | `0/d41d8cd98f00b204e9800998ecf8427e` |
| Player profiles | `1/409014b9d4ddecb23cfd41600719ceda` |
| Achievement grants | `17/e18b5bba8bc92a1c129b6e8a07c7cda8` |
| Reward grants | `17/f8c950d847b867804d4b51b9cee70971` |
| Player inventory | `0/d41d8cd98f00b204e9800998ecf8427e` |
| Team inventory | `7/e5a3c62aa06218156930e31eab7cab7d` |
| Team mappings | `5/43ec6570d18b53b719152b81445a991e` |
| Billing projection | `11/f4d7dc5191a199d51dd9e32d520f74a4` |

Resultado: cero mutaciones de Rating V2, facetas, fiabilidad, Season Score, logros, cajas, cosmetics, Team Rewards o billing causadas por la activacion.

Los cinco mappings de Team Rewards siguen exactamente iguales:

```text
team.external.clean_sheets.001 -> team.shield.effect.edge_glow
team.external.matches.010      -> team.shield.ornament.banner
team.external.wins.001         -> team.shield.border.copper
team.matches.025               -> team.shield.ornament.laurels
team.matches.050               -> team.shield.border.silver
```

Premium Ball conserva cero filas en catalogo, inventario, mapping, reward ledger y loadout. Ninguna propuesta del Premium Art Pack se activo.

## Seguridad, privacidad y Realtime

- `anon`: no puede cambiar flags, reportar ni leer tablas privadas de asistencia/conducta/notificaciones.
- `authenticated`: puede alcanzar las RPC publicas previstas, pero cada mutacion resuelve actor, contexto y RBAC en servidor.
- Admin de grupo: no obtiene evidencia privada ni identidad de denunciante.
- Moderador interno y `platform_owner`: solo las capacidades definidas por RBAC.
- Los reportes no exponen identidad, informacion medica, evidencia ni texto privado por respuesta, notificacion o Realtime.
- No existe sancion automatica por uno, diez correlacionados o varias fuentes independientes.
- Realtime publica `pachanga_attendance_group_state`, `pachanga_conduct_subject_state` y `pachanga_user_notifications`; el cliente invalida la entidad y recupera el read model canonico.

## PWA y cliente antiguo

- `manifest.webmanifest`: HTTP 200, `display=fullscreen`, fallbacks `standalone`, `minimal-ui`, `browser`, orientacion `any` e iconos any/maskable/monochrome.
- `sw.js`: HTTP 200, `Cache-Control: no-cache, no-store`, version `2.0.0+sw.3ef0322cf4bb`.
- `/api/client-policy`: HTTP 200, `private, no-store`, minimo `2.0.0`.
- Un cliente sin version se clasifica `v1-unversioned`: las lecturas siguen disponibles y las escrituras devuelven `CLIENT_UPDATE_REQUIRED` sin falso exito.
- No existe cola offline de operaciones deportivas; el cliente sustituye cualquier preview por la respuesta confirmada.

## QA y observabilidad productivas

- Control Center autenticado en Chrome: `/admin/flags` muestra Attendance `PRODUCT / ACTIVE_PRODUCT / Activo`, Conduct `PRODUCT / ACTIVE_PRODUCT / Activo`, Social Restrictions `OFF / READY_WITH_GUARDS / Inactivo` y Triage `LAB / SHADOW_ONLY / Inactivo` con shadow vigente.
- Rutas HTTP 200: `/`, `/mercado`, `/perfil/avisos`, `/perfil/conducta`, `/reportar`, `/admin`, `/admin/flags` y `/admin/conduct`.
- Auditoria visual: 40 combinaciones principales mas 12 comprobaciones aisladas de Alineacion/Resultado/Admin en 1440x900, 390x844, 844x390 y PWA standalone.
- Resultado visual: cero errores de consola, warnings, requests fallidas, imagenes rotas, overflow horizontal, controles fijos fuera del viewport o roturas del chrome de juego.
- Vercel: deployment `READY`, cero errores runtime; 409 respuestas 200 y 147 respuestas 304 en la ventana final.
- Supabase API desde activacion: 25 respuestas 200 y dos upgrades Realtime 101; cero respuesta fallida.
- Realtime: 12 eventos recientes y cero mensaje de error.
- PostgreSQL: tres errores recientes proceden de consultas diagnosticas de esta auditoria (`get_pachanga_attendance_capabilities_v1`, un `UNION ORDER BY` y una columna `occurred_at` supuesta). No son llamadas de producto; no hubo error posterior ni mutacion parcial.

## Tests y capacidad

| Gate | Resultado |
| --- | --- |
| `npm test` | PASS: 20/20 estructurales y 242/242 TS/TSX |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| Lint focalizado | PASS |
| Lint global | 43 problemas basales, 23 errores y 20 warnings; ninguno del diff |
| `git diff --check` | PASS |
| Instalacion vacia | PASS, 90 migraciones, schema `simulation` ausente |
| SQL/RLS/idempotencia/concurrencia | PASS para Rating, Social, invitados, Conduct, logros, cosmetics, notifications y Control Center |
| Synthetic World soak | PASS: 30 seeds, 35 dias/seed, 4.721 partidos y 309.193 eventos |
| Advisors | 248 security y 210 performance basales; cero regresion nueva atribuible |

## Rollback preparado

No se ejecuto rollback porque todos los gates quedaron verdes. Si aparece una condicion de stop:

1. Llamar la misma RPC autoritativa con `expectedRevision=3`, un operation ID nuevo y motivo de incidente.
2. Apagar primero Conduct o Attendance segun el origen; la revision debe avanzar monotonicamente.
3. Verificar ledger, read model, cero nuevas escrituras y convergencia Realtime.
4. Mantener las fronteras y evidencias existentes; no reabrir escrituras V1 ni convertir payload/localStorage en autoridad.
5. Preferir roll-forward para schema. La migracion no necesita revertirse para apagar la capacidad.

## Modificaciones exactas de produccion

1. Schema: migracion forward-only `20260812062731_production_feature_activation_v1`, con dos fronteras temporales, guards no retroactivos, read model de readiness, correcciones de indices/funciones Attendance y sus tests contractuales.
2. Historial: una entrada nueva en `supabase_migrations.schema_migrations`, total 90.
3. Configuracion: `attendance_closure_enabled=true`, `conduct_reports_enabled=true`, revision global `1 -> 3` y sus dos timestamps efectivos.
4. Auditoria: dos entradas nuevas de platform flag ledger, secuencias 2 y 3.
5. Frontend: deployment de `main` `3ef0322cf4bb20ae1e8750b96dee4da47e147927` con readiness visible en `/admin/flags`.

No se modificaron usuarios, grupos, partidos, reportes, casos, asistencia historica, notificaciones existentes, Rating, rewards, cosmetics, mappings, billing, Premium Ball, Premium Art ni datos Synthetic World.

## Documentos relacionados

- `PRODUCTION_FEATURE_ACTIVATION_AUDIT_V1.md`: inventario de 35 gates y auditoria tecnica.
- `RANKING_PRODUCTIZATION_NEXT_STEPS.md`: hueco LAB -> PRODUCT sin implementacion.
- Este documento: evidencia del release productivo y rollback.
