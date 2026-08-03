# Rating System V2 - Runbook de staging y producción

## 1. Objetivo y regla de seguridad

Este runbook coordina PostgreSQL/Supabase y el frontend de Pachangas IQ sin dejar una versión incompatible en servicio.

Advertencias obligatorias:

- Las migraciones V2 crean las RPC nuevas, pero la activación final revoca las RPC antiguas.
- El frontend V1 puede dejar de funcionar si se revocan las RPC antiguas antes de desplegar el frontend V2.
- El frontend V2 puede fallar si se despliega antes de instalar las RPC V2.
- Nunca ejecutar un `supabase db push` improvisado contra producción.
- Supabase aplica las migraciones pendientes por orden de timestamp. La guía oficial está en [Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations).

La entrega quedó separada físicamente durante la implantación y la unidad 25 se promueve en el PR de activación:

- `supabase/migrations/`: 36 migraciones históricas anteriores a V2, 24 migraciones aditivas V2 y la unidad 25 `20260803062830_rating_v2_legacy_write_closure.sql`. La número 24 traduce conflictos de revisión/lock a HTTP 409; la 25 revoca las escrituras V1 solo después de verificar el frontend V2.
- `supabase/deferred-migrations/20260802203605_rating_v2_emergency_safe_hold.sql`: guardia de continuidad versionada, fuera del flujo normal y también excluida de `db push`.

La unidad 25 no debe aplicarse hasta la fase 5 y se publica mediante un PR de activación independiente.

La guardia de emergencia no es una migración 26: no forma parte del despliegue normal, no devuelve autoridad a V1 y no se aplica salvo incidente aprobado y ensayo previo en staging.

PRs relacionados:

- Rating System V2: https://github.com/puntoracingrc/pachangas/pull/92
- Release puente PWA/client version: https://github.com/puntoracingrc/pachangas/pull/93 (fusionado primero en `main`, SHA `12be27f720c53f7ee95967e8024eade2d9dd198e`)
- Activación y cierre V1: https://github.com/puntoracingrc/pachangas/pull/94 (fusionado en `main`, SHA `7695fc283f7eed9d9ce5d2fe31cb842b0e588e68`)

### 1.1 Contrato permanente server-authoritative

Pachangas IQ adopta como contrato permanente una arquitectura server-authoritative con caché local. Supabase/PostgreSQL es la única fuente de verdad para creaciones, modificaciones, valoraciones, resultados, acciones sociales, invitados, snapshots, permisos, niveles y recálculos. El cliente solo puede enviar intenciones: objetivo, acción semántica, `operationId`, revisión esperada y metadatos de versión/sesión.

El cliente nunca confirma ni reintenta por su cuenta una operación deportiva offline. No existe cola offline autoritativa: sin confirmación central, la operación queda pendiente/fallida y la pantalla debe volver al snapshot canónico. Las previsualizaciones son solo visuales y se sustituyen por la respuesta con `confirmedRevision`, `serverSequence` y payload/read model oficial.

Las lecturas pueden usar caché local derivada: snapshots, catálogos, campos, partidos finalizados y modelos de lectura. La invalidación se guía por `payload_revision`, `updated_at`, eventos Realtime y secuencias de servidor. Los partidos activos se leen desde el snapshot actual y Realtime solo avisa para recargar la entidad afectada; los partidos finalizados, campos y catálogos casi inmutables admiten caché larga. Las cartas, medias, historiales y niveles no se recalculan en cada lectura del navegador: se recalculan en servidor ante el evento que los cambia y se publican como read models canónicos.

### 1.2 Contrato de versión de cliente

