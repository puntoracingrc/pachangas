# Prueba local del cofre — 2026-09-05

Base: origin/main 9739b84. Rama: codex/reward-chest-animation.

Se recuperó el GLB original versionado `public/models/rewards/reward-box-blue.glb` mediante Blender 5.1.2. No se localizó el .blend fuente anterior; `recovered.blend` es una reconstrucción editable importada del GLB. El original versionado permanece intacto.

- `reward-box-refined.blend`: modelo editable, cámaras y luces de revisión, secuencia 0–90 a 30 fps.
- `reward-box-refined.glb`: exportación comprimida Draco, 566196 bytes, un clip de 3 segundos que contiene todas las piezas animadas.
- `refined-closed.png`, `refined-opening.png`, `refined-open.png`: fotogramas revisados en Blender.
- `inspect.py`, `refine.py`: recuperación y modificación reproducibles usando Blender Python; refine.py debe ejecutarse tras inspect.py.

Cambios: pausa y apertura suavizadas, tapa con asentamiento amortiguado, tarjeta con breve estabilización, conjunto inmóvil. En la web: cámara frontal, encuadre de toda la trayectoria con una acción activa, centrado mediante grupo exterior, reajuste al cambiar tamaño y panel separado del lienzo.

Prueba: http://127.0.0.1:3187/laboratorio-cofre. La página usa únicamente el componente visual, sin otorgar premios.

Validación: render de tres poses en Blender, typecheck, ESLint de componentes, cinco tests de contrato/GLB y compilación Next completados correctamente. No se ha realizado QA visual de navegador ni validación en teléfonos físicos. No publicado, sin PR ni merge.

Se conserva el worktree porque hay cambios sin commit, no existe PR fusionado ni despliegue/validación de producción y el servidor local está disponible para revisión. También se conserva el .blend abierto en Blender. No retirar mientras se esté revisando.

## Acercamiento del sobre

Tras el clip de Blender (3 s), el visor acerca el objeto `Reward_Card` durante 1,25 s y lo orienta hacia la cámara. El destino se calcula según el tamaño del visor para ocupar hasta el 78% de su ancho o alto. Se presenta texto HTML mediante CSS3D, vinculado al mismo objeto, usando `title`, `description` y `eyebrow`; estos datos se actualizan sin reiniciar la animación cuando llega la respuesta del premio. El movimiento reducido muestra directamente el estado final. La prueba presenta “Marco de campeón” como ejemplo, sin otorgarlo.

Este tramo es una presentación adaptativa del visor web, no modifica el clip .blend/.glb de apertura. Se mantiene el flujo original de apertura real/confirmación del premio. ESLint, typecheck y los cinco tests existentes han pasado; compilación actual en build-approach.log. Sigue siendo una prueba local sin publicación ni merge; se conserva el worktree para revisión.

## Secuencia de cofres

La prueba local encadena tres recompensas de ejemplo. Tras completar el acercamiento aparece un botón principal para abrir el siguiente cofre y un contador pendiente; el último permite terminar y ver un resumen de los tres premios. Cada cofre monta de nuevo el visor mediante una key, reiniciando la animación. Cerrar la prueba no marca la secuencia como completada.

En la vista real de identidad, continuar está disponible únicamente tras recibir `openedReward`. La acción avanza y solicita abrir el siguiente mediante la misma función RPC existente, conservando su revisión e idempotencia. Equipar se mantiene como opción aparte. No se ejecutaron RPC ni se alteraron datos reales durante esta tarea.

Validación: ESLint y TypeScript sin errores, 12 tests de modelo/recompensas correctos usando tsx, ruta local HTTP 200; compilación en sequence-build.log. Pendiente revisión visual humana y publicación. Se conserva el worktree con cambios locales y el servidor de prueba, sin PR/merge/despliegue.

## Cinco rarezas

`app/reward-rarity-visuals.json` define la paleta compartida entre Blender y web: común gris verdoso, poco común verde, raro azul, épico morado y legendario dorado. La rareza real llega desde `currentSequenceReward.boxRarity`; la prueba recorre las cinco y permite comenzar en cualquiera.

`rarity-variants.py` produce cinco .blend editables y renders de color en `rarities/`, conservando geometría y clip. Los destellos adicionales, partículas instanciadas y aros se calculan en el visor web, con intensidad creciente; no están horneados en esos .blend. La web sigue descargando un solo GLB. Los efectos terminan a los tres segundos, antes de que finalice el acercamiento del sobre; movimiento reducido suprime partículas y aros.

Se revisaron los cinco renders de Blender. Pasaron 12 tests existentes, TypeScript, ESLint y una comprobación de matrices finitas y finalización de efectos para las cinco rarezas con/sin movimiento reducido. Build final en rarity-build.log. No se ha realizado inspección visual automatizada del navegador ni publicación. Se mantiene el worktree para la revisión local, sin commit/PR fusionado/despliegue de producción.

