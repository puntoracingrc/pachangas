# Official UI V2 - Production Release

## Estado

- Fecha UTC: `2026-08-22`.
- Autorizacion: `RELEASE`, emitida expresamente por Alberto.
- Visual approval: `APPROVED BY PRODUCT OWNER`.
- Resultado: `OFFICIAL UI V2 PRODUCTION RELEASED`.
- Produccion: <https://pachangasiq.com>.
- Supabase modificado por esta release: **NO**.
- R3 activado: **NO**.
- Canonical backfill ejecutado: **NO**.
- R4 iniciado: **NO**.

La aprobacion visual no equivale a una prueba fisica:

- Android physical QA: `PENDING - WAIVED FOR RELEASE`.
- iPhone physical QA: `PENDING - WAIVED FOR RELEASE`.

## Alcance y Git

| Evidencia | Valor |
| --- | --- |
| `origin/main` inicial real | `0d8ceecd2e24016cf11a3dd6d4bf959c2611fbfa` |
| PR funcional | [#158](https://github.com/puntoracingrc/pachangas/pull/158) |
| HEAD visual autorizado | `5f3333b7d781e876e73e90b224f0781dcf452b26` |
| HEAD final de la rama | `cacd05b71aaf53cce3fa9453186303dbdfd6f021` |
| Avance de `main` antes del merge | Ninguno; seguia en el SHA conocido |
| Metodo de merge | squash |
| Merge SHA de #158 | `05a245024ffacbbaaf85b719cfabfc4231a0b4db` |
| Hotfix reproducible | [#160](https://github.com/puntoracingrc/pachangas/pull/160) |
| HEAD del hotfix | `4f136e73aa70acade923ed0e9f8e95b96feb7635` |
| Merge SHA tras hotfix | `a3a820f653f649afd4575f62cf80811879626870` |
| PR documental | [#161](https://github.com/puntoracingrc/pachangas/pull/161) |

El unico ajuste posterior a la aprobacion fue un defecto objetivo de contraste:
tres valores de acceso al grupo se renderizaban con texto casi blanco sobre
fondo blanco. El hotfix cambio exclusivamente `app/globals.css` y su regresion
en `tests/official-ui-v2.test.ts`. No introdujo ningun rediseño adicional.

El diff acumulado hasta `a3a820f` contiene 160 rutas. La inspeccion confirma:

- rutas `supabase/`: 0;
- migraciones, SQL, RPC y RLS: 0;
- cambios de flags: 0;
- secretos o credenciales: 0;
- project refs de staging hardcodeados en runtime: 0;
- cambios en los contratos autoritativos de Rating, Conduct, Rewards o
  Cosmetics: 0.

Las dos referencias de staging localizadas pertenecen a documentacion historica
y no forman parte del runtime.

## Validacion automatizada

Sobre el Release Candidate de #158:

- `npm ci`: PASS, 522 paquetes;
- Node: `20/20`;
- TSX: `342/342`;
- total: `362/362`;
- Official UI V2: `6/6`;
- R3: `18/18`;
- integracion R3: `10/10`;
- Rendered HTML: `9/9`;
- PWA: `14/14`;
- Demo/Synthetic World focal: `22/22`;
- `npm run typecheck`: PASS;
- `npm run build`: PASS;
- lint focalizado: 0 incidencias;
- `git diff --check`: PASS;
- skipped/todo/cancelled nuevos: 0.

Despues del hotfix #160 se repitio la bateria completa:

- Node: `20/20`;
- TSX: `343/343`;
- total: `363/363`;
- typecheck: PASS;
- build: PASS;
- lint focalizado: 0;
- `git diff --check`: PASS.

El lint global conserva 43 incidencias preexistentes (23 errores y 20
warnings) en `app/legal-data.tsx`, `app/page.tsx`, `app/mercado/page.tsx` y
`app/theme-toggle.tsx`. La release no las incremento. `npm ci` informo 21
vulnerabilidades heredadas (1 low, 4 moderate y 16 high), no introducidas por
esta release.

## Preview y QA visual previa

Preview exacta del HEAD final de #158:

- deployment: `dpl_8XcYMjMTHXDePyPPqnYQqaGife12`;
- URL: <https://pachangas-edxvqpw9o-persianas-almar-web-s-projects.vercel.app>;
- estado: `READY`.

Se validaron 19 superficies en tres viewports: `1440x900`, `390x844` y
`844x390`. Resultado: `57/57` comprobaciones limpias, con 0 overflow raiz, 0
controles recortados, 0 imagenes rotas y 0 errores o warnings de consola.

Las superficies incluyeron Inicio, Partido, Proximo, Alineacion, Resultado,
Admin de partido, Mercado, Ranking, Avisos, Carta, Escudo, Control Center,
Demo World y las superficies de Referee Platform. Tambien pasaron las muestras
de alto riesgo en `360x800`, `667x375` y `932x430`.

En `844x390`, `667x375` y `932x430` se confirmo
`MOBILE_GAME_LANDSCAPE`: HUD movil, sin footer, sin sidebar de escritorio
comprimida, sin doble navegacion y con acciones visibles. Un desktop no tactil
de `960x600` permanecio en modo desktop. El giro portrait-landscape-portrait
conservo ruta, tab, filtros y seleccion de Mercado.

## Deployments y rollback

Rollback capturado antes del merge:

| Evidencia | Valor |
| --- | --- |
| `main` anterior | `0d8ceecd2e24016cf11a3dd6d4bf959c2611fbfa` |
| deployment anterior | `dpl_Dz8vjkiZnzngmThmCzmxSWxxC1pS` |
| URL anterior | `pachangas-khxqk64h8-persianas-almar-web-s-projects.vercel.app` |
| READY | `2026-08-22T04:44:18Z` |
| Service Worker anterior | `2.0.0+sw.0d8ceecd2e24` |
| captura del rollback | `2026-08-22T12:12:41Z` |

Deployment inicial de Official UI V2:

- deployment: `dpl_7exn8PeFgxEhCCVfAiMw4o3PgVat`;
- main: `05a245024ffacbbaaf85b719cfabfc4231a0b4db`;
- READY: `2026-08-22T12:33:19Z`;
- Service Worker: `2.0.0+sw.05a245024ffa`.

Deployment final tras el hotfix:

- deployment: `dpl_Htoy4jZGBxcvSVv11zZCaT77YdKi`;
- URL: `pachangas-nhuvtsq7j-persianas-almar-web-s-projects.vercel.app`;
- main: `a3a820f653f649afd4575f62cf80811879626870`;
- READY: `2026-08-22T13:09:09Z`;
- aliases: `pachangasiq.com` y `www.pachangasiq.com`;
- Service Worker: `2.0.0+sw.a3a820f653f6`.

Rollback ejecutado: **NO**. El unico defecto encontrado era acotado,
reproducible y ya existia en el deployment anterior; se corrigio con #160.

## QA productiva

### Anonima

- `/`, `/mercado`, `/demo`, `/admin` y `/perfil/arbitro`: sin exposicion de
  email o telefono;
- `/admin`: gate de sesion correcto;
- `/perfil/arbitro`: gate seguro y `noindex`;
- `/arbitros/arbitro-inexistente`: ficha cerrada, sin datos y `noindex`;
- `/mercado?tab=arbitros`: vuelve a una pestaña valida y no muestra Arbitros;
- `/laboratorio-referee-platform`: laboratorio visual `noindex`, sin escritura;
- warning tecnico de Google Places: ausente;
- errores, warnings de consola e imagenes rotas: 0.

### Autenticada

Con una sesion autorizada de `platform_owner`, sin escrituras deportivas, se
comprobaron Inicio, Partido, Proximo, Alineacion, Resultado, Admin de partido,
Mercado, Ranking, Avisos, Carta, Escudo y Control Center.

- navegacion activa con `aria-current=page`;
- submenus de Partido correctos;
- drawer movil cerrado no enfocable;
- permisos de Platform Admin preservados;
- 0 overflow, controles recortados, imagenes rotas o errores runtime;
- las tres metricas del grupo reparadas tienen fondo `rgb(20, 33, 29)` y texto
  `rgb(241, 246, 242)` en produccion.

La matriz autenticada paso en `390x844`, `360x800`, `667x375`, `844x390` y
`932x430`. Los tres viewports apaisados activaron modo juego y ocultaron el
footer. El giro de Mercado conservo los filtros `Martes`, `futbol7` y la tab
Jugadores.

### Demo World y R3

- `/demo` funciona online, offline, portrait y landscape;
- Demo World permanece separado del estado oficial y no realiza escrituras;
- R3 esta desplegado pero sus seis flags siguen apagados;
- Mercado no muestra Arbitros;
- los perfiles y slugs arbitrales quedan tras gates seguros;
- no se creo ninguna peticion, perfil, relacion ni assignment R3.

## PWA

- manifest: HTTP 200, `display=fullscreen` y fallbacks `standalone`,
  `minimal-ui`, `browser`;
- Service Worker: HTTP 200, control activo y `updateViaCache=none`;
- offline: `/demo` se sirve desde cache sin pantalla blanca, exito falso ni
  mezcla de bundles;
- reconexion: `/api/client-policy` vuelve a 200 con
  `private, no-store, max-age=0, must-revalidate`;
- cliente sin version: `CLIENT_UPDATE_REQUIRED`, conservando lecturas;
- una PWA anterior real en Chrome actualizo desde
  `2.0.0+sw.013167572598` a la version Official UI, espero operaciones activas,
  ejecuto una unica recarga controlada y elimino la cache antigua;
- tras #160 actualizo de nuevo a `2.0.0+sw.a3a820f653f6`, con una sola cache,
  sin worker en espera, bucle ni error.

Esta evidencia corresponde a navegador/PWA instalada en macOS, no a un
dispositivo Android o iPhone fisico.

## Supabase pre/post

Las comprobaciones fueron estrictamente de lectura sobre el proyecto Pachangas
`qonbngfrnrqgmxbdfbea`. No se uso `apply_migration`, DDL, DML ni cambios de
configuracion.

- ledger remoto previo: 113;
- ledger remoto posterior: 113;
- migraciones locales: 113;
- ultima migracion local/remota:
  `20260821182107_referee_platform_access_v1`;
- repositorio y remoto: alineados.

| Flags | Pre | Post |
| --- | --- | --- |
| R1 foundation / creation / context binding | `false / false / false` | `false / false / false` |
| R2 foundation / self-service / team relationships / public profiles / organizer | todos `false` | todos `false` |
| R3 foundation / self-service / public profiles / marketplace / club relationships / assignments | todos `false` | todos `false` |

R1, R2 y R3 mantienen `revision=1` y `serverSequence=1`. Todos los conteos R1 y
R2 siguen en cero. Los conteos R3 posteriores son:

| Entidad R3 | Filas |
| --- | ---: |
| Profiles | 0 |
| Marketplace listings | 0 |
| Club-Referee relationships | 0 |
| Invitations | 0 |
| Invitation secrets | 0 |
| Assignments | 0 |
| Statistics snapshots | 0 |
| Events / receipts / invalidations | 0 / 0 / 0 |
| Modalities / service areas | 0 / 0 |
| Availability windows / exceptions | 0 / 0 |

Canonical Match permanece:

- estado `NOT_INITIALIZED`;
- `initialized=false`, `initializedAt=null`;
- `dirty=true`;
- revision 3, server sequence 4;
- canonical matches 0;
- bindings 0;
- binding reviews 0;
- `canonical.backfill` events 0.

Supabase modificado por esta release: **NO**.

## Invariantes

El diff no toca `supabase/` ni las fuentes autoritativas de Rating V2,
assessments, Conduct, Team Cosmetic Rewards, Player Cosmetics o Team Shield
Cosmetics. Las cinco asignaciones Team Cosmetic Rewards permanecen exactamente:

1. `team.external.wins.001` -> `team.shield.border.copper`;
2. `team.external.matches.010` -> `team.shield.ornament.banner`;
3. `team.matches.025` -> `team.shield.ornament.laurels`;
4. `team.matches.050` -> `team.shield.border.silver`;
5. `team.external.clean_sheets.001` -> `team.shield.effect.edge_glow`.

Premium Ball sigue inactivo. Ninguna de las propuestas del laboratorio Premium
Art se convirtio en reward, propiedad o catalogo activo.

Permanecen intactos: Rating V2, facetas, fiabilidad, partidos, resultados,
participantes, Attendance, Conduct, Achievements, Rewards, Player Cosmetics,
Team Cosmetics, Team Reward mappings, Billing, Season Score, Ranking,
Competition, Clubs, Canonical Match y los datos de Referee Platform.

## Logs e incidencias

- clusters runtime atribuibles a Official UI V2: 0;
- warnings/error/fatal del deployment final: 0;
- hydration, chunk, Service Worker, imagen y permission errors atribuibles: 0.

Se observo `GET /api/internal/rankings/refresh` con HTTP 503 por
`RANKING_REFRESH_NOT_CONFIGURED`: falta `CRON_SECRET` en el entorno. La misma
respuesta aparece cada cinco minutos tanto en el deployment anterior como en
el de #158, por lo que es una incidencia de entorno preexistente, sin impacto
en la UI de esta release. No se modifico el entorno ni se oculto la deuda; debe
resolverse en una tarea autorizada separada.

## QA fisica pendiente

- Android physical QA: `PENDING - WAIVED FOR RELEASE`.
- iPhone physical QA: `PENDING - WAIVED FOR RELEASE`.

La checklist de dispositivo real permanece abierta para portrait, landscape,
giro, teclado, safe areas, instalacion PWA y actualizacion del Service Worker.
No se declara `PHYSICAL QA PASSED`.

## Estado final

| Componente | Estado |
| --- | --- |
| Official UI V2 | `LIVE / ACTIVE` |
| Demo World | `LIVE / SHOWCASE` |
| R3 Referee Platform | `DEPLOYED / INACTIVE` |
| R2 Club Foundation | `DEPLOYED / INACTIVE` |
| R1 Competition Foundation | `DEPLOYED / INACTIVE` |
| Canonical Match | `NOT_INITIALIZED` |
| Physical Android QA | `PENDING / WAIVED` |
| Physical iPhone QA | `PENDING / WAIVED` |
| R4 League Engine | `NOT STARTED` |

Produccion fue modificada exclusivamente mediante codigo/UI. Supabase y los
datos deportivos no fueron modificados. Official UI V2 queda activa y lista
para el siguiente bloque del roadbook.
