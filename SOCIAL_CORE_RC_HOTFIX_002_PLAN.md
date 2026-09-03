# Social Core RC Hotfix 002 - Plan

## Checkpoint

- Auditoria iniciada: `2026-09-03 07:43:14 CEST`.
- Repositorio: `puntoracingrc/pachangas`.
- Checkout compartido: `/Users/macbookpro14/Documents/steam deck`, rama local `main`, 649 commits por detras de `origin/main` y con cambios preexistentes fuera de este trabajo.
- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-social-core-rc-hotfix-002`.
- Rama funcional: `codex/social-core-rc-hotfix-002`.
- Base real: `origin/main` en `fe6430a8f02dadf4300645d07713d91bcbc15cd0`, coincidente con el checkpoint esperado y conteniendo los PR #260 y #261.
- Deployment productivo de referencia: `dpl_49uSaxXrngooxXnSRNhGLdPWJjRk`, estado conocido `READY`.
- Produccion de referencia: <https://pachangasiq.com>.
- Service Worker de referencia: `2.0.0+sw.fe6430a8f02d`.
- Entorno local: macOS Darwin `24.6.0` arm64, Node `v24.16.0`, npm `11.13.0`, Chromium controlado y servidor Next local en `http://localhost:3098`.
- Informe fuente esperado: `/tmp/pachangas-social-core-field-review-v1/SOCIAL_CORE_FIELD_REVIEW_V1.md`.
- SHA-256 esperado del informe: `296ff621313ff07e9feb351d36b2c5fcf1058b4a25da6b5d823abfbd21226979`.
- Estado del informe fuente: ausente. No se reconstruye ni se atribuye contenido al archivo eliminado; las reproducciones se han repetido contra produccion y contra el codigo exacto de `origin/main`.
- Baseline limpio: `npm ci` PASS; Node `20/20`; TS/TSX `815/815`; total `835/835`; failed/skipped/todo/cancelled `0/0/0/0`; typecheck PASS; build PASS con 78 rutas; lint PASS; `git diff --check` PASS.
- Los archivos `AGENTS.md` y `CLAUDE.md` sin seguimiento fueron generados por `next dev`; son temporales del servidor local, no forman parte del hotfix y se retiraran al cierre.

## Reconciliacion de defectos

### SOCIAL-RC-002 - Usuario nuevo conserva la perspectiva anterior

- Severidad: P2.
- Clasificacion: `REPRODUCED_DEMO_STATE_DEFECT`.
- Intento 1, produccion: abrir `/demo?tab=inicio&perspective=admin`, abrir `Revision rapida`, elegir `Usuario nuevo` y pulsar `Abrir recorrido`. El recorrido de primera vez se abre, pero URL, cabecera y selector siguen en `admin`.
- Intento 2, `origin/main` local: repetir desde `http://localhost:3098/demo?tab=inicio&perspective=admin&review=1`. La URL permanece en `perspective=admin`, el contexto accesible sigue siendo `team - Admin del grupo` y el dialogo de usuario nuevo aparece encima de la portada admin.
- Causa confirmada: `DemoSocialQuickReview.openJourney` llama a `onOpenFirstTime()` sin entregar `journey.perspectiveId`; el callback padre solo intercambia dialogos y nunca ejecuta `choosePerspective`. El restaurador `popstate` tampoco sincroniza la apertura de los dialogos con `journey`/`review`.
- Correccion minima: entregar `free-agent` al callback, activar perspectiva e Inicio antes de abrir el recorrido, escribir una ruta coherente con `journey=first-time`, sincronizar Back/Forward con esa ruta y retirar el parametro al cerrar sin reiniciar la sesion.
- Archivos previstos: `app/demo-world/demo-social-quick-review.tsx`, `app/demo-world/demo-world-app.tsx`.
- Cierre: desde admin, owner o jugador siempre abre como `free-agent`; URL, React y sessionStorage convergen; cerrar, recargar, Back y Forward no mezclan perspectivas; los otros seis recorridos conservan su perspectiva declarada; `remoteWrites = 0`.

### SOCIAL-RC-003 - El boton de ubicacion comprime el buscador

