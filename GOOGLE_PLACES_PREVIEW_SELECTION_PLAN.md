# Google Places Preview Selection Plan

Fecha del checkpoint inicial: 2026-09-04.

## 1. SHA base real

- Repositorio: `puntoracingrc/pachangas`.
- Rama de trabajo: `codex/google-places-preview-selection-closure`.
- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-google-places-preview-selection`.
- `origin/main`: `dc9ad0e519edeb058e0a9c60d16ab22aca8fcd31`.
- El SHA coincide con el checkpoint esperado y contiene los PR #269 y #270.
- El checkout compartido conserva cambios preexistentes del laboratorio de ficha; no se han modificado.

## 2. Estado del issue #166

- Estado inicial: `OPEN`.
- Titulo: `Google Places: cerrar seleccion real en Preview`.
- No contiene comentarios de cierre ni evidencia posterior a la incidencia historica.
- Solo podra cerrarse tras una seleccion real, persistencia por flujos oficiales, recarga canonica y limpieza del staging.

## 3. Fuentes revisadas

- Issue #166, eventos y referencia desde PR #162.
- PR #163 y sus informes de QA autenticada y convergencia visual.
- `OFFICIAL_UI_V2_1_AUTHENTICATED_QA_REPORT.md`.
- `OFFICIAL_UI_V2_1_DEEP_DEMO_PARITY_REPORT.md`.
- `GLOBAL_VISUAL_CONSISTENCY_AUDIT_V1.md`, incluido GVC-020.
- Informes de campos, disponibilidad, reservas, vinculacion canonica de partidos y release de Venue Operations.
- Commits `466f3b3e583f16518fad3d1dbfab1f1e24493207` y `db288ec7fc6c43b743126aca51e597a684475090`.
- Codigo y consumidores actuales de `attachVenueAutocomplete`.
- Scripts y pruebas vigentes de UI, PWA, offline, campos y partidos.
- Documentacion oficial de Google Maps Platform y Vercel.

## 4. Estado historico del bloqueo

Official UI V2.1 permitio escribir texto en el campo, pero no mostro una prediccion seleccionable. `Guardar campo` permanecio deshabilitado y no se fabrico un campo ni un partido para esquivar el bloqueo. Ese informe se mantiene intacto como evidencia historica.

## 5. Call graph actual

1. `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` se lee en los componentes cliente durante el build de Next.js.
2. `attachVenueAutocomplete` llama a `loadGooglePlaces`.
3. El helper carga `https://maps.googleapis.com/maps/api/js` con `libraries=places`, `loading=async`, `v=weekly` y callback propio.
4. Tras la carga usa `google.maps.importLibrary("places")` cuando la libreria no esta ya disponible.
5. Prefiere `PlaceAutocompleteElement`, espera a `gmp-place-autocomplete`, oculta el input original e inserta el custom element.
6. Escucha `gmp-select`, obtiene `placePrediction`, llama a `toPlace()` y despues a `fetchFields()`.
7. Convierte `id`, `displayName`, `formattedAddress`, `location` y `addressComponents` en `VenuePlace`.
8. El formulario oficial guarda el resultado en `selectedVenuePlace` y solo entonces habilita `Guardar campo`.
9. `addVenue` incorpora el campo al read model de React y al partido activo.
10. Para un grupo real, el autosave y el guardado explicito terminan en `save_pachanga_payload_authoritative_v2`, con actor autenticado, `operation_id` y revision esperada.
11. La respuesta de la RPC aplica el commit canonico; Realtime provoca una relectura de `pachanga_groups` y la recarga vuelve a leer el payload confirmado.

## 6. Consumidores de Google Places

- `app/page.tsx`: creacion de campo para el partido y zonas personales de Mercado.
- `app/mercado/marketplace-client.tsx`: filtro geografico del Mercado.
- `app/mercado/team-challenges-panel.tsx`: campo de un reto.
- `app/mercado/challengeable-teams-panel.tsx`: zona publica retable del equipo.
- El issue #166 se certificara en el flujo autenticado de creacion de campo y partido. No se hara un refactor global de consumidores.

## 7. Widget nuevo

- Primario: `google.maps.places.PlaceAutocompleteElement`.
- Custom element: `gmp-place-autocomplete`.
- Restriccion regional: Espana mediante `includedRegionCodes = ["es"]`.
- Tipos opcionales se trasladan a `includedPrimaryTypes`.
- Se conserva como implementacion primaria.

