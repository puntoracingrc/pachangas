# Team Shield Premium 3D V1 - Release Candidate

Fecha de cierre tecnico local: 2026-08-10 (Europe/Madrid)

## Trazabilidad

- Rama: `codex/team-shield-premium-3d-v1-rc`.
- Base exacta: `384069febd4d16f1f2b4d651727137e4a9bfd220` (head comprobado de PR #131 al iniciar).
- PR base: #131, apilado a su vez sobre #130.
- Produccion: no modificada.
- Supabase de produccion: no consultado ni modificado durante el RC.
- Staging Supabase: `iozcjirlfytryzrcmrnq` (`pwa-bridge-staging`).
- Migracion incremental: `20260810201451_team_shield_premium_3d_v1_catalog.sql`.

El RC no fusiona #130 ni #131. No asigna recompensas, no activa flags en produccion y no cambia Rating V2, facetas, Season Score ni TOPS.

## Decision tecnica

El Balon Premium utiliza el pipeline B del laboratorio: ocho vistas WebP prerenderizadas y seleccionadas mediante una tuberia de orientacion pequena y determinista. `DeviceMotion` queda descartado en V1. Solo se usa `DeviceOrientation`, porque el efecto necesita postura e inclinacion, no aceleracion ni velocidad angular.

El escudo sigue siendo valido sin sensor. En PC, API ausente, permiso denegado, componente fuera de pantalla o `prefers-reduced-motion: reduce`, se muestra el mismo cosmetico premium en estado estatico.

Three.js y el GLB permanecen exclusivamente en el laboratorio. Ninguna lista, miniatura, reto, Mercado, TOPS, ranking o notificacion crea un canvas/WebGL.

## DeviceOrientation

### Permiso y ciclo de vida

- El listener no se registra al cargar la pagina.
- `DeviceOrientationEvent.requestPermission()` solo se llama tras pulsar `Activar movimiento`.
- Estados de UI: desactivado, activo, permiso denegado y fallback estatico.
- Un rechazo no elimina el cosmetico ni deja un hueco.
- `visibilitychange` y `IntersectionObserver` detienen las actualizaciones fuera de vista o en background.
- Al volver a primer plano, reentrar en viewport o rotar la pantalla se recalibra el neutro.
- El desmontaje elimina listeners y observadores.
- No existe un `requestAnimationFrame` continuo.
- La orientacion no se persiste, no se incluye en telemetria y no viaja a Supabase.

### Tuberia pura

```text
DeviceOrientation
  -> mapeo segun rotacion de pantalla
  -> calibracion respecto a la postura actual
  -> dead zone 1.15 grados
  -> clamp +/-6 grados
  -> smoothing 0.18
  -> seleccion de una de ocho vistas con hysteresis 0.28
  -> transformacion visual sutil y crossfade
```

El procesador limita el trabajo visual a un maximo aproximado de 60 actualizaciones por segundo incluso si el dispositivo emite eventos a 120 Hz. Oscilaciones de +/-0.5 y +/-1 grado alrededor del neutro no cambian continuamente de frame.

### Rotacion de pantalla

El mapeo cubre 0, 90, 180 y 270 grados. Portrait y landscape no reutilizan de forma cruda `beta/gamma`: se transforman al eje visual actual y se toma un nuevo neutro al cambiar la orientacion de pantalla.

## Integracion canonica

No se ha creado un segundo modelo de escudo. `TeamShieldView` sigue siendo el renderer canonico y recibe opcionalmente el estado visual efimero del Balon Premium.

| Pieza | Slot/contrato | Catalogo RC | Economia | Veredicto |
| --- | --- | --- | --- | --- |
| Balon Premium | `primary_symbol`, `multiview-8-v1` | MANTENER | Sin reward mapping | READY_PENDING_PHYSICAL_QA |
| Borde Cobre | borde premium WebP | MANTENER | Sin ventaja | READY_FOR_PRODUCTION |
| Borde Plata | borde premium WebP | MANTENER | Sin ventaja | READY_FOR_PRODUCTION |
| Borde Oro | borde premium WebP | MANTENER | 0 Rating/Season Score/TOPS | READY_FOR_PRODUCTION |
| Cromo premium | laboratorio | REVISAR | Ninguna | LAB_ONLY |
| Carbono premium 3D | laboratorio | REVISAR | Ninguna | LAB_ONLY |
| Corona 3D | laboratorio | REVISAR | Ninguna | LAB_ONLY |

El Carbono 2D ya existente en Team Shield V1 no se confunde con el material Carbono premium 3D que permanece en el laboratorio.

## LOD y assets

| Superficie | Representacion |
| --- | --- |
| 24/32 px | simbolo premium 2D simplificado, sin ocho descargas |
| 48/64 px | prerender premium estatico apropiado |
| Media/grande visible | ocho vistas WebP y movimiento opcional |
| Laboratorio/editor de inspeccion | multivista; GLB solo como herramienta de laboratorio |

Los once assets productivos llevan hash de contenido en el nombre y cabecera `Cache-Control: public, max-age=31536000, immutable`. Los ocho frames pesan aproximadamente 5-6 KB cada uno y los tres bordes 35-37 KB cada uno. Los frames adicionales solo se precargan cuando el premium interactivo esta activado y visible.

Fuentes reproducibles del laboratorio:

- Blender: `artifacts/team-shield-premium-3d-lab/team-shield-premium-kit.blend`.
- Generador: `scripts/team-shield-premium-3d/generate-assets.py`.
- Preparacion y comprobacion de hashes V1: `scripts/team-shield-premium-3d/prepare-v1-assets.mjs`.
- Blender 5.1.2 en batch, camara e iluminacion fijadas por el generador, ocho vistas y salida WebP con transparencia.

## Staging

La migracion solo registra el catalogo premium. No contiene grants, reward mappings, flags deportivos ni cambios de formulas. El historial local y remoto de migraciones termina exactamente en `20260810201451`.

Configuracion comprobada:

- `team_cosmetics_enabled = true`.
- `team_cosmetic_rewards_enabled = false`.
- Cuatro piezas premium promovidas.
- Cero asociaciones al pool de recompensas.

E2E controlado sobre el fixture sintetico `Raval FC`:

1. Grant canonico del Balon Premium al equipo.
2. Marc y Laura conservan `NEW` por admin de forma independiente.
3. El owner marca su propia novedad como vista y equipa el balon.
4. Laura recibe por Realtime el snapshot canonico actualizado.
5. Un miembro normal recibe un read model privado sanitizado y no ve inventario administrativo.
6. Un outsider solo obtiene la lectura publica segura.
7. El loadout persistido contiene la pieza equipada; nunca contiene postura u orientacion fisica.

Resultado final:

```json
{"fixture":"Raval FC","newPerAdmin":true,"premiumBallEquipped":true,"publicReadSafe":true,"ratingChecksumUnchanged":true,"realtimeConverged":true}
```

La primera suscripcion Realtime sobre el tenant dormido agoto el timeout durante su arranque en frio. La escritura canonica ya estaba confirmada y publicada. Tras calentar la suscripcion y repetir desde fixture limpio, dos ejecuciones completas convergieron correctamente. La regresion espera `SUBSCRIBED` y aplica una breve estabilizacion antes de la escritura.

## Rendimiento

Entorno local: Node 24.16.0, Next.js 16.2.6, Chromium/CDP en pantalla de 120 Hz.

| Escenario | FPS observados | p95 frame | Max frame | Trabajo principal / 5 s | Script / 5 s | Actualizaciones visuales |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sensor OFF | 125.25 | 9.0 ms | 9.7 ms | 0.087 s | 0.010 s | 0 |
| Sensor ON optimizado | 126.39 | 9.1 ms | 14.7 ms | 1.039 s | 0.359 s | <= 62.7/s |

Antes del limitador, el sensor emulado a alta frecuencia consumia 1.728 s de trabajo principal y 0.852 s de script en cinco segundos. La version final reduce aproximadamente un 40% el trabajo principal y un 58% el tiempo de script en esa prueba. No se hacen afirmaciones sobre bateria.

Al quedar oculto, fuera de viewport o con reduced motion, no se procesa movimiento. El heap de la prueba ON final no mostro crecimiento sostenido (`-132880` bytes en la ventana medida).

## QA visual

Las capturas locales verifican desktop 1440x900, movil portrait 390x844 y landscape 844x390, sin overflow horizontal, imagenes rotas ni errores de consola:

- `artifacts/team-shield-premium-3d-v1-rc/desktop-2d-vs-premium.png`
- `artifacts/team-shield-premium-3d-v1-rc/desktop-contact-sheet.png`
- `artifacts/team-shield-premium-3d-v1-rc/mobile-portrait-rc.png`
- `artifacts/team-shield-premium-3d-v1-rc/mobile-landscape-contact-sheet.png`

La comparacion BASE 2D vs PREMIUM utiliza exactamente el mismo escudo y no introduce una corona u otro adorno que falsee el valor visual del balon.

## QA fisica

| Plataforma | Estado | Evidencia |
| --- | --- | --- |
| iPhone / iOS Safari | PENDING | No hay un iPhone fisico conectado; no se declara PASS. |
| Android / Chrome | PENDING | Se detecto un Redmi Note 14 5G fisico autorizado. La prueba HTTPS de la Preview se completa despues de publicar este RC. |

Mientras cualquiera de estas filas siga pendiente, el Balon Premium conserva el veredicto `READY_PENDING_PHYSICAL_QA` y el conjunto no se presenta como listo para produccion.

## Pruebas y regresiones

- Tests RC de orientacion, permiso, jitter, extremos y contratos: 10/10.
- Team Shield Cosmetics: 8/8.
- Bootstrap PostgreSQL aislado: 85 migraciones, correcto.
- SQL/RLS de Team Shield: correcto.
- Concurrencia e idempotencia: una revision canonica, un recibo y conflicto explicito para la revision obsoleta.
- `npm test`: 20/20 pruebas Node y 225/225 pruebas TypeScript.
- Incluye Player Cosmetics, Team Shield, Rating V2, Achievements, Reward boxes, Notifications, Core Social, TOPS, Conduct y PWA.
- Build: correcto.
- Typecheck: correcto.
- Lint focalizado: correcto.
- Lint global: 43 incidencias preexistentes (23 errores, 20 avisos), ninguna creada por este RC.
- `git diff --check`: correcto.

Los checksums deportivos son identicos antes y despues del grant/equipado. El sistema premium no escribe ratings, facetas, Season Score, TOPS, assessments ni evidencias deportivas.

## Recomendacion

El Balon Premium y los bordes Cobre, Plata y Oro pueden permanecer como candidatos reales de Team Shield Cosmetics V1 en staging. Los tres bordes estan tecnicamente listos para una futura activacion de producto; el Balon Premium queda pendiente de QA fisica completa iOS y Android. Cromo, Carbono premium 3D, Corona y GLB siguen en laboratorio.

No debe fusionarse la pila ni activarse en produccion hasta revisar la Preview, completar la validacion fisica pendiente y tomar la decision conjunta sobre #130, #131 y este RC.
