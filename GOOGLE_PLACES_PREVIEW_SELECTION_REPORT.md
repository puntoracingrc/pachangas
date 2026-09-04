# Google Places Preview Selection Report

Fecha de cierre tecnico: 2026-09-04.

## 1. Clasificacion final

`REPRODUCED_PREVIEW_INTEGRATION_DEFECT`.

Causas confirmadas:

- `PREVIEW_KEY_ORIGIN_CONFIGURATION`.
- `PREVIEW_ENVIRONMENT_INJECTION`.
- `CLIENT_ERROR_HANDLING`.
- `CLIENT_SELECTION_FLOW`.
- `COMBINED_CONFIGURATION_AND_CODE`.

No fueron causa `PROVIDER_API_ENABLEMENT`, `PROVIDER_BILLING_OR_QUOTA` ni un defecto de la autoridad canonica de campos o partidos.

## 2. SHA base

- Base auditada: `dc9ad0e519edeb058e0a9c60d16ab22aca8fcd31`.
- Rama aislada: `codex/google-places-preview-selection-closure`.
- Implementacion certificada: `5d73140277096c9bc32a7c609d8d908308f11045`.
- Los PR #269 y #270 continuan contenidos en la base.
- El checkout compartido y sus cambios preexistentes no se modificaron.

## 3. Issue #166