## Etiqueta en ficha y efectos reforzados

La ficha CSS3D lleva una etiqueta independiente de rareza en la esquina superior izquierda, con colores de su paleta. El texto de contexto se actualiza por su propio selector para no sobrescribir esa etiqueta.

Épico: 100 partículas en espiral, 3 aros y 10 rayos facetados. Legendario: 180 partículas, 5 aros y 20 rayos. Estos efectos terminan a los 3,65 s, antes del final del acercamiento a los 4,25 s. El movimiento reducido mantiene su variante estática. Las variantes .blend conservan los colores; estos efectos son del visor web.

Validación: ESLint, 12 tests existentes, matrices finitas en todos los niveles y movimiento reducido; build en rarity-polish-build.log. Sin publicación; continúa el worktree local pendiente de revisión y merge.

## Prueba con textos reales del catálogo

La prueba utiliza cinco casos del catálogo colectivo V3 (`20260808205638_achievement_catalog_v3.sql`): Doblete repetido/common, Hat-trick repetido/uncommon, Manita repetida/rare, Primer dominio absoluto/epic (primera ocurrencia de base rare) y Quinientos partidos/legendary. Las descripciones se copian del catálogo, incluida la descripción generada del hito de 500 partidos. Se respeta la subida de rareza por primera ocurrencia y el tope legendary.

Son situaciones simuladas con textos reales, no premios reales concedidos ni contenido sorteado confirmado. No se accedió a cuentas ni se invocaron RPC. Se conserva la navegación entre cinco cofres. Build: real-achievements-build.log. Continúa en local, pendiente de revisión/publicación; worktree conservado.

## Sin adelantar ni duplicar el contenido

Se retiran el título, la descripción y el contexto del panel inferior. Permanecen exclusivamente en la ficha; el panel conserva el contador y las acciones. La prueba no muestra el panel hasta el final del acercamiento; el flujo real conserva el botón necesario para solicitar la apertura. La etiqueta accesible del diálogo es genérica para no anticipar el logro. Sigue siendo trabajo local, sin publicar, con el worktree conservado.

## Fila seleccionable de cofres pendientes

El visor muestra miniaturas existentes de Blender por rareza, sin título ni contenido del premio. La fila permanece visible durante la animación, con selección deshabilitada hasta terminar; el cofre actual se identifica visualmente. La selección explícita abre ese cofre; el botón siguiente toma el primero pendiente en el orden original.

La simulación conserva los índices abiertos al cerrar y permite repetir una vez agotados. Se retira cada cofre al terminar su revelado. El flujo real retira una caja únicamente tras la respuesta de apertura confirmada del servidor y permite volver a cajas pendientes anteriores al escoger fuera de orden. No se ejecutaron operaciones en datos reales.

Miniaturas en public/models/rewards/thumbnails copiadas de los renders de esta tarea. Validación en queue-build.log y queue-tests.log. Sigue en local, con worktree/servidor conservados para revisión; sin PR fusionado ni despliegue.

## Audio del cofre

Actualización: la síntesis descrita a continuación ha sido sustituida por grabaciones de Kenney RPG Audio e Impact Sounds (CC0). Se usan cierre metálico, papel, aire, madera y pequeños impactos de cristal, con 0/2/4/7/10 partículas según rareza y capas adicionales para épico/legendario. Las fuentes, modificaciones y licencias están en public/audio/rewards/CREDITS.md y los LICENSE adjuntos. Se conservan reloj, silencio, desbloqueo por interacción y limpieza de voces. Compilación correcta en foley-build.log y archivos WAV servidos correctamente en la prueba local. Pendiente valoración auditiva del usuario; sin publicar y con worktree conservado.

Sonidos sintetizados mediante Web Audio (sin archivos ni servicios externos): cierre a 0,65 s, tapa a 0,95 s, 0/4/8/15/24 destellos según rareza y resolución suave al terminar el acercamiento. Las señales se disparan con el reloj del visor. Las señales perdidas no se acumulan al volver de segundo plano. El movimiento reducido utiliza solo una resolución breve.

El navegador se desbloquea desde una interacción del usuario. El botón de sonido permite silenciar con transición suave y recuerda la preferencia local. Cerrar o cambiar de cofre detiene/desconecta las voces de ese cofre. Autoplay bloqueado o Web Audio no disponible no impiden la animación.

Build: audio-build.log; tests de contrato: audio-tests.log. No se ha realizado escucha de QA ni prueba de audio en dispositivos físicos. Se mantiene la prueba local, pendiente de revisión/publicación; worktree conservado.

## Recuperación del bloqueo de carga