- Severidad: P3.
- Clasificacion: `REPRODUCED_RESPONSIVE_DEFECT`.
- Intento 1, produccion `360x800`: en `/demo?tab=mercado&perspective=player`, el boton de ubicacion ocupa una columna de 44 px pero conserva 80 px de contenido textual, mide 74 px de alto y comprime/recorta su etiqueta junto al campo de 238 px y el control de limpieza.
- Intento 2, `origin/main` local `360x800`: mismas medidas (`44/80` px de caja/contenido para ubicacion, buscador 238 px, control de limpieza 44 px); no hay overflow de raiz, pero la accion no adopta el primitive iconico movil del Mercado real.
- Causa confirmada: Demo reutiliza `locationRow`, pero su boton carece de `locationAction`, icono y `span`; por tanto, la media query no puede ocultar solo la etiqueta y conservar el target 44x44.
- Correccion minima: aplicar el primitive compartido existente al boton Demo, conservar su nombre accesible/title e incorporar el mismo icono de ubicacion. No se cambian geolocalizacion, filtros, consultas ni contador.
- Archivos previstos: `app/demo-world/demo-world-app.tsx`, `app/mercado/marketplace-v3d.module.css` para completar el primitive responsive ya compartido.
- Cierre: buscador util en 360/390 px, accion identificable con target minimo 44x44, foco visible, consultas cortas/largas sin overflow; desktop y landscape conservan la etiqueta completa cuando cabe.

### SOCIAL-RC-005 - Nombres internos de versiones visibles

- Severidad: P3.
- Clasificacion: `REPRODUCED_CODE_DEFECT`.
- Intento 1, produccion: el recorrido de usuario nuevo muestra `Mundo Demo - First-time social journey` y, al llegar a `Como quieres empezar`, `Abre Mercado V3D con datos ficticios`; las etapas posteriores contienen `Partidos V3B`, `Retos V3C`, `Mercado V3D` e `Invitacion de jugador V2`.
- Intento 2, `origin/main` local: al completar los dos primeros pasos aparecen dos ocurrencias visibles de `V3D`; la inspeccion de los recorridos sociales confirma tambien V3B/V3C, y el detalle colapsable de Mercado incluye nombres de fase.
- Causa confirmada: textos de laboratorio quedaron escritos directamente en JSX y en el ledger social, aunque los identificadores tecnicos y `data-*` pueden seguir siendo internos.
- Correccion minima: sustituir solo copy visible de las superficies sociales por lenguaje de producto. Se preservan nombres de archivos, tipos, tests, atributos, documentacion historica, version real del Service Worker, `SIMULACION` y todos los valores de garantia.
- Archivos previstos: `app/demo-world/demo-social-first-time-contract.ts`, `app/demo-world/demo-social-first-time-journey.tsx`, `app/demo-world/demo-social-inbox.tsx`, `app/demo-world/demo-world-app.tsx`, y el selector compartido para traducir el tipo visible sin alterar su valor tecnico.
- Cierre: el DOM social renderizado no expone V3/V3H/V3.5/RC/Official UI/read model/fases; `/admin/demo` y los identificadores tecnicos quedan intactos.

### SOCIAL-RC-007 - Cuatro acciones equivalentes en el detalle de un reto

- Severidad: P2.
- Clasificacion: `REPRODUCED_DEMO_STATE_DEFECT`.
- Intento 1, produccion: abrir Retos como owner/admin y el detalle de la contrapropuesta de Vertice Gracia. Se presentan al mismo nivel `Aceptar cambios`, `Proponer otro momento`, `Rechazar` y `Ver como Vertice Gracia`.
- Intento 2, `origin/main` local: la misma contrapropuesta vuelve a mostrar los cuatro botones consecutivos sin agrupacion destructiva ni separacion de la herramienta de perspectiva.
- Causa confirmada: `demoChallengeActions` es un unico flex para acciones primaria, secundaria y destructiva, mientras `demoPerspectiveSwitch` usa una apariencia de boton equivalente. No existe guarda local comun para dobles mutaciones.
- Correccion minima: mantener una sola accion primaria por estado, dejar la contrapropuesta como secundaria, mover cancelar/rechazar a un menu `Mas acciones` claramente destructivo, presentar el cambio de perspectiva en una franja de revision aparte y bloquear una segunda mutacion mientras se procesa la primera.
- Archivos previstos: `app/demo-world/demo-world-app.tsx`, `app/demo-world/demo-world.module.css`.
- Cierre: pendiente recibido, pendiente enviado, contrapropuestas recibida/enviada, aceptado y jugador sin permiso conservan capacidades y maquina de estados; orden visual/DOM/teclado coinciden; Demo sigue local y live sigue server-authoritative.

