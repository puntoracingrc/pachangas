# Official UI V3D - Clean Location-First Marketplace

Fecha de cierre: 2026-09-01 (Europe/Madrid)

## Resultado ejecutivo

Official UI V3D queda fusionada y verificada en produccion. Mercado deja de
presentarse como una superficie administrativa extensa y pasa a un flujo social
directo: elegir zona, encontrar un partido, jugador o equipo, abrir un detalle y
solicitar, invitar o preparar un reto.

La release conserva las autoridades existentes de V3A, V3B y V3C. No se ha
modificado Supabase, RLS, Auth, RPC, flags, Stripe, Rating, Rewards ni ningun
motor deportivo. Las historias mutables de QA se ejecutaron solo en Demo local;
no se crearon entidades reales ni se enviaron notificaciones.

## Versiones y release

| Evidencia | Resultado |
| --- | --- |
| Main inicial | `188264d93e24c5ad8b80bae61335d4302891dc3a` |
| PR funcional | [#249](https://github.com/puntoracingrc/pachangas/pull/249) |
| Commit funcional | `ae6988412500336356b343a146c481b2b89d8662` |
| Merge funcional | `a5797761480b2a06110f88a796e66f7946060bb1` |
| Main funcional final | `a5797761480b2a06110f88a796e66f7946060bb1` |
| PR documental | [#250](https://github.com/puntoracingrc/pachangas/pull/250) |
| Preview exacta | `pachangas-asrqts2z8-persianas-almar-web-s-projects.vercel.app` |
| Deployment productivo | `dpl_2m82qyUe47d1UT7oJMUM7FKkPzrs` |
| URL inmutable productiva | `pachangas-oaz5c555m-persianas-almar-web-s-projects.vercel.app` |
| Dominio | [pachangasiq.com](https://pachangasiq.com) |
| Service Worker | `2.0.0+sw.a5797761480b` |

El PR documental no cambia runtime. El SHA definitivo de `main` despues de
fusionarlo queda registrado por GitHub y en la entrega final de esta tarea.

## Mercado anterior y Mercado final

Antes, Mercado combinaba navegacion, busqueda, configuracion y detalle en una
superficie de alta densidad, con un rail de escritorio de 176 px y demasiado
contenido permanente. La accion relevante variaba de posicion y el cambio desde
otras secciones se percibia como un salto de formato.

Ahora la pantalla comparte el shell oficial y contiene solamente:

1. cabecera compacta;
2. Partidos, Jugadores y Equipos;
3. ubicacion principal;
4. filtros rapidos y hoja avanzada contextual;
5. contador y orden;
6. tarjetas compactas;
7. hoja de detalle con una accion primaria.

Partidos es la pestaña predeterminada. El rail administrativo de escritorio se
ha eliminado; el rail reducido solo aparece en landscape tactil, donde forma
parte del modo juego existente.

## Cierre de los 57 puntos

| # | Punto | Estado y evidencia |
| ---: | --- | --- |
| 1 | Main inicial | `188264d93e24c5ad8b80bae61335d4302891dc3a`. |
| 2 | Main final | Main funcional `a5797761480b2a06110f88a796e66f7946060bb1`; #250 solo agrega este informe. |
| 3 | PR funcional | #249, fusionado sin hotfix. |
| 4 | PR documental | #250, dedicado exclusivamente al informe. |
| 5 | Deployment | `dpl_2m82qyUe47d1UT7oJMUM7FKkPzrs`, READY, aliases productivos confirmados. |
| 6 | Service Worker | `2.0.0+sw.a5797761480b`; `/mercado` esta en precache y rutas navegables. |
| 7 | Mercado anterior | Rail grande y mezcla de busqueda, configuracion y detalle permanente. |
| 8 | Mercado final | Flujo location-first compacto y coherente con el shell oficial. |
| 9 | Shell | Navegacion V3A conservada; Mercado ya no cambia de formato frente al resto. |
| 10 | Tabs | Exactamente Partidos, Jugadores y Equipos. |
| 11 | Partidos por defecto | Confirmado en carga directa, Preview y produccion. |
| 12 | Ubicacion | Es el primer control del flujo y conserva una zona publica legible. |
| 13 | Geolocalizacion opt-in | Solo se solicita al pulsar `Usar mi ubicacion`; nunca al cargar. La rama de denegacion esta cubierta por tests. |
| 14 | Filtros rapidos | Hoy, Manana, Esta semana y modalidades visibles como chips. |
| 15 | Filtro avanzado | Hoja contextual responsive; no invade la navegacion movil o landscape. |
| 16 | Orden | Relevancia, proximidad, plazas y distancia segun la pestaña. |
| 17 | Contador | Resultado visible y singular/plural por entidad. |
| 18 | Partidos | Tarjetas compactas con fecha, rival, modalidad, campo, zona, confirmados y plazas. |
| 19 | Detalle | Hoja independiente con contexto suficiente y sin datos tecnicos del servidor. |
| 20 | Solicitud | Una accion primaria; espera confirmacion canonica en producto y es local en Demo. |
| 21 | Estados de solicitud | Disponible, pendiente, aceptada y cancelable conservan los RPC existentes. |
| 22 | Jugadores | Tarjetas compactas, filtros de posicion/disponibilidad y paginacion estable. |
| 23 | Perfil y carta | La carta completa aparece solo al abrir detalle; la lista usa resumen. |
| 24 | Contexto de invitacion | Conserva partido activo, plazas y retorno a V3B. |
| 25 | Invitaciones | Mantiene `create_pachanga_match_invitation_v1` y `cancel_pachanga_match_invitation_v1`. |
| 26 | Equipos | Tarjetas compactas por zona, plantilla, retos y ranking secundario. |
| 27 | Perfil de equipo | Hoja de detalle con identidad, plantilla, zona y accion contextual. |
| 28 | Configuracion propia separada | `Mi equipo en Mercado` permanece fuera de la busqueda social. |
| 29 | V3B | Solicitud aceptada abre el partido concreto y permite volver conservando filtros. |
| 30 | V3C | Retar abre el wizard con rival preseleccionado; no envia automaticamente. |
| 31 | Usuario sin equipo | Ve ocho equipos publicos Demo y cero botones Retar. |
| 32 | Usuario sin sesion | Conserva filtros y sustituye mutaciones por `Entrar para continuar`. |
| 33 | Fallback integrity | Producto sin autoridad muestra `No disponible`; ningun dato Demo se presenta como LIVE. |
| 34 | Cached/offline | Lectura derivada permitida; mutaciones deportivas quedan deshabilitadas y sin cola. |
| 35 | Errores | Mensajes de producto; no se exponen PostgREST, IDs, payloads ni stack traces. |
| 36 | Deep links | Tabs, filtros, detalle y retorno conservan contexto; coordenadas exactas no forman parte del enlace. |
| 37 | Realtime | Sigue invalidando y releyendo snapshot canonico; WAL no es autoridad. |
| 38 | PWA | Manifest `fullscreen` con fallbacks, `/sw.js` activo, actualizacion, offline y reconexion comprobados. |
| 39 | Demo social | Recorrido de 31 pasos incorporado con perspectivas player, admin, sin equipo y sin sesion. |
| 40 | Remote writes | `0`; las acciones Demo modifican solo estado de sesion. |
| 41 | Responsive | 1440x900, 1920x1080, 390x844, 360x800, 667x375, 740x360, 844x390 y 932x430. |
| 42 | Landscape | Rail compacto permitido, filtros y detalles ajustados; sin doble navegacion ni overflow. |
| 43 | Accesibilidad | Roles, labels, estados pressed/disabled, cierre de hojas y orden de foco conservados. |
| 44 | Rendimiento | Mercado se divide en cliente, contrato y hojas; detalles solo se montan al abrirse. No se recalculan ratings ni read models autoritativos. |
| 45 | Tests | `745/745`: Node `20/20`; TS/TSX `725/725`; fail/skipped/todo/cancelled `0/0/0/0`. |
| 46 | Typecheck | PASS. |
| 47 | Build | PASS con Next.js 16.3.3; 70 rutas. |
| 48 | Lint | Focal: 0 errores, 0 warnings. Global: 0 errores. |
| 49 | Warnings | Dos preexistentes en `app/page.tsx`: `groupOptionLabel` y `deleteCurrentTeam`; V3D anade 0. |
| 50 | Supabase sin cambios | 0 migraciones, 0 RPC, RLS/Auth/flags intactos; no se ejecuto `db push` ni SQL QA. |
| 51 | Stripe sin cambios | No se abrieron secretos; 0 Customers, Checkout OFF y 0 pagos. |
| 52 | Entidades reales utilizadas | `0`. |
| 53 | Notificaciones reales | `0`. |
| 54 | Runtime errors | Navegador: 0. Vercel: 0 errores, warnings, 4xx y 5xx en la ventana de release. |
| 55 | Cleanup | Procesos locales cerrados. Preview, ramas y worktree se retiran tras fusionar #250 y verificar ancestro/estado limpio. |
| 56 | Wave 9C iniciada | NO. |
| 57 | V3E iniciada | NO. |

## Contrato autoritativo conservado

- `request_pachanga_open_match_authoritative_v2` sigue siendo la autoridad para
  solicitar plaza.
- `cancel_my_pachanga_open_match_request_v1` sigue siendo la autoridad para
  cancelar una solicitud propia.
- `create_pachanga_match_invitation_v1` y
  `cancel_pachanga_match_invitation_v1` siguen siendo las autoridades de
  invitacion.
- El cliente envia intenciones, espera respuesta canonica y no confirma una
  operacion deportiva offline.
- Los read models locales son copias derivadas; Realtime solo invalida y provoca
  una nueva lectura.
- `ChallengeableTeamsPanel`, navegacion V3A, Partido V3B y Retos V3C permanecen
  integrados.

## QA visual y funcional

### Local y Preview

- Matriz: 1440x900, 1920x1080, 390x844, 360x800, 667x375,
  740x360, 844x390 y 932x430.
- Resultado agregado: 0 overflow raiz/cuerpo, 0 imagenes rotas y 0 colisiones
  de cabecera o navegacion.
- Hojas de filtros y detalle comprobadas en portrait y landscape.
- Solicitud Demo, aceptacion admin, plaza confirmada, V3B, invitacion,
  usuario sin sesion, usuario sin equipo, offline y V3C preseleccionado.
- Google Places visible sin warning tecnico en las superficies migradas.

### Produccion

- Mercado abre en Partidos y mantiene `zona`, `dia` y `modalidad` al cambiar a
  Jugadores y Equipos.
- Visitante sin sesion recibe un estado honesto `No disponible` y no recibe
  tarjetas ficticias.
- Demo: solicitud local, aceptacion local por admin, plaza confirmada y acceso
  al partido V3B.
- Demo: invitacion local marcada como simulada y no enviada.
- Demo: Equipo abre V3C con `rival=demo_team_002` preseleccionado y sin reto
  enviado.
- Usuario sin equipo: 8 equipos visibles, 0 acciones Retar.
- Usuario sin sesion: 8 acciones `Entrar para continuar`, 0 acciones Retar.
- `/admin/demo` no se expone al visitante: devuelve `Sesion necesaria`.
- Portrait 390x844 y landscape 844x390: 0 overflow y 0 imagenes rotas.
- Manifest: HTTP 200, `display=fullscreen`, fallbacks standalone/minimal-ui/browser.
- Service Worker: activo, controlador y ruta `/sw.js`.
- Offline: red no alcanzable, `Sin conexion` y `Solo lectura sin conexion`.
- Reconexion: `navigator.onLine=true`, policy HTTP 200 y copy offline retirado.
- Consola del navegador: 0 errores y 0 warnings de produccion.
- Logs Vercel: 0 errores, warnings, 4xx y 5xx en la ventana comprobada.

No se invocaron RPC productivas de escritura durante QA porque el contrato de
la fase prohibe usuarios, equipos, jugadores y partidos reales. Su integracion
queda cubierta por la bateria automatizada y por la preservacion literal de las
RPC existentes.

## QA fisica pendiente

| Superficie | Estado |
| --- | --- |
| Android fisico | PENDING |
| iPhone fisico | PENDING |
| PWA instalada fisica | PENDING |

La politica de release permite mantener estos tres puntos como PENDING. No se
presentan como PASS.

## Matriz final

| Criterio | Resultado |
| --- | --- |
| Mercado limpio | SI |
| Partidos por defecto | SI |
| Tabs reducidas a tres | SI |
| Rail desktop eliminado | SI |
| Ubicacion principal | SI |
| Geolocalizacion solo opt-in | SI |
| Filtros progresivos | SI |
| Tarjetas de partidos compactas | SI |
| Solicitud clara | SI |
| Tarjetas de jugadores compactas | SI |
| Carta completa solo en detalle | SI |
| Contexto Invitar preservado | SI |
| Tarjetas de equipos compactas | SI |
| Configuracion propia separada | SI |
| Equipo -> Retos V3C | SI |
| Partido -> V3B | SI |
| Fallback ficticio presentado como LIVE | 0 |
| Modo juego horizontal preservado | SI |
| Demo actualizada | SI |
| Remote Demo writes | 0 |
| Supabase modificado | NO |
| Stripe tocado | NO |
| Entidades reales utilizadas | 0 |
| Tests | 745/745 |
| Lint errores | 0 |
| Lint warnings nuevas | 0 |
| Todo funcional fusionado | SI |
| Todo funcional desplegado | SI |

## Estado final

Official UI V3D queda en produccion como un flujo centrado en jugar:

`elige zona -> encuentra partido, jugador o equipo -> abre detalle -> solicita,
invita o reta -> jugar`

No se inicia Wave 9C ni Official UI V3E.
