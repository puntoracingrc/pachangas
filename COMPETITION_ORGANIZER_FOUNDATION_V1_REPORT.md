# Competition & Organizer Foundation V1 Report

Estado: `READY FOR REVIEW`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Rama | `codex/competition-organizer-foundation-v1` |
| Base R1 / main posterior a R0 | `0ea46f1cfa797a253678b68a3ffb8d7456856c81` |
| R0 | PR #152 fusionado; tres documentos presentes en `origin/main` |
| Implementacion auditada | `47649d8` mas las correcciones y evidencias de cierre de este informe |
| PR R1 | [#153](https://github.com/puntoracingrc/pachangas/pull/153) |
| Inicio | `2026-08-21 07:39:27 CEST` |
| Entorno | Worktree Git aislado, Node 24, PostgreSQL/Supabase local y Supabase staging |
| Supabase staging | `iozcjirlfytryzrcmrnq` |
| Supabase produccion | `qonbngfrnrqgmxbdfbea`, no modificado |
| Merge R1 | No realizado |

El checkout principal contenia trabajo ajeno y no se utilizo para implementar
R1. El worktree R0 se retiro solo despues de merge, checks, ancestry y estado
limpio. Este worktree R1 se conservara mientras el PR no este fusionado.

## Alcance y limites

R1 implementa la autoridad de Competition, Edition, reglas versionadas,
estructura de stages, identidad canonica de partido, organizer TEAM,
entitlements, staff RBAC, receipts, eventos, read models, Realtime y las dos
superficies internas solicitadas.

Permanecen deliberadamente fuera: scheduler, jornadas, standings, plantillas,
convocatorias, arbitros, disciplina, resultados administrativos, League Engine,
Tournament Engine, sorteos, pagos, inscripciones economicas, premios,
Achievements y cosmeticos de competicion. Los estados de Edition dependientes
de esos motores devuelven `FEATURE_NOT_AVAILABLE`.

## Migraciones forward-only

| Version | Contenido |
| --- | --- |
| `20260821054224` | Canonical matches, bindings, reviews, restricciones y backfill base. |
| `20260821054225` | Competition/Edition/RuleSet/RuleRevision, stages, divisions, groups, graph, staff, contexts, receipts, events, invalidations y RPC organizer. |
| `20260821054227` | Acceso de plataforma, feature flags, entitlements, canonical commands, health materializado y Control Center read model. |
| `20260821074741` | Consistencia temporal de grants con una muestra de reloj autoritativa. |
| `20260821075245` | Permiso minimo del helper RLS para entrega Realtime autenticada; `anon` sigue revocado. |
| `20260821082136` | Volatilidad correcta del read model que resuelve entitlements temporales. |
| `20260821101510` | Compatibilidad de capabilities: conserva `rankings.write` y añade únicamente acceso R1 a owner/admin de plataforma. |
| `20260821102613` | Estado explícito de inicialización canónica; evita presentar un registro sin backfill como saludable. |

Las seis versiones originales estan aplicadas en staging y permanecen
inmutables. Las dos correcciones de release son migraciones forward-only nuevas.
El fresh bootstrap local contiene exactamente `106` migraciones y termina en
`20260821102613`; el ledger productivo previo contiene `98` y no incluye R1. La CLI
`supabase migration list --linked` no puede usar el perfil global de esta
maquina (`Unsupported Config Type ""`); la equivalencia se comprobo mediante
ledger local de la CLI y ledger remoto de la API de Supabase. No se reescribio
ninguna migracion ya aplicada.

## Entidades creadas

| Bloque | Entidades |
| --- | --- |
| Canonical | `pachanga_canonical_matches`, `pachanga_canonical_match_bindings`, `pachanga_canonical_match_binding_reviews` |
| Organizer | `pachanga_competition_organizer_states`, `pachanga_competition_entitlement_grants` |
| Competition | `pachanga_competitions`, `pachanga_competition_editions` |
| Rules | `pachanga_competition_rule_sets`, `pachanga_competition_rule_revisions` |
| Structure | `pachanga_competition_stages`, `pachanga_competition_divisions`, `pachanga_competition_groups`, `pachanga_competition_stage_edges` |
| Delegation/context | `pachanga_competition_staff_assignments`, `pachanga_competition_match_contexts` |
| Sync | `pachanga_competition_invalidations` |
| Private authority | foundation settings, operation receipts, events y canonical health materializado |

## Modelo funcional

### Competition y Edition

- `Competition` tiene identidad estable, nombre, slug, familia `LEAGUE` o
  `TOURNAMENT`, organizer TEAM, visibilidad, estado y revision.
- `CompetitionEdition` separa temporada/edicion, fechas, estado y revision.
- R1 permite operar `draft` y `cancelled`; el catalogo conserva los estados
  futuros, que no pueden activarse sin los motores posteriores.
- Crear una Competition requiere owner actual, entitlement vigente y ambos
  feature flags activos.

### Reglamento versionado

- `CompetitionRuleSet` es la familia logica.
- `CompetitionRuleRevision` guarda version, `competition_rules.v1`, documento
  tipado, checksum normalizado, vigencia, estado y `supersedes_revision_id`.
- El documento exige `format`, `registration`, `structure`, `results`,
  `operations`, `discipline`, `governance`, `publication` y
  `futureCapabilities`.
- Se validan tipos, rangos, referencias, grafo alcanzable y aciclico, y
  distincion entre restricciones duras y preferencias.
- Reordenar claves JSON produce el mismo checksum.
- Lifecycle probado: `draft -> validated -> published -> frozen`.
- Una revision frozen no se modifica; cualquier cambio requiere una revision
  nueva que preserve el historial.
- R1 no crea presets productivos.

### Estructura

- Stages: `SPLIT`, `LEAGUE_STAGE`, `GROUP_STAGE`, `KNOCKOUT`, `PLAYOFF`,
  `FINALS` y `CUSTOM`.
- Divisions y Groups se vinculan a Edition/Stage con orden y nivel conceptual.
- El grafo usa edges versionados, valida nodos/destinos y rechaza ciclos.
- No se inscriben equipos ni se generan partidos, avances o clasificaciones.

### Canonical Match

El detalle completo esta en `CANONICAL_MATCH_BINDING_V1_REPORT.md`. R1 enlaza
las cuatro procedencias reales (`GROUP_MATCH`, `OPEN_MATCH`, `EXTERNAL_MATCH`,
`TEAM_CHALLENGE`) sin duplicar el encuentro ni tocar sus datos deportivos.

### Organizer, entitlements y staff

El detalle completo esta en `COMPETITION_ENTITLEMENTS_V1_REPORT.md`. El unico
organizador habilitado es TEAM/`pachanga_groups`; CLUB queda como adaptador
futuro, sin tabla ficticia. El entitlement pertenece al grupo y el owner actual
conserva la autoridad ultima. Staff es una delegacion por Competition.

## Autoridad y API

### Command envelope

Todas las escrituras nuevas reciben `operationId`, `expectedRevision`, `action`,
`payload` y metadata cliente saneada. PostgreSQL resuelve actor, rol,
entitlement, estado, reglas, reloj y secuencia. No hay INSERT/UPDATE/DELETE
cliente sobre tablas R1.

RPCs publicas:

- `command_pachanga_competition_foundation_v1`;
- `command_pachanga_competition_platform_v1`;
- `get_my_pachanga_competition_foundation_v1`;
- `get_pachanga_competition_foundation_snapshot_v1`;
- `get_pachanga_competition_foundation_flags_v1`;
- `get_pachanga_platform_canonical_match_health_v1`;
- `get_pachanga_platform_canonical_match_v1`;
- `get_pachanga_platform_competition_foundation_v1`.

Comandos organizer probados: create/cancel Competition, create/cancel Edition,
create RuleSet/RuleRevision, validate/publish/freeze revision, assign rule,
create Stage/edge/Division/Group y grant/revoke staff. Comandos de plataforma
probados: flags, entitlement grant/revoke, canonical backfill/bind/review y
CompetitionMatchContext bind.

El mismo actor, operationId y payload devuelve el mismo receipt. El operationId
reutilizado con otro payload falla `PT409`; una revision obsoleta falla
`STALE_REVISION`. Los eventos y receipts usan secuencia monotona del servidor y
orden estable, no la hora del dispositivo.

## Read models, PWA y Realtime

- Organizer read model: competiciones propias, ediciones, reglas, estructura,
  staff y estado del entitlement.
- Platform read model: competiciones, organizer, grants, staff, revisiones,
  health canonico, eventos y errores agregados.
- El health canonico permanece `NOT_INITIALIZED` hasta que un
  `canonical.backfill` confirmado por servidor marque su inicializacion; una
  instalacion vacia ya no puede mostrarse como un falso estado saludable.
- El laboratorio conserva solo read models derivados en cache local.
- Offline permite un borrador visual, nunca una Competition confirmada ni una
  cola deportiva.
- Las nuevas operaciones estan clasificadas como escrituras protegidas por el
  bridge PWA.
- Realtime entrega una invalidacion RLS-scoped; el cliente invalida la entidad y
  vuelve a solicitar el snapshot canonico. No aplica el payload WAL como estado.
- El E2E usa dos clientes autenticados y demuestra invalidacion + refetch
  convergente.

## UI interna

| Ruta | Acceso | Funcion |
| --- | --- | --- |
| `/laboratorio-competition-foundation` | Usuario autenticado y flags/autoridad R1 | Recorrer el flujo de foundation sin presentar una pantalla publica de torneo. |
| `/admin/competitions` | Platform role con capability | Salud canonica, Competition, organizers, grants, rules, staff, eventos y errores. |

Ambas rutas usan el contrato visual vigente, son `noindex,nofollow` y no estan
en la navegacion publica. La API de Control Center reutiliza la autoridad de
plataforma existente.

## Validacion local

| Gate | Resultado |
| --- | --- |
| Tests focalizados TypeScript | PASS, `15/15` |
| SQL/RLS story | PASS, `23` eventos y `23` receipts; lifecycle, RBAC, RLS, idempotencia e invariantes |
| Concurrencia | PASS, un ganador + un stale; replay converge; revision final `3` |
| Fresh bootstrap | PASS, `106` migraciones desde baseline `20260731080738` hasta `20260821102613` |
| Synthetic World / escala | PASS, 1.000 equipos, 10.000 bindings, 500 competitions y 100 publicaciones |
| `npm test` | PASS, `289/289`, incluido build integrado |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, `34` paginas y ambas rutas R1 |
| ESLint focalizado | PASS, `0` incidencias en 11 rutas TS/TSX/MJS modificadas |
| ESLint global | FAIL historico, `43` incidencias (`23` errores, `20` warnings), ninguna en rutas R1 |
| DB lint R1 | PASS, `0` warnings funcionales R1 tras la migracion de volatilidad |
| `git diff --check` | PASS |

## Preview y responsive

Preview funcional auditada: `pachangas-2y0mhbnx8-persianas-almar-web-s-projects.vercel.app`, deployment
`dpl_BJ9ZGVB73fGvzYz6x4Jcwii6x975`, correspondiente a `c3da2e2`.

Matriz sobre `/`, `/laboratorio-competition-foundation` y
`/admin/competitions`:

| Modo | Viewport | Resultado |
| --- | --- | --- |
| Desktop | `1440x900` | PASS |
| Desktop wide | `1920x1080` | PASS |
| Portrait | `390x844` | PASS |
| Portrait small | `360x800` | PASS |
| Landscape | `844x390` | PASS |
| PWA standalone | `390x844` | PASS |

Resultado consolidado: `0` overflow horizontal, `0` imagenes rotas, `0`
controles fixed/sticky fuera del viewport, `0` errores de consola y `0`
peticiones fallidas. El laboratorio y Control Center conservan
`noindex,nofollow` y muestran un gate claro sin sesion. La experiencia interna
autenticada completa se valido localmente; la autoridad se valido con actores
autenticados en staging, mientras Preview permanece fail-closed frente al
entorno productivo no migrado.

En la emulacion PWA, `matchMedia('(display-mode: standalone)')` y
`data-display-mode` devolvieron `standalone`; manifest y Service Worker
respondieron `200`, el manifest declara `fullscreen` y el worker quedo
registrado.

## Rendimiento

| Medicion | p50 | p95 |
| --- | ---: | ---: |
| Binding lookup | `0.299 ms` | `0.500 ms` |
| Organizer read model | `172.776 ms` | `298.482 ms` |
| Admin competitions | `12.661 ms` | `16.825 ms` |
| Rule publish | `1.449 ms` | `2.099 ms` |

La prueba produjo 100 receipts y 100 eventos de publicacion. Los planes usan
`pachanga_canonical_match_active_source_idx` y
`pachanga_competitions_organizer_idx`; los indices del dominio medido ocupan
`3.407.872 bytes` en la base local inicializada.

Advisors remotos R1: 24 avisos de seguridad documentados (15 tablas privadas
RLS sin policy general, 8 RPC security-definer con RBAC interno, 1 configuracion
global de anonymous sign-ins) y 41 de rendimiento (38 FKs no indexadas, 3
indices aun sin uso). Ninguno abre acceso directo; el ensayo de volumen no
justifica indices especulativos.

## Staging autenticado

Historia completa ejecutada con siete usuarios sinteticos y dos grupos:

```text
Owner A + entitlement
  -> Competition draft
  -> Edition 2026/27
  -> RuleSet + RuleRevision
  -> validate + publish + freeze
  -> Split + stage edge + Division + Group
  -> staff grant/revoke
  -> canonical context bind
```

Negativos demostrados: Admin A no crea, Jugador A no crea, Owner B sin grant no
crea, expiry/revocation bloquean, staff de A no accede a B, frozen no muta,
operationId conflictivo falla y revision concurrente produce un unico ganador.

Lectura final:

- flags restaurados a `OFF`, revision `21`;
- grants fixture activos `0`;
- staff fixture activo `0`;
- owner del Grupo A restaurado;
- health no stale, revision `38`, server sequence `312`;
- 48 bindings, 26 canonical matches, 1 context, 1 fuente no vinculada, 1 review
  ambigua, 0 conflictos duplicados y 0 canonical huerfanos;
- Realtime invalidation recibida por el segundo cliente y seguida de refetch.

## Invariantes fuera de alcance

Comparacion exacta staging antes/despues:

| Dominio | Filas | Checksum |
| --- | ---: | --- |
| Billing no fixture | `26` | `b8cb702490514e5d37f6d17a0caf5b24` |
| Conduct | `4` | `6f90fc444c9c44aff1851550127aa506` |
| Ranking | `923` | `621af0cdffc36bf10607f081f6c94722` |
| Results | `21` | `67c001f371ac3e32afff06e7d21c67f4` |
| Rewards | `52` | `602b0a35e102fd0aaf564f3b07395579` |
| Scorers | `0` | `d41d8cd98f00b204e9800998ecf8427e` |
| Achievements | `122` | `f5324cc1403b827af66e650d074eed1e` |
| Participants | `12` | `4eabde3485377e8f9c9c6806f410439a` |
| Rating evidence | `0` | `d41d8cd98f00b204e9800998ecf8427e` |
| Rating profiles | `88` | `97706544cff2595599366b83ed9bf198` |
| Rating snapshots | `55` | `445caa672f7b67856d8fced29f6f4eb9` |

R1 produjo `0` reports/cases/warnings/restrictions, `0` productos/precios Stripe,
`0` suscripciones, `0` cambios de billing, `0` Season Score/ranking grants y no
modifico Demo World, Player Cosmetics ni Team Cosmetics.

## Registro permanente de incidencias

Cada fallo se registro antes de corregirse. Ninguno se oculto para continuar.

| ID | Clase | Escenario original | Resolucion | Regresion |
| --- | --- | --- | --- | --- |
| R1-VAL-001 | `PRODUCT_BUG` | Health recalculaba 10.000 fuentes en cada lectura. | `fixed`: snapshot materializado e invalidacion. | `regression_verified`: admin p95 final `16.825 ms`. |
| R1-VAL-002 | `SIMULATION_BUG` | Escala media un indice como `authenticated` pese a estar revocado. | `fixed`: medicion interna separada. | `regression_verified`: lookup p95 final `0.500 ms`, ACL cerrada. |
| R1-VAL-003 | `SIMULATION_BUG` | Fixture `validated` no incluia `effective_from`. | `fixed`: fixture conforme al contrato. | `regression_verified`: 100 publicaciones. |
| R1-VAL-004 | `PRODUCT_BUG` | Avisos flotante solapaba el laboratorio en portrait. | `fixed`: oculto solo en la superficie R1. | `regression_verified`: 390x844, 360x800 y standalone. |
| R1-VAL-005 | `PRODUCT_BUG` | Control Center leia claves health inexistentes. | `fixed`: contrato canonico exacto. | `regression_verified`: tests y QA visual. |
| R1-VAL-006 | `PRODUCT_BUG` | `canonical.bind` tenia variables ambiguas con columnas SQL. | `fixed`: variables `target_source_*`. | `regression_verified`: DB story y bootstrap. |
| R1-VAL-007 | `SIMULATION_BUG` | Fixture escribia `auth.users.confirmed_at` generado. | `fixed`: campo retirado. | `regression_verified`: rollback completo, 0 residuos. |
| R1-VAL-008 | `SIMULATION_BUG` | Fixture escribia `auth.identities.email` generado. | `fixed`: campo retirado. | `regression_verified`: rollback completo, 0 residuos. |
| R1-VAL-009 | `SIMULATION_BUG` | Fixture dejo `auth.users.email_change=NULL` y GoTrue no podia leerlo. | `fixed`: siete cuentas normalizadas. | `regression_verified`: login HTTP autenticado completo. |
| R1-VAL-010 | `ENVIRONMENT_ISSUE` | Signup publico de fixture choco con dominio y rate limit de correo. | `fixed`: fixtures sinteticos acotados. | `regression_verified`: sin usuarios parciales ni cambio Auth. |
| R1-VAL-011 | `SIMULATION_BUG` | Diagnostico Auth mezclo `LIMIT/UNION` con sintaxis invalida. | `fixed`: CTEs separados. | `regression_verified`: comparacion fixture/control. |
| R1-VAL-012 | `SIMULATION_BUG` | UPDATE de fixtures devolvia `email` ambiguo. | `fixed`: alias explicitos. | `regression_verified`: exactamente 7 usuarios actualizados y autenticados. |
| R1-VAL-013 | `SIMULATION_BUG` | Orquestador interpreto mal el wrapper `keys`. | `fixed`: forma normalizada. | `regression_verified`: login E2E. |
| R1-VAL-014 | `SIMULATION_BUG` | `node -e` con saltos escapados volcaba el script en stderr. | `fixed`: invocacion sin credenciales en salida. | `regression_verified`: E2E sanitizado; nunca hubo service_role cliente. |
| R1-VAL-015 | `SIMULATION_BUG` | Diagnostico supuso una tabla de roles inexistente. | `fixed`: autoridad de plataforma real. | `regression_verified`: platform admin comprobado. |
| R1-VAL-016 | `PRODUCT_BUG` | Grant inmediato se veia programado por dos relojes distintos. | `fixed`: migracion `20260821074741`. | `regression_verified`: receipt devuelve `canCreate=true`. |
| R1-VAL-017 | `ENVIRONMENT_ISSUE` | `supabase migration new` fallo por perfil global invalido. | `fixed`: HOME aislado para CLI local. | `regression_verified`: migracion forward-only creada/listada. |
| R1-VAL-018 | `SIMULATION_BUG` | E2E esperaba `22023`, contrato devuelve `PT409`. | `fixed`: asercion alineada. | `regression_verified`: conflicto idempotente remoto. |
| R1-VAL-019 | `PRODUCT_BUG` | Realtime no podia ejecutar helper RLS. | `fixed`: migracion `20260821075245`. | `regression_verified`: evento + refetch; anon denegado. |
| R1-VAL-020 | `SIMULATION_BUG` | Diagnostico ordenaba invalidaciones por `id` inexistente. | `fixed`: server sequence + claves estables. | `regression_verified`: lectura remota consistente. |
| R1-VAL-021 | `SIMULATION_BUG` | Test ACL confundia comentario/REVOKE con GRANT a anon. | `fixed`: regex sobre concesion real. | `regression_verified`: 15/15 focales. |
| R1-VAL-022 | `SIMULATION_BUG` | Consulta de invariantes uso tablas supuestas. | `fixed`: misma consulta exacta del baseline. | `regression_verified`: checksums identicos. |
| R1-VAL-023 | `TESTABILITY_GAP` | Staging no tenia OPEN_MATCH para probar link exacto ni huerfano. | `fixed`: dos fixtures deportivos sinteticos minimos. | `regression_verified`: mismo canonical + review sin fusion + replay. |
| R1-VAL-024 | `SIMULATION_BUG` | Repeticion intentaba crear segundo context activo. | `fixed`: reutiliza contexto persistido. | `regression_verified`: unicidad conservada. |
| R1-VAL-025 | `SIMULATION_BUG` | Ejecucion interrumpida dejo staff fixture activo. | `fixed`: normalizacion por RPC antes/despues. | `regression_verified`: 0 staff activo, historia intacta. |
| R1-VAL-026 | `SIMULATION_BUG` | Owner transfer fijaba revision 0 en reintento. | `fixed`: lee revision canonica antes del CAS. | `regression_verified`: transferencia y retorno. |
| R1-VAL-027 | `ENVIRONMENT_ISSUE` | `migration list --linked` no funciona con el perfil CLI global. | `mitigated`: ledger API remoto + CLI local exactos. | `regression_verified_by_equivalent`: 104 versiones iguales; comando enlazado sigue indisponible. |
| R1-VAL-028 | `PRODUCT_BUG` | Read model `STABLE` invocaba resolver temporal `VOLATILE`. | `fixed`: migracion `20260821082136`. | `regression_verified`: lint DB R1 sin warnings funcionales. |
| R1-VAL-029 | `SIMULATION_BUG` | Wrapper zsh uso la variable reservada `status`. | `fixed`: variable `rc`. | `regression_verified`: fresh bootstrap sale 0. |
| R1-VAL-030 | `SIMULATION_BUG` | Diagnostico de password uso window function en `RETURNING`. | `fixed`: UPDATE mediante CTE. | `regression_verified`: exactamente siete fixtures, sin datos ajenos. |
| R1-VAL-031 | `SIMULATION_BUG` | Replay de `canonical.bind` no fijaba el canonical conocido. | `fixed`: fixture canonico estable. | `regression_verified`: replay converge al mismo ID. |
| R1-VAL-032 | `TESTABILITY_GAP` | `SUBSCRIBED` podia preceder la inicializacion de replicacion del tenant. | `fixed`: cola unica y probe de entitlement antes del evento objetivo. | `regression_verified`: E2E Realtime completo. |
| R1-VAL-033 | `SIMULATION_BUG` | Diagnostico invoco helper RLS con aridad incorrecta. | `fixed`: tres argumentos reales. | `regression_verified`: publication activa, authenticated si, anon no. |
| R1-VAL-034 | `ENVIRONMENT_ISSUE` | Tras reanudar la sesion, el primer gate SQL no heredo `COMPETITION_FOUNDATION_DATABASE_URL` y `psql` intento el socket 5432. | `fixed`: URL local explicita del contenedor R1 en cada comando. | `regression_verified`: SQL/RLS, concurrencia y escala salen 0; no hubo escritura remota. |
| R1-VAL-035 | `TESTABILITY_GAP` | El navegador integrado acepto `Emulation.setEmulatedMedia`, pero no activo `display-mode: standalone`; su raw CDP tampoco permite inyectar el init script. | `fixed`: auditor headless temporal con el mismo patron CDP del repositorio y perfil aislado. | `regression_verified`: standalone emulado en runtime, manifest/SW 200 y registrados, 0 errores/overflow. |
| R1-VAL-036 | `PRODUCT_BUG` | La migracion de acceso R1 partia de una matriz anterior a Ranking Productization y retiraba `rankings.write` a owner/admin. | `fixed`: migracion forward-only `20260821101510`, sin editar las seis ya aplicadas. | `regression_verified`: upgrade productivo simulado y SQL comprueban matriz anterior mas solo `competitions.read/manage`. |
| R1-VAL-037 | `PRODUCT_BUG` | El refresh de instalacion dejaba health `stale=false` y el Control Center mostraba `Canonico` sin haber ejecutado backfill. | `fixed`: migracion `20260821102613` con estado `NOT_INITIALIZED` y UI explicita. | `regression_verified`: bootstrap, upgrade incremental y receipt del primer backfill. |
| R1-VAL-038 | `SIMULATION_BUG` | Un `supabase db reset` generico no aplico migraciones porque el producto desactiva deliberadamente el cargador automatico. | `fixed`: uso del bootstrap guardado oficial del repositorio. | `regression_verified`: ledger fresco exacto `106/106`. |
| R1-VAL-039 | `SIMULATION_BUG` | La primera asercion nueva intento leer un helper privado bajo `authenticated`. | `fixed`: la prueba usa la RPC publica protegida del platform owner. | `regression_verified`: SQL/RLS completo y schema `private` sigue denegado. |

## Entrega 1-73

| # | Entrega | Resultado |
| ---: | --- | --- |
| 1 | Estado #152 | Fusionado, solo tres documentos R0. |
| 2 | Main posterior R0 | `0ea46f1c...` |
| 3 | Rama R1 | `codex/competition-organizer-foundation-v1` |
| 4 | PR R1 | #153, sin merge. |
| 5 | HEAD final | Se comunica en la entrega tras el commit documental de cierre. |
| 6 | Migraciones | Seis originales inmutables y dos correcciones forward-only de release. |
| 7 | Tablas/entidades | Inventario en este informe. |
| 8 | Canonical Match | Implementado y probado. |
| 9 | Binding | Implementado, unico e idempotente. |
| 10 | Procedencias | Cuatro autoridades auditadas. |
| 11 | Backfill staging | Ejecutado dos veces. |
| 12 | Ambiguedades | Registradas sin fusion. |
| 13 | Competition | Implementada. |
| 14 | Edition | Implementada. |
| 15 | RuleSet | Implementado. |
| 16 | RuleRevision | Implementada. |
| 17 | Rule schema | `competition_rules.v1`. |
| 18 | Checksum | Determinista sobre JSON normalizado. |
| 19 | Rule lifecycle | Draft/validate/publish/freeze probado. |
| 20 | Inmutabilidad | Frozen protegido. |
| 21 | Stage | Implementado. |
| 22 | Split | Representado por Stage. |
| 23 | Division | Implementada. |
| 24 | Group | Implementado. |
| 25 | Stage graph | Implementado, validado y aciclico. |
| 26 | MatchContext | Vinculado en staging. |
| 27 | Organizer R1 | TEAM/`pachanga_groups`. |
| 28 | Futuro Club | Contrato extensible, sin entidad ficticia. |
| 29 | Entitlement | Organizacional y versionado. |
| 30 | Sources | Cuatro soportados; solo platform_grant usado. |
| 31 | Owner-only | Verificado. |
| 32 | Admin rejection | Verificado. |
| 33 | Owner transfer | Verificado y revertido. |
| 34 | Expiry | Verificado. |
| 35 | Revocation | Verificado, historia preservada. |
| 36 | Staff roles | Cinco roles del contrato. |
| 37 | RBAC | Matriz local y staging. |
| 38 | RPC/API | Dos comandos y seis lecturas. |
| 39 | operationId | Obligatorio e idempotente. |
| 40 | expectedRevision | Obligatoria; stale rechazado. |
| 41 | Receipts | Privados, inmutables. |
| 42 | Events/audit | Secuencia de servidor. |
| 43 | RLS | Directo cerrado; lecturas scoped. |
| 44 | Realtime | Invalidacion + refetch probado. |
| 45 | PWA | Escrituras protegidas; sin fake success offline. |
| 46 | Feature flags | Staging restaurado OFF; produccion intacta. |
| 47 | Organizer read model | Implementado y medido. |
| 48 | Platform read model | Implementado y medido. |
| 49 | `/admin/competitions` | Implementado, interno. |
| 50 | Laboratorio | Implementado, noindex/nofollow. |
| 51 | Bootstrap | 106 migraciones, PASS. |
| 52 | SQL/RLS | PASS. |
| 53 | Concurrencia | PASS. |
| 54 | Synthetic World | PASS aislado. |
| 55 | Scale | 10k/1k/500. |
| 56 | Performance | p50/p95 registrados. |
| 57 | Advisors | Revisados, deuda R1 explicada. |
| 58 | Responsive | PASS en seis modos/viewports. |
| 59 | Rating | Checksum identico. |
| 60 | Results | Checksum identico. |
| 61 | Rewards | Checksum identico. |
| 62 | Conduct | 0 cambios R1. |
| 63 | Billing | 0 cambios R1. |
| 64 | Ranking | 0 cambios R1. |
| 65 | Build | PASS. |
| 66 | Typecheck | PASS. |
| 67 | Tests | 289/289 PASS. |
| 68 | Lint focalizado | PASS; lint global historico documentado. |
| 69 | Preview | PASS; deployment y matriz documentados. |
| 70 | Staging | E2E autenticado PASS. |
| 71 | Produccion | **NO modificada**. |
| 72 | Merge R1 | **NO realizado**. |
| 73 | Worktree | Conservado mientras #153 siga sin fusionar. |

## Conclusion

R1 cumple el criterio de exito y queda `READY FOR REVIEW`. El PR permanece sin
merge, los flags productivos siguen inactivos, no se ejecuto backfill productivo
y el worktree se conserva porque #153 sigue abierto.
