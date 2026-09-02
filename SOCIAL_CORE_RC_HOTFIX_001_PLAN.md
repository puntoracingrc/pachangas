# Social Core RC Hotfix 001 - Plan

## Checkpoint

- Rama base: `origin/main`.
- SHA base: `c762948cad6fc80579189c4e6f33b41de13820a4`.
- Deployment auditado: `dpl_6GcXaumwXj17hKoic2VzBGggeppv`.
- Informe fuente: `/tmp/pachangas-social-core-field-review-v1/SOCIAL_CORE_FIELD_REVIEW_V1.md`.
- SHA-256 del informe fuente: `296ff621313ff07e9feb351d36b2c5fcf1058b4a25da6b5d823abfbd21226979`.
- Evidencias revisadas en el paquete fuente: 91 archivos, sin copiarlos al repositorio.
- Supabase, Stripe, entidades reales y notificaciones reales: fuera de alcance.

## Defectos incluidos

### SOCIAL-RC-006 - El aviso de asistencia no puede resolverse

- Clasificación original: `FUNCTIONAL`, P1.
- Reproducción exacta: `/demo?tab=avisos&perspective=admin`, Chromium PWA emulada, `390x844` portrait, release actual con Service Worker. Abrir `Pendientes`, seleccionar `Confirma si juegas` y pulsar `Revisar`.
- Resultado observado: el aviso abre el resumen del partido como Admin Demo, no aparecen `Voy / Duda / No voy` y el contador permanece en 3. Reproducido `2/2` y clasificado `REPRODUCED_DEMO_STATE_DEFECT`.
- Causa confirmada: la acción se crea para la perspectiva admin y selecciona el partido correcto, pero `MatchView` limita la respuesta de asistencia a `perspective.role === "player"`. Además, el botón de retorno del partido ignora que el origen fue Avisos.
- Corrección mínima prevista: derivar la capacidad de responder de la pertenencia del actor al equipo, permitir que owner/admin responda por sí mismo en Demo, conservar la mutación exclusivamente local y devolver a Avisos cuando el partido se abrió desde ese aviso.
- Criterio de cierre: aviso pendiente -> partido correcto -> control visible -> respuesta local -> aviso resuelto -> badge reducido -> retorno a Avisos; `remoteWrites = 0`.
- Regresión requerida: admin/jugador, tres estados de asistencia, retorno, badge e Inicio sin obligación duplicada.

### SOCIAL-RC-008 - Los detalles de Mercado no gestionan foco ni Escape

- Clasificación original: `ACCESSIBILITY`, P2.
- Reproducción exacta: `/demo?tab=mercado`, jugador y admin Demo, Chromium PWA emulada, `390x844` portrait. Abrir ficha, comprobar foco, Tab, Shift+Tab, Escape, cerrar y repetir con jugador/equipo/partido.
- Resultado observado: el foco permanece en el trigger del fondo, Escape no cierra y Axe señala `aria-allowed-role` en `aside[role=dialog]`. Reproducido `2/2` en esta pasada y `3/3` en la auditoría; clasificado `REPRODUCED_ACCESSIBILITY_DEFECT`.
- Causa confirmada: `MarketDetailSheet` es un `aside` con `role="dialog"`, sin apertura modal nativa, foco inicial, contención de Tab, Escape, bloqueo de scroll ni restauración al trigger.
- Corrección mínima prevista: convertir solo este primitive compartido en `dialog` modal, enfocar una acción segura, contener Tab/Shift+Tab, cerrar con Escape, bloquear/restaurar scroll y devolver el foco al disparador.
- Criterio de cierre: semántica válida, fondo inerte, foco dentro durante apertura, cierre por Escape/botón y retorno al trigger tras aperturas repetidas, sin violaciones Axe críticas o serias nuevas.
- Regresión requerida: foco inicial, Tab, Shift+Tab, Escape, retorno, fondo modal y reduced motion.

### SOCIAL-RC-001 - Atrás abandona el Mundo Demo

- Clasificación original: `NAVIGATION`, P2.
- Reproducción exacta: entrar desde Landing a `/demo`, `1280x720` desktop Chromium, recorrer Inicio -> Partidos -> Mercado y pulsar Atrás del navegador.
- Resultado observado: Atrás vuelve a Landing porque las transiciones internas sustituyen la misma entrada. Reproducido `2/2` y clasificado `REPRODUCED_CODE_DEFECT`.
- Causa confirmada: la navegación primaria de `DemoWorldApp` y el estado interno de Mercado usan `history.replaceState` y no existe restauración `popstate` en la shell Demo.
- Corrección mínima prevista: crear entradas reales solo para transiciones navegables, restaurar la ruta Demo desde `popstate`, mantener `replaceState` para filtros/estado de la entrada actual y sembrar un fallback Inicio en accesos directos profundos.
- Criterio de cierre: Atrás recorre Mercado -> Partidos -> Inicio; Adelante restaura; un deep link directo vuelve primero a Inicio y un segundo Atrás puede abandonar Demo; no hay bucles.
- Regresión requerida: browser Back/Forward, botón interno, entrada directa, reload, perspectiva, detalle de Mercado y retorno desde Partidos/Retos/Mercado/Equipo/Avisos.