### SOCIAL-RC-009 - Ver proximo partido abre el calendario

- Severidad: P2.
- Clasificacion: `REPRODUCED_CODE_DEFECT`.
- Intento 1, produccion: desde Inicio admin, `Ver proximo partido` navega a `/demo?tab=partido&perspective=admin` y muestra `Tu calendario de juego`, sin `match` ni detalle.
- Intento 2, `origin/main` local: resultado identico; URL sin ID y H1 del calendario general.
- Causa confirmada: `WorldHome` calcula `upcoming`, pero la accion principal llama a `onTab("partido")` en vez de `onMatch(upcoming[0].id)`.
- Correccion minima: abrir el primer partido programado ya ordenado mediante `onMatch`; si ya no existe, usar la vista general existente como fallback humano. No se cambia el calendario.
- Archivos previstos: `app/demo-world/demo-world-app.tsx`.
- Cierre: admin/owner/jugador abren el ID sintetico exacto, conservan equipo/perspectiva, Back vuelve a Inicio y Forward restaura el detalle; sin partido, el fallback no inventa uno.

### SOCIAL-RC-011 - El selector de contexto pierde informacion en desktop

- Severidad: P3.
- Clasificacion: `REPRODUCED_RESPONSIVE_DEFECT`.
- Intento 1, produccion `1440x900`: las opciones del selector solo dicen `Jugador del grupo`, `Admin del grupo`, `Jugador sin equipo` y `Owner de equipo`; tipo, detalle, estado y siguiente accion quedan fuera de cada opcion y sin descripcion completa.
- Intento 2, `origin/main` local `1440x900`: el select mide unos 113 px, no tiene title descriptivo y repite las mismas etiquetas simples; CSS limita el detalle a `32vw` con ellipsis.
- Causa confirmada: cada `<option>` renderiza solo `context.title`; el tipo se muestra como identificador ingles, el detalle se trunca y no existe un nombre/descripcion calculado con todos los campos existentes.
- Correccion minima: crear una etiqueta calculada y deduplicada con `title`, tipo humano, rol, detalle, estado y siguiente accion; usarla en opciones y descripcion accesible; permitir wrap y ancho util en desktop; conservar portrait y landscape compactos.
- Archivos previstos: `app/_components/product-context-selector.tsx`, `app/_components/product-context-selector.module.css`.
- Cierre: uno o varios contextos, titulos largos/iguales, rol/detalle distintos, status y nextAction son distinguibles; no se crean datos ni contextos; cero overflow en todos los viewports.

### SOCIAL-RC-012 - Franja de garantias no accesible con teclado

- Severidad: P2.
- Clasificacion: `REPRODUCED_ACCESSIBILITY_DEFECT`.
- Intento 1, produccion `390x844`: la franja desborda horizontalmente, pero es un `div` generico con `tabIndex=-1`, sin rol navegable ni pista de desplazamiento; el dialogo solo considera botones en su trampa de foco.
- Intento 2, `origin/main` local `390x844`: ancho visible 372 px frente a 673 px desplazables, `role=null`, `tabIndex=-1` y scrollbar oculto. No puede recibir foco ni manejar flechas/Home/End.
- Causa confirmada: `.proof` oculta scrollbar y no tiene semantica, foco ni teclado; el selector de focusables de `handleKeyDown` excluye cualquier `tabindex` explicito.
- Correccion minima: region con nombre y un unico tab stop, ArrowLeft/ArrowRight/Home/End con desplazamiento inmediato, foco visible y scrollbar fino; incluirla en la contencion de foco sin convertir chips en botones.
- Archivos previstos: `app/demo-world/demo-social-quick-review.tsx`, `app/demo-world/demo-social-quick-review.module.css`.
- Cierre: teclado recorre todo el contenido en desktop/portrait/landscape; Tab/Shift+Tab siguen contenidos, Escape cierra, foco vuelve al opener, forced colors/reduced motion se conservan y las siete garantias no cambian.

## Regresiones requeridas

