# Competition & Organizer Foundation V1 - Production Release

## Resultado

- Fecha de cierre: `2026-08-21`.
- Proyecto Supabase: `qonbngfrnrqgmxbdfbea`.
- Dominio: `https://pachangasiq.com`.
Estado final: `DEPLOYED / INACTIVE / READY FOR R2`

Esta release instala la infraestructura R1, pero no lanza Competiciones como
producto. Las tres flags permanecen apagadas, no existen entidades deportivas
R1 en produccion y no se ha ejecutado el backfill canonico.

| Componente | Estado |
| --- | --- |
| Competition Foundation | `DEPLOYED / INACTIVE` |
| Canonical Match schema | `INSTALADO` |
| Canonical Match backfill | `NO EJECUTADO` |
| League Engine | `NOT IMPLEMENTED` |
| Tournament Engine | `NOT IMPLEMENTED` |
| Club Foundation | `NOT IMPLEMENTED` |
| Referee Platform | `NOT IMPLEMENTED` |
| Competition Discipline | `NOT IMPLEMENTED` |

## Git y Pull Request

- `origin/main` inicial real: `0ea46f1cfa797a253678b68a3ffb8d7456856c81`.
- PR funcional: [#153](https://github.com/puntoracingrc/pachangas/pull/153).
- Rama: `codex/competition-organizer-foundation-v1`.
- HEAD funcional final: `113972558c99ac0d0c78fb276cd4c6c15d614314`.
- Base funcional: `0ea46f1cfa797a253678b68a3ffb8d7456856c81`.
- Estado inmediatamente anterior al merge: `OPEN`, `CLEAN`, `MERGEABLE`, Vercel `SUCCESS`.
- Divergencia funcional con `main`: ninguna; el diff final seguia limitado a las 27 rutas documentadas de R1.
- Metodo de merge: squash merge.
- Merge SHA y `main` funcional: `871128f637ed2cbc74b8fdbe78e8c7c6f311547d`.
- Tree SHA: `6caef31f9dbc2f3a5fe440da49c616f404ec1174`.
- Hora del merge: `2026-08-21T11:07:22Z`.

El checkout principal contenia trabajo ajeno y no se utilizo para implementar,
validar ni documentar R1. Todo el trabajo se hizo en worktrees aislados.

## Validacion Pre-release

Entorno: macOS, Node `v24.16.0`, Supabase CLI y PostgreSQL local. Los checks
finales del HEAD funcional fueron:

| Gate | Resultado |
| --- | --- |
| `npm ci` | PASS |
| `npm test` | PASS, `289/289` |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, 34 paginas |
| Lint focalizado R1 | PASS |
| Tests TypeScript focalizados | PASS, `15/15` |
| SQL/RLS | PASS |
| Idempotencia | PASS |
| Concurrencia | PASS |
| Bootstrap limpio | PASS, ledger `106` |
| Upgrade incremental | PASS, ledger `98 -> 106` |
| Escala | PASS |
| `git diff --check` | PASS |

El lint global mantiene 43 incidencias preexistentes y ninguna pertenece a las
rutas R1. No se modifico esa deuda en esta release.

## Staging

El proyecto `iozcjirlfytryzrcmrnq` termino con ledger `106`. El E2E autenticado
uso siete cuentas sinteticas y dos clientes e incluyo Realtime/refetch,
idempotencia, concurrencia, RBAC, transferencia de owner, freeze, expiracion y
revocacion. Las tres flags quedaron en `false`; las credenciales sinteticas se
rotaron al terminar.

## Backup y Preflight Productivo

- Backup fisico recuperable verificado: `2026-08-21 00:20:55 UTC`.
- PostgreSQL: `17.6.1.147`.
- Deployment anterior: `dpl_DukTQC4rToB6b9J6c3ozfD25SNMH`.
- SHA anterior desplegado: `0ea46f1cfa797a253678b68a3ffb8d7456856c81`.
- Ledger anterior: 98 filas; ultima migracion
  `20260820213930_ranking_productization_r8_idle_health`.
- Las ocho versiones R1 estaban ausentes.
- Tablas, flags, RPC y publicacion Realtime R1 estaban ausentes.

No se almacenaron contrasenas, tokens, `service_role` ni cadenas de conexion en
el repositorio.

## Migraciones

Las seis migraciones originales aplicadas en staging se conservaron sin editar,
renombrar ni reordenar. Dos fallos encontrados durante la validacion se
resolvieron con migraciones adicionales `forward-only`:

1. `20260821054224_competition_canonical_match_foundation_v1.sql`
2. `20260821054225_competition_organizer_core_v1.sql`
3. `20260821054227_competition_platform_access_v1.sql`
4. `20260821074741_competition_entitlement_clock_consistency_v1.sql`
5. `20260821075245_competition_realtime_rls_execution_v1.sql`
6. `20260821082136_competition_organizer_read_model_volatility_v1.sql`
7. `20260821101510_competition_platform_capabilities_preserve_ranking_v1.sql`
8. `20260821102613_competition_canonical_health_initialization_v1.sql`

La migracion 7 conserva `rankings.write` al ampliar capabilities. La migracion 8
distingue de forma explicita una instalacion sin backfill y evita el falso
estado verde `OK - 0 partidos`.

Cada migracion se aplico de forma secuencial dentro de una transaccion explicita,
con confirmacion del ledger antes de continuar. Los arrays de sentencias del
ledger remoto coinciden byte a byte con los archivos locales:

| Version | Sentencias | MD5 |
| --- | ---: | --- |
| `20260821054224` | 33 | `a82b53d1062225947c5c7e70a2d796fb` |
| `20260821054225` | 149 | `585cc09d667dd533d585e461374a733b` |
| `20260821054227` | 55 | `a74284e3b9d6d4dfaf3b285ab0ec89a8` |
| `20260821074741` | 6 | `30f9e50fc11cb5555c0bfc1c5332a11c` |
| `20260821075245` | 3 | `5f0106e668ffd5d3b494c54a07562ad4` |
| `20260821082136` | 2 | `766e15d3597ed7a893b7edc9728eab49` |
| `20260821101510` | 3 | `ff073c9422a98082eb9114f0efc8b490` |
| `20260821102613` | 8 | `dce77d7a10343ad4e15282014641614a` |

Ledger final: 106 filas; ultima migracion
`20260821102613_competition_canonical_health_initialization_v1`.

## Estado de Datos

Foundation settings final:

```text
foundation_enabled      = false
creation_enabled        = false
context_binding_enabled = false
revision                = 1
server_sequence         = 1
```

Canonical health final:

```text
status                   = NOT_INITIALIZED
initialized              = false
initialized_at           = null
canonical backfill events = 0
canonical matches        = 0
bindings                 = 0
binding reviews          = 0
contexts linked          = 0
sources detected         = 7
unbound sources          = 7
```

Los siete origenes existentes solo marcan el read model como pendiente/sucio;
no se transformaron ni se enlazaron. No se ejecuto `canonical.backfill`.

Conteos R1 finales:

| Entidad | Filas |
| --- | ---: |
| Foundation settings | 1 |
| Canonical health | 1 |
| Canonical matches | 0 |
| Canonical bindings | 0 |
| Binding reviews | 0 |
| Organizer states | 0 |
| Entitlement grants | 0 |
| Competitions | 0 |
| Editions | 0 |
| Rule sets / revisions | 0 / 0 |
| Stages / divisions / groups | 0 / 0 / 0 |
| Stage edges | 0 |
| Staff assignments | 0 |
| Match contexts | 0 |
| Realtime invalidations | 0 |
| Events / receipts | 0 / 0 |

Competition Entitlements schema esta instalado, pero los entitlements
comerciales no estan activos. Los grants de plataforma, suscripcion,
partnership y promocion son todos `0`. No se crearon productos, precios,
clientes ni suscripciones Stripe.

## Seguridad

- Todas las tablas publicas R1 tienen RLS activado.
- `anon` no tiene lectura ni escritura directa en ninguna tabla R1.
- `authenticated` no tiene escritura directa; tampoco lectura salvo el `SELECT`
  RLS-scoped de `pachanga_competition_invalidations` necesario para Realtime.
- Las tablas privadas no son accesibles por `anon` ni `authenticated`.
- `anon execute = 0` para todas las funciones R1 publicas y privadas.
- `authenticated` solo puede ejecutar las ocho RPC publicas previstas y el
  helper privado utilizado para evaluar la policy Realtime.
- Todas las funciones `SECURITY DEFINER` fijan `search_path`, resuelven
  `auth.uid()` en PostgreSQL y no aceptan un actor autoritativo desde cliente.
- Las mutaciones comprueban flag, entitlement, RBAC, revision esperada e
  idempotencia antes de persistir.
- El helper Realtime es ejecutable por `authenticated` solo durante la
  evaluacion RLS; `anon` no puede ejecutarlo.
- `pachanga_competition_invalidations` esta en `supabase_realtime` y permanece
  vacia.

Pruebas negativas de produccion, todas dentro de transaccion con rollback:

| Actor | Lectura global | Creacion |
| --- | --- | --- |
| Anonimo | denegada | denegada |
| Jugador normal | `Platform access required` | `COMPETITION_FOUNDATION_DISABLED` |
| Admin de equipo | `Platform access required` | `COMPETITION_FOUNDATION_DISABLED` |
| Owner sin entitlement | `Platform access required` | `COMPETITION_FOUNDATION_DISABLED` |

No quedo ninguna escritura de estas pruebas.

## Capabilities y Platform Owner

Los roles `platform_owner`, `platform_admin`, `moderator`, `support`, `finance`
y `ops` conservan sus capabilities anteriores. El unico cambio es
`competitions.read` y `competitions.manage` para los roles previstos. Se
comprobo expresamente que `rankings.write`, `billing.read`, `moderation.write`,
`flags.write` y `audit.read` no se perdieran.

La cuenta productiva existente `ece5365e...` conserva el rol activo
`platform_owner`. No se modifico el RBAC global.

## Checksums Antes y Despues

La misma consulta reproducible, sin PII, produjo exactamente los mismos valores
antes y despues de la instalacion:

| Dominio | Filas | Checksum |
| --- | ---: | --- |
| Achievements | 395 | `cded70d67b8da68cbe29d8f4979869f9` |
| Billing | 11 | `e26cfc3ea2448aa73dd3076d90570b97` |
| Conduct | 9 | `a141a6afaca86a23f9544dcbc922b834` |
| Participants | 4 | `b499832f697f535ff50ce808b882862d` |
| Player Cosmetics | 1 | `fcacb6bda2ae34da708fa9bb398df8c8` |
| Ranking | 19 | `5e48c6ee971009c8401bbc0446843bd3` |
| Rating V2 | 3 | `071b47449dec7fb26416f21a483a333a` |
| Results | 2 | `6eb5fcc8f46681ef22c56e61b1ad3d1d` |
| Rewards | 42 | `01f04a968e632f168bc1ace9e82a39f0` |
| Scorers | 4 | `a3708b7e119305c44a73788e2f215a2f` |
| Team Cosmetics | 41 | `c631b768e43e90d09d15fd6e7d386d63` |
| Facetas y reliability | 1 | `c7bb0ef049c38cec84622d2cbf48ef5f` |

Side effects antes/despues tambien identicos:

```text
conduct reports/warnings/cases/restrictions = 0/0/0/0
ranking receipts/snapshots/publications      = 6/0/1
reward box grants/recipients                 = 17/0
team reward ledger                           = 7
player points ledger                         = 0
Stripe webhook events                        = 0
team cosmetic inventory                      = 7
groups with subscription                     = 0
player cosmetic loadouts                     = 0
```

Por tanto, la release creo cero cajas, puntos, cosmeticos, rewards, reportes,
warnings, casos, restricciones, cambios de billing, snapshots de Season Score,
revisiones de ranking o grants inesperados.

## Team Cosmetic Rewards

Los cinco mappings permanecen exactamente iguales:

| Achievement | Cosmetic |
| --- | --- |
| `team.external.wins.001` | `team.shield.border.copper` |
| `team.external.matches.010` | `team.shield.ornament.banner` |
| `team.matches.025` | `team.shield.ornament.laurels` |
| `team.matches.050` | `team.shield.border.silver` |
| `team.external.clean_sheets.001` | `team.shield.effect.edge_glow` |

Mappings de Premium Ball activos: `0`.

## Deployment y PWA

- Deployment funcional: `dpl_6qvYfUdgQXwXTkXUTfZB5fpiEW3Y`.
- URL Vercel: `pachangas-gztd4g4l1-persianas-almar-web-s-projects.vercel.app`.
- Git SHA desplegado: `871128f637ed2cbc74b8fdbe78e8c7c6f311547d`.
- Estado: `READY`.
- Alias confirmado: `pachangasiq.com` y `www.pachangasiq.com`.
- Service Worker: `2.0.0+sw.871128f637ed`.
- Manifest: HTTP 200, `display: fullscreen` y fallbacks
  `standalone`, `minimal-ui`, `browser`.
- PWA simulada instalada a `390x844`: controlada por el Service Worker, scope
  raiz, manifest presente, cero overflow, cero imagenes rotas y cero errores.

Las escrituras R1 siguen clasificadas como operaciones protegidas y no existe
una cola offline que pueda mostrarlas como confirmadas.

## QA Productiva

La cuenta `platform_owner` cargo `/admin/competitions` con:

- flags OFF;
- 0 competiciones, editions, rules, entitlements, staff, bindings y reviews;
- Canonical Match `Pendiente de inicializacion`;
- 0 eventos;
- politica `private, no-cache, no-store`.

La API `/api/platform-admin/competitions` responde `401 ADMIN_ACCESS_DENIED` a
anonimo, sin datos parciales y con `no-store`. La ruta y API administrativas son
`noindex,nofollow`.

`/laboratorio-competition-foundation` permanece fuera de la navegacion publica,
con `noindex,nofollow`, las tres flags inactivas y el boton de creacion
deshabilitado. Su HTML prerender solo contiene la carcasa publica; cualquier
dato vivo continua protegido por auth/RPC.

Smoke de producto normal:

| Superficie | Resultado |
| --- | --- |
| `/` | PASS |
| Demo World | PASS |
| Equipo | PASS |
| Partido / alineacion / resultado / admin | PASS |
| Mercado jugadores / partidos / retos | PASS |
| Ranking | PASS |
| `/personalizar-carta` | PASS |
| `/equipo/identidad` | PASS |
| Avisos | PASS |

La matriz incluyo desktop `1440x900`, portrait `390x844`, landscape `844x390`
y PWA standalone. Resultado: cero overflow horizontal, cero imagenes rotas,
cero errores de consola y ningun CTA de Competiciones en navegacion publica.

## Advisors y Logs

Supabase Security devolvio 24 avisos R1:

- 15 `INFO` por tablas RLS cerradas sin policy directa;
- 8 `WARN` por RPC `SECURITY DEFINER` publicas con RBAC interno;
- 1 warning global sobre anonymous sign-ins en la policy de invalidaciones.

No se encontro una regresion critica de acceso. Referencias:

- [RLS enabled no policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
- [Authenticated security definer executable](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)

Supabase Performance devolvio 51 avisos R1: 38 foreign keys sin indice y 13
indices aun no usados. Con cero trafico y cero entidades R1 no se anadieron
indices especulativos. Referencias:

- [Unindexed foreign keys](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys)
- [Unused index](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)

Los logs de Supabase no contienen errores R1 en API ni Realtime. Tres consultas
diagnosticas del propio cierre asumieron inicialmente nombres de columnas/tablas
que no existian (`pachanga_platform_roles`, `subscription_status` y
`allow_repeat`); se corrigieron usando el schema real y no produjeron cambios.
Se clasifican como fallos de validacion, no de producto.

Vercel reporta cero runtime error clusters atribuibles al deployment. Los
accesos de QA generaron HTTP `200/304`; el `401` de la API administrativa fue la
prueba anonima esperada. Se observaron tres `503` del cron preexistente
`/api/internal/rankings/refresh`: responde deliberadamente
`RANKING_REFRESH_NOT_CONFIGURED` porque `CRON_SECRET` no esta configurado. No es
una regresion R1 y no se modifico en esta release.

## Rollback

Las flags ya estan apagadas. Ante un problema de frontend se debe revertir el
deployment de Vercel; ante un problema de acceso, mantener las rutas fail-closed
y corregir hacia delante. No se debe ejecutar una down migration destructiva,
borrar tablas ni eliminar historial. El schema aditivo puede permanecer
instalado con las flags en `false`.

## Cierre

Produccion fue modificada exclusivamente con:

1. Las ocho migraciones R1, incluidas las dos correcciones `forward-only`.
2. El codigo funcional del PR #153 desplegado desde `main`.
3. Este informe documental, sin cambios funcionales adicionales.

Estado final obligatorio:

```text
R1 schema/backend/frontend = DEPLOYED
R1 product                 = INACTIVE
R1 flags                   = OFF / OFF / OFF
R1 entities                = 0
Canonical backfill         = NO EJECUTADO
Ready for R2               = SI
```
