# Official UI V3C - Simple Team Challenges

Fecha de cierre: 2026-09-01 (Europe/Madrid)

## Resultado ejecutivo

Official UI V3C queda fusionada y verificada en produccion. Retos se presenta como un flujo social sencillo: elegir rival, proponer fecha y campo, responder o contraproponer, acordar el partido y abrir la experiencia V3B. No se ha creado ninguna autoridad deportiva nueva ni se ha modificado Supabase, Stripe, Rating, resultados o competiciones.

Durante la verificacion final se reprodujo un defecto Demo-only: despues de enviar una contrapropuesta propia, Inicio podia seguir mostrando el reto como pendiente de respuesta. Se corrigio en el PR #246, se anadio regresion y se repitio el recorrido en Preview y produccion.

## Versiones y release

| Evidencia | Resultado |
| --- | --- |
| Main inicial | `258c3556ecf63aeb1de484c5408a652b1a4066f9` |
| PR funcional | [#245](https://github.com/puntoracingrc/pachangas/pull/245) |
| Commits funcionales | `63df4907115bb723d6844dc687825e5bcdbe64c5`, `3d12edb301a3223dfdce4a202de04663b158e4d6` |
| Merge funcional | `f4d747080b0831bd66f95b8caa2f9944335ee347` |
| PR hotfix | [#246](https://github.com/puntoracingrc/pachangas/pull/246) |
| Commit hotfix | `6ab31b2c44c63b1dbedf7f796046bda570321050` |
| Main funcional final | `c2a4b897a38728473d134f202a8ec40eecab6095` |
| PR documental | #247 |
| Produccion | [pachangasiq.com](https://pachangasiq.com) |
| Deployment funcional | `pachangas-gy4jn9e3m-persianas-almar-web-s-projects.vercel.app` |
| Deployment funcional final | `pachangas-mclfnlj9g-persianas-almar-web-s-projects.vercel.app` |
| Deployment documental | Vercel despliega automaticamente cada merge documental de `main`; la URL y el SHA final se incluyen en la entrega de cierre. |
| Service Worker | `2.0.0+sw.<12 primeros caracteres del SHA desplegado>`; el build funcional fue `2.0.0+sw.c2a4b897a387`. |

El PR documental no cambia runtime. El SHA definitivo de `main` tras fusionarlo queda registrado en GitHub y en la entrega final de la tarea.

## Cierre de los 48 puntos

| # | Punto | Estado y evidencia |
| ---: | --- | --- |
| 1 | Main inicial | `258c3556ecf63aeb1de484c5408a652b1a4066f9`. |
| 2 | Main final | Main funcional: `c2a4b897a38728473d134f202a8ec40eecab6095`; el PR documental solo agrega este informe. |
| 3 | PR funcional | #245, fusionado. |
| 4 | PR documental | #247, dedicado exclusivamente al informe. |
| 5 | Deployment | Deployment funcional y deployment documental READY; dominio productivo verificado despues de ambos. |
| 6 | Service Worker | Se deriva de cada SHA desplegado, precachea `/retos`, admite `SKIP_WAITING` y mantiene las escrituras fuera de cache. |
| 7 | Navegacion anterior | Recibidos, Enviados e Historial actuaban como vistas principales y el contexto tecnico ocupaba la superficie. |
| 8 | Navegacion final | Solo Activos e Historial; Todos, Recibidos y Enviados son filtros compactos dentro de Activos. |
| 9 | Activos | Agrupa respuesta necesaria, espera del rival y partidos acordados; oculta grupos vacios. |
| 10 | Historial | Lista compacta de estados terminales sin mezclar acciones vivas. |
| 11 | Necesitan respuesta | Se deriva del snapshot canonico y de `lastProposedBy`; muestra una accion primaria coherente. |
| 12 | Esperando rival | Una propuesta propia queda en espera y no se presenta como accion pendiente en Inicio. |
| 13 | Partidos acordados | Los retos aceptados siguen en Activos y ofrecen `Ver partido`. |
| 14 | Wizard tres pasos | Rival, propuesta y revision; el envio real solo ocurre al confirmar el tercer paso. |
| 15 | Rivales conocidos | Hasta cinco rivales recientes en el primer paso; seleccionar solo preselecciona. |
| 16 | Codigo de equipo | Busqueda canonica exacta y accion discreta para copiar o compartir el codigo propio. |
| 17 | Deep link desde Mercado | `/retos?view=active&crear=1&rival=<teamCode>` abre el wizard y preselecciona sin enviar. |
| 18 | Contrapropuesta | Distingue propuesta actual y cambios; usa `respond_pachanga_team_challenge_authoritative` con `propose_changes`. |
| 19 | Aceptacion | Espera snapshot confirmado, mueve a acordados y permite abrir el partido. |
| 20 | Rechazo | Accion secundaria/destructiva con confirmacion y sin inventar campos. |
| 21 | Cancelacion | Solo para propuestas salientes permitidas, con confirmacion e historial preservado. |
| 22 | Error mapper | Traduce stale revision, permisos, red, estado, rival y servicio a copy de producto; no muestra PostgREST ni IDs. |
| 23 | Permisos por rol | Owner/admin gestionan; player consulta; el servidor sigue siendo la autoridad real. |
| 24 | Jugador read-only | Demo y producto ocultan controles de mutacion al jugador ordinario. |
| 25 | Sin equipo | Estado propio con Crear equipo, Unirme y Ver partidos abiertos. |
| 26 | Detalle | Rival, estado, propuesta y siguiente accion sin revisiones, operationId, JSON o Auth IDs. |
| 27 | Enlace a Partido V3B | Reutiliza `ExternalResultsPanel` y la experiencia V3B; no crea otro Match. |
| 28 | Inicio | Muestra como maximo una accion: responder si procede o abrir el partido acordado. Hotfix #246 cubre la contrapropuesta propia. |
| 29 | Realtime | Invalida, agrupa y relee snapshot canonico; el payload WAL nunca se aplica como autoridad. |
| 30 | PWA | Manifest y Service Worker comprobados; `/retos` queda disponible como shell de lectura. QA fisica instalada sigue PENDING. |
| 31 | Offline | Lecturas cacheadas disponibles; crear, aceptar, rechazar, cancelar o contraproponer fallan cerradas sin fake success ni cola deportiva. |
| 32 | Demo social | Recorrido local de recibir, aceptar, contraproponer, cambiar perspectiva, acordar, crear, cancelar e ir a Historial. |
| 33 | Remote writes | `0`; tambien `externalNotifications = 0`, `realEntities = 0` y `StripeCalls = 0`. |
| 34 | Responsive | Verificado en 360x800, 390x844, 667x375, 740x360, 844x390, 932x430, 1440x900 y 1920x1080. Sin overflow raiz ni imagenes rotas. |
| 35 | Landscape | Rail, detalle, wizard y acciones conservan composicion de juego; sin doble navegacion ni footer invasivo. |
| 36 | Accesibilidad | Semantica, nombres de acciones, estados, foco, `aria-current`, `aria-pressed`, reduced motion y controles de 40 px cubiertos. Cero violaciones criticas/serias introducidas. |
| 37 | Tests | `742/742`: Node `20/20`; TS/TSX `722/722`; skipped/todo/cancelled `0/0/0`. Baseline declarado: `726/726`; V3C incorpora 16 pruebas TS/TSX. |
| 38 | Typecheck | PASS, `tsc --noEmit --incremental false`. |
| 39 | Build | PASS con Next.js 16.3.3; 70 paginas estaticas generadas. |
| 40 | Lint | Focal V3C: 0 errores y 0 warnings. Global: 0 errores y 2 warnings preexistentes en `app/page.tsx` (`groupOptionLabel`, `deleteCurrentTeam`); V3C no anade warnings. |
| 41 | Supabase | Sin cambios: 0 migraciones, 0 RPC, RLS y flags intactos; no se ejecuto `db push`, repair ni escritura QA. |
| 42 | Stripe | Sin acceso ni cambios; 0 Customers, 0 Checkout y 0 pagos. |
| 43 | Entidades reales utilizadas | `0`. Todas las historias usan datos sinteticos o estado local Demo. |
| 44 | Notificaciones reales | `0`. |
| 45 | Runtime errors | `0` en la QA navegada; logs Vercel finales sin warnings ni errores. |
| 46 | Cleanup | Tres Preview V3C retiradas; temporales y procesos cerrados. Worktree y ramas se retiran tras fusionar este informe y confirmar ancestro/estado limpio. |
| 47 | Wave 9C iniciada | NO. |
| 48 | V3D iniciada | NO. |

## Contrato conservado

- `TeamChallengesPanel`, `TeamSocialSnapshot`, las RPC existentes, `operationId`, `expectedRevision`, idempotencia, Realtime y `ExternalResultsPanel` siguen siendo las unicas piezas autoritativas del flujo.
- El cliente envia intenciones, espera la respuesta canonica y descarta cualquier previsualizacion ante error.
- La Demo solo modifica estado de sesion y no puede escribir en remoto.
- No se ha cambiado Rating V2, Team Rewards, Player Cosmetics, Team Cosmetics, resultados, asistencia, pagos ni motores de competicion.

## QA de produccion

- Retos: Activos, Historial, recibido, enviado, contrapropuesta, acordado, jugador read-only y sin equipo.
- Navegacion: Inicio -> Responder, Mercado -> Retar y Reto -> Partido V3B.
- Regresion final: Cobalto envia una contrapropuesta a Vertice, vuelve a Inicio y ya no ve el falso `Pendiente de ti`; el siguiente CTA es el partido acordado con Carboni.
- 1920x1080: `rootScrollWidth = rootClientWidth = 1920`, 0 imagenes rotas. Los unicos controles fuera del viewport pertenecen al carrusel horizontal intencional del historial.
- Service Worker productivo: `/retos` en precache y rutas cacheables, `SKIP_WAITING` presente. Readbacks observados: `sw.c2a4b897a387` tras el hotfix y `sw.545c0f867830` tras el PR documental; cada merge posterior deriva su version del nuevo SHA por diseno.
- Android fisico: PENDING.
- iPhone fisico: PENDING.
- PWA instalada fisica: PENDING.

## Matriz final

| Criterio | Resultado |
| --- | --- |
| Retos sencillo | SI |
| Activos/Historial | SI |
| Acordados visibles en Activos | SI |
| Crear Reto en 3 pasos | SI |
| Contrapropuesta clara | SI |
| Una accion principal por tarjeta | SI |
| Contexto de equipo sin duplicar | SI |
| Revision tecnica oculta | SI |
| Jugador read-only | SI |
| Admin oculto al jugador | SI |
| Mercado -> Retar | SI |
| Reto -> Partido V3B | SI |
| Modo juego horizontal preservado | SI |
| Demo actualizada | SI |
| Remote Demo writes | 0 |
| Supabase modificado | NO |
| Stripe tocado | NO |
| Entidades reales utilizadas | 0 |
| Tests | 742/742 |
| Lint errores | 0 |
| Lint warnings | 2 preexistentes / 0 V3C |
| Todo funcional fusionado | SI |
| Todo funcional desplegado | SI |

## Estado final

V3C queda en produccion como un flujo centrado en jugar:

`elige rival -> propone dia y campo -> envia -> acepta o contrapropone -> partido acordado -> jugar`

No se inicia Wave 9C ni Official UI V3D.