### SOCIAL-RC-004 - Mercado sin sesión afirma que hay cero resultados

- Clasificación original: `EMPTY_STATE`, P2.
- Reproducción exacta: `/mercado`, visitante sin sesión, Chromium normal/emulado, `390x844` portrait, caché limpia y repetición con caché actual; esperar el fin de carga.
- Resultado observado: aparecen a la vez `0 partidos encontrados`, `No disponible` y una explicación técnica aunque no se ejecutó la consulta autenticada. Reproducido `2/2` en esta pasada y `3/3` en la auditoría; clasificado `REPRODUCED_CODE_DEFECT`.
- Causa confirmada: `resultCount` se renderiza con arrays inicialmente vacíos sin condicionarlo al estado de la fuente; la ausencia de sesión se clasifica como `UNAVAILABLE` en vez de `IDLE/NOT_QUERIED`.
- Corrección mínima prevista: distinguir `IDLE`, `LOADING`, `LIVE`, `CACHED` y `UNAVAILABLE`; mostrar contador solo tras lectura `LIVE` o `CACHED`; usar una explicación humana y CTA de entrada cuando todavía no se consultó.
- Criterio de cierre: nunca se muestra cero en IDLE, LOADING, UNAVAILABLE u offline sin caché; cero solo existe tras una lectura autoritativa vacía; caché y error conservan su etiqueta correcta.
- Regresión requerida: sin sesión, loading, error, caché, vacío real, resultados y filtros conservados.

### SOCIAL-RC-010 - Solicitar plaza no confirma dentro del detalle

- Clasificación original: `CONTEXT_LOSS`, P2.
- Reproducción exacta: `/demo?tab=mercado&perspective=player&marketPane=partidos`, Chromium emulado, `390x844` portrait. Abrir un partido público y pulsar `Solicitar plaza`.
- Resultado observado: la tarjeta tapada cambia a `Solicitud enviada`, pero el botón del sheet permanece deshabilitado con `Solicitar plaza` y no muestra confirmación. Reproducido `2/2` en partidos distintos y clasificado `REPRODUCED_DEMO_STATE_DEFECT`.
- Causa confirmada: la tarjeta deriva su presentación de `requestMatchId/requestStatus`; el detalle solo usa ese estado para deshabilitar el botón y conserva una etiqueta fija.
- Corrección mínima prevista: derivar tarjeta y detalle del mismo estado local, mostrar transición de envío y confirmación persistente en el sheet, bloquear duplicados y conservar estado al cerrar/reabrir.
- Criterio de cierre: `Solicitar plaza` -> `Enviando...` -> `Solicitud enviada`; tarjeta y detalle convergen, aceptación muestra `Plaza confirmada`, offline falla cerrado y reiniciar Demo limpia el estado.
- Regresión requerida: envío único, sending, pending, accepted, estados live rejected/cancelled, doble clic, reapertura, cambio de tab y offline.

## Regresiones cruzadas

- Avisos -> Partido -> respuesta -> Avisos.
- Mercado -> solicitud -> detalle -> cerrar/reabrir.
- Demo -> detalle -> Atrás -> Adelante.
- Diálogo -> cierre -> retorno de foco -> segunda apertura.
- Estados de lectura de Mercado sin confundir `UNAVAILABLE` con vacío autoritativo.

## Backlog no incluido

Permanecen `DOCUMENTED / NOT FIXED IN BATCH 001`:

- `SOCIAL-RC-002` - Usuario nuevo conserva la perspectiva anterior.
- `SOCIAL-RC-003` - El botón de ubicación comprime el buscador.
- `SOCIAL-RC-005` - La interfaz muestra nombres internos de versiones.
- `SOCIAL-RC-007` - Cuatro acciones equivalentes en el detalle de un reto.
- `SOCIAL-RC-009` - `Ver próximo partido` abre el calendario.
- `SOCIAL-RC-011` - El selector de contexto pierde información en desktop.
- `SOCIAL-RC-012` - La franja de garantías no es accesible con teclado.

## Gates

Tras la implementación: regresiones focalizadas, `npm ci`, `npm test`, `npm run typecheck`, `npm run build`, `npm run lint`, `git diff --check`, Preview exacta, QA visual/teclado/Axe y smoke productivo. No se tocarán `supabase/`, migraciones, RPC, RLS, flags ni Stripe.
