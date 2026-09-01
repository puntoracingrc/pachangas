# Official UI V3E - Simple Player Identity and Social Onboarding

Fecha de cierre: 2026-09-01 (Europe/Madrid)

## Resultado ejecutivo

Official UI V3E queda fusionada y verificada en produccion. Pachangas IQ ofrece
ahora una entrada social sencilla y no bloqueante: preparar el perfil minimo,
indicar zona y disponibilidad y elegir entre unirse, crear o buscar una
pachanga. La carta y la publicacion en Mercado siguen siendo opcionales.

La release no crea una segunda autoridad. El servidor sigue siendo la fuente de
verdad y el estado local se limita a borradores visuales y copias de lectura.
Cuando no existe una operacion central suficientemente segura, la UI se cierra
de forma explicita: un codigo de equipo identifica, pero no concede acceso, y
la creacion productiva de equipos no se confirma mediante las dos escrituras
directas antiguas.

No se modificaron Supabase, RLS, Auth, RPC, flags, Stripe, Rating V2, resultados,
recompensas, cosmeticos, Conduct ni motores deportivos. La Demo usa solo estado
local sintetico: cero escrituras remotas, entidades reales, notificaciones y
llamadas Stripe.

## Versiones y release

| Evidencia | Resultado |
| --- | --- |
| Main inicial | `8a06116a93fca46a9926bfea413368ceed42d051` |
| Commit funcional | `e603929bf59238e2a454e6731bcf3da6f5d77bf7` |
| PR funcional | [#251](https://github.com/puntoracingrc/pachangas/pull/251) |
| Merge funcional / main funcional | `1e8655e7794704cf8f9e5dd9e2242e1637576016` |
| PR documental | [#252](https://github.com/puntoracingrc/pachangas/pull/252) |
| Preview exacta | `pachangas-5dui16g31-persianas-almar-web-s-projects.vercel.app` |
| Deployment productivo funcional | `dpl_6qmnswxcMjCin3xLd1LFFWuThGNh` |
| URL inmutable productiva | `pachangas-c91h6ph05-persianas-almar-web-s-projects.vercel.app` |
| Dominio | [pachangasiq.com](https://pachangasiq.com) |
| Service Worker funcional | `2.0.0+sw.1e8655e77947` |

El PR documental solo agrega este informe. El SHA definitivo de `main` y el
Service Worker posterior a su merge quedan registrados en la entrega final.

## Contrato autoritativo y gaps

### Confirmado

- La identidad se deriva de Auth, `pachanga_player_profiles`, membresias y
  equipos canonicos; no existe una entidad paralela de onboarding.
- `/perfil` lee el perfil y las membresias con RLS, conserva una copia local
  versionada y relee tras Realtime o reconexion.
- Las invitaciones nunca se aceptan al abrir un enlace. El usuario confirma y
  la aplicacion relee los equipos desde el servidor.
- La invitacion de admin usa
  `accept_pachanga_admin_invite_authoritative_v1`, con `operation_id`, revision
  esperada y metadatos de cliente.
- Offline nunca muestra como confirmada una escritura social.

### Parcial o cerrado de forma segura

- La invitacion ordinaria reutiliza `join_pachanga_team`, pero esa RPC heredada
  no devuelve el contrato completo V2 de `operationId`, revision esperada y
  recibo canonico. Sigue centralizada, pero se clasifica como **PARCIAL**.
- El perfil minimo de un usuario sin equipo no dispone de una RPC canonica
  independiente localizada. V3E conserva su avance como `BORRADOR LOCAL` y no
  lo presenta como perfil persistido.
- Un codigo de equipo por si solo no concede membresia. La UI solicita un enlace
  de invitacion valido y mantiene el codigo introducido.
- La creacion antigua de equipos dependia de dos escrituras directas separadas.
  El wizard de tres pasos y la Demo estan disponibles, pero el submit productivo
  queda deshabilitado hasta disponer de una autoridad transaccional unica.

## Cierre de los 62 puntos

| # | Punto | Estado y evidencia |
| ---: | --- | --- |
| 1 | Main inicial | `8a06116a93fca46a9926bfea413368ceed42d051`. |
| 2 | Main final | Main funcional `1e8655e7794704cf8f9e5dd9e2242e1637576016`; el merge documental se registra en la entrega final. |
| 3 | PR funcional | #251, fusionado, sin hotfix posterior. |
| 4 | PR documental | #252, dedicado solo a este informe. |
| 5 | Deployment | `dpl_6qmnswxcMjCin3xLd1LFFWuThGNh`, READY y asociado al merge funcional. |
| 6 | Service Worker | `2.0.0+sw.1e8655e77947`; incluye `/perfil`, `/equipo`, `/equipo/unirse` y `/equipo/crear`. |
| 7 | Onboarding anterior | No habia un recorrido social unico que ordenase perfil, contexto y forma de empezar. |
| 8 | Onboarding final | Tres pasos y tres salidas claras, sin crear autoridad paralela. |
| 9 | Estados de entrada | `NEW_USER`, `PROFILE_READY_NO_TEAM`, `TEAM_INVITATION_PENDING`, `TEAM_MEMBER` y `MULTI_TEAM_MEMBER`, derivados del estado canonico. |
| 10 | Perfil minimo | Nombre visible, posicion y modalidad; zona y disponibilidad recomendadas, foto opcional. La persistencia sin equipo permanece como gap autoritativo. |
| 11 | Paso 1 | Nombre, foto opcional, posicion y modalidad, sin facetas ni controles tecnicos. |
| 12 | Paso 2 | Zona general, dias y franja; no solicita geolocalizacion al cargar. |
| 13 | Paso 3 | Unirme, Crear mi equipo o Buscar una pachanga, con jerarquia clara. |
| 14 | Onboarding no bloqueante | Se puede cerrar con `Ahora no`, reanudar desde una tarjeta discreta y no reaparece en cada navegacion. |
| 15 | Mi perfil | `/perfil` separa identidad, resumen, carta, Mercado y privacidad. |
| 16 | Editar perfil | Enlaza la edicion existente cuando hay equipo; sin equipo vuelve al flujo de perfil. No finge una escritura ausente. |
| 17 | Avatar | La foto es opcional, se previsualiza localmente y no se publica al seleccionarla. |
| 18 | Mi carta | Muestra la carta canonica cuando existe y un estado de producto cuando falta. |
| 19 | Carta opcional | No bloquea Inicio, Mercado, invitaciones ni exploracion. |
| 20 | Personalizacion | `/personalizar-carta` y los cosmeticos existentes se preservan sin alterar grants. |
| 21 | Mercado del jugador | Bloque compacto con `NO PUBLICADO`, `PUBLICADO` o `PAUSADO`. |
| 22 | Opt-in | Completar onboarding no publica el perfil; la visibilidad sigue siendo explicita. |
| 23 | Privacidad | Email, telefono, fecha completa, coordenadas, Auth IDs y notas privadas no aparecen. |
| 24 | Usuario sin equipo | Recibe un estado util con Unirme, Crear y Buscar; no ve administracion ni roles. |
| 25 | Invitacion | Se muestra antes que el codigo, explica el rol, permite `Ahora no` y exige confirmacion. |
| 26 | Codigo | Se analiza de forma segura; un codigo solo no concede acceso y los errores no exponen SQL ni IDs. |
| 27 | Unirse | Invitacion admin autoritativa; invitacion ordinaria central pero heredada y clasificada PARCIAL. No hay autoaceptacion. |
| 28 | Crear equipo | Wizard visual de tres pasos; submit productivo fail-closed por ausencia de RPC transaccional segura. |
| 29 | Escudo inicial | Selector sencillo en wizard y Demo, sin abrir editor avanzado ni conceder cosmeticos. |
| 30 | Equipo creado | Completo en Demo local. En producto no se presenta como creado hasta existir confirmacion canonica. |
| 31 | Selector | V3A se conserva y actualiza el contexto canonico del equipo. |
| 32 | Varios equipos | La Demo acredita cambio de equipo y el producto mantiene el selector V3A. |
| 33 | Portada minima | La portada existente de equipo se preserva; V3E no introduce gestion avanzada. |
| 34 | Jugador ordinario | Ve solo identidad y acciones permitidas; no recibe controles owner o plataforma. |
| 35 | Owner/admin | Mantienen acciones existentes; la invitacion usa autoridad y la gestion avanzada sigue separada. |
| 36 | Platform owner | Se resuelve por rol/capability del servidor; no por email, query, CSS o localStorage. `/admin/demo` sigue separado. |
| 37 | Inicio | Adapta los estados de entrada sin redisenar V3A ni anadir otro carrusel. |
| 38 | V3B | Partidos y la navegacion `?mobile=partido` permanecen operativos. |
| 39 | V3C | Retos conserva roles, estados y experiencia sin equipo. |
| 40 | V3D | Mercado conserva Partidos, Jugadores y Equipos, sus filtros y autoridad. |
| 41 | Deep links | `/perfil`, `/equipo`, `/equipo/unirse` y `/equipo/crear` resuelven las rutas canonicas y preservan query/retorno. |
| 42 | OAuth | La intencion social se conserva en la URL y no se acepta ninguna invitacion al iniciar sesion. |
| 43 | PWA | Manifest `fullscreen` con fallbacks y Service Worker actualizado con las rutas V3E. |
| 44 | Offline | Lecturas cacheadas y borrador local permitidos; membresias, perfil, Mercado y equipos nunca se confirman offline. |
| 45 | Demo social | 34 historias locales: perfil, unirse, crear, carta, Mercado, cambio de equipo, offline y reinicio. |
| 46 | Remote writes | `0`; notificaciones externas `0`; Stripe calls `0`. |
| 47 | Responsive | Matriz completa en desktop, portrait y landscape: 0 overflow, controles cortados o imagenes rotas. |
| 48 | Landscape | Composicion compacta, controles de al menos 40 px, safe area y lanzador de reanudacion preservados. |
| 49 | Accesibilidad | Labels, foco visible, Escape, focus trap, teclado, `aria-live` y reduced motion verificados; 0 defectos criticos introducidos. |
| 50 | Rendimiento | Perfil canonico con cache versionada e invalidacion selectiva; no carga editores completos al iniciar ni recalcula ratings. |
| 51 | Tests | `767/767`: Node `20/20`; TS/TSX `747/747`; fail/skipped/todo/cancelled `0/0/0/0`. |
| 52 | Typecheck | PASS. |
| 53 | Build | PASS dentro de la bateria final. |
| 54 | Lint | PASS: 0 errores y 0 warnings; solo nota informativa de Babel por tamano de `app/page.tsx`. |
| 55 | Supabase sin cambios | 0 migraciones, 0 RPC, RLS/Auth/flags intactos; no se ejecuto `db push`. |
| 56 | Stripe sin cambios | No se abrieron secretos; 0 Customers, Checkout OFF y 0 pagos. |
| 57 | Entidades reales usadas | `0`. |
| 58 | Notificaciones reales | `0`. |
| 59 | Runtime errors | Navegador: 0. Vercel: 0 errores, 4xx y 5xx en la ventana de release. |
| 60 | Cleanup | Procesos, Preview, ramas, temporales y worktrees propios se retiran tras fusionar este informe y comprobar estado/ancestro. |
| 61 | Wave 9C iniciada | NO. |
| 62 | V3F iniciada | NO. |

## QA visual y funcional

### Local y Preview

- Viewports: 1440x900, 1920x1080, 390x844, 360x800, 667x375,
  740x360, 844x390 y 932x430.
- Resultado agregado: 0 overflow de raiz, cuerpo o dialogo; 0 controles
  cortados; 0 imagenes rotas; 0 errores de consola.
- Se comprobaron los tres pasos, cierre y reanudacion, invitacion, codigo
  incorrecto, confirmacion, estado sin equipo, creacion fail-closed, carta,
  Mercado, cambio de equipo y offline.
- Rutas comprobadas: `/`, `/perfil`, `/mercado`, Partido, `/retos`,
  `/personalizar-carta`, `/equipo`, `/equipo/unirse`, `/equipo/crear` y
  `/admin/demo`.
- Preview exacta del commit funcional: Service Worker
  `2.0.0+sw.e603929bf592`.

### Produccion

- Matriz de diez superficies: 0 overflow, 0 imagenes rotas y navegacion
  correcta.
- `/equipo` redirige a `/?mobile=equipo`; `/equipo/unirse` a `/?social=join`;
  `/equipo/crear` a `/?social=create`.
- `/admin/demo` sin sesion devuelve `Sesion necesaria` y no expone la Demo
  completa.
- Demo first-time: perfil, disponibilidad, invitacion, confirmacion y equipo
  activo; rotacion 390x844 a 844x390 sin perder estado.
- Escape cierra el recorrido y el lanzador `Primeros pasos` permite reanudarlo.
- Manifest HTTP 200 y Service Worker exacto del merge funcional.
- Consola de navegador: 0 errores y 0 warnings.
- Logs Vercel: 0 errores, 4xx y 5xx en la ventana inspeccionada.

No se invocaron escrituras productivas: la politica de la fase prohibe usuarios,
equipos, perfiles, invitaciones y notificaciones reales.

## QA fisica pendiente

| Superficie | Estado |
| --- | --- |
| Android fisico | PENDING |
| iPhone fisico | PENDING |
| PWA instalada fisica | PENDING |

Estos puntos no se presentan como PASS. El contrato de release permite
mantenerlos pendientes si se declaran de forma explicita.

## Matriz final

| Criterio | Resultado |
| --- | --- |
| Onboarding sencillo | SI |
| Onboarding no bloqueante | SI |
| Perfil minimo claro | SI; persistencia independiente sin equipo pendiente |
| Foto opcional | SI |
| Carta opcional | SI |
| Mi perfil limpio | SI |
| Mercado opt-in | SI |
| Privacidad preservada | SI |
| Usuario sin equipo resuelto | SI |
| Unirse mediante codigo | NO; el codigo no concede acceso, requiere invitacion canonica |
| Invitacion clara | SI |
| Crear equipo en 3 pasos | SI en UI y Demo; submit productivo fail-closed |
| Escudo inicial sencillo | SI |
| Equipo seleccionado tras crear | SI en Demo; NO en producto hasta disponer de RPC segura |
| Varios equipos | SI |
| Portada minima de equipo | SI |
| Partidos V3B preservados | SI |
| Retos V3C preservados | SI |
| Mercado V3D preservado | SI |
| Platform owner separado | SI |
| Modo juego horizontal preservado | SI |
| Demo actualizada | SI |
| Remote Demo writes | 0 |
| Supabase modificado | NO |
| Stripe tocado | NO |
| Entidades reales utilizadas | 0 |
| Tests | 767/767 |
| Lint errores | 0 |
| Lint warnings | 0 |
| Todo funcional fusionado | SI |
| Todo funcional desplegado | SI |

## Estado final

Official UI V3E queda en produccion con una entrada social comprensible y con
las limitaciones autoritativas visibles, no disimuladas:

`dime como juegas -> elige donde -> unete con invitacion, prepara tu equipo o busca`

No se inicia Official UI V3F ni Wave 9C.
