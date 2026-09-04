# Ranking CRON_SECRET Production Verification Report

Fecha de cierre de evidencia: 2026-09-04 (UTC y Europe/Madrid)

## 1. Clasificacion final

`ALREADY_CONFIGURED_AND_VERIFIED`

Estado del gate: `VERIFIED - READY TO CLOSE ISSUE`.

`CRON_SECRET` ya estaba configurado correctamente. No hizo falta cambiar codigo, `vercel.json`, variables, deployments, Supabase ni datos. Su valor no se leyo, imprimio, descifro, copio, rotó ni convirtio en fingerprint.

## 2. SHA base

- Repositorio: `puntoracingrc/pachangas`.
- Base auditada: `origin/main` en `3fa6fe778fe00b7b2218b3ee1fbee108b2a060d6`.
- Rama aislada: `codex/ranking-cron-secret-production-verification`.
- El checkout compartido estaba atrasado y contenia cambios locales ajenos; se preservo sin editar ni limpiar.

## 3. Issue #170

- Issue: [#170 - Ranking: verificar CRON_SECRET productivo sin exponerlo](https://github.com/puntoracingrc/pachangas/issues/170).
- Estado al congelar esta evidencia: `OPEN`, sin comentarios previos.
- Cierre autorizado: inmediatamente despues de fusionar este plan e informe.
- `#167`, `#168` y `#169`: `OPEN/PENDING` y fuera de alcance.
- `#165` y `#166`: `CLOSED/FROZEN`.

## 4. Fuentes revisadas

- Issue `#170` y estados de `#165` a `#169`.
- Informes y runbook de Ranking Productization V1.
- Migraciones Ranking R1-R8, cola, formula, temporadas, candidatos, publicaciones, recibos, eventos, integridad y health.
- Rutas server-side de Ranking, Billing y Team Operational; Control Center, producto provincial, `vercel.json`, `.env.example` y `package.json`.
- Suites Ranking, DB/RLS, concurrencia, Control Center y PWA/offline relacionadas.
- Metadatos de entorno, deployments, cron jobs, runtime logs y metricas de Vercel.
- Readback SQL agregado y exclusivamente de lectura en el proyecto Supabase `Pachangas`.
- Documentacion oficial de Vercel para Cron Jobs, variables sensibles, entornos y runtime logs; changelog oficial de Supabase.

## 5. Estado del piloto Ranking

- Temporada activa: `barcelona-pilot-2026` (`Piloto provincial Barcelona 2026`).
- Estado: `open`.
- Provincia piloto: Barcelona `08`.
- Revision de temporada: `2`.
- Revision Ranking/publicada: `2 / 2`.
- Formula: `season_score_v3`, version `1`.
- No hay entradas reales publicadas: `0` entradas y `0` clasificadas; es un estado vacio valido y saludable.

## 6. Call graph

`Vercel Cron GET (UTC)` -> `/api/internal/rankings/refresh` -> carga server-only de `CRON_SECRET` -> comparacion exacta del Bearer -> `platformServiceClient()` -> `process_pachanga_ranking_refresh_queue_v1(maximum_operations => 25)` -> snapshot JSON canonico con `Cache-Control: no-store, max-age=0`.

La RPC se alcanza solo despues de una autorizacion valida. Variable ausente termina en `503`; header ausente o diferente termina en `403` antes de crear el cliente Supabase.

## 7. Rutas protegidas

Los tres cron productivos que comparten el secreto son:

1. `/api/internal/rankings/refresh`.
2. `/api/internal/billing/reconcile`.
3. `/api/internal/team-operational/expire`.

El scan de codigo encontro una cuarta referencia server-only en `/api/internal/billing/expire`, que no figura como cron registrado. No hay referencias cliente ni se modifico esa ruta.

## 8. Schedule registrado

| Worker | Ruta | Schedule UTC | Registro activo |
| --- | --- | --- | --- |
| Ranking | `/api/internal/rankings/refresh` | `*/5 * * * *` | Si |
| Billing | `/api/internal/billing/reconcile` | `17 * * * *` | Si |
| Team Operational | `/api/internal/team-operational/expire` | `*/10 * * * *` | Si |

Vercel informa cron habilitado, cero definiciones modificadas sin desplegar y cero definiciones pendientes. Hay una sola definicion de Ranking, sin ruta alternativa ni duplicado. Las tres pertenecen al deployment productivo activo.

## 9. Metadata de variable

- Nombre: `CRON_SECRET`.
- Entradas en el proyecto: exactamente `1`.
- Creada y actualizada: `2026-08-28T16:23:08.034Z`.
- Scope: proyecto `pachangas`, no variable compartida.
- Overrides de rama: ninguno.
- Duplicados contradictorios: ninguno.
- El informe conserva solo metadata; nunca el valor ni una propiedad derivada de el.

## 10. Scope de entornos

- Production: `PRESENT`.
- Preview: `ABSENT`.
- Development: `ABSENT`.
- Custom environments: ninguno.

Es el scope minimo necesario: Vercel Cron se ejecuta contra Production y no se ha propagado el secreto a clientes ni entornos que no lo necesitan.

## 11. Tipo de variable

- Tipo Vercel: `sensitive`.
- Visibilidad: secreta y no legible despues de su creacion.
- Variable publica o `NEXT_PUBLIC_`: no.
- Shared variable: no; es una variable especifica del proyecto.

## 12. Confirmacion de no exposicion

- Valor leido o impreso: `NO`.
- Valor enviado manualmente: `NO`.
- Hash/fingerprint, longitud, prefijo o sufijo publicado: `NO`.
- Header Authorization capturado o registrado: `NO`.
- Secretos en URL, captura, HAR, plan, informe, PR o comentario: `0`.
- `service_role` expuesto al navegador: `NO`.

## 13. Confirmacion de no rotacion

- Secreto rotado: `NO`.
- Secreto reemplazado, duplicado, movido o eliminado: `NO`.
- Razon: el secreto existente es sensible, tiene scope Production, fue incorporado a un deployment posterior y mantiene operativos los tres cron compartidos.

## 14. Distribucion de logs

Ventana historica fija, para evitar deriva de una ventana movil: `2026-08-28T12:00:00Z` a `2026-09-04T12:00:00Z`.

| Status | Total |
| --- | ---: |
| `200` | 1.963 |
| `403` | 0 |
| `503` | 54 |
| `500` | 0 |

Snapshot de 24 horas posterior a las pruebas negativas: `293` respuestas `200`, `9` respuestas `403` controladas por esta auditoria y `0` respuestas `503/500`. Los `403` no proceden del scheduler y estan separados por timestamp de la cadencia programada.

La cifra preliminar `1.957 / 60` pertenecia a otra posicion de la ventana movil. La tabla anterior es el intervalo fijo autoritativo de este informe.

## 15. Reconciliacion de los 503

- Ventana retenida afectada: desde al menos `2026-08-28T11:31:36Z` hasta `2026-08-28T16:25:01Z`.
- Deployments afectados: revisiones `8807ed66548b4b2ea749f46c27f71dcf855057f0`, `a8fa127901fcb32e60bd5cc096770f5ee1737a3d` y `42e697e294ba2849b1cb5116f2aec24b29f010f9` construidas antes de configurar la variable Production.
- Las tres revisiones y el HEAD actual tienen el mismo SHA-256 de fuente para la ruta Ranking; el contrato devuelve `503 RANKING_REFRESH_NOT_CONFIGURED` cuando falta la variable.
- La variable quedo configurada a `16:23:08Z`; un redeploy de la misma revision comenzo a `16:23:26Z`, quedo `READY` a `16:24:56Z`, el deployment anterior recibio su ultimo `503` a `16:25:01Z` durante la transicion de alias y el nuevo devolvio `200` a `16:25:37Z`.
- No se observan `503` actuales ni en la ventana reciente del deployment vigente.

Clasificacion de la ventana: `RESOLVED_ENVIRONMENT_DEFECT`. Fue un deployment previo a la inyeccion de entorno, ya resuelto antes de esta tarea; no es un defecto actual ni requirio correccion adicional.

## 16. Prueba sin header

Se realizaron dos peticiones independientes sin `Authorization` contra produccion.

- Status: `403`.
- Error: `RANKING_REFRESH_FORBIDDEN`.
- Claves del body: solo `error`.
- Cache-Control: `no-store, max-age=0`.
- Redirect/login/HTML generico: no.
- Stack, metadata privada o eco de credencial: no.
- RPC invocada: no, confirmado por orden del codigo y readback identico.

## 17. Prueba con Bearer falso

Se probaron de forma acotada: Bearer falso, esquema en minusculas, Bearer sin valor, espacios, texto plano, Basic falso y token falso largo. No se probo ninguna variante, prefijo o propiedad del secreto real.

Las siete variantes devolvieron exactamente `403`, `RANKING_REFRESH_FORBIDDEN`, body sanitizado y `no-store`. Sumadas a las dos peticiones sin header fueron nueve rechazos controlados, todos sin efectos laterales ni reflejo del header.

## 18. Prueba sin variable en entorno aislado

Se ejecuto el build productivo local con `CRON_SECRET` explicitamente ausente en un proceso desechable, sin alterar Vercel ni Supabase.

- Status: `503`.
- Error: `RANKING_REFRESH_NOT_CONFIGURED`.
- Claves del body: solo `error`.
- Cache-Control: `no-store, max-age=0`.
- RPC invocada: no.
- Proceso local: detenido tras la prueba.

## 19. Ejecucion autorizada

Se utilizo la evidencia preferente: invocaciones reales de Vercel Cron. El secreto no se obtuvo ni se construyo un header manual.

- Resultado: `200`.
- Ruta/RPC: la ruta solo puede devolver `200` despues de que `process_pachanga_ranking_refresh_queue_v1(25)` responda sin error.
- Cola: vacia; `0` operaciones procesadas y `0` fallidas es un PASS valido.
- Respuesta segura observada: `226` bytes por slot seleccionado.
- Cache: `BYPASS`; no hubo cacheo de la respuesta de funcion.

## 20. Seis slots consecutivos

Deployment: `dpl_9vz9zs67SxE2DhTX1YrL3RXUq3wY`, rama `main`, SHA `3fa6fe778fe00b7b2218b3ee1fbee108b2a060d6`.

| Slot UTC | Status | Duracion | Inicio | Bytes | Error |
| --- | ---: | ---: | --- | ---: | --- |
| `2026-09-04T11:30:20Z` | 200 | 459 ms | hot | 226 | ninguno |
| `2026-09-04T11:35:20Z` | 200 | 437 ms | hot | 226 | ninguno |
| `2026-09-04T11:40:20Z` | 200 | 356 ms | hot | 226 | ninguno |
| `2026-09-04T11:45:20Z` | 200 | 460 ms | hot | 226 | ninguno |
| `2026-09-04T11:50:20Z` | 200 | 468 ms | hot | 226 | ninguno |
| `2026-09-04T11:55:20Z` | 200 | 283 ms | hot | 226 | ninguno |

Resumen: `6/6` status `200`, `0` status `403/503/500`, `0` timeout/crash, maxima `468 ms`, cero ejecuciones Preview y cero duplicacion anomala. Slots posteriores, incluidos `12:05Z` y `12:10Z`, continuaron en `200` despues de las pruebas negativas.

## 21. Cola antes/despues

| Medida | Antes (`12:04:37Z`) | Despues de rechazos (`12:05:20Z`) | Final (`12:46:56Z`) |
| --- | ---: | ---: | ---: |
| Total | 0 | 0 | 0 |
| Queued | 0 | 0 | 0 |
| Processing | 0 | 0 | 0 |
| Completed | 0 | 0 | 0 |
| Failed | 0 | 0 | 0 |
| Dead letter | 0 | 0 | 0 |
| Attempts | 0 | 0 | 0 |

Oldest queued: `null`. Operaciones procesadas por los slots observados: `0`. Operaciones fallidas: `0`.

## 22. Readback de health

- Estado: `OK`.
- Reason codes: `[]`.
- Queued/stuck/failed/dead letter: `0 / 0 / 0 / 0`.
- Failed rebuilds/integrity pending/pending rebuild diffs: `0 / 0 / 0`.
- Pilot publications: `1`.
- Pending rebuilds: `0`.
- `last_error_code`: `null`.

El estado final coincide con los snapshots anterior y posterior a los rechazos.

## 23. Publicacion

- Provincia: `08`.
- Revision publicada: `2`.
- Server sequence: `16`.
- Checksum: `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`.
- Entry count/ranked count: `0 / 0`.
- Ranking receipts: `6`, max sequence `17`.
- Ranking events: `4`, max sequence `18`.

No cambio ninguna revision, checksum, receipt o evento durante las pruebas rechazadas ni los slots sobre cola vacia.

## 24. Flags

- `season_score_product_enabled = true`.
- `provincial_rankings_product_enabled = true`.
- `provincial_awards_enabled = false`.
- `pilot_province_codes = ['08']`.
- Revision de settings: `3`.
- Formula checksum de temporada y registro: `e7b1788fa2d6d7ce2c37cd00f8fa55d78a87539bfa68c76a383bb3500ac388a4` en ambos; `matches = true`.

## 25. Premios

- Awards flag: `OFF`.
- Awards creados por esta tarea: `0`.
- Rewards creados por esta tarea: `0`.
- Grants preexistentes: `17` achievement grants y `17` reward grants; permanecieron estables en la comparacion de efectos laterales.
- Premium/provincial rewards activados: no.

## 26. Otros sistemas

Readback protegido antes y despues de las nueve peticiones rechazadas:

- Rating snapshots: `1`; individual rating evidence: `0`; player profiles: `1` en el readback final.
- Conduct reports/warnings/social restrictions: `0 / 0 / 0`.
- Notifications: `61`.
- Team Cosmetic Reward ledger: `7`.
- Competition sanctions: `0`.
- Stripe webhook events/reconciliations: `0 / 0`.
- Rating, assessments, facetas, perfiles, Conduct, restricciones, achievements, rewards, cosmetics, notificaciones y sanciones modificados por Ranking: `NO`.

El ledger de Billing era `329` antes y despues de los rechazos. En el readback final posterior era `331` debido a ejecuciones normales del cron independiente de Billing; Ranking no lo modifico.

## 27. Safety check Billing/Team Operational

- Billing `/api/internal/billing/reconcile`: `25/25` ejecuciones programadas `200` en 24 horas; `0` estados alternativos.
- Team Operational `/api/internal/team-operational/expire`: `147/147` ejecuciones programadas `200` en 24 horas; `0` estados alternativos.
- Invocaciones manuales a esas rutas: `0`.
- Stripe inspeccionado o modificado: `NO`.
- Equipos o estados sinteticos creados: `0`.

La comprobacion demuestra que la verificacion y la ausencia de rotacion no rompieron los otros cron que comparten el secreto.

## 28. Tests

- `npm ci`: PASS, `525` paquetes instalados desde lockfile.
- Baseline `npm test`: PASS, Node `20/20`, TS/TSX `854/854`, total `874/874`.
- Focalizados Ranking + Control Center + PWA bridge/routes: `39/39` PASS.
- DB/RLS Ranking local aislado: `RANKING_PRODUCTIZATION_V1_DB_OK`, transaccion revertida.
- Concurrencia Ranking local aislada: PASS; misma operacion converge, un ganador de lifecycle, revision obsoleta rechazada y cola durable con `SKIP LOCKED`.
- Primer intento de concurrencia: fallo de entorno porque la imagen PostgreSQL aislada no incluia la semantica JSON de `auth.uid()` de Supabase. Se corrigio solo el shim del contenedor desechable y la regresion paso; no fue un defecto de producto ni genero diff.
- Cobertura nueva: no se anadio. La evidencia combinada cubre los estados HTTP reales/aislados, el orden de autorizacion, la RPC, schedule, DB/RLS y concurrencia sin refactorizar el Route Handler solo para testearlo.
- Final full rerun: `npm test` PASS, Node `20/20`, TS/TSX `854/854`, total `874/874`; failed/skipped/todo/cancelled `0/0/0/0`.
- `npm run typecheck`: PASS.
- `npm run build`: PASS, `78/78` rutas generadas.
- `npm run lint`: PASS; solo nota informativa de Babel por el tamano preexistente de `app/page.tsx`.
- Lint focalizado de la ruta Ranking, prueba Ranking, autenticacion de plataforma, API admin y producto provincial: PASS.
- `git diff --check`: se exige PASS en el gate inmediatamente anterior al commit.

## 29. Preview

- Preview nueva: no creada; el diff es exclusivamente documental y no existe cambio de runtime o test que justificar.
- `CRON_SECRET` Preview: `ABSENT`.
- El caso sin variable se verifico en un build productivo local desechable y devolvio `503` fail-closed.
- No se conecto una Preview a Supabase produccion ni se creo secreto temporal.
- Deployment protection: sin cambios.

## 30. Produccion

- Dominio: [https://pachangasiq.com](https://pachangasiq.com).
- Deployment: `dpl_9vz9zs67SxE2DhTX1YrL3RXUq3wY`.
- URL inmutable: `https://pachangas-qs9adxod9-persianas-almar-web-s-projects.vercel.app`.
- Estado/target: `READY / production`.
- Creado: `2026-09-04T08:57:56.424Z`.
- Metadata SHA: `3fa6fe778fe00b7b2218b3ee1fbee108b2a060d6`.
- Deployment construido despues de configurar la variable: `SI`.
- Runtime de Ranking: `nodejs`; `dynamic = force-dynamic`; `maxDuration = 60`.
- Vercel Cron y alias productivo: operativos.

## 31. Secret scan

- Git tracked con asignaciones de valor `CRON_SECRET=...`: `0`.
- Uso de `NEXT_PUBLIC_CRON_SECRET` en runtime o codigo cliente: `0`; el nombre aparece solo en esta evidencia documental de ausencia.
- Referencias en componentes cliente: `0`.
- Referencias en `app`: `4`, todas Route Handlers server-side.
- `.next/static` y `public`: `0` referencias por nombre.
- HTML generado: `0`.
- Manifest/Service Worker/cache PWA: `0`.
- Runtime logs, busqueda `CRON_SECRET`: `0`.
- Runtime logs, busqueda `Authorization`: `0`.
- Body de respuestas negativas con token falso o secreto: `0`.
- Secret value found in public artifact: `NO`.
- Patrones plausibles de secretos Stripe, Supabase, JWT o asignaciones de valor cron en los `2.087` archivos revisados, incluidos plan e informe: `0`.

La herramienta disponible no incluia `gitleaks` ni `trufflehog`; se usaron scans deterministas de Git, diff, codigo cliente, bundle publico, HTML, PWA y logs. Ningun scan necesito conocer el valor.

## 32. Archivos modificados

Diff previsto y final:

1. `RANKING_CRON_SECRET_PRODUCTION_VERIFICATION_PLAN.md`.
2. `RANKING_CRON_SECRET_PRODUCTION_VERIFICATION_REPORT.md`.

Codigo/runtime/tests/SQL/migraciones/UI/configuracion: `0` archivos. `package.json` y `package-lock.json`: sin cambios.

## 33. Configuracion externa modificada

- Vercel env: `NO`.
- Vercel cron/schedule/domain/alias: `NO`.
- Secreto: `NO`.
- Supabase schema/RPC/RLS/flags/datos: `NO`.
- Stripe: `NO`.
- Google Places/PWA/Service Worker: `NO`.

## 34. Datos reales

- Usuarios/equipos/partidos/perfiles reales creados: `0`.
- Trabajo Ranking sintetico productivo creado: `0`.
- Awards/rewards/sanciones creados: `0 / 0 / 0`.
- Notificaciones, emails, push, SMS o WhatsApp enviados: `0`.
- Stripe calls causadas por esta tarea: `0`.
- Consultas Supabase productivas: exclusivamente `SELECT` agregados, sin PII ni IDs de jugador.

## 35. Rollback

No existe rollback operativo porque no se modifico runtime, variable, cron ni base de datos. Si fuese necesario retirar la evidencia, se revierte el commit documental. La variable Production valida y los tres cron deben conservarse.

## 36. Limpieza

Al finalizar el merge y cierre se eliminan exclusivamente: contenedor PostgreSQL local de esta tarea, `.env.local` generado por el link de Vercel, artefactos/procesos propios, rama local fusionada y worktree aislado. No se eliminan caches, worktrees, contenedores, cambios o procesos ajenos. Residuos finales se confirmaran en el comentario de cierre y la respuesta final.

## 37. Estado del issue

`VERIFIED - READY TO CLOSE ISSUE`.

El issue `#170` permanece abierto mientras este informe aun no este fusionado. Tras el merge recibira un comentario sanitizado con clasificacion, PR, SHA final, deployment, schedule, scope, seis slots, pruebas negativas, readback, exposicion `0`, rotacion `NO` y enlace a este informe; entonces se cerrara. Los issues fisicos `#167`, `#168` y `#169` no se modifican.

## 38. Conclusion

El cron de Ranking esta correctamente registrado en Production a cinco minutos, el deployment vigente recibe una unica variable sensible y project-scoped, las invocaciones reales autorizadas ejecutan la autoridad PostgreSQL con limite `25`, y todas las formas no autorizadas probadas fallan antes de la RPC. Los `503` historicos corresponden a deployments anteriores a la configuracion de entorno y no continuan. Cola, health, publicacion, checksums y sistemas protegidos permanecen canonicos.

No existe defecto actual. El cierre correcto es documental, sin falso hotfix, sin rotacion, sin migracion y sin datos QA productivos.

## Evidencia enlazada

- [Plan de verificacion](./RANKING_CRON_SECRET_PRODUCTION_VERIFICATION_PLAN.md)
- [Issue #170](https://github.com/puntoracingrc/pachangas/issues/170)
- [Ranking Productization V1](./RANKING_PRODUCTIZATION_V1_PRODUCTION_RELEASE.md)
- [Produccion](https://pachangasiq.com)