| Dato | Definición obligatoria |
| --- | --- |
| `clientVersion` | SemVer inmutable del bundle, `MAJOR.MINOR.PATCH+<gitSha12>`, generada en build mediante `NEXT_PUBLIC_PACHANGAS_CLIENT_VERSION`. Para V2 el protocolo mínimo es `2.0.0`; el metadata de build no participa en la comparación. |
| `minimumSupportedClientVersion` | SemVer controlada por servidor, nunca por `localStorage`, publicada mediante una respuesta `no-store`. Empieza en `1.0.0` durante el bridge y solo sube a `2.0.0` al autorizar V2. |
| `serviceWorkerVersion` | Identificador inmutable del `sw.js` que controla la ventana. Debe viajar en telemetría junto con `clientVersion`. |
| Cliente sin versión | Se clasifica como `v1-unversioned`; nunca se presupone actualizado. |

Todas las escrituras deben enviar `clientVersion`, `serviceWorkerVersion`, `operationId` y el tipo de cliente (`browser`, `standalone` o `fullscreen`). El servidor compara SemVer sin el metadata `+sha`. Las lecturas siguen disponibles para un cliente obsoleto, pero cualquier escritura se bloquea antes de la mutación y devuelve un error explícito `CLIENT_UPDATE_REQUIRED`, nunca un resultado de éxito.

## 2. Responsables y entornos

Antes de actuar, registrar:

| Dato | Valor requerido |
| --- | --- |
| Responsable de base de datos | Nombre y hora de inicio |
| Responsable de frontend | Nombre y despliegue exacto |
| Proyecto Supabase de staging | Ref comprobada visualmente |
| Proyecto Vercel de staging | Proyecto y dominio comprobados |
| Proyecto Supabase de producción | Ref comprobada visualmente |
| Proyecto Vercel de producción | Proyecto y dominio comprobados |
| Commit V2 | SHA exacto aprobado |
| Copia de seguridad | Identificador y hora |
| `clientVersion` servido | SemVer y SHA exactos |
| `minimumSupportedClientVersion` | Valor antes y después de cada fase |
| Ventana sin escrituras V1 | Inicio, fin y consulta de evidencia |
| Service Worker | Versión esperada y versión controladora observada |
| Restauración ensayada | Backup, destino aislado, RTO, RPO y verificador |
| Volumen del ensayo | Filas por tabla y factor respecto a producción/previsión |

Hay otros proyectos en Supabase y Vercel: no continuar si la referencia, organización o dominio no coinciden exactamente con Pachangas IQ.

## 3. Preflight

1. Congelar otros cambios de esquema y elegir una ventana con un único operador de base de datos.
2. Confirmar 61 archivos en `supabase/migrations/` y paridad exacta de versión/nombre con el historial enlazado: 36 históricos, 24 V2 aditivos y `20260803062830_rating_v2_legacy_write_closure.sql`.
3. Confirmar mediante `supabase db push --dry-run` que no aparece la unidad 25 antes de autorizarla y que, una vez promovida, es la única migración pendiente.
4. Ejecutar y guardar:

```bash
git rev-parse HEAD
git status --short
supabase --version
supabase migration list --linked
supabase db push --linked --dry-run
```

5. Crear una copia recuperable y restaurarla realmente en un proyecto aislado antes de tocar producción. Ver una copia en el panel no demuestra que sea restaurable.
6. Registrar métricas base: errores RPC, latencia, CPU, locks, conexiones, eventos Realtime, filas y tamaño de índices.
7. Confirmar que el release puente PWA registra versión y telemetría, actualiza el Service Worker de forma controlada y bloquea solo escrituras incompatibles.
8. Confirmar la política de observación aplicable. En el lanzamiento preusuarios de agosto de 2026 no hay usuarios reales ni PWAs activas que preservar, por lo que el owner ha dispensado la ventana real de 24 horas/7 días. Se mantiene una prueba controlada de PWA antigua y la telemetría queda lista para futuros despliegues con usuarios.
9. Ejecutar el ensayo de volumen definido en la sección 13 y adjuntar sus medidas por migración.
10. Aplicar los criterios objetivos de parada de la sección 12. Cualquier error de autorización, revisión, RLS, duplicado o divergencia entre dispositivos detiene la fase.

