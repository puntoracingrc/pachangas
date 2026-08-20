# Production Feature Activation Audit V1

Estado: `PRODUCCION ACTIVADA Y VERIFICADA`. Attendance y Conduct estan activos; Social Restrictions sigue OFF y Triage conserva solo autoridad shadow.

## Trazabilidad

- Inicio: 2026-08-12, zona `Europe/Madrid`.
- Base exacta: `origin/main` en `97fb945850b0b843050cd5b4288e24d7397a339b`.
- Rama: `codex/production-feature-activation-audit-v1`.
- PR borrador: [#142](https://github.com/puntoracingrc/pachangas/pull/142).
- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-production-feature-activation-audit-v1`.
- Checkout principal: no utilizado porque contiene cambios ajenos del laboratorio.
- Entorno local: macOS, Node 22 o superior, Supabase CLI `2.107.0`, PostgreSQL local en Docker.
- Fuentes externas consultadas: Supabase produccion `qonbngfrnrqgmxbdfbea`, staging `iozcjirlfytryzrcmrnq`, Vercel Production, GitHub y QA autenticada en Chrome. Produccion recibio exclusivamente la migracion versionada, dos cambios de flag por RPC autoritativa y sus dos entradas de ledger descritas abajo.
- PR funcional: [#142](https://github.com/puntoracingrc/pachangas/pull/142), fusionado en `main` como `3ef0322cf4bb20ae1e8750b96dee4da47e147927`.
- Deployment productivo: `dpl_6u6MVL18K2wd6dmZPLvqTeEKSsSj`, estado `READY`, SHA exacto `3ef0322cf4bb20ae1e8750b96dee4da47e147927` y alias canonico `pachangasiq.com`.

## Alcance y criterio de inventario

La auditoria distingue siempre:

```text
codigo desplegado != funcion productiva != flag activo
```

Se considera gate canonico cualquier configuracion global, de runtime, de entrega, por tenant/usuario o de ciclo de vida de catalogo que habilita o impide una capacidad. No se cuentan como feature flag los estados ordinarios del dominio: `injured`, `inactive`, estados de partido, `requires_approval`, pertenencias, invitaciones concretas, estado de una suscripcion o una fila concreta de asistencia.

Resultado: **35 gates canónicos**.

- 12 capacidades globales o de laboratorio.
- 7 politicas de runtime/entrega.
- 10 gates por grupo, usuario o entidad.
- 6 gates de ciclo de vida de catalogo.

No se ha localizado un flag global independiente para Core Social, billing o invitados. Core Social se gobierna por estado/revision de cada reto, perfil o partido; billing por estado Stripe/suscripcion; invitados por permisos contextuales y las preferencias de mercado documentadas abajo.

## Resumen ejecutivo

| Capacidad | Antes en produccion | Clasificacion | Riesgo/dependencia | Recomendacion | Accion prevista | Despues |
| --- | --- | --- | --- | --- | --- | --- |
| Asistencia | OFF, revision 1 | `ACTIVE_PRODUCT` | Frontera no retroactiva instalada | Activar primero | Migracion + RPC auditada | ON, revision global 3 |
| Conducta/reportes | OFF, revision 1 | `ACTIVE_PRODUCT` | Moderacion humana y privacidad | Activar tras Asistencia | Migracion + RPC auditada | ON, revision global 3 |
| Restricciones sociales | OFF, revision 1 | `READY_WITH_GUARDS` | Necesita experiencia real de moderacion | Mantener OFF | Ninguna activacion | OFF obligatorio |
| Triage | OFF; shadow ON | `SHADOW_ONLY` | No tiene autoridad automatica | Mantener laboratorio/sombra | Ninguna promocion | SHADOW/LAB |
| Player Cosmetics | ON, revision 1 | `ACTIVE_PRODUCT` | Ninguna nueva | No modificar | Ninguna | ON |
| Team Cosmetics | ON, revision 1 | `ACTIVE_PRODUCT` | Ninguna nueva | No modificar | Ninguna | ON |
| Team Cosmetic Rewards | ON, revision 1 | `ACTIVE_PRODUCT` | Team Cosmetics + 5 mappings | No modificar | Ninguna | ON |
| Season Score V3 | Sin gate productivo | `NEEDS_PRODUCTIZATION` | Falta read model PostgreSQL | Mantener LAB | Plan separado | LAB |
| Ranking provincial | ON solo en piloto LAB | `NEEDS_PRODUCTIZATION` | Season Score, territorio e integridad | Mantener LAB | Plan separado | LAB |
| Premios provinciales | OFF en LAB | `BLOCKED` | Ranking y cierre de temporada productivos | Mantener OFF | Ninguna | OFF |
| Premium Ball | Ausente de produccion | `BLOCKED` | `READY_PENDING_PHYSICAL_QA` | Mantener OFF | Ninguna | OFF |

## Matriz canónica completa

Las cifras `x/y` significan filas activas sobre filas existentes. `N/A` indica que no existe revision monotona para ese gate; cuando corresponde se usa `updated_at`, revision de la entidad o version de build.

| # | Feature / key real | Fuente y default | Valor produccion antes | Rev. | Clasificacion | Consumidor, escrituras y avisos | Dependencia / backfill / rollback / test |
| ---: | --- | --- | --- | ---: | --- | --- | --- |
| 1 | Asistencia / `attendance_closure_enabled` | `private.pachanga_conduct_settings`; `false` | OFF | 1 | `ACTIVE_PRODUCT` | RPC de cierre, disputa, revision y correccion; avisos in-app obligatorios solo tras un cierre negativo | `attendance_effective_from` instalado; cero backfill; OFF por RPC; SQL/RLS, concurrencia, PWA y Synthetic World |
| 2 | Conducta / `conduct_reports_enabled` | misma tabla; `false` | OFF | 1 | `ACTIVE_PRODUCT` | Alta privada de reportes, casos y cola humana; avisos internos/objetivo sin identidad denunciante | `conduct_effective_from` instalado y moderacion humana obligatoria; cero backfill; OFF por RPC; SQL/RLS, concurrencia y Synthetic World |
| 3 | Restricciones / `social_restrictions_enabled` | misma tabla; `false` | OFF | 1 | `READY_WITH_GUARDS` | Permite aplicar, nunca inferir, restricciones a Mercado/Retos/partidos publicos/invitaciones | Datos reales + decision humana; sin Rating/rewards; OFF por RPC; tests de enforcement y apelacion |
| 4 | Triage / `conduct_triage_enabled` | misma tabla; `false` | OFF | 1 | `SHADOW_ONLY` | Calcula prioridad operacional cuando se active; no sanciona | Debe seguir sin autoridad; OFF por RPC; pruebas V1.1 |
| 5 | Triage sombra / `conduct_triage_shadow_mode` | misma tabla; `true` | ON | 1 | `SHADOW_ONLY` | Calcula recomendaciones pero conserva cola humana V1 | No es mutable desde el Control Center general; rollback = conservar ON; SQL y simulacion |
| 6 | Player Cosmetics / `player_cosmetics_enabled` | `private.pachanga_player_cosmetic_settings`; `false` | ON | 1 | `ACTIVE_PRODUCT` | Catalogo, inventario, loadout y render de carta; sin efectos deportivos | Ninguna nueva; OFF por RPC; suites de cosmetics y concurrencia |
| 7 | Team Cosmetics / `team_cosmetics_enabled` | `private.pachanga_team_cosmetic_settings`; `false` | ON | 1 | `ACTIVE_PRODUCT` | Identidad y loadout del escudo | Ninguna nueva; OFF por RPC; SQL/RLS, visual y concurrencia |
| 8 | Team Cosmetic Rewards / `team_cosmetic_rewards_enabled` | misma tabla; `false` | ON | 1 | `ACTIVE_PRODUCT` | Cinco mappings idempotentes; concede cosmetics, nunca moneda | Team Cosmetics; frontier no retroactivo propio; OFF por RPC; SQL/concurrencia |
| 9 | Season Score / `season_score_v3` | motor bajo `simulation/season-ranking-lab`; sin flag DB, default producto OFF | LAB | 0 | `NEEDS_PRODUCTIZATION` | Solo laboratorio/tests; no escritura ni UI publica productiva | Falta read model, rebuild, API y lifecycle; no rollback necesario |
| 10 | Ranking provincial / `provincial_rankings_enabled` | constante/resolver LAB; default piloto `true` | ON solo LAB | 0 | `NEEDS_PRODUCTIZATION` | `/laboratorio-ranking-provincial`; no ranking productivo persistido | Depende de Season Score productivo, territorio e integridad; no afecta produccion |
| 11 | Premios provinciales / `provincial_awards_enabled` | constante/resolver LAB; default `false` | OFF | 0 | `BLOCKED` | Solo simulacion de cierre; ningun grant productivo | Ranking productivo, elegibilidad y award readiness; debe seguir OFF |
| 12 | Premium Ball / `team.shield.symbol.ball_premium` | ausencia de fila en catalogo productivo | OFF/ausente | 0 | `BLOCKED` | Renderer y laboratorio 3D; cero mappings productivos | QA fisica real pendiente; rollback = seguir ausente. Staging conserva un fixture antiguo sin mapping |
| 13 | Canal push / `private.pachanga_notification_channels.push` | DB; `false` | OFF | N/A | `NEEDS_PRODUCTIZATION` | Crearia intents de outbox si usuario lo permite | Falta proveedor/worker productivo; activar no reconstruye historico; OFF por canal |
| 14 | Canal email / `private.pachanga_notification_channels.email` | DB; `false` | OFF | N/A | `NEEDS_PRODUCTIZATION` | Crearia intents de outbox si usuario lo permite | Falta proveedor productivo; activar no reconstruye historico; OFF por canal |
| 15 | Minimo cliente / `PACHANGAS_MINIMUM_SUPPORTED_CLIENT_VERSION` | servidor; default `2.0.0` | `2.0.0` por default | build | `ACTIVE_PRODUCT` | Bloquea solo escrituras incompatibles con `CLIENT_UPDATE_REQUIRED`; lecturas siguen | Endpoint `no-store`, SemVer, PWA bridge tests; rollback por env |
| 16 | Release cliente/SW / `PACHANGAS_CLIENT_RELEASE_VERSION` | build; default `2.0.0` + SHA | Activo | build SHA | `ACTIVE_PRODUCT` | Version inmutable de cliente y Service Worker; una recarga controlada | Requiere despliegue; tests de update/reconexion |
| 17 | Registro PWA / runtime Service Worker | `app/pwa-runtime.tsx`; produccion o loopback | ON en produccion | SW version | `ACTIVE_PRODUCT` | Cachea shell/lecturas y actualiza worker; nunca confirma escrituras offline | Rollback por deploy; PWA/manifest/browser tests |
| 18 | Synthetic World / `PACHANGAS_SYNTHETIC_WORLD` | env; ausencia equivale OFF | OFF | N/A | `LAB_VALIDATED` | Habilita simulador solo en loopback seguro | Rechaza Supabase remoto/produccion; no se activa ni despliega datos |
| 19 | Synthetic admin / `PACHANGAS_SYNTHETIC_ADMIN` | env; ausencia equivale OFF | OFF | N/A | `LAB_VALIDATED` | Expone dashboard/API sintetica solo con gate anterior | Ademas bloqueado por `NODE_ENV=production`; no activar |
| 20 | Rating por grupo / `pachanga_groups.ratings_enabled` | DB; `true` | 11/11 ON | revision grupo | `ACTIVE_PRODUCT` | Habilita Rating V2 del grupo mediante RPC revisionada | No es global; OFF por RPC de grupo; SQL/RLS/concurrencia Rating V2 |
| 21 | Publicacion jugador / `pachanga_player_profiles.market_enabled` | DB; `false` | 0/1 ON | perfil v. | `ACTIVE_PRODUCT` | Publica/retira la ficha del mercado | Usuario/admin autorizado; no backfill; RPC y RLS de mercado |
| 22 | Perfil de mercado / `pachanga_market_profiles.active` | DB; `true` al publicar | 0/1 ON | `updated_at` | `ACTIVE_PRODUCT` | Hace indexable una proyeccion canonica del jugador | Derivado de publicacion; no es fuente de Rating; cache invalidable |
| 23 | Acepta grupos / `market_open_to_group` | perfil universal; `true` | 1/1 ON, latente | perfil v. | `ACTIVE_PRODUCT` | Permite invitaciones de grupo si Mercado esta publicado | Depende de #21; desactivable por usuario; tests mercado |
| 24 | Acepta invitados / `market_open_to_guest` | perfil universal; `true` | 1/1 ON, latente | perfil v. | `ACTIVE_PRODUCT` | Permite invitaciones como invitado si Mercado esta publicado | Depende de #21 y contexto; restricciones sociales futuras pueden bloquear |
| 25 | Equipo retable / `pachanga_challengeable_team_profiles.enabled` | DB; `false` al no publicar | 2/3 ON | revision entidad | `ACTIVE_PRODUCT` | Publica equipo y habilita recepcion de retos | Admin de grupo, revision, cache; SQL/RLS Core Social |
| 26 | Partido publico / `pachanga_open_matches.active` | DB; lifecycle | 0/1 ON | source revision | `ACTIVE_PRODUCT` | Publica partido y permite solicitudes sujetas a aprobacion | Admin, plazas y revision; se desactiva por RPC; Core Social tests |
| 27 | Preferencia in-app / `in_app_enabled` | usuario/categoria; default `true` | 0 overrides | revision preferencia | `ACTIVE_PRODUCT` | Oculta avisos opcionales; los `mandatory_in_app` siempre aparecen | Sin backfill; RPC usuario; notification SQL/RLS |
| 28 | Preferencia push / `push_enabled` | usuario/categoria; default `false` | 0 overrides | revision preferencia | `READY_WITH_GUARDS` | Solicita push, pero #13 OFF impide entrega | Requiere canal/proveedor; no altera avisos obligatorios |
| 29 | Preferencia email / `email_enabled` | usuario/categoria; default `false` | 0 overrides | revision preferencia | `READY_WITH_GUARDS` | Solicita email, pero #14 OFF impide entrega | Requiere canal/proveedor; no altera in-app obligatorio |
| 30 | Definiciones de logro / `pachanga_achievement_definitions.active` | catalogo DB; `true` | 106/222 ON | version fila | `ACTIVE_PRODUCT` | Evaluadores allowlist y grants idempotentes | Solo eventos canónicos posteriores; desactivar fila detiene grants futuros |
| 31 | Reglas logro-caja / `pachanga_achievement_box_rules.active` | catalogo DB; `true` | 156/156 ON | economy/version | `ACTIVE_PRODUCT` | Convierte logro elegible en tipo de caja | Economia activa; sin barrido historico; tests catalogo/economia |
| 32 | Catalogo de cajas / `pachanga_reward_box_catalog.active` | DB; `true` | 5/5 ON | economy version | `ACTIVE_PRODUCT` | Tipos de caja y pool | Sin backfill; apertura autoritativa e idempotente |
| 33 | Pools de recompensa / `pachanga_reward_pool_catalog.active` | DB; `true` | 19/19 ON | economy version | `ACTIVE_PRODUCT` | Entradas ponderadas de premios | Economia versionada; no modificar en esta fase |
| 34 | Catalogo cosmetico / `pachanga_cosmetic_catalog.active` | DB; `true` | 89/89 ON | version fila | `ACTIVE_PRODUCT` | Assets elegibles de jugador/equipo | Player/Team Cosmetics; Premium Ball no esta en produccion |
| 35 | Mapping Team Reward / `pachanga_team_cosmetic_reward_mappings.active` | DB; `true` | 5/5 ON | policy v1 | `ACTIVE_PRODUCT` | Convierte cinco logros de equipo en cosmetics | Mappings congelados; ledger idempotente; no tocar economia |

## Valores productivos verificados antes de activacion

Consulta remota de solo lectura, sin PII:

```text
conduct platform revision: 1
attendance: false
conduct: false
social restrictions: false
triage enabled: false
triage shadow: true

player cosmetics: true, revision 1
team cosmetics: true, revision 1
team cosmetic rewards: true, revision 1
push channel: false
email channel: false
notification preference rows: 0
```

Los cinco mappings activos siguen exactamente iguales:

```text
team.external.clean_sheets.001 -> team.shield.effect.edge_glow
team.external.matches.010      -> team.shield.ornament.banner
team.external.wins.001         -> team.shield.border.copper
team.matches.025               -> team.shield.ornament.laurels
team.matches.050               -> team.shield.border.silver
```

Premium Ball tiene `0` filas de catalogo y `0` mappings en produccion. Ninguna de las 29 propuestas de Premium Art se ha convertido en reward o propiedad activa.

## Asistencia

### Autoridad y elegibilidad

- Solo owner/admin del grupo puede cerrar la plantilla de su propio partido.
- El actor debe estar autenticado; la identidad y participantes se resuelven en servidor.
- El partido debe estar `played`, `finalized` o `historical`, dentro de la ventana de 48 horas.
- La plantilla debe coincidir exactamente con los participantes canónicos, sin faltas ni duplicados.
- Estados: `played`, `excused_absence`, `late_cancellation`, `unexcused_no_show`.
- Un cambio normal `voy -> no` no se convierte en no-show. `unexcused_no_show` exige un `voy` previo y certificacion posterior.
- El cierre, respuesta, disputa, revision y correccion son revisionados, idempotentes y auditados con secuencia del servidor.
- Realtime publica solo el invalidator minimo de grupo; el cliente recarga el read model canónico.

### Falta de respuesta y disputa

- El jugador dispone de 72 horas para aceptar o disputar.
- La falta de respuesta puede confirmar un hecho no disputado, pero no aplica culpabilidad ni sancion.
- La revision humana puede mantener, corregir o escalar y conserva el estado original, actor, motivo y eventos.

### Efectos prohibidos

Las pruebas verifican:

```text
attendance event -> Rating/GRL/facets/reliability = 0 cambios
attendance event -> Season Score/TOPS = 0 cambios
attendance event -> achievements/rewards/cosmetics = 0 grants inesperados
attendance event -> billing = 0 mutaciones
attendance event -> automatic social restriction = 0
```

`unexcused_no_show` es un hecho privado. Dos o tres hechos pueden producir recordatorio o recomendacion de revision humana segun la politica experimental; nunca ban, restriccion, bajada de Rating o sancion automatica.

Readiness previa: `READY_FOR_ACTIVATION`. Clasificacion final tras instalar y probar `attendance_effective_from`: `ACTIVE_PRODUCT`.

## Conducta y reportes

### Alcance real del flag

`conduct_reports_enabled` gobierna la recepcion de nuevos reportes contextuales. No activa por si mismo restricciones sociales ni convierte triage en autoridad. Casos, evidencias, warnings y moderacion siguen siendo privados y humanos.

### Validaciones

- Actor autenticado y no auto-reporte.
- Objetivo registrado y relacion deportiva canónica: partido finalizado, reto aceptado con partido finalizado, partido publico finalizado o acceso invitado finalizado.
- Categoria allowlist: `abusive_behavior`, `harassment`, `threats_or_violence`, `discriminatory_behavior`, `deliberate_cheating`, `repeated_disruption`, `other`.
- El servidor resuelve identidades, grupo, contexto, revision, cluster y prioridad.
- Un `operationId` repetido devuelve el mismo recibo.
- Una opinion activa por evaluador, objetivo, contexto y categoria.
- RLS revoca las tablas privadas a `anon` y `authenticated`; las RPC no revelan identidad del denunciante.
- Realtime solo invalida el estado opaco del sujeto; no transmite texto, evidencia ni identidad.

### Fuentes y sanciones

El cluster se define por caso, equipo fuente, tipo y contexto. Por ello diez reportes del mismo equipo/contexto aumentan el recuento correlacionado, no diez fuentes independientes. Fuentes de equipos distintos pueden elevar prioridad de revision, nunca culpabilidad.

```text
1 reporte -> 0 sanciones automaticas
10 reportes correlacionados -> 0 sanciones automaticas
varias fuentes independientes -> prioridad humana posible -> 0 sanciones automaticas
```

El objetivo no ve identidad denunciante, informacion medica, evidencia privada ni texto interno. Los admins ordinarios de grupo tampoco obtienen esa identidad.

Readiness previa: `READY_WITH_GUARDS`. Clasificacion final tras `conduct_effective_from`, smoke privado y conservacion de la moderacion humana: `ACTIVE_PRODUCT`.

## Restricciones sociales y triage

Social Restrictions esta implementado para `public_market`, `send_challenges`, `receive_public_challenges`, `public_match_access` y `public_guest_access`. Requiere caso confirmado, flag independiente y accion explicita de un moderador de seguridad. Apelacion, correccion y expiracion conservan auditoria.

No puede cambiar Rating, GRL, facetas, historico deportivo, logros, Season Score o premios. Clasificacion: `READY_WITH_GUARDS`; decision de esta release: **OFF en staging final y produccion**.

Triage V1.1 clasifica en `record_only`, `watch`, `review`, `priority_review` y `urgent_review`. En sombra propone y mide; no sanciona, cierra, banea ni restringe. Clasificacion y estado final: **`SHADOW_ONLY`, `conduct_triage_enabled=false`, `conduct_triage_shadow_mode=true`**.

## Activacion no retroactiva

### Hueco encontrado

Con los flags OFF no existe procesamiento automatico. Sin embargo, al encenderlos, un actor autorizado podia intentar cerrar o reportar manualmente un contexto historico anterior a la activacion. Eso incumplia la frontera no retroactiva aunque no hubiera un job de backfill.

### Correccion forward-only

La migracion `20260812062731_production_feature_activation_v1.sql`:

1. Anade `attendance_effective_from` y `conduct_effective_from`.
2. La RPC administrativa fija fecha del servidor en cada transicion OFF -> ON.
3. Triggers privados rechazan cierres/reportes cuyo contexto deportivo sea anterior.
4. Si un flag esta ON sin frontera, falla cerrado.
5. Desactivar conserva evidencia; reactivar crea una frontera nueva.
6. El read model del Control Center expone clasificacion, readiness, dependencia y fecha efectiva.

La migracion no recorre partidos, reportes, notificaciones, ratings, rewards ni billing. No crea jobs y el proyecto no tiene `pg_cron` instalado.

### Zero-backfill local

Prueba con dataset historico y contadores antes/despues:

```text
flag OFF -> historial existente
activar por RPC -> revision monotona + frontera
0 cierres historicos
0 hechos historicos
0 eventos historicos
0 reportes historicos
0 casos historicos
0 notificaciones historicas
```

Los intentos manuales contra historia anterior son rechazados. Solo los contextos ocurridos despues de la frontera son elegibles.

## Staging

Estado previo remoto confirmado:

```text
revision: 3
attendance/conduct/restrictions/triage: false
triage shadow: true
closures/facts/events/reports/cases/warnings/restrictions/notifications: 0
```

Staging contiene una migracion historica adicional `20260810201451_team_shield_premium_3d_v1_catalog` y un fixture `team.shield.symbol.ball_premium` en catalogo/inventario, sin mapping ni reward ledger. No existe en repositorio vigente ni en produccion. Se documenta como divergencia de laboratorio y no se copia, activa ni elimina destructivamente en esta release.

La migracion quedo registrada como `20260812062731_production_feature_activation_v1`; el archivo del repositorio y todas sus referencias se alinearon a esa version antes de continuar. No se duplico ni reaplico SQL.

| Paso | Operacion | Revision | Frontera / resultado |
| --- | --- | ---: | --- |
| Attendance ON | `a8120000-0000-4000-8000-000000000001` | 3 -> 4 | `2026-08-12T06:30:11.441792Z` |
| Conduct ON | `a8120000-0000-4000-8000-000000000002` | 4 -> 5 | `2026-08-12T06:33:51.210587Z` |
| Social Restrictions ON, solo rehearsal | `a8120000-0000-4000-8000-000000000003` | 5 -> 6 | una restriccion `public_market` manual y sintetica |
| Social Restrictions OFF | `a8120000-0000-4000-8000-000000000004` | 6 -> 7 | medida corregida; gate final vacio |

Resultado Attendance:

- Activar el flag produjo `0` cierres, hechos, casos y avisos historicos.
- Un partido posterior a la frontera genero exactamente `played=1`, `excused_absence=1`, `late_cancellation=1` y `unexcused_no_show=1`.
- El replay devolvio el mismo recibo; hubo una disputa y una correccion. El hecho original se conserva y el resultado canonico termina como ausencia justificada.
- Se emitieron cuatro avisos esperados: no-show, cancelacion tardia, disputa y correccion; `0` fugas del texto privado.
- El estado Realtime avanzo a revision 3 y las tablas `pachanga_attendance_group_state`, `pachanga_conduct_subject_state` y `pachanga_user_notifications` estan publicadas.

Resultado Conduct:

- Activar el flag produjo `0` reportes, casos, restricciones y avisos historicos.
- El contexto anterior a la frontera fue rechazado. Tambien se rechazaron outsider, auto-reporte y duplicado; ninguno dejo recibo o caso parcial.
- Cuatro reportes validos crearon dos casos. El principal consolida `3` opiniones en `2` fuentes independientes y `1` correlacionada; el reciproco queda marcado `mutualRetaliation=true`.
- El denunciado no ve IDs ni evidencia. Un admin de grupo no puede leer evidencia; el rol interno de seguridad si puede reconstruir las tres identidades.
- Triage termino `enabled=false`, `shadow=true`, con dos recomendaciones `review`; warnings `0`, restricciones automaticas `0`.

Invariantes staging:

- El cohorte anterior a la frontera conserva los hashes iniciales: Rating snapshots `d41d8cd98f00b204e9800998ecf8427e`, achievements `6e216b3837ec3975a83f8f970d37a8a9` y rewards `45f10b09cb2d492d5bd2ebfa42dab53b`.
- Los fixtures nuevos activaron mecanismos ordinarios de alta y generaron 4 snapshots, 13 grants y 3 rewards propios. Se separaron por timestamp y no son efectos del cambio de flag.
- Los cinco mappings mantienen hash `f7ad71f1a8825a1dccbf5ec66ff2bc68`; billing de los 17 grupos preexistentes mantiene hash `0923bdbe8bbefe7cb5774a2c9b899c72`.
- Premium Ball sigue siendo el fixture historico de staging: una fila de catalogo, cero mappings.

Los fixtures `a812...` se conservan exclusivamente en staging como conjunto reproducible de QA. Estan aislados por IDs y timestamps, no contienen PII real y no deben copiarse ni recrearse en produccion. Su retirada no justifica una cascada destructiva sobre una base compartida.

Los invariantes, la regresion completa, Preview responsive y el diff final pasaron antes de marcar el PR ready.

## Rankings: estado exacto

Season Score V3 dispone de motor congelado y pruebas de integridad, diversidad y ataques. El ranking provincial dispone de piloto visual y readiness sintetico. Ninguno tiene fuente de verdad productiva.

Faltan: tablas/read model PostgreSQL, proceso idempotente de refresh/rebuild, ciclo de temporada, territorio canónico, elegibilidad, confidence e integridad persistidas, API privada/publica, UI productiva, cierre de temporada y ledger de premios. El plan detallado vive en `RANKING_PRODUCTIZATION_NEXT_STEPS.md`.

## Flags obsoletos y duplicados

- Obsoletos localizados: **0**. No se ha encontrado un gate definido sin consumidor real que pueda declararse muerto con evidencia.
- Duplicados destructivos: **0**.
- Solapamiento deliberado: `market_enabled` controla publicacion; `pachanga_market_profiles.active` es su proyeccion/lifecycle. No deben consolidarse porque uno es intencion del perfil y el otro read model canónico.
- Solapamiento deliberado: preferencia push/email y canal global son dos guardas acumulativas; ambas deben estar ON para entregar.
- `conduct_triage_enabled` y `conduct_triage_shadow_mode` son ortogonales: calculo operacional frente a modo sin autoridad.

## PWA, Realtime, rendimiento y privacidad

- Minimo cliente efectivo: `2.0.0`; el endpoint es `private, no-store`.
- Cliente sin version o inferior: lecturas disponibles, escrituras rechazadas con `CLIENT_UPDATE_REQUIRED`.
- Offline: las operaciones deportivas se rechazan como no confirmadas; solo la telemetria no-PII puede ponerse en cola.
- Service Worker: `updateViaCache: none`, pausa escrituras, espera las activas, `SKIP_WAITING` y una sola recarga tras `controllerchange`.
- Attendance y Conduct usan invalidadores Realtime minimos y recarga de read model; no anaden listeners a todas las paginas.
- No se cambia la version minima en esta release: el bridge actual ya conoce las RPC y el rechazo explicito.
- Tablas privadas sin grants directos; `anon` no ejecuta mutaciones; usuario, admin de grupo, moderador y platform owner conservan capacidades separadas.
- Ninguna key `service_role` tiene prefijo `NEXT_PUBLIC_` ni llega al bundle.

## Verificacion local completada

| Gate | Resultado actual |
| --- | --- |
| Instalacion vacia completa | PASS, 90 migraciones y `BOOTSTRAP_COMPLETE` |
| Regresion completa de producto | PASS: Rating V2, Core Social, invitados, Conduct, logros V2/V3, cajas, Player Cosmetics, Team Shield, Team Rewards, avisos, triage y Platform Control Center; SQL/RLS e idempotencia/concurrencia |
| Regresion umbral de no-show y disputas | PASS; filtro por usuario, un caso abierto por fuente, reminder deduplicado y cero restricciones automaticas |
| `npm test` | PASS: 20/20 estructurales y 242/242 TS/TSX |
| Typecheck | PASS |
| Build | PASS |
| Lint focalizado | PASS |
| Lint global | 43 problemas basales: 23 errores y 20 warnings; ninguno procede del diff |
| Synthetic World soak | PASS: 30 seeds, 35 dias/seed, 4.721 partidos, 309.193 eventos, 24.635 ms, 23,46 ms/dia virtual y 376,2 MB de pico |
| Platform Control Center volumen | PASS: 10.000 usuarios y 1.000 equipos, 0 locks en espera; pagina de usuarios 37,50/44,28 ms y equipos 9,34 ms frente a umbral 10.000 ms |
| PostgreSQL lint del alcance | PASS; desaparecen los dos errores de Attendance, con tres errores basales ajenos documentados |
| Supabase Security Advisors | Sin hallazgo nuevo atribuible a la migracion; staging 253 y produccion 248 avisos basales. Las cinco diferencias pertenecen a cuatro RPC historicas exclusivas de staging |
| Supabase Performance Advisors | Sin hallazgo nuevo atribuible a la migracion; staging 203 y produccion 210 avisos basales tras aplicarla. La diferencia son contadores `unused_index` dependientes de trafico/fixtures |
| Preview responsive | PASS publico: 1440x900, 390x844 y 844x390; cero overflow global, imagenes rotas o errores de consola en partido demo, perfil de conducta y reporte contextual |
| Preview PWA | PASS estructural/runtime: manifest `fullscreen` con fallbacks, Service Worker `2.0.0+sw.7e3a479fca38` activo, `sw.js` no-store y client policy `private, no-store` con minimo `2.0.0` |
| `git diff --check` | PASS en ultima ejecucion; se repetira al cierre |

Incidencia de entorno: el arranque completo de Supabase local intenta exponer el schema `simulation` antes de que exista, mientras el bootstrap productivo exige que ese schema no forme parte del producto. El bootstrap DB-only fue el camino limpio y completo. No es un fallo de la migracion ni se ha relajado el contrato para ocultarlo.

### Incidencias encontradas durante la regresion

`PFA-001` - `TESTABILITY_GAP` - fixture de cajas con claves cosmeticas legadas - **fixed + regression_verified**.

- Estado: corregido despues de registrarlo; regresion verificada.
- Esperado: la suite de cajas abre ejemplos de puntos, cosmetico, combinacion y duplicado contra el catalogo universal vigente.
- Actual: el fixture sellaba manualmente `symbol.ball` y `pattern.stripes`; el guard productivo rechazo correctamente la primera porque Player Cosmetics migro los pools a claves `player.*`.
- Impacto: solo la transaccion local de prueba; rollback completo, cero cambios de producto o datos.
- Correccion permitida: sustituir exclusivamente las dos claves del fixture por `player.frame.barrio.steel` y `player.background.asphalt_night`.
- Regresion: `test:collective-boxes:db` pasa completa con apertura, replay, duplicados, correccion y rollback; el catalogo y la economia no se modificaron.

`PFA-002` - `PRODUCT_BUG` - escalado de fiabilidad y disputa sin indice unico compatible - **fixed + regression_verified**.

- Estado: corregido despues de registrarlo; regresion verificada.
- Esperado: al alcanzar el umbral de no-shows confirmados o escalar una disputa se crea o actualiza un unico caso abierto, sin sancion automatica.
- Actual: Conduct Triage V1.1 retiro el indice parcial generico y dejo uno exclusivo de `conduct_report`; los dos `ON CONFLICT` de Attendance ya no tienen una restriccion compatible y fallan al alcanzar esas ramas.
- Impacto: bloquea la activacion de Attendance; no afecta datos mientras la bandera productiva siga OFF.
- Correccion: indices parciales separados para `attendance_reliability` y `attendance_dispute`, con predicados identicos a sus `ON CONFLICT`.
- Regresion: el tercer no-show confirmado crea un caso; una nueva evaluacion actualiza ese mismo caso. Dos disputas escaladas convergen tambien en un caso. En ambos recorridos permanecen cero restricciones automaticas.

`PFA-003` - `PRODUCT_BUG` - parametro ambiguo en el contador de fiabilidad - **fixed + regression_verified**.

- Estado: corregido despues de registrarlo; regresion verificada.
- Esperado: el contador de no-shows y bajas tardias filtra exclusivamente por el usuario objetivo resuelto por el servidor.
- Actual: `private.pachanga_evaluate_attendance_reliability_v1` compara `attendance.target_user_id = target_user_id`; PL/pgSQL no puede resolver de forma inequivoca parametro y columna.
- Impacto: la evaluacion puede abortar cuando un usuario acepta un hecho negativo o expira su ventana de disputa; no modifica Rating ni aplica sanciones por si sola.
- Correccion: copiar el parametro a `evaluated_user_id` y usar esa referencia inequivoca en todas las consultas y notificaciones.
- Regresion: cuatro no-shows confirmados de otro usuario no elevan al objetivo; solo su tercer no-show confirmado abre el caso. El reminder obligatorio queda deduplicado a una notificacion.

`PFA-004` - `TESTABILITY_GAP` - la regresion integrada de logros seguia invocando escrituras de escudo legado - **fixed + regression_verified**.

- Estado: registrado antes de corregir la prueba; regresion verificada sobre el bootstrap completo.
- Esperado: una instalacion final debe mantener revocadas `save_pachanga_team_crest_draft_v1` y `publish_pachanga_team_crest_v1`; el flujo productivo se prueba mediante `save_pachanga_team_shield_loadout_v1`.
- Actual: `tests/achievements-crests-db.sql` aun intentaba guardar y publicar con las RPC legado, por lo que el bootstrap completo respondio correctamente `permission denied`.
- Impacto: solo la regresion integrada; las ACL productivas son las esperadas y la nueva RPC autoritativa conserva permiso `authenticated`.
- Correccion: se sustituyo el recorrido de escritura legado por una asercion explicita de cierre y se mantuvo la cobertura funcional activa en `test:team-shield:db`.
- Regresion: `test:achievements-crests:db` pasa sobre las 90 migraciones y confirma simultaneamente RPC legado sin `EXECUTE` y RPC canonica alcanzable para `authenticated`.

`PFA-005` - `TESTABILITY_GAP` - la regresion V2 esperaba 60 logros colectivos despues de incorporar Team Rewards - **fixed + regression_verified**.

- Estado: registrado antes de corregir la prueba; regresion verificada sobre el bootstrap completo.
- Esperado: el catalogo final contiene las 60 definiciones colectivas V3 y el hito autoritativo adicional de 10 Retos, total `61`.
- Actual: `tests/achievement-catalog-v2-db.sql` seguia exigiendo exactamente `60`, aunque la suite V3 y la migracion Team Rewards ya definen `60 + 1`.
- Impacto: solo la regresion integrada; el bootstrap contiene las 61 filas activas esperadas y no hay grants retroactivos.
- Correccion: se alineo la asercion V2 con el contrato final `60 V3 + 1 Team Rewards`, sin modificar catalogo, economia ni datos.
- Regresion: `test:achievement-catalog:db` cuenta `61` definiciones colectivas activas y mantiene las 45 individuales V2.

`PFA-006` - `TESTABILITY_GAP` - la regresion V2 exigia una box rule incluso a logros V3 con componentes autoritativos - **fixed + regression_verified**.

- Estado: registrado antes de corregir la prueba; regresion verificada sobre el bootstrap completo.
- Esperado: cada logro colectivo resuelve su caja mediante `reward_components` ordenados o una `pachanga_achievement_box_rules` activa.
- Actual: la asercion solo aceptaba la segunda ruta; `team.external.matches.010` utiliza la primera y quedaba falsamente marcado como incompleto.
- Impacto: solo la regresion integrada; el sellado V3 ya consume componentes y Team Rewards prueba el desbloqueo exacto 9 -> 10 -> 11.
- Correccion: se comprueba la disyuncion canonica componentes/regla, manteniendo obligatorios rareza, animacion y presentacion.
- Regresion: `test:achievement-catalog:db` recorre grants, cajas, anulacion e invariantes Rating sin rechazar el componente V3 de 10 Retos.

`PFA-007` - `ENVIRONMENT_ISSUE` - Synthetic World se lanzo inicialmente contra el bootstrap productivo sin schema `simulation` - **fixed + regression_verified**.

- Estado: registrado antes de repetir la prueba en un schema local desechable.
- Esperado: el bootstrap productivo rechaza cualquier fuga de `simulation`; Synthetic World se ejecuta en su base local aislada.
- Actual: el primer comando reutilizo la URL del bootstrap limpio y fallo con `schema "simulation" does not exist` antes de generar datos.
- Impacto: ninguno sobre producto; la transaccion aborto y las 90 migraciones productivas permanecen limpias.
- Correccion: se instalo el schema de simulacion solo en el contenedor desechable, se ejecuto el contrato y se retiro con `DROP SCHEMA`; el ledger productivo termino con 90 migraciones y `simulation` ausente.
- Regresion: `test:synthetic-world:db` pasa RLS, guard interno, idempotencia, revision obsoleta y orden por `server_sequence`.

`PFA-008` - `ENVIRONMENT_ISSUE` - OAuth de Google no admite el dominio efimero de Preview - **closed for release by canonical-production QA**.

- Estado: registrado antes de cerrar la QA visual; no se cambio configuracion OAuth.
- Esperado: la Preview permite validar superficies publicas y el guard de sesion; la QA administrativa necesita un origen registrado.
- Actual: Google rechaza `https://pachangas-76cybzuou-persianas-almar-web-s-projects.vercel.app/auth/google` con `redirect_uri_mismatch`. `/admin`, `/admin/flags` y `/admin/conduct` responden correctamente con `Sesion necesaria`, sin fugas ni errores de consola.
- Impacto: impide la QA autenticada del Control Center en la URL efimera; no afecta `pachangasiq.com`, staging SQL/RLS ni la activacion por RPC.
- Cierre de release: la QA administrativa autenticada se completo en `pachangasiq.com/admin/flags` con el `platform_owner`; la UI mostro Attendance y Conduct activos, Social Restrictions OFF y Triage LAB/SHADOW.
- Regresion: rutas publicas afectadas pasan escritorio, portrait, landscape y PWA; tests de RBAC/API y read model pasan localmente, staging y dominio canonico. Una futura Preview autenticada sigue necesitando dominio de staging estable y callback Google registrado.

El linter PostgreSQL posterior ya no informa de `resolve_pachanga_attendance_review_v1` ni de `private.pachanga_evaluate_attendance_reliability_v1`. Conserva tres errores basales fuera del diff (`ensure_pachanga_external_team_authoritative_v2_impl`, `get_pachanga_global_rating_context_v2` y `open_pachanga_reward_box_v2`) y warnings historicos; no se han ocultado ni corregido dentro de esta activacion.

Los Advisors remotos se compararon por tipo, nivel, schema y objeto. La migracion no incorpora nuevas tablas ni RPC expuestas que aparezcan solo en staging. Las diferencias de seguridad son `create_pachanga_admin_invite`, `finalize_pachanga_match_if_current`, `patch_pachanga_match_player_paid` y `sync_pachanga_open_match`, todas procedentes de divergencias historicas de staging anteriores a esta rama. No se amplian ACL dentro de esta activacion. Referencias de remediacion: [Security Definer ejecutable](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS sin policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) e [indices no utilizados](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Preflight productivo y backup recuperable

- Proyecto confirmado: `qonbngfrnrqgmxbdfbea` (`Pachangas`), PostgreSQL 17.6, Pro, `ACTIVE_HEALTHY`.
- Backup fisico recuperable mas reciente: `2026-08-12T00:16:24Z`, visible en Dashboard con accion Restore. PITR no esta contratado.
- La ultima mutacion aplicativa localizada fue el alta del `platform_owner` a `2026-08-11T20:43:10.337474Z`, anterior al backup. Los unicos timestamps posteriores pertenecen a migraciones internas de Storage y refresco de sesion Auth; por tanto el backup contiene el estado de negocio y schema previos a esta activacion.
- Tamano DB: `31.804.563` bytes (~30 MB). En la inspeccion previa: CPU 3%, disco 20%, RAM 40% y 5/90 conexiones.
- Historial remoto antes de esta migracion: **89** entradas, desde `20260728051437_create_pachanga_groups` hasta `20260811172700_platform_control_center_overview_restriction_fix`. Coincide exactamente con las 89 migraciones de `main`; la nueva `20260812062731_production_feature_activation_v1` debe elevar el total a 90. No existe historial que reparar.
- Flags antes: Attendance OFF, Conduct OFF, Social Restrictions OFF, Triage OFF + shadow ON, revision global 1; Player Cosmetics ON revision 1; Team Cosmetics y Team Rewards ON revision 1.
- Estado historico antes: 0 cierres/eventos/revisiones de asistencia; 0 reportes/casos/eventos/warnings/restricciones/recibos de conducta; 32 notificaciones generales preexistentes.
- Invariantes antes, `filas/hash`: Rating snapshots `1/ce838b082d476871c05aa6df5cdf589c`; evidencia Rating `0/d41d8cd98f00b204e9800998ecf8427e`; perfiles `1/409014b9d4ddecb23cfd41600719ceda`; achievement grants `17/e18b5bba8bc92a1c129b6e8a07c7cda8`; reward grants `17/f8c950d847b867804d4b51b9cee70971`; inventario player `0/d41d8cd98f00b204e9800998ecf8427e`; inventario team `7/e5a3c62aa06218156930e31eab7cab7d`; mappings team `5/43ec6570d18b53b719152b81445a991e`; billing `11/f4d7dc5191a199d51dd9e32d520f74a4`.
- Los cinco mappings productivos coinciden exactamente con el contrato. Premium Ball mantiene 0 filas de catalogo, inventario, loadout, mapping y reward ledger.
- Realtime incluye `pachanga_attendance_group_state`, `pachanga_conduct_subject_state` y `pachanga_user_notifications`.

La migracion se aplico de forma atomica y el historial remoto paso de 89 a 90 entradas. El SQL almacenado para `20260812062731_production_feature_activation_v1` coincide exactamente con el archivo local (`md5 b74207ab78ad026618c5a1a235b33eb1`). Deployment, activacion escalonada, QA administrativa canonica y smoke productivo quedaron completados sin activar ningun gate no autorizado.

## Secuencia productiva ejecutada

1. Backup fisico `2026-08-12T00:16:24Z` y snapshot de migraciones, flags, hashes y contadores: PASS.
2. Migracion forward-only con flags aun OFF: PASS; revision 1.
3. Deployment del Control Center/read model actualizado: `READY`.
4. Attendance ON por RPC: revision 1 -> 2, `serverSequence=2`, frontera `2026-08-12T07:53:14.023506Z`.
5. Smoke Attendance: cero backfill, burst, 500, fuga RLS, Rating o reward inesperado.
6. Conduct ON por RPC: revision 2 -> 3, `serverSequence=3`, frontera `2026-08-12T07:56:33.639969Z`.
7. Smoke Conduct: cero casos historicos, sanciones, restricciones o mutaciones colaterales.
8. Estado final confirmado: Social Restrictions OFF, Triage OFF + shadow ON, rankings LAB, awards OFF y Premium Ball ausente.

## Estado de los documentos

- `PRODUCTION_FEATURE_ACTIVATION_AUDIT_V1.md`: este inventario y auditoria.
- `RANKING_PRODUCTIZATION_NEXT_STEPS.md`: plan de producto sin implementacion.
- `PRODUCTION_FEATURE_ACTIVATION_V1_RELEASE.md`: evidencia exacta del release y de las dos activaciones productivas.