## 8. Fallback legacy

- Fallback existente: `google.maps.places.Autocomplete`.
- Evento: `place_changed`.
- Restriccion de pais: `es`.
- Se conserva en codigo, pero Places API legacy solo se autorizara a la clave Preview si una prueba real demuestra que es necesaria para este flujo.

## 9. Eventos actuales

- Seleccion del widget nuevo: `gmp-select`.
- Seleccion legacy: `place_changed`.
- El helper no escucha actualmente `gmp-error`.
- El input React original invalida la seleccion con `onChange`, pero ese input queda oculto cuando funciona el widget nuevo; la edicion dentro del custom element no tiene una invalidacion compartida demostrada.

## 10. Campos solicitados

- Widget nuevo: `id`, `displayName`, `formattedAddress`, `location`, `addressComponents`.
- Legacy: `place_id`, `name`, `formatted_address`, `geometry`, `address_components`.
- `VenuePlace`: `placeId`, `name`, `address`, `lat`, `lng`, `city`, `province`, `country`.

## 11. Estado del formulario

- Al abrir, el estado es `loading` cuando existe clave y `missing-key` en caso contrario.
- La inicializacion correcta pasa a `ready`.
- Una excepcion de carga pasa a `error` con un mensaje visible.
- `Guardar campo` usa `disabled={!selectedVenuePlace}`.
- Solo escribir texto no habilita el guardado.
- Riesgo localizado, aun pendiente de reproduccion: una seleccion anterior podria seguir habilitada al editar el custom element nuevo.

## 12. Flujo de persistencia

- Campo: `addVenue` actualiza `venues` y asigna el `venueId` al partido activo.
- Autoridad remota: el read model se serializa y se envia a `save_pachanga_payload_authoritative_v2`.
- Concurrencia: revision esperada; en conflicto se relee el grupo.
- Idempotencia: `operation_id` nuevo por intencion.
- Partido: `confirmQuickMatch` prepara el partido y llama a `saveMatchConfiguration`, que usa el mismo guardado autoritativo y backup.
- Lectura canonica: snapshot confirmado de la RPC y relectura de `pachanga_groups` por carga/Reatime.
- La prueba E2E no escribira tablas ni alterara payloads directamente.

## 13. Configuracion Vercel actual, sin valores

- Proyecto Vercel correcto y worktree enlazado.
- `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` existe como variable Preview general y como variable Production.
- Ambos valores tenian el mismo fingerprint SHA-256 real: `43042d3d2fb1c3d2f28ed7b3aa0a2341298b62e50788b7cb053af939548c42e1`. El fingerprint `3930fb7a9a99cc3dae417b58f54434ef8fb795ef4e1229eaba49b37e8b48424a` observado durante el primer inventario correspondia al marcador cifrado de Vercel, no al valor servido por el bundle, y queda descartado como evidencia de clave.
- No existe override de Google Maps para la rama nueva.
- La Preview general tambien hereda el mismo Supabase URL y publishable key que Production.
- Existen variables branch-specific antiguas para staging, pero el endpoint usado por Official UI V2.1 ya no resuelve por DNS y no hay una rama staging activa reutilizable.
- No se ha creado aun deployment ni URL estable para esta rama.
- Todos los archivos temporales usados para comparar fingerprints fueron eliminados al terminar cada comando.

## 14. Configuracion Google Cloud actual, sin valores

- Proyecto correcto seleccionado y facturacion vinculada mediante una cuenta de prueba activa en el momento de la auditoria.
- `Maps JavaScript API`, `Places API` y `Places API (New)` aparecen habilitadas en el proyecto.
- La unica clave web de Maps localizada usa restricciones `Websites`.
- Tiene siete referrers, mezclando localhost, varios hostnames Preview historicos y los dos dominios productivos.
- La clave permite 35 APIs, muchas no usadas por este flujo.
- En las ultimas 24 horas el panel muestra cero trafico y cero errores.
- El estado de cuota se certificara mediante la llamada real desde la Preview nueva.
- No se mostro, copio ni guardo el valor de la clave.

## 15. Separacion Preview/produccion

Estado inicial: `NO CUMPLE`.

