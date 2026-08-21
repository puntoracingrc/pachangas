# Demo World V1 Report

## Checkpoint

- Auditoria iniciada: 2026-08-11 (Europe/Madrid).
- Base inicial: `851418d688e4078d9fb9166174b961dc5c22d4d9` (`origin/main` al abrir la rama).
- Main integrado para el cierre: `7e7cfdf110110d63b92dfee2d5529ffa284c92e5`.
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
| DW-019 | PERFORMANCE_BUG | fixed + regression_verified | La entrada a `/demo` descargaba `core`, `players`, `matches` y `activity` en paralelo, aunque Inicio solo necesita una parte del mundo. | `core` incorpora el preview inicial; los tres dominios secundarios se solicitan una sola vez al abrir una seccion profunda. | Test de carga diferida + red fria: Inicio solo solicita `core`; Equipo solicita despues los otros tres chunks, todo por `GET`. |
| DW-020 | DEMO_DATA_BUG | fixed + regression_verified | Equipo mostraba una clasificacion por equipos propia de la demo, pero no reproducia el Ranking Provincial ni los estados de elegibilidad de Season Score V3. | Read model V3 congelado y tablero compartido con `/ranking`: 55/30/15, Top 10, #27 y tres estados no clasificados. | Regresion de formula, umbrales, revision, premios OFF y texto `Pendiente de verificación`. |
| DW-021 | DEMO_DATA_BUG | fixed + regression_verified | Los partidos incluian convocados y reservas, pero no una evidencia canonica de asistencia que diferenciase jugo, baja justificada, cancelacion tardia y no-show. | Se anaden 168 evidencias publicas con cuatro estados explicitos, sin sanciones automaticas. | Regresion de distribucion, referencias a partido/jugador y pertenencia de `played` a la alineacion canonica. |
| DW-022 | DEMO_ADAPTER_BUG | fixed + regression_verified | Abrir una caja solo cambiaba su estado local a guardada; no existia el ciclo visible pieza nueva, inventario y equipar en la carta. | Inventario efimero, distintivo NEW y equipamiento local reversible mediante Reiniciar. | Regresion de hat-trick/caja/pieza + QA manual abrir, guardar, NEW, equipar y reset. |
| DW-023 | DEMO_DATA_BUG | fixed + regression_verified | Las historias no cubrian de extremo a extremo hat-trick, caja, pieza nueva, equipamiento, asistencia y entrada al ranking. | Catalogo ampliado a 12 historias enlazadas a evidencias canonicas. | Regresion de tipos, referencias resolubles y cobertura de asistencia, reward y ranking. |
| DW-024 | PERFORMANCE_BUG | fixed + regression_verified | El Service Worker no reconocia `/demo` como navegacion cacheable ni los chunks con query de hash como recursos estaticos. | `/demo` y manifest entran en precache; chunks hasheados usan stale-while-revalidate y las escrituras se ignoran. | Regresion sobre el codigo generado del Service Worker. |
| DW-025 | PERFORMANCE_BUG | fixed + regression_verified | La carga real de Inicio solicitaba los chunks JavaScript de Three.js y de la caja aunque ninguna caja estuviese abierta. | El modulo 3D se importa al seleccionar una caja, no al montar Perfil. | Red fria sin Three/GLB/Draco; tras abrir, canvas visible y assets 3D cargados bajo demanda. |
| DW-026 | DEMO_ADAPTER_BUG | fixed + regression_verified | Al cambiar desde Admin a Jugador con Admin de partido abierto, desaparecia el permiso pero el panel seguia apuntando a `admin` y quedaba vacio. | El panel visible se deriva de rol/estado y `MatchView` se reinicia por perspectiva. | Regresion unitaria + QA Admin a Jugador: reaparece `Mi asistencia`. |
| DW-027 | DEMO_UX_BUG | fixed + regression_verified | Mercado renderizaba 48 fichas a la vez y producia mas de 11.000 px de scroll en 360x800. | Primera pagina de 12 y accion local `Mostrar más` en bloques de 12; buscar reinicia el limite. | Regresion de fuente + QA 360x800: 12, 24 y filtro restaurado sin writes. |
| DW-028 | DEMO_UX_BUG | fixed + regression_verified | El modo juego ocultaba la cabecera y con ella el unico selector de perspectiva. | Perfil incorpora `Perspectiva en modo juego` dentro del submenu visible en apaisado tactil. | QA 844x390 cambia a Admin sin overflow ni salir de Demo World. |
| DW-029 | TESTABILITY_GAP | fixed + regression_verified | `visual-audit-v1` esperaba 650 ms y podia medir `/demo` antes de que el snapshot inicial estuviese listo. | El auditor espera `[data-demo-world='ready']` antes de acciones y metricas. | Matriz final 114/114 sin falsos fallos de navegacion. |
| DW-030 | ENVIRONMENT_ISSUE | fixed + regression_verified | En `next dev`, el Chrome aislado recibia HTML y `core.json` desde `127.0.0.1` pero no hidrataba; `localhost` si. | `localhost` pasa a ser el origen local canonico del auditor. | Diagnostico A/B conservado + matriz final completa en `localhost`: 114/114. |
| DW-031 | CODE_QUALITY_BUG | fixed + regression_verified | React 19 rechazo dos `setState` sincronicos dentro de efectos: panel Admin y paginacion de busqueda. | Panel derivado y reinicio de pagina dentro del evento de busqueda. | Lint focalizado PASS + regresiones de rol y paginacion + QA manual. |
| DW-032 | DEMO_DATA_BUG | fixed + regression_verified | La historia del puesto 27 enlazaba `demo_ranking_entry_01`, que identifica la primera fila del Top 10, porque el showcase propio no exponia su `entryKey`. | El read model propio conserva `demo_ranking_entry_27` y la historia enlaza esa evidencia. | Regresion exacta de historia, jugador, `entryKey` y posicion 27; 22/22 pruebas Demo PASS. |
| DW-033 | PRODUCT_BUG | fixed + regression_verified | El smoke anonimo posterior al merge revelo que `/` seguia mostrando la demo heredada completa cuando no habia sesion ni equipo, aunque `?demo=1` ya redirigia a `/demo`. Quedaban dos demos publicas competidoras y el acceso principal no enseñaba un CTA al Mundo Demo V1. | La raiz sin equipo termina antes de montar las superficies heredadas y presenta una entrada compacta con login, creacion de grupo y CTA `/demo`. El seed antiguo queda como `INTERNAL_FIXTURE`, sin consumidor publico. | Regresion de fuente + QA local desktop, 390x844 y 844x390: CTA abre `/demo`, formulario de grupo cabe, el CTA queda en el primer viewport y no aparecen `Demo jueves` ni `Jugadores del próximo partido`. |