Se observó la pestaña real detenida en Preparando animación con el épico como único pendiente. Las descargas GLB/Draco habían terminado; no había error registrado inicialmente. Al probar la limpieza explícita del contexto apareció un error WebGL de reinicio en Strict Mode, corregido creando un canvas nuevo por montaje. No se atribuye con certeza el bloqueo inicial a una única causa interna.

El modelo ahora se decodifica una sola vez por página, con un trabajador Draco y copias independientes de geometrías/materiales para cada cofre. La carga tiene límite de 15 segundos y botón Reintentar este cofre; errores de inicialización WebGL entran en ese mismo estado. Se libera el contexto gráfico junto con su canvas al cerrar. Se recargó únicamente la simulación local para retirar el estado anterior.

Build y cinco tests correctos (loading-fix-*). QA interactiva del navegador: épico revelado y retirado, siguiente común correcto, legendario seleccionado fuera de orden correcto, poco común correcto y comprobación del último pendiente. Esta comprobación no opera sobre premios reales. Worktree y servidor conservados; sin publicar.

## Transición entre cofres

Salida de la ficha: desplazamiento a la izquierda y desvanecido de 280 ms. Entrada: desplazamiento desde la derecha y fundido de 420 ms; el clip espera 350 ms antes de avanzar. El fondo permanece estable. La selección de otro cofre y el botón siguiente pasan por la misma transición, con bloqueo de doble pulsación y cancelación del temporizador al cerrar. Movimiento reducido conserva el cambio inmediato. El aviso de carga se retrasa para evitar destellos breves.

Build en transitions-build.log y cinco tests de contrato en transitions-tests.log. Se comprobó la entrada en la pestaña local; la prueba permanece disponible para valoración visual. Sin publicar; se conserva el worktree.


## Premio protagonista en el laboratorio

La ficha muestra un resultado ilustrativo del catálogo: 6 puntos, Marco Cobre, Motor del equipo + 10 puntos, Future IQ Navy o Retro Cromo. Nombres/descripciones proceden de player-cosmetics-catalog; las combinaciones respetan las entradas de los pools colectivos y su reasignación de player_cosmetics_v1. No se presentan como premios fijos de cada logro. Vista previa SVG ilustrativa de marcos, puntos y título; motivo del logro separado debajo. Resumen final de premios sin anticiparlos en la cola. El componente admite rewardPreview y achievementLabel opcionales; este cambio se aplica a la simulación.

Compilación correcta (prize-card-build.log), cinco tests de cofre correctos y diff sin errores de espacios. Verificado en navegador el legendario Retro Cromo, su vista previa, el motivo Quinientos partidos y los cuatro cofres restantes. ESLint detecta el setPhase síncrono ya existente en el manejo de error de inicialización WebGL; no se modifica esa ruta en este cambio. Se conserva el worktree y el servidor para revisión local; sin commit, PR ni despliegue.


## Tamaño estable tras el zoom

La fila de controles reserva entre 190 y 240 px según la altura disponible desde el inicio. El contador, las acciones y la retirada del último cofre ya no cambian el alto del visor 3D. En horizontal se conserva la columna lateral fija. El panel admite desplazamiento si el contenido excede su espacio. Cinco tests del cofre correctos; comprobada la ficha revelada en navegador con visor de 672 x 531. La recarga retiró un error de HMR de CSS del servidor local. Cambio local sin publicar; worktree y servidor conservados.


## Cámara fija en móvil y escritorio

OrbitControls ya estaba desactivado. Se retira completamente su importación, instancia, configuración de gestos y actualización por fotograma; la cámara usa lookAt al encuadrar el modelo. Se conservan la apertura y el acercamiento automático. Cinco tests del cofre correctos; compilación registrada en fixed-camera-build.log. Cambio local sin publicar; servidor y worktree conservados.


## QA móvil en navegador (2026-09-05)

Chrome automatizado con agent-browser, sesión independiente chest-mobile cerrada al terminar. Tamaños 393x852 (perfil iPhone 16), 360x640, 320x568 y horizontal 852x393. No es una prueba en Safari ni en hardware físico. Se revisaron capturas, apertura épica, selección legendaria fuera de orden, siguientes común/poco común/raro, retirada del último y resumen con cinco premios. Sin errores de página al finalizar. Movimiento reducido completó apertura y el botón de sonido cambió a Activar sonido al silenciar; no se evaluó la calidad auditiva ni el rendimiento físico.

Correcciones: texto secundario mayor en móvil, ilustración más compacta, filas del panel sin compresión, miniaturas menores en pantallas de poca altura y botones horizontales de al menos 44 px. En 360x640 el visor midió 358x433.84375 antes y después de retirar el último cofre: sin cambio de tamaño. Capturas mobile-epic-final.png (antes del aumento tipográfico), mobile-landscape-fixed.png, mobile-last.png y mobile-320-reduced.png. Cinco tests correctos; build mobile-qa-build.log. Sigue local, sin publicación; worktree y servidor conservados para revisión.