### 3.1 Fase 0: bridge PWA y clientes antiguos

Esta fase precede a las migraciones aditivas. No se autoriza staging V2 hasta completarla.

1. Publicar un release puente compatible con V1 que incluya `clientVersion`, telemetría de intentos de escritura y el diálogo de actualización obligatoria.
2. Servir `minimumSupportedClientVersion` desde el servidor con `Cache-Control: no-store`; ni el Service Worker ni el navegador pueden reutilizar una política antigua.
3. Enviar la versión en cada escritura y clasificar como `v1-unversioned` cualquier llamada sin cabecera o metadata.
4. Mantener `minimumSupportedClientVersion=1.0.0` durante la observación o, en el lanzamiento preusuarios autorizado, durante la prueba controlada de PWA antigua. La telemetría debe distinguir intento, RPC, resultado, versión, modo instalado, versión SW y hora del servidor, sin nombres, correo ni contenido deportivo.
5. Actualizar `sw.js` conservando la misma URL, llamar a `registration.update()` con `updateViaCache: "none"` y evitar una activación mezclada. Cuando el nuevo worker esté listo, detener nuevas escrituras, esperar a que no haya ninguna intención pendiente, enviar `SKIP_WAITING` y recargar una sola vez tras `controllerchange`. Referencia: [Update a PWA](https://web.dev/learn/pwa/update/).
6. Al detectar `clientVersion < minimumSupportedClientVersion`, mantener navegación y lecturas, deshabilitar mutaciones, mostrar `Actualización obligatoria` y conservar cualquier intención local como pendiente o fallida, nunca confirmada.
7. Un error `CLIENT_UPDATE_REQUIRED`, `42501` o de RPC revocada obliga a descartar la previsualización optimista y recargar el snapshot oficial. Ningún `catch`, timeout o estado offline puede transformarlo en éxito.
8. No iniciar una ventana de silencio futura hasta que el bridge lleve desplegado al menos un ciclo normal de uso y todas las instalaciones activas observadas hayan enviado una versión. Esta espera queda dispensada solo mientras no existan usuarios reales ni instalaciones activas.

La implementación del bridge, su endpoint `no-store` y la telemetría son requisitos de código previos a staging; documentarlos no equivale a tenerlos desplegados.

## 4. Fase 1: infraestructura y RPC V2 aditivas

### Staging

1. Enlazar exclusivamente el proyecto de staging.
2. Revisar el `--dry-run`: debe listar las 24 migraciones aditivas y nunca la activación diferida.
3. Aplicar las 24 migraciones primero en una copia restaurada y con volumen representativo, registrando la ficha de la sección 14 para cada archivo.
4. Usar `SET LOCAL lock_timeout = '3s'` y `SET LOCAL statement_timeout = '60s'` en DDL/permisos. Para el backfill se permite hasta `15min` solo si el ensayo confirma progreso, ausencia de bloqueos y duración esperada; en caso contrario se divide en lotes antes de producción.
5. Verificar que las RPC V2 existen y que las RPC V1 siguen ejecutables para `authenticated`.
6. Ejecutar pruebas SQL/RLS y concurrencia contra staging con datos sintéticos.
7. Confirmar que el frontend V1 de staging todavía puede leer y escribir.
8. Comparar filas previstas/afectadas, locks, CPU e índices con el ensayo; cualquier desviación fuera de umbral detiene la fase.

### Producción

Solo después de aprobar staging, su prueba de restauración y su ensayo de volumen, repetir el `--dry-run` con la referencia de producción verificada. Aplicar únicamente las 24 migraciones aditivas. El frontend V1 debe seguir funcionando durante esta fase. No improvisar un timeout mayor durante producción: una migración que exceda el valor ensayado se detiene y se rediseña.

## 5. Fase 2: frontend V2 en staging

1. Desplegar el commit V2 en un deployment de staging/preview conectado solo al Supabase de staging.
2. Confirmar que no contiene claves `service_role` ni apunta a producción.
3. Verificar que el navegador envía solo intención, `operationId` y `expectedRevision`.
4. Confirmar que la respuesta reemplaza la previsualización con `confirmedRevision`, `serverSequence` y snapshot canónico.
5. Mantener V1 disponible; todavía no ejecutar la unidad 25.
6. Confirmar que el bundle expone su `clientVersion`, obtiene la política con `no-store` y adjunta versión/SW a toda escritura.
7. Con un mínimo superior al cliente, verificar que las lecturas continúan y que las escrituras quedan bloqueadas con actualización obligatoria.
8. Verificar una actualización controlada del Service Worker: worker nuevo en espera, pausa de escrituras, `SKIP_WAITING`, un único `controllerchange` y una única recarga.

## 6. Fase 3: QA autenticada y Realtime

Usar al menos dos usuarios y dos sesiones independientes. Deben pasar:

- primera valoración inmediata y sustitución tras tres partidos compartidos;
- anonimato, lectura del propio voto y moderación mediante identificador opaco;
- resumen social oculto con 0, 1 y 2 evaluadores, visible con 3;
- assessment inicial y avanzado de una sola ejecución;
- asistencia, alineación, pago, goleadores y finalización concurrentes;
- rechazo de una revisión obsoleta como HTTP 409/`PT409`, sin timeout, y recarga del snapshot oficial;
- reconexión y Realtime con convergencia de ambos clientes;
- restauración A->B sin voto, peso ni fecha de opinión nuevos;
- selección idéntica del último snapshot cuando varios comparten `created_at`;
- invitado, enlace reversible y valoración global;
- intento directo de RPC V1 y V2 fuera de permisos.
- PWA V1 abierta antes del despliegue, mantenida en segundo plano, reconectada después y clasificada por telemetría como antigua;
- la misma PWA recibe actualización obligatoria, no confirma una escritura rechazada, actualiza el Service Worker y recarga una sola vez;
- cliente V2 compatible que conserva lecturas y escrituras normales tras el cambio de versión mínima;
- cliente sin versión clasificado como `v1-unversioned` y bloqueado para escribir cuando se eleva el mínimo;
- restauración real del backup en un destino aislado, con conteos y snapshots canónicos equivalentes;
- backfill con el volumen representativo y métricas dentro de todos los umbrales.

Guardar evidencias sin PII: SHA, operación, revisiones, secuencias, resultado y capturas de staging.

### 6.1 Evidencia de staging aprobada (3 de agosto de 2026)

| Dato | Evidencia |
| --- | --- |
| Supabase staging | Rama `pwa-bridge-staging`, ref `iozcjirlfytryzrcmrnq`, estado `ACTIVE_HEALTHY`. |
| Frontend probado | Preview Vercel `dpl_pgKLgSh4CKB4jhgziwvX62KBe7mn`, commit funcional `442a2196ad97a0c7ad392bd5c84d5e8bbffd809f`, conectado exclusivamente a staging. |
| Migraciones | 24 aditivas aplicadas; `rating_v2_http_conflicts` registrada como `20260803050527`. Unidad 25 no aplicada. |
| Permisos internos | 28 funciones `_impl`; `anon` y `authenticated` sin `EXECUTE` sobre las 28; 28 wrappers públicos coincidentes. |
| Concurrencia | Desde revisión `6`: un dispositivo confirmado, otro rechazado con `PT409`, reintento sobre estado canónico y revisión final `8`. |
| Realtime | Dos eventos recibidos por cada dispositivo; convergencias observadas en 51 ms y 359 ms. |
| Valoración | Primera valoración B->A confirmada de revisión `8` a `9`, evento Realtime en 563 ms y replay idempotente. |
| Datos sintéticos | Grupo, usuarios y evidencias exactos eliminados transaccionalmente; verificación final a cero. |
| Producción | No modificada. |

El primer intento de Realtime coincidió con el arranque en frío de la replicación del tenant: ambos clientes alcanzaron `SUBSCRIBED`, pero el stream no entregó el primer evento dentro de 10 segundos. Tras esperar la disponibilidad del stream, la prueba completa pasó sin cambiar la lógica de negocio. Esta observación no se interpreta como éxito silencioso: los clientes siempre recargaron el snapshot canónico y nunca divergieron.

## 7. Fase 4: activación controlada de V2

1. Aplicar primero las 24 migraciones aditivas en producción y comprobar V1.
2. Desplegar/promover el frontend V2 exacto.
3. Hacer smoke autenticado inmediato con un grupo sintético o controlado.
4. Observar durante la ventana acordada errores RPC, revisiones obsoletas, CPU, locks y Realtime. En el lanzamiento preusuarios, esta observación se limita a QA controlada de staging porque no existe tráfico real que esperar.
5. Si falla V2 antes de la revocación, revertir el frontend a V1. No hay que revertir el esquema aditivo.
6. Mantener `minimumSupportedClientVersion=1.0.0` mientras convivan V1 y V2; el bridge continúa registrando ambos protocolos.
7. Cuando V2 sea estable, elevar el mínimo a `2.0.0`: solo se bloquean escrituras antiguas y se fuerza la actualización controlada.
8. Iniciar entonces la ventana de producción de 7 días cuando existan usuarios reales o instalaciones activas. Para el lanzamiento preusuarios autorizado, sustituirla por una prueba controlada de cliente antiguo, versión mínima y escritura rechazada.

No avanzar mientras exista tráfico V1 conocido, telemetría incompleta o una versión cliente antigua que todavía necesite escribir. Reiniciar la ventana completa ante cualquier evento V1 en despliegues con usuarios reales.

## 8. Fase 5: revocación final de escrituras V1

La activación se publica en un PR independiente:

1. Promover la unidad 25 como `supabase/migrations/20260803062830_rating_v2_legacy_write_closure.sql`, creada originalmente con `supabase migration new` y sincronizada después con la versión remota aplicada, en un PR independiente.
2. Revisar que el nuevo archivo contiene únicamente las revocaciones aprobadas.
3. Adjuntar la consulta de telemetría que demuestra 24 horas limpias en staging y 7 días limpios en producción, incluyendo clientes sin versión. En el lanzamiento preusuarios aprobado, adjuntar la evidencia de inexistencia de usuarios reales y la prueba controlada de PWA antigua en lugar de esperar la ventana temporal.
4. Ejecutar `supabase db push --linked --dry-run`; debe aparecer solo la migración de cierre.
5. Aplicarla primero en staging y repetir los intentos directos contra V1, incluida la PWA que quedó abierta antes del despliegue.
6. Ensayar en staging la guardia `20260802203605_rating_v2_emergency_safe_hold.sql`; debe mantener V1 y `UPDATE` revocados y permitir únicamente asistencia por la RPC V2 autoritativa.
7. Aplicar el cierre en producción únicamente tras confirmar que el frontend V2 está estable y todos los umbrales siguen verdes.
8. Verificar que V1 devuelve error explícito, nunca éxito, y V2 continúa operativo.

## 9. Fase 6: verificación

Comprobar y registrar:

- SHA del frontend servido y dominio de producción;
- versión de migración aplicada;
- RPC V1 sin `EXECUTE` para `authenticated`;
- tabla `pachanga_groups` sin `UPDATE` directo para `authenticated`;
- RPC V2 operativas con RLS y actor autenticado;
- un solo evento y recibo por `operationId`;
- secuencias monotónicas y revisiones convergentes;
- Realtime provoca recarga del estado oficial;
- CPU, locks, errores y latencia dentro del umbral acordado.
- `clientVersion >= minimumSupportedClientVersion` en todos los clientes activos observados;
- cero escrituras V1 y `v1-unversioned` durante toda la ventana exigida;
- `sw.js` controlador coincide con la versión del release y no quedan workers antiguos en espera;
- cualquier PWA antigua conserva lecturas, bloquea escrituras y muestra actualización obligatoria;
- backup restaurado y verificado, con RTO/RPO registrados;
- filas, tiempos e índices de cada migración coinciden con el ensayo de volumen.

## 10. Reversión

### Antes de la fase 5

Revertir únicamente el frontend a V1. Las 24 migraciones son aditivas y se conservan para evitar pérdida de historial.

### Después de la fase 5

No volver a desplegar V1 con escrituras abiertas. El orden de preferencia es:

1. activar mantenimiento temporal de solo lectura;
2. corregir V2 y hacer roll-forward;
3. si la asistencia es imprescindible, desplegar un frontend mínimo que use únicamente `patch_pachanga_match_player_status_authoritative_v2` con `operationId` y revisión esperada;
4. aplicar, solo si la matriz de permisos se ha probado en staging, `supabase/deferred-migrations/20260802203605_rating_v2_emergency_safe_hold.sql` mediante un PR/migración de incidente independiente.

La guardia de emergencia es versionada y revisable. Reafirma la revocación de todas las escrituras V1 y de `UPDATE` directo; solo garantiza `EXECUTE` a `authenticated` sobre la RPC V2 autoritativa de asistencia. No concede acceso a `save_pachanga_payload_if_current`, assessments V1, ratings V1, mercado V1, alineación, pagos, goleadores ni finalización V1.

Antes de usarla:

1. crear una migración de incidente con timestamp nuevo mediante `supabase migration new` y copiar exactamente la guardia revisada;
2. aplicar y revertir el escenario en staging con una PWA antigua, un cliente V2 y dos usuarios concurrentes;
3. confirmar que `has_table_privilege('authenticated', 'public.pachanga_groups', 'UPDATE')` es falso;
4. confirmar que todas las RPC V1 siguen sin `EXECUTE` y que la asistencia V2 mantiene revisión, recibo, evento y snapshot canónico;
5. aprobar duración máxima de la contingencia y responsable del roll-forward.

Durante la contingencia, el payload sigue siendo un modelo derivado. Está prohibido usarlo para reconstruir o sobrescribir evidencias, snapshots, cartas, valoraciones o secuencias V2. No borrar tablas V2, no reescribir historial y no restaurar una copia sobre producción como mecanismo de rollback de aplicación.

La reversión de base solo se considera posible si el backup se restauró previamente en un destino aislado y se verificaron esquema, filas, RLS, funciones, índices, snapshots y secuencias. Una restauración física provoca indisponibilidad y puede requerir reconfigurar elementos externos; se trata como recuperación ante desastre, no como rollback ordinario.

## 11. Criterio de cierre

La activación solo se considera cerrada cuando frontend, PostgreSQL, Realtime y dos clientes convergen; los permisos V1 están revocados; no hay errores de autorización inesperados; la ventana de telemetría está limpia; la PWA antigua queda bloqueada y actualizada de forma controlada; el ensayo de volumen está dentro de umbral; y existe una restauración realmente comprobada. Un deployment `READY` por sí solo no basta.

## 12. Telemetría y umbrales de parada

La telemetría usa hora y secuencia del servidor. No acepta la hora del dispositivo como orden. Debe poder agrupar por `clientVersion`, `serviceWorkerVersion`, tipo de RPC, resultado y modo instalado. Un `installationId` aleatorio puede correlacionar una instalación, pero no se guarda nombre, correo, respuesta de assessment, resultado deportivo ni payload.

Consulta mínima de autorización para la unidad 25:

| Señal | Umbral para continuar | Umbral de parada |
| --- | --- | --- |
| Escrituras V1 aceptadas | 0 en la ventana aplicable; en preusuarios, 0 durante QA controlada | Cualquier evento reinicia la ventana si hay usuarios reales |
| Intentos `v1-unversioned` | 0 en la ventana aplicable; en preusuarios, solo el intento controlado esperado | Cualquier intento no controlado |
| Errores de escritura V2 | < 0,5% durante 5 min y ninguno de integridad | >= 0,5% o cualquier divergencia |
| Realtime | p95 <= 2 s | p95 > 5 s durante 1 min |
| CPU de base | < 70% sostenido y < 20 puntos sobre baseline | >= 70% durante 5 min o +20 puntos |
| Conexiones | < 80% del límite | >= 80% durante 1 min |
| Espera de lock | < 3 s | lock bloqueante >= 3 s o deadlock |
| RPC p95 | <= 2x baseline y <= 1 s | > 2x baseline o > 1 s durante 5 min |
| Migración no-backfill | <= 60 s y <= 2x staging | Supera cualquiera |
| Backfill | <= 15 min, progreso continuo y <= 2x staging | Sin progreso 60 s, > 15 min o > 2x staging |
| Disco/índices | >= 30% libre; crecimiento dentro de +20% del ensayo | < 30% libre o > 20% inesperado |

Ante un umbral de parada: no aumentar timeouts para forzar el avance, cancelar la fase, conservar evidencias, volver al estado compatible anterior y decidir mantenimiento o roll-forward.

## 13. Ensayo de volumen y restauración

El dataset de staging debe ser sintético y reproducible. Su tamaño será el mayor de: `2x` las filas actuales de producción, `2x` la previsión de 12 meses o estos mínimos de ensayo:

| Entidad | Mínimo |
| --- | ---: |
| Grupos | 500 |
| Perfiles universales | 10.000 |
| Partidos | 50.000 |
| Participaciones/asistencias | 500.000 |
| Evidencias individuales | 250.000 |
| Eventos y recibos | 1.000.000 |

Procedimiento:

1. restaurar una copia compatible en un proyecto aislado o crear el dataset sintético con la misma distribución de tamaños JSON, miembros, partidos y evidencias; seguir [Database Backups](https://supabase.com/docs/guides/platform/backups) y [Backup and Restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore);
2. registrar conteos, `pg_total_relation_size`, `pg_indexes_size`, CPU, conexiones y locks antes del primer archivo;
3. aplicar las 24 migraciones una a una en el ensayo, capturando hora del servidor, duración, filas afectadas, locks máximos, CPU máxima y crecimiento de índices;
4. repetir el backfill con actividad concurrente de lectura y escritura equivalente al pico previsto;
5. validar conteos, restricciones, RLS, snapshots canónicos y convergencia de dos clientes;
6. crear un backup posterior y restaurarlo en otro destino aislado; comprobar los mismos conteos y una muestra determinista de hashes/snapshots;
7. registrar RPO y RTO reales. No autorizar producción si la restauración falla o si el RTO supera la ventana de mantenimiento aprobada.

Los timeouts se fijan con `SET LOCAL` dentro de la transacción ensayada. No se cambian valores globales del proyecto para acomodar una migración lenta.

## 14. Ficha de evidencia por migración

Completar una fila por cada una de las 24 migraciones y otra para la unidad 25 en su ensayo independiente:

| Migración | Inicio/fin servidor | Duración | Filas antes/después/afectadas | Lock máximo | CPU base/máxima | Índices antes/después | Resultado/decisión |
| --- | --- | ---: | --- | ---: | --- | --- | --- |
| `<timestamp>_<nombre>.sql` | `<timestamptz>` | `<ms>` | `<n>/<n>/<n>` | `<ms>` | `<%>/<%>` | `<bytes>/<bytes>` | `continuar/detener` |

Adjuntar también: SHA del frontend, refs exactas de Supabase/Vercel, versiones cliente mínima/servida, consulta de telemetría, identificador del backup restaurado, RPO/RTO, pruebas PWA y responsable que autorizó cada transición.