- Google Preview y Production comparten valor.
- Supabase Preview general y Production comparten valor.
- Objetivo: clave Google web nueva exclusiva de la rama Preview y Supabase desechable exclusivo de QA.
- La clave productiva no se rotara ni se cambiara de valor.
- Tras validar la nueva clave Preview, solo se estudiara retirar de la clave productiva los referrers Preview ya innecesarios, sin tocar dominios productivos ni APIs por intuicion.

## 16. Reproduccion inicial

- Evidencia historica: dos intentos de Official UI V2.1 no produjeron una prediccion seleccionable.
- Reproduccion desde el main actual: `PENDING` al crear este plan.
- Motivo: la rama nueva aun no tiene Preview y la configuracion Preview general apunta a Supabase productivo; no se ejecutara un E2E autenticado en ese estado.
- Siguiente paso: crear una rama Supabase desechable, trasladar solo sus credenciales publicas/servidor necesarias a variables branch-specific, desplegar el main sin cambios y reproducir dos veces antes de modificar el helper o la clave Google existente.

## 17. Errores del navegador

- Historicos: ausencia de predicciones y boton deshabilitado; no se conservo un error de consola concluyente.
- Actual main: pendientes de capturar en Preview exacta mediante consola, red y estado visible.
- Las URL de red que incluyan clave se sanitizaran en memoria; no se conservara HAR sin redactar.

## 18. Errores del proveedor

- El panel actual no registra trafico ni errores durante las ultimas 24 horas.
- El cliente no escucha `gmp-error`, por lo que una denegacion del backend puede no llegar a la UI aunque la carga inicial termine.
- Este hueco se considerara causa de producto solo si la reproduccion confirma la ruta.

## 19. Clasificacion provisional

Pendiente de la reproduccion nueva. La hipotesis provisional es `REPRODUCED_PREVIEW_INTEGRATION_DEFECT` con:

- `PREVIEW_KEY_ORIGIN_CONFIGURATION`.
- `PREVIEW_ENVIRONMENT_INJECTION`.
- Posible `CLIENT_ERROR_HANDLING` y `CLIENT_SELECTION_FLOW`, sujetos a reproduccion.

No es una clasificacion final.

## 20. Archivos previstos

Antes de reproducir no se modificara runtime. Si se confirma defecto de cliente, el cambio se limitara a:

- `app/googlePlacesClient.ts`.
- `app/page.tsx`, solo para conectar invalidacion/error visible.
- Una prueba focalizada nueva o pruebas existentes estrictamente relacionadas.
- `package.json` y lockfile solo si una prueba indispensable lo exige; no se preve una dependencia nueva.
- `GOOGLE_PLACES_PREVIEW_SELECTION_REPORT.md`.
- `GLOBAL_VISUAL_CONSISTENCY_AUDIT_V1.md` solo si GVC-020 necesita reconciliacion documental.

Este plan es el primer archivo creado.

## 21. Cambios externos previstos

- Crear y destruir una rama Supabase de staging sin datos productivos.
- Copiar sus variables al scope Preview de esta rama, nunca a Production.
- Crear una clave Google Maps web Preview separada, restringida al hostname estable de la rama y solo a las APIs demostradas.
- Crear deployments Preview posteriores a cada cambio de variable.
- No modificar Stripe, Supabase productivo, migraciones, RLS, RPC ni flags.

## 22. Pruebas

- Dos reproducciones desde sesiones limpias antes de tocar runtime.
- Seleccion real por teclado y por puntero.
- `gmp-select`, `fetchFields`, estado seleccionado, boton e invalidacion posterior.
- `gmp-error`, clave ausente, clave denegada y red offline con mensajes visibles y fail-closed.
- Campo y partido mediante UI oficial; recarga y readback canonico.
- Duplicados, Realtime y reconexion.
- Desktop, portrait, landscape y PWA emulada; QA fisica seguira `PENDING`.
- Tests focalizados, `npm test`, typecheck, build, rutas, lint focalizado/global, `git diff --check` y secret scan.

## 23. Datos sinteticos

- Una identidad QA sin PII, owner de un unico grupo QA.
- El perfil minimo y el equipo se crearan mediante sus RPC oficiales autenticadas; el campo y el partido se crearan exclusivamente mediante la UI oficial, sin inserts directos.
- Un campo real seleccionado desde una prediccion devuelta por Google.
- Un partido minimo creado con ese campo.
- La evidencia solo publicara localidad general, hash del place ID y presencia de coordenadas.
- Cero datos o notificaciones reales.

## 24. Limpieza