- Issue: [#166 Google Places: cerrar seleccion real en Preview](https://github.com/puntoracingrc/pachangas/issues/166).
- Estado al emitir este informe: `OPEN`, pendiente unicamente de merge, limpieza final y comentario de cierre.
- Resultado tecnico: `READY TO CLOSE ISSUE`.

## 4. Fuentes

Se revisaron el issue #166, PR #163, los commits historicos indicados en el plan, los informes de Official UI V2.1, GVC-020, los contratos de Venue Operations, el helper y todos sus consumidores, las pruebas de UI/PWA/offline y la configuracion efectiva de Vercel y Google Cloud sin exponer secretos. La referencia normativa fue la documentacion oficial vigente de Google Maps Platform y Vercel.

## 5. Estado historico

Official UI V2.1 permitia introducir texto, pero no obtuvo una prediccion seleccionable. `Guardar campo` siguio deshabilitado y no se fabrico ningun campo ni partido para sortear el bloqueo. Los informes historicos no se han reescrito.

## 6. Call graph

1. Next.js incorpora `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` durante el build de cada entorno.
2. El formulario oficial llama a `attachVenueAutocomplete`.
3. `loadGooglePlaces` carga una sola vez Maps JavaScript API con `libraries=places`, `loading=async` y `v=weekly`.
4. El helper asegura `importLibrary("places")` y prefiere `PlaceAutocompleteElement`.
5. `gmp-select` entrega `placePrediction`; `toPlace()` crea el objeto Place y `fetchFields()` obtiene los detalles minimos.
6. El helper normaliza el resultado a `VenuePlace`; el formulario solo entonces guarda `selectedVenuePlace` y habilita `Guardar campo`.
7. `addVenue` incorpora el lugar seleccionado al read model, y `save_pachanga_payload_authoritative_v2` confirma el snapshot con actor autenticado, `operation_id` y revision esperada.
8. La creacion del partido reutiliza esa autoridad. La recarga borra la copia derivada y relee el payload canonico.

El E2E ejercito la creacion de campo y partido autenticada. Mercado y los demas consumidores compartidos quedaron cubiertos por regresiones, sin refactor global.

## 7. Configuracion inicial de Vercel

- Proyecto y rama correctos.
- Preview heredaba inicialmente la clave Google y el backend Supabase de produccion.
- No existia override seguro para la rama nueva.
- Una primera publicacion manual sin metadata de rama demostro que un deployment Preview puede conservar variables generales; no se utilizo para escribir y quedo descartada.
- Toda certificacion posterior uso un deployment Git reconstruido despues de introducir los overrides de rama.

## 8. Configuracion inicial de Google sanitizada

- Habia una unica clave web compartida por Preview y produccion.
- La restriccion era de tipo Websites, con hostnames historicos y productivos mezclados.
- La allowlist de APIs era mucho mas amplia que este flujo.
- Maps JavaScript API, Places API y Places API (New) estaban habilitadas en el proyecto.
- La reproduccion inicial sobre el nuevo hostname fallo dos veces por restriccion de referrer.

No se copio ni conservo el valor de ninguna clave.

## 9. Fingerprints comparativos

- Clave Preview: `f4ce75cb57f57469088fd7cbbd339f521dd3b7e4fb568749e0f1fef2878ab420`.
- Clave produccion: `43042d3d2fb1c3d2f28ed7b3aa0a2341298b62e50788b7cb053af939548c42e1`.
- Resultado: diferentes.

Los fingerprints son SHA-256 y no permiten recuperar los valores. El marcador cifrado de Vercel observado durante el inventario no se uso como evidencia de clave.

## 10. Separacion Preview/produccion

- Clave Preview separada: `SI`.
- Backend Supabase desechable y variables de Preview separadas: `SI`.
- Clave productiva modificada: `NO`.
- Variables Production modificadas: `NO`.
- Clave Preview presente en Production: `NO`, verificado por fingerprint del bundle.
- `service_role` en bundle cliente: `NO`.

## 11. Origenes autorizados

La clave Preview solo autorizo:

`https://pachangas-git-codex-googl-ff0eb8-persianas-almar-web-s-projects.vercel.app/*`

Es el alias estable de la rama y apunto al deployment exacto certificado. No se autorizo la URL inmutable ni un wildcard general de `vercel.app`.

## 12. APIs autorizadas

- Maps JavaScript API: `SI`.
- Places API (New): `SI`.
- Places API legacy: `NO` en la clave Preview.
- Otras APIs: `NO`.

El fallback legacy permanece en codigo por compatibilidad, pero no fue necesario ni autorizado para esta certificacion.

## 13. Billing y cuota

- Billing: `OPERATIVO` durante la prueba.
- Cuota: `OPERATIVA` durante la prueba.
- Evidencia: el proveedor devolvio predicciones reales y detalles reales en ambos mecanismos de seleccion.
- No se cambiaron cuenta de facturacion, limites de gasto ni cuotas.
- No se detecto trafico inesperado en la ventana revisada.

## 14. Reproduccion

La Preview aislada del main conocido se abrio en dos sesiones nuevas, sin cache compartida y con intentos independientes. En ambos casos el script y el widget cargaron, pero el proveedor rechazo la busqueda por referrer y el producto no mostro el fallo. La inyeccion general de Preview tambien apuntaba al backend productivo, por lo que el E2E autenticado se mantuvo bloqueado hasta instalar los overrides de staging.

La certificacion corregida se ejecuto sobre `https://pachangas-3r9tpvon7-persianas-almar-web-s-projects.vercel.app`, deployment `dpl_C6CAXoekeSyKzr5aYTYtjbb7jvNu`, estado `READY`, con metadata Git `5d73140277096c9bc32a7c609d8d908308f11045`. El alias estable autorizado apuntaba a ese mismo deployment.

## 15. Errores observados

- Referrer no autorizado en los dos intentos iniciales.
- Error visible ausente pese al error del widget.
- Una seleccion antigua no tenia invalidacion demostrable al editar dentro del custom element.
- Un fallo de script podia dejar una promesa fallida compartida e impedir un retry limpio.
- Una publicacion manual no vinculada a la rama recibio variables generales; fallo cerrado y no escribio.

## 16. Causa raiz

La causa fue combinada. La Preview no tenia una clave propia autorizada para su hostname ni un backend aislado inyectado por rama. Ademas, el cliente no propagaba `gmp-error` ni rechazos de `fetchFields`, no invalidaba de forma compartida el lugar anterior al editar el widget nuevo y no limpiaba todos los estados de carga fallida. La autoridad de persistencia existente funciono correctamente una vez resueltos esos puntos.

## 17. Correccion de configuracion

- Se creo una clave web Preview exclusiva.
- Se restringio a un unico alias HTTPS estable.
- Se restringio a Maps JavaScript API y Places API (New).
- Se instalaron variables Supabase de staging y Google exclusivamente en Preview y para la rama exacta.
- Se reconstruyo el deployment despues de cada cambio relevante.
- El alias estable se apunto al deployment Git exacto.
- Produccion no fue alterada.

## 18. Correccion de codigo

`app/googlePlacesClient.ts` ahora:

- propaga mensajes de producto mediante `onError`;
- escucha `gmp-error`;
- trata el rechazo de `fetchFields`;
- invalida una seleccion al editar;
- rechaza lugares incompletos y coordenadas no finitas;
- ignora resultados asincronos obsoletos y eventos posteriores al cleanup;
- deduplica una seleccion repetida;
- libera script y promesa tras error o timeout para permitir retry;
- restaura input y listeners al cerrar;
- conserva `gmp-select`, `toPlace()`, `fetchFields()`, el widget nuevo y el fallback legacy.

`app/page.tsx` conecta error e invalidacion al formulario oficial, borra el lugar anterior y mantiene `Guardar campo` cerrado hasta una seleccion nueva y valida.

## 19. Seleccion real

- Predicciones devueltas realmente por Google: `PASS`, al menos una por intento certificado.
- Recinto deportivo real y publico en Espana: `PASS`.
- Consulta conservada: solo categoria y localidad general; no se publica el recinto exacto.
- Localidad general: Barcelona.
- Place ID: presente y comprobado mediante hash interno; no se publica el identificador.
- Coordenadas: presentes y finitas; no se publican valores.
- No se inyecto un `VenuePlace` ni se uso fixture del proveedor.

## 20. Teclado

Seleccion desde la lista real con teclado: `PASS`. El runner exigio una opcion dentro del `listbox` accesible, observo `gmp-select`, espero `fetchFields` y verifico el estado habilitado.

## 21. Puntero

Seleccion independiente con puntero: `PASS`. El runner resolvio el nodo real de prediccion, su geometria y hit-test, y envio eventos de puntero reales mediante CDP. No se despacho artificialmente un evento de seleccion.

## 22. Campos recibidos

- `id`: presente.
- `displayName`: presente.
- `formattedAddress`: presente.
- `location`: presente y finita.
- `addressComponents`: presente.
- Ciudad/pais coherentes con la restriccion a Espana: `PASS`.

El informe no contiene place ID, direccion exacta ni coordenadas.

## 23. Estado de Guardar

- Solo texto escrito: deshabilitado.
- Error de proveedor: deshabilitado.
- Lugar incompleto: deshabilitado.
- Seleccion real valida: habilitado.
- Confirmacion visible `Direccion verificada`: `PASS`.

## 24. Invalidacion de seleccion

Tras seleccionar se edito de nuevo el widget sin elegir otra prediccion. El estado anterior se elimino, la direccion canonica se borro y `Guardar campo` volvio a quedar deshabilitado. El place ID y las coordenadas anteriores no pudieron persistirse bajo otro texto. Regresion determinista y E2E: `PASS`.

## 25. Persistencia del campo

- Campo guardado desde la UI oficial: `PASS`.
- Escritura directa en tablas: `NO`.
- Snapshot confirmado por la autoridad existente: `PASS`.
- Nombre, direccion, place ID, localidad, pais y coordenadas recuperables: `PASS`.
- Coste, modalidad y pertenencia al equipo: sin alteracion.
- Duplicado: `0`.

## 26. Creacion del partido

- Partido creado desde la UI oficial: `PASS`.
- Campo guardado seleccionado en el formulario: `PASS`.
- Persistencia mediante `save_pachanga_payload_authoritative_v2`: `PASS`.
- Actor, idempotencia y revision esperada resueltos por el contrato vigente: `PASS`.
- Escritura directa o sustitucion del payload por el runner: `NO`.

## 27. Readback tras recarga

El runner limpio deliberadamente la cache local derivada, recargo la aplicacion, abrio el partido desde el listado oficial y verifico que el campo seguia vinculado en el snapshot canonico. Resultado: `VENUE_AND_MATCH_PASS`.

## 28. Errores visibles

Se comprobaron mensajes sanitizados para carga de script, timeout, `gmp-error`, fallo de detalles, resultado incompleto y red. El estado `missing-key` se conserva. No se muestran clave, proyecto, cuenta de billing, URL interna, stack ni texto crudo del proveedor.

## 29. Offline

- Places offline: `FAIL-CLOSED`.
- Predicciones antiguas presentadas como actuales: `NO`.
- `Guardar campo` habilitado offline sin seleccion actual: `NO`.
- Cola offline de escritura deportiva: `NO`.
- Exito ficticio: `NO`.
- El unico error de red esperado quedo limitado a la ventana offline intencional.

## 30. PWA

Standalone emulada en `390x844` y `844x390`: `PASS`. Shell, estado visible, bloqueo de escritura offline, reconexion, nueva seleccion real y unicidad del widget pasaron. Manifest y Service Worker no se modificaron. PWA fisicamente instalada: `PENDING`.

## 31. Responsive

Matriz certificada:

| Viewport | Entrada | Resultado | Overflow raiz |
| --- | --- | --- | ---: |
| 1440x900 | teclado/puntero | PASS | 0 |
| 1280x720 | teclado/puntero | PASS | 0 |
| 1024x768 | tactil emulado | PASS | 0 |
| 390x844 | tactil emulado | PASS | 0 |
| 360x800 | tactil emulado | PASS | 0 |
| 844x390 | tactil emulado | PASS | 0 |

Dropdown, foco, nombre accesible, safe areas, controles, imagenes, consola y red se comprobaron. No se estilizo el Shadow DOM del proveedor ni se incorporo un selector privado a producto.

## 32. Pruebas focalizadas

- `npm run test:google-places`: `6/6`, PASS.
- E2E real de Preview: PASS.
- Rendered HTML: `9/9`, PASS.
- Seleccion real por teclado y puntero: PASS.
- Eventos observados en el E2E: `gmp-select` 2 y `gmp-error` 1.
- Official UI V2.1/V3B, Venue Operations, Mercado/Core UX, PWA/offline, Social RC, Official UI V3I y visual consistency: `151/151`, PASS.
- Retries que oculten fallos, skip, todo o fixtures de proveedor: `0`.

## 33. Suite global

- Baseline: `868/868` (`20` Node + `848` TS/TSX).
- Final: `874/874` (`20` Node + `854` TS/TSX).
- Añadidos: `6` tests focalizados.
- Eliminados: `0`.
- Failed/skipped/todo/cancelled: `0/0/0/0`.
- Typecheck: PASS.
- Build: PASS, `78/78` rutas.
- Lint focalizado: PASS.
- Lint global: PASS.
- `git diff --check`: PASS.
- Node: `v24.16.0`; npm: `11.13.0`.

## 34. Seguridad

- Claves en Git, diff, informes o fixtures: `0`.
- Archivos `.env` temporales: `0`.
- Google Preview key fuera de variable cliente requerida: `0`.
- `service_role` en navegador: `0`.
- HAR, cookies, tokens o emails conservados: `0`.
- Wildcard general Vercel: `NO`.
- Hostname inmutable temporal autorizado: `NO`.
- La clave publica esperada se comparo solo por fingerprint.
- Secret scan de fuentes cambiadas: PASS.

## 35. Datos

- Usuarios, equipos, campos y partidos reales: `0`.
- Notificaciones reales: `0`.
- Escrituras en Supabase produccion: `0`.
- Migraciones, schema, RPC, RLS y flags modificados: `0`.
- Stripe modificado: `NO`.
- La identidad, equipo, campo y partido de QA vivieron solo en la rama Supabase desechable.

## 36. Limpieza

Los perfiles Chromium y directorios temporales de cada ejecucion se eliminaron, no quedan procesos del runner, HAR, cookies, logs con clave ni archivos de entorno. Las filas sintéticas no pueden eliminarse parcialmente por los triggers de evidencia inmutable; el intento de limpieza fue transaccional y se revirtio completo. Por ello, la unica limpieza correcta es destruir la rama Supabase aislada entera. Esa destruccion, la retirada de variables branch-specific, la revocacion de la clave Preview y la retirada del worktree son gates posteriores al merge y anteriores al cierre de #166. No se confundira este estado aislado temporal con residuos productivos.

## 37. GVC-020

La descripcion historica se conserva. La fila se amplia con la prueba de #166: widget nuevo real, seleccion por teclado/puntero, persistencia, readback, error visible y offline fail-closed en Preview autenticada. El estado continua `FIXED_REGRESSION_VERIFIED`. El ledger permanece reconciliado en 20 hallazgos, 19 corregidos y verificados, 1 mitigado y 0 abiertos.

## 38. Estado del issue

`READY TO CLOSE ISSUE`. Se cerrara solo despues de fusionar este informe, desplegar el cambio runtime, verificar produccion sin escrituras, destruir el staging desechable y confirmar residuos cero.

## 39. Rollback

- Configuracion: retirar variable y clave Preview, sin sustituirlas por la clave productiva.
- Codigo: revertir unicamente la correccion de Google Places; conservar las regresiones si siguen describiendo el contrato.
- Staging: destruir la rama desechable completa.
- Produccion: no hay migracion, datos ni configuracion productiva que revertir.

El rollback se activa ante fuga de credenciales, clave Preview en produccion, wildcard amplio, widget/fallback ausente, lugar incompleto guardable, seleccion obsoleta persistida, Mercado roto, fake success offline o regresion congelada.

## 40. Conclusion

`READY TO CLOSE ISSUE`.

Una Preview autenticada, aislada y ligada al SHA de implementacion obtuvo predicciones reales de Google Places, selecciono resultados reales por teclado y puntero, recibio detalles mediante `fetchFields`, guardo un campo y creo un partido por la autoridad oficial, y recupero ambos tras eliminar la cache derivada y recargar. La configuracion Preview queda separada de produccion y la correccion cliente cubre errores, retry, invalidacion y cleanup sin cambiar el proveedor ni la autoridad de datos.