## Estado del cierre

## Arquitectura elegida

`/demo` es una aplicacion publica aislada que carga un manifest versionado y cuatro chunks JSON estaticos. Inicio recibe solo un preview canonico desde `core`; los tres dominios secundarios se cargan una vez al entrar en cualquier seccion profunda. El generador reutiliza Rating V2 y los catalogos productivos de cosmeticos; el cliente reutiliza `PlayerCosmeticCard`, `TeamShieldView`, `RewardBoxDemo`, `MobileAppNav` y el mismo tablero de Ranking Provincial que produccion.

El modo heredado `?demo=1` redirige al nuevo mundo. El centro global de notificaciones conectado y el footer real no se montan en `/demo`. No se han creado usuarios Auth, tablas, migraciones, funciones RPC ni filas ficticias.

## Dataset congelado

| Metrica | Resultado |
| --- | ---: |
| Equipos | 30 |
| Jugadores | 331 |
| Partidos | 128 |
| Retos | 48 |
| Evidencias de asistencia | 168 |
| Logros | 75 |
| Cajas | 28 |
| Avisos | 12 |
| Historias | 12 |
| Perspectivas | 3 |

Territorios: Barcelona 9 equipos, Valles 9, Girona 6 y Maresme 6. Hay 120 partidos finalizados y 8 programados; 53 son externos/Reto y 75 internos. Los 48 Retos cubren `countered` (2), `pending` (2), `accepted` (2), `rejected` (1), `cancelled` (1) y `completed` (40).

Mercado incluye 48 perfiles publicos abiertos, un agente libre, 24 equipos retables y 8 partidos con plazas. El Ranking Provincial muestra el Top 10 sobre 32 entradas y permite comprobar una ficha #27, otra no elegible, una provisional y una pendiente de verificacion. Los premios territoriales permanecen desactivados.

## Rating y progresion

- Jugadores de campo: read models calculados con `pachangas-rating-v2`.
- Porteros: GRL `null` bajo dominio `goalkeeper_legacy`; no se inventa la formula pendiente.
- Season Score: read model canonico V3 con formula 55/30/15, sin recalculo cliente ni formula alternativa.
- Team Rewards: los cinco mappings productivos siguen exactos y cada grant tiene evidencia.
- Premium Ball: ausente y no activado.
- Premium Art Pack: ninguna de sus 29 propuestas se declara propiedad o reward.

## Diversidad visual

| Indicador | Resultado |
| --- | ---: |
| Loadouts de jugador unicos | 187 de 331 |
| Base/casi base, 0-1 piezas | 77 (23,3 %) |
| Ligera, 2 piezas | 62 (18,7 %) |
| Media, 3 piezas | 78 (23,6 %) |
| Alta, 4-5 piezas | 114 (34,4 %) |
| Piezas Premium/Oro equipadas | 0 |
| Escudos unicos | 30 de 30 |
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
- Abrir una caja 3D determinista, guardar la pieza, verla como NEW y equiparla localmente.
- Recorrer 48 jugadores de Mercado en paginas locales de 12.
- Comparar Top 10, #27, no elegible, provisional y pendiente de verificacion.
- Reiniciar el mundo.

La unica persistencia es `sessionStorage`. Reset borra asistencia, cajas abiertas, inventario, marcas NEW, equipamiento, avisos leidos y perspectiva. Las acciones nunca se representan como confirmaciones del servidor ni generan una cola offline.

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
| Core | 76.158 |
| Players | 323.156 |
| Matches | 169.906 |
| Activity | 34.032 |
| Payload canonico total | 603.252 |