- Borrar por flujos autorizados el partido, campo, grupo, perfil, usuario y sesion QA.
- Confirmar readback a cero en staging.
- Retirar la rama Supabase temporal.
- Eliminar archivos de entorno, HAR, cookies/perfiles temporales y procesos propios.
- Conservar la clave Preview final y su variable branch-specific solo mientras sean necesarias para la evidencia/Preview segura; retirar hostnames temporales.
- Retirar este worktree solo tras merge, deployment solicitado, estado limpio y HEAD contenido en `origin/main`.

## 25. Rollback

- Configuracion: retirar el override branch-specific Google y cualquier hostname temporal; no sustituirlo por la clave productiva.
- Codigo: revertir solo el cambio Google Places, conservando regresiones que sigan describiendo el contrato.
- Staging: destruir la rama Supabase completa.
- Activar rollback ante fuga de clave, wildcard amplio, clave Preview en Production, seleccion incompleta que habilite guardado, stale selection, ruptura de Mercado, fake success offline o regresion productiva.

## 26. Criterios para cerrar el issue

- Clave Preview y produccion distintas, restringidas y con fingerprints distintos.
- URL estable de rama autorizada y enlazada al deployment/commit exactos.
- Predicciones reales y seleccion real por teclado y puntero.
- `gmp-select` y `fetchFields` observados; errores del proveedor visibles.
- Place ID, nombre, direccion y coordenadas validas presentes sin publicarlos.
- `Guardar campo` deshabilitado sin seleccion, habilitado tras seleccion e invalidado al editar.
- Campo y partido persistidos por los flujos oficiales y recuperados tras recarga.
- Offline fail-closed, reconexion, Realtime, responsive y PWA verificados.
- Secret scan limpio, staging a cero, informe fusionado y produccion separada.
- Si alguno de estos puntos no puede demostrarse con seguridad, el issue permanece abierto.

## 27. Actualizacion tras la reproduccion aislada

- Preview Git aislada: `https://pachangas-kgopmn31t-persianas-almar-web-s-projects.vercel.app`.
- Alias estable de rama: `https://pachangas-git-codex-googl-ff0eb8-persianas-almar-web-s-projects.vercel.app`.
- La reproduccion se ejecuto dos veces con consultas reales y devolvio bloqueo por referrer en ambas ocasiones.
- El widget emitia el error en consola, pero el producto no mostraba un error visible.
- Clasificacion provisional confirmada: `REPRODUCED_PREVIEW_INTEGRATION_DEFECT`.
- Causas reproducidas: `PREVIEW_KEY_ORIGIN_CONFIGURATION`, `PREVIEW_ENVIRONMENT_INJECTION`, `CLIENT_ERROR_HANDLING` y `CLIENT_SELECTION_FLOW`.
- Se creo una clave Preview separada, limitada al alias estable y exclusivamente a Maps JavaScript API y Places API (New).
- Fingerprint SHA-256 de la clave Preview nueva: `f4ce75cb57f57469088fd7cbbd339f521dd3b7e4fb568749e0f1fef2878ab420`.
- El fingerprint Preview es distinto del productivo y la clave productiva no se modifico.
- La seleccion y persistencia reales quedan pendientes del deployment construido despues del cambio de runtime y de la nueva variable.

## 28. Checkpoint de ejecucion completado

- Deployment Git certificado: `https://pachangas-3r9tpvon7-persianas-almar-web-s-projects.vercel.app` (`READY`).
- Alias estable autorizado: `https://pachangas-git-codex-googl-ff0eb8-persianas-almar-web-s-projects.vercel.app`.
- SHA de implementacion: `5d73140277096c9bc32a7c609d8d908308f11045`.
- La clave Preview quedo limitada al alias estable, Maps JavaScript API y Places API (New); la clave productiva permanecio intacta.
- El E2E real obtuvo predicciones, selecciono por teclado y puntero, observo `gmp-select` y `gmp-error`, completo `fetchFields`, invalido una seleccion editada y mantuvo el guardado cerrado sin seleccion valida.
- El campo y el partido se guardaron mediante la UI y autoridad existentes; la recarga, tras limpiar la cache derivada, recupero el mismo campo canonico.
- Offline y reconexion, PWA emulada, seis viewports y overflow cero pasaron.
- La rama Supabase aislada se destruira completa despues del merge para respetar sus evidencias inmutables y confirmar residuos cero antes de cerrar #166.
