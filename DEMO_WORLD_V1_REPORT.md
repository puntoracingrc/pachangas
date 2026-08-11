# Demo World V1 Report

## Checkpoint

- Auditoria iniciada: 2026-08-11 (Europe/Madrid).
- Base exacta: `851418d688e4078d9fb9166174b961dc5c22d4d9` (`origin/main`).
- Rama: `codex/demo-world-v1`.
- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-demo-world-v1`.
- Produccion y Supabase: no modificados.

## Registro de incidencias

Este registro es permanente. Una incidencia no se elimina al corregirse; se actualiza su estado y se enlaza con su regresion.

| ID | Clase | Estado | Hallazgo original | Correccion | Regresion |
| --- | --- | --- | --- | --- | --- |
| DW-001 | DEMO_DATA_BUG | fixed + regression_verified | La demo heredada incluia campos de telefono y mezclaba datos de presentacion con el payload local historico. | Snapshot publico V1 saneado, con namespace `demo_*` y sin PII ni datos privados. | `tests/demo-world-v1.test.ts`: rechazo recursivo de PII y campos privados. |
| DW-002 | DEMO_ADAPTER_BUG | fixed + regression_verified | `?demo=1` activaba el gran payload de la aplicacion real y podia montar superficies conectadas a Supabase. | Ruta aislada `/demo`, carga estatica same-origin y bloqueo del centro global de notificaciones dentro de Demo World. | `tests/demo-world-v1.test.ts`: redireccion heredada y prueba de cero mutaciones remotas. |
| DW-003 | TESTABILITY_GAP | fixed + regression_verified | No existia una invariante ejecutable que demostrase cero escrituras remotas en toda accion demo. | Contrato `assertDemoWorldLocalIntent` y estado efimero exclusivo de `sessionStorage`. | `tests/demo-world-v1.test.ts`: POST/PUT/PATCH/DELETE, RPC e inserts/updates/deletes rechazados. |
| DW-004 | DEMO_ADAPTER_BUG | fixed + regression_verified | La inicializacion de `tab` y perspectiva desde URL/sessionStorage hacia `setState` sincrono dentro de un efecto, rechazado por el lint de React 19. | Inicializacion perezosa unica; la URL prevalece sobre sessionStorage sin render intermedio. | `tests/demo-world-v1.test.ts`: URL valida/invalida y precedencia de perspectiva. |
| DW-005 | VISUAL_BUG | fixed + regression_verified | En 360–390 px el escudo principal de 210 px escalado conservaba su caja original y quedaba recortado aproximadamente un 28%; la primera correccion redujo la escala pero seguia dejando 26 px fuera al transformar desde el centro. | Escala movil `0.58` desde el borde interior de la columna. | QA DOM: `right=342` en 360 px y `right=372` en 390 px, sin overflow. |
| DW-006 | VISUAL_BUG | fixed + regression_verified | Reiniciar, Salir, marca, selector y acciones principales median 34–42 px en portrait, por debajo del objetivo tactil de 44 px. | Minimo 44 px en portrait y 40 px solo en modo juego compacto. | Visual Audit + medicion DOM de controles visibles en portrait/landscape. |
| DW-007 | DEMO_ADAPTER_BUG | fixed + regression_verified | Un partido finalizado mostraba en Admin acciones incompatibles de partido activo: cerrar alineacion, abrir Mercado, invitar, editar campo y crear partido. | Un historico conserva solo `Borrar partido`; un partido programado mantiene las seis herramientas simuladas. | `tests/demo-world-v1.test.ts`: matriz explicita por estado y QA de navegador. |
| DW-008 | DEMO_DATA_BUG | fixed + regression_verified | Retos rechazados, pendientes o con contrapropuesta podian conservar `matchId` y abrir un partido; ademas, dos avisos y una historia enlazaban Retos cuyo estado no coincidia con su texto. | Relacion estricta estado-partido; avisos e historias resuelven el Reto por estado, nunca por indice. | `tests/demo-world-v1.test.ts`: seis estados, vinculos canonicos y semantica aviso/historia. |
| DW-009 | DEMO_ADAPTER_BUG | fixed + regression_verified | Mercado mostraba `Invitar` en las perspectivas jugador y jugador sin equipo, aunque invitar es una accion administrativa. | Capacidad explicita `canDemoWorldInvite`, verdadera solo para admin. | `tests/demo-world-v1.test.ts`: matriz admin/player/visitor y QA de perspectiva. |
| DW-010 | DEMO_ADAPTER_BUG | fixed + regression_verified | Tras regenerar V1 durante QA, `force-cache` reutilizo chunks antiguos bajo las mismas URLs y el validador rechazo una mezcla incoherente de manifest y datos. | Cada chunk conserva cache larga, pero su URL incorpora los primeros 16 caracteres del hash canonico. | `tests/demo-world-v1.test.ts`: todas las URLs deben terminar en el hash del payload. |
| DW-011 | VISUAL_BUG | fixed + regression_verified | La auditoria multidispositivo encontro que la marca, Reiniciar, Salir e Invitar conservaban superficies tactiles de 26-38 px en algunas vistas. | Minimo de 40 px aplicado a esas tres superficies sin alterar su densidad visual. | Visual Audit focalizado: 13 combinaciones, cero targets pequenos. |
| DW-012 | VISUAL_BUG | fixed + regression_verified | Demo World respondia a `prefers-color-scheme`, pero no al `data-theme` explicito que utiliza el selector Claro/Oscuro del producto. | La cascada usa el tema del sistema solo cuando no existe una eleccion explicita y aplica `data-theme="light"` de forma autoritativa. | Test de contrato + Visual Audit con paletas computadas distintas en Claro/Oscuro. |
| DW-013 | VISUAL_BUG | fixed + regression_verified | A zoom 200 %, el breakpoint global estrecho reducia la navegacion de Demo World a 36 px aunque el contrato demo fija 40 px para modo juego compacto. | Demo World fija localmente `--game-nav-height: 40px` sin cambiar la navegacion del producto real. | Visual Audit a zoom 200 %: cero targets pequenos, overflow o errores. |
| DW-014 | TESTABILITY_GAP | fixed + regression_verified | La matriz heredada conservaba 172 checks, pero no abria automaticamente la perspectiva sin equipo ni las subpantallas Demo de Retos, recompensas, avisos, plantilla, logros y escudo. | Se anaden diez superficies Demo automatizadas sin retirar ningun check existente. | Visual Audit final: 232 combinaciones, 172 conservadas + 60 nuevas. |
| DW-015 | VISUAL_BUG | fixed + regression_verified | Los botones `Abrir demo` de cajas median 38 px en desktop, portrait, landscape y PWA. | Minimo tactil de 44 px aplicado a las acciones de caja. | Visual Audit final: cero targets pequenos en 130 checks Demo. |
| DW-016 | TESTABILITY_GAP | fixed + regression_verified | El auditor buscaba texto exacto y no podia activar `Avisos` porque el contador accesible forma parte del texto del boton. | El contrato de superficie admite `clickTextPrefix` y evita acoplarse al numero de avisos. | La superficie Avisos se abre en seis viewports sin error de navegacion. |
| DW-017 | PRODUCT_BUG | open; baseline outside Demo World | La matriz final mantiene 222 targets menores de 40 px en 38 combinaciones de superficies productivas ajenas a Demo World, concentrados en tabs desktop de Mercado y enlaces del footer legal. | No se modifica en este PR para evitar mezclar una correccion global no relacionada. | Demo World tiene cero targets pequenos y no degrada los 172 checks existentes. |
| DW-018 | DEMO_ADAPTER_BUG | fixed + regression_verified | La Preview protegida de Vercel sirve `/demo`, pero los cuatro chunks estaticos fallaban porque `credentials: "omit"` excluia tambien la cookie de proteccion del mismo origen. La UI quedaba detenida en `Preparando el Mundo Demo`. | Los chunks usan `credentials: "same-origin"`; siguen siendo rutas relativas, `GET` estaticos, sin Supabase, Auth de producto ni escrituras. | Contrato automatizado PASS; Preview protegida `f3f32e8` carga en frio en 330 ms y supera 84 checks remotos sin peticiones fallidas. |

## Estado del cierre

## Arquitectura elegida

`/demo` es una aplicacion publica aislada que carga un manifest versionado y cuatro chunks JSON estaticos. El generador reutiliza Rating V2 y los catalogos productivos de cosmeticos; el cliente reutiliza `PlayerCosmeticCard`, `TeamShieldView`, `RewardBoxDemo` y `MobileAppNav`.

El modo heredado `?demo=1` redirige al nuevo mundo. El centro global de notificaciones conectado y el footer real no se montan en `/demo`. No se han creado usuarios Auth, tablas, migraciones, funciones RPC ni filas ficticias.

## Dataset congelado

| Metrica | Resultado |
| --- | ---: |
| Equipos | 28 |
| Jugadores | 365 |
| Partidos | 128 |
| Retos | 26 |
| Logros | 74 |
| Cajas | 28 |
| Avisos | 12 |
| Historias | 10 |
| Perspectivas | 3 |

Territorios: Barcelona 8 equipos, Valles 8, Girona 6 y Maresme 6. Hay 120 partidos finalizados y 8 programados; 53 son externos/Reto y 75 internos. Los 26 Retos cubren `countered` (2), `pending` (2), `accepted` (2), `rejected` (1), `cancelled` (1) y `completed` (18).

Mercado incluye 281 perfiles abiertos a invitaciones demo, un agente libre, 23 equipos retables y 8 partidos con plazas publicas. El ranking contiene los 28 equipos y se presenta siempre como Ranking Demo, no como TOP oficial.

## Rating y progresion

- Jugadores de campo: read models calculados con `pachangas-rating-v2`.
- Porteros: GRL `null` bajo dominio `goalkeeper_legacy`; no se inventa la formula pendiente.
- Season Score: no se recalcula ni se presenta una formula alternativa.
- Team Rewards: los cinco mappings productivos siguen exactos y cada grant tiene evidencia.
- Premium Ball: ausente y no activado.
- Premium Art Pack: ninguna de sus 29 propuestas se declara propiedad o reward.

## Diversidad visual

| Indicador | Resultado |
| --- | ---: |
| Loadouts de jugador unicos | 197 de 365 |
| Base/casi base, 0-1 piezas | 96 (26,3 %) |
| Ligera, 2 piezas | 54 (14,8 %) |
| Media, 3 piezas | 99 (27,1 %) |
| Alta, 4-5 piezas | 116 (31,8 %) |
| Piezas Premium/Oro equipadas | 0 |
| Escudos unicos | 28 de 28 |
| Formas | 8 |
| Fondos | 2 |
| Patrones | 4 |
| Colores primarios | 4 |
| Colores secundarios | 3 |
| Simbolos | 5 |
| Bordes | 4 |

Los escudos usan tambien Banner, Laureles y Edge Glow cuando la evidencia desbloquea esas piezas. Las contact sheets reales estan en:

- `artifacts/demo-world-v1/team-shields-contact-sheet.png`
- `artifacts/demo-world-v1/player-cards-contact-sheet.png`

## Personas y navegacion

El selector discreto permite explorar como jugador, admin o jugador sin equipo. Las cinco areas principales son Inicio, Partido, Mercado, Equipo y Perfil. Partido incluye Proximo/Historico, Alineacion, Resultado y Admin cuando corresponde; Mercado incluye jugadores, partidos y Retos/equipos.

Las tres perspectivas son estado local y no sesiones Auth. Al cambiarlas se restablecen partido, jugador y equipo seleccionados cuando resultan incompatibles.

## Acciones simuladas

- Voy, Duda y No en un proximo partido.
- Revisar Retos y abrir sus partidos canonicos cuando existen.
- Invitar solo desde la perspectiva Admin.
- Herramientas Admin compatibles con el estado del partido.
- Leer avisos.
- Abrir una caja determinista y guardar la pieza en la sesion demo.
- Reiniciar el mundo.

La unica persistencia es `sessionStorage`. Reset borra asistencia, cajas abiertas, avisos leidos y perspectiva. La red se audito en navegador recorriendo esas acciones: 33 solicitudes, todas `GET`, cero mutaciones.

## Privacidad y aislamiento

- Cero PII y cero campos privados tras validacion recursiva.
- Identificadores `demo_*` sin colision con produccion.
- `credentials: "same-origin"` solo en los `GET` estaticos y relativos, necesario para Previews protegidas; nunca `include` ni credenciales cross-origin.
- Sin import de cliente Supabase ni `service_role`.
- Sin Google Places para ubicaciones demo.
- Sin datos de conducta, moderacion, reporters, riesgo, recibos o internals de Synthetic World.
- Usuario autenticado y visitante reciben la misma experiencia aislada.

## Payload y rendimiento

| Recurso | Bytes |
| --- | ---: |
| Manifest | 635 |
| Core | 36.678 |
| Players | 355.011 |
| Matches | 141.645 |
| Activity | 33.695 |
| Payload canonico total | 567.068 |

El manifest y los cuatro chunks ocupan 58.390 bytes con gzip y 46.603 con Brotli. El HTML prerenderizado ocupa 15.389 bytes (3.758 gzip). Los assets iniciales referenciados por `/demo` suman 982.783 bytes de JS (279.345 gzip), 437.914 de CSS compartido (69.286 gzip) y 52.396 de fuentes. Estas cifras incluyen runtime y estilos globales compartidos, no solo codigo exclusivo de Demo World.

V1 usa chunks de dominio cargados en paralelo y cacheados por hash. No existe lazy loading por pestana en esta version: el payload queda bajo 700 KB y se prioriza navegacion instantanea posterior. La caja 3D mantiene su modulo separado mediante import dinamico y el GLB de 563.072 bytes solo se solicita al abrirla. Los avatares son SVG deterministas inline y no dependen de hosts remotos.

Seed: `pachangas-iq-demo-world-v1-2026-27`.

Hash: `cef767f201a00f9f36fdaad8b27a195e9c767147651153717dabf043b71d16d3`.

## SEO y accesibilidad

- `/demo` y sus contact sheets: `noindex,nofollow`.
- Banner discreto Modo Demo, salida y CTA no invasivos.
- Targets estables `data-tour-target` sin tutorial lineal.
- Safe areas y navegacion PWA reutilizada.
- Objetivo tactil 44 px en portrait y 40 px en modo juego compacto.
- `prefers-reduced-motion` desactiva transiciones y scroll suave.
- Tema del sistema y eleccion explicita Claro/Oscuro soportados.

## QA visual focalizada

Auditoria inicial Demo World: 67 combinaciones de superficie/viewport, con cero errores de consola, warnings, imagenes rotas, overflow horizontal o chrome fuera de pantalla. El hallazgo de targets pequenos se registro como DW-011, se corrigio y su regresion paso en 13 combinaciones adicionales.

Visual Audit V1 final: 232 checks, cero errores de navegacion/consola, warnings, solicitudes fallidas, imagenes rotas, overflow, violaciones de viewport o chrome de juego. Conserva los 172 checks anteriores y anade 60 para las diez superficies profundas. Demo World aporta 130 checks y todos tienen cero targets pequenos. Los 222 targets pequenos restantes pertenecen a 38 combinaciones productivas preexistentes y quedan registrados como DW-017.

QA de Preview protegida Vercel sobre `f3f32e8`: 84 combinaciones Demo (21 superficies por desktop 1440x900, portrait 390x844, landscape 844x390 y PWA standalone), con cero errores de navegacion/consola, warnings, solicitudes fallidas, imagenes rotas, overflow, targets pequenos o violaciones de chrome. Un arranque frio con cache desactivada alcanzo el contenido navegable en 330 ms. El recorrido de admin, asistencia, cambio de perspectiva, apertura/guardado de caja, avisos y reset genero nueve solicitudes, todas `GET`, sin RPC, REST de Supabase ni mutaciones remotas.

Tema explicito: Claro `rgb(238, 242, 239)` / texto `rgb(16, 32, 26)` y Oscuro `rgb(7, 17, 15)` / texto `rgb(241, 246, 242)`, ambos sin overflow, errores, warnings o targets pequenos.

Spot checks manuales ya realizados:

- desktop 1440x900;
- portrait 390x844 y 360x800;
- landscape 844x390 con modo juego;
- PWA standalone simulada;
- contact sheets de cartas y escudos.

## Experiencia de descubrimiento

Recorrido de dos minutos: Inicio expone equipo/carta, proximo partido, ranking, historias y avisos; la navegacion superior/inferior permite llegar a Partido, Retos y Mercado sin modal obligatorio.

Recorrido de diez minutos: permite cambiar perspectiva, abrir fichas, recorrer historicos, alineacion y goleadores, comparar equipos/escudos, revisar logros y abrir una caja. La principal decision de rendimiento es cargar el snapshot completo al entrar; no se observo espera funcional en local, pero V2 puede cargar Players/Matches por demanda si el mundo crece.

## Documentos relacionados

- `DEMO_WORLD_V1_DATA_CONTRACT.md`
- `DEMO_WORLD_V1_STORIES.md`
- `artifacts/demo-world-v1/visual-audit/`

## Validaciones finales

| Gate | Estado |
| --- | --- |
| `npm run test:demo-world` | PASS, 14/14 |
| Red de navegador, cero writes | PASS |
| Focused lint | PASS |
| `npm test` | PASS, 241/241 |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| Visual Audit V1 completo | PASS, 232/232; 130 Demo sin targets pequenos |
| Preview Vercel protegida | PASS, 84/84; arranque frio 330 ms; cero writes |
| Global lint | deuda previa: 23 errores y 20 warnings fuera de los modulos Demo |
| `git diff --check` | PASS |

## Publicacion

- Rama: `codex/demo-world-v1`.
- Commit de implementacion validado: `f3f32e88be537fce4ac0af16c45f29af98330132`.
- PR draft: `https://github.com/puntoracingrc/pachangas/pull/140`.
- Preview Vercel exacta validada: `https://pachangas-m9xm8jbow-persianas-almar-web-s-projects.vercel.app/demo`.
- Merge: no.
- Produccion modificada: no.
- Supabase modificado: no.