- Los otros seis recorridos de Revision rapida mantienen perspectiva y destino.
- SOCIAL-RC-001: Inicio -> Partidos -> Mercado, dos Back, dos Forward y deep link sin bucle.
- SOCIAL-RC-004: Mercado sin sesion muestra `Sin consultar`; cero solo tras lectura autoritativa vacia.
- SOCIAL-RC-006: Avisos -> asistencia -> partido exacto -> respuesta local -> badge reducido -> Avisos.
- SOCIAL-RC-008: dialogos de Mercado conservan foco inicial, inert, Tab/Shift+Tab, Escape, scroll y retorno al opener.
- SOCIAL-RC-010: solicitud `idle -> sending -> pending`, reapertura consistente, doble envio bloqueado y offline sin fake success.
- Reto: una sola mutacion por gesto y las acciones de todos los estados/roles siguen disponibles.
- Proximo partido: ID exacto, `matchView=detail`, Back/Forward y fallback sin inventar datos.
- Selector: etiqueta calculada para un contexto, multiples, nombres largos e iguales.
- Garantias: semantica, foco, flechas, Home/End, Escape y focus trap.

## Matriz de QA

| Superficie | 1440x900 | 1280x720 | 1024x768 | 390x844 | 360x800 | 844x390 |
| --- | --- | --- | --- | --- | --- | --- |
| Revision rapida / Usuario nuevo | dark + teclado | light | dark | dark + touch | light | game landscape |
| Mercado ubicacion | dark | light | dark | dark + consultas | light + consultas | game landscape |
| Retos detalle | owner/admin/player | owner | admin | owner + teclado | player | owner + teclado |
| Inicio / proximo partido | admin | owner | player | admin | player | owner |
| Selector de contexto | 1/multiples/largos/iguales | multiples | largos | compacto | compacto | game compacto |
| Garantias | teclado/Axe | teclado | forced colors | teclado/touch | reduced motion | teclado/game |

En cada celda aplicable: root overflow, imagenes, cortes, targets, hidratacion, consola, red, foco, orden DOM, nombres accesibles y Axe critico/serio. Se repetira una pasada standalone PWA emulada con actualizacion, offline y reconexion. Android fisico, iPhone fisico y PWA fisicamente instalada permanecen `PENDING`.

## Areas expresamente prohibidas

No se modificaran `supabase/`, SQL, migraciones, RPC, RLS, flags, Auth, Stripe, Billing, Rating, resultados, confirmacion bilateral, recompensas, logros, cajas, cosmeticos, cartas, escudos, Conduct, Clubes, Competiciones, Manifest, estrategia de Service Worker, Background Sync, dependencias ni `package-lock.json`. No se iniciara Official UI V3I ni se reanudara Wave 9C. No se crearan usuarios, equipos, partidos, retos, solicitudes, notificaciones, pagos ni ninguna entidad real.

## Archivos previstos del lote funcional

- `SOCIAL_CORE_RC_HOTFIX_002_PLAN.md`.
- `SOCIAL_CORE_RC_HOTFIX_002_REPORT.md`.
- `SOCIAL_CORE_RC_HOTFIX_002_BEFORE_AFTER.png`.
- `app/_components/product-context-selector.tsx`.
- `app/_components/product-context-selector.module.css`.
- `app/demo-world/demo-social-first-time-contract.ts`.
- `app/demo-world/demo-social-first-time-journey.tsx`.
- `app/demo-world/demo-social-inbox.tsx`.
- `app/demo-world/demo-social-quick-review.tsx`.
- `app/demo-world/demo-social-quick-review.module.css`.
- `app/demo-world/demo-world-app.tsx`.
- `app/demo-world/demo-world.module.css`.
- `app/mercado/marketplace-v3d.module.css`.
- `tests/social-core-rc-hotfix-002.test.ts`.
- `tests/official-ui-v3f-social-team-core.test.ts`, solo para reconciliar la expectativa historica de copy con la etiqueta humana renderizada.
- `package.json`, exclusivamente para incluir la nueva regresion en la bateria; `package-lock.json` debe permanecer intacto.

## Criterio de salida

Los siete IDs deben quedar `FIXED + REGRESSION_VERIFIED` o, si surgiera evidencia contradictoria, `NOT_REPRODUCED` con dos intentos y sin parche especulativo. Solo despues pasaran suite completa, QA visual/teclado/Axe/PWA, Preview exacta, PR funcional, merge, deployment, smoke productivo sin escrituras, PR documental y limpieza exclusiva de este worktree.