El manifest y los cuatro chunks ocupan 62.650 bytes con gzip y 49.244 con Brotli. El presupuesto canonico total sigue por debajo de 700 KB sin comprimir.

Inicio solicita solo `core.json`; la primera seccion profunda solicita `activity`, `matches` y `players`, todos cacheados por hash. La caja 3D no solicita Three.js, GLB ni Draco hasta que el usuario la abre. El Service Worker conserva la navegacion Demo y chunks inmutables, pero nunca mutaciones. Los avatares son SVG deterministas inline y no dependen de hosts remotos.

Seed: `pachangas-iq-demo-world-v1-2026-27`.

Hash: `34158b4f56a3011c9010b0952f74043435e9f896f0b7ea5fd90e0dfacdfac3ae`.

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

Visual Audit final del HEAD local: 114 combinaciones, 19 superficies Demo por seis viewports (`1440x900`, `1920x1080`, `390x844`, `360x800`, `844x390` y PWA portrait). Resultado: cero errores de navegacion/consola, warnings, solicitudes fallidas, imagenes rotas, overflow horizontal, targets pequenos, violaciones de viewport o chrome de juego. Evidencia canonica: `artifacts/demo-world-v1/visual-audit/demo-world-v1-final/` y capturas en `artifacts/demo-world-v1/visual-audit/focused/`.

La red se comprobo tambien en frio: Inicio solicita el manifest y solo `core`; al entrar en Equipo llegan `activity`, `matches` y `players`. No aparece ninguna peticion distinta de `GET`. Three.js, GLB y Draco no se descargan antes de abrir una caja y si se cargan al pulsarla, con canvas visible.

Tema explicito: Claro `rgb(238, 242, 239)` / texto `rgb(16, 32, 26)` y Oscuro `rgb(7, 17, 15)` / texto `rgb(241, 246, 242)`, ambos sin overflow, errores, warnings o targets pequenos.

Spot checks manuales ya realizados:

- desktop 1440x900;
- portrait 390x844 y 360x800;
- landscape 844x390 con modo juego;
- tablet tactil 1024x768 con modo juego;
- PWA standalone;
- Ranking Provincial Top 10, #27, no elegible, provisional y pendiente;
- cambio Admin a Jugador con panel Admin abierto;
- Mercado 12 a 24 y busqueda con restauracion del limite;
- caja abrir, guardar, NEW, equipar y Reiniciar;
- contact sheets de cartas y escudos.

## Experiencia de descubrimiento

Recorrido de dos minutos: Inicio expone equipo/carta, proximo partido, Ranking Provincial, historias y avisos sin descargar aun el mundo completo; la navegacion superior/inferior permite llegar a Partido, Retos y Mercado sin modal obligatorio.

Recorrido de diez minutos: permite cambiar perspectiva incluso en modo juego, abrir fichas, recorrer historicos, alineacion y goleadores, comparar equipos/escudos, revisar logros, asistencia y estados de ranking, y completar el ciclo de caja, inventario NEW y equipamiento. Mercado entrega primero 12 perfiles y revela el resto de 12 en 12.

## Documentos relacionados

- `DEMO_WORLD_V1_DATA_CONTRACT.md`
- `DEMO_WORLD_V1_STORIES.md`
- `artifacts/demo-world-v1/visual-audit/`

## Validaciones finales

| Gate | Estado |
| --- | --- |
| `npm run test:demo-world` | PASS, 22/22 |
| Red de navegador, cero writes | PASS |
| Focused lint | PASS |
| `npm test` | PASS: build + 20/20 base + 274/274 funcionales |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, Next.js 16.2.6, 33 paginas estaticas generadas |
| Visual Audit V1 focalizado | PASS, 114/114 |
| Preview Vercel exacta | PASS en `59f8ed4b83ff4d73628bd7b4411684284fd8d80a`: `/demo` publico protegido, acceso legado redirigido, cinco secciones, portrait, landscape y caja 3D bajo demanda |
| Global lint | deuda previa: 23 errores y 20 warnings fuera de los modulos Demo |
| `git diff --check` | PASS antes de commit; se repite al cerrar |

## Publicacion

- Rama: `codex/demo-world-v1`.
- Commit de implementacion validado: `2af987832e59a321ddf8c177dfca4fea2c38ded1`.
- PR draft: `https://github.com/puntoracingrc/pachangas/pull/140`.
- Preview Vercel de implementacion validada: `https://pachangas-inra7ez0e-persianas-almar-web-s-projects.vercel.app/demo` (`59f8ed4b83ff4d73628bd7b4411684284fd8d80a`).
- QA remota: carga fria solo de `core`, chunks secundarios al abrir Equipo, cero writes, navegacion completa, 390x844 y 844x390 sin overflow, caja 3D diferida y ciclo guardar/equipar/reiniciar correcto.
- Merge: no.
- Produccion modificada: no.
- Supabase modificado: no.
