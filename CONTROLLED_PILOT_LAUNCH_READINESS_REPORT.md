# Pachangas IQ Controlled Pilot Launch Readiness

Fecha de cierre: 2026-09-05 CEST

## Clasificacion

`READY FOR CONTROLLED PILOT AFTER FIXES`

Pachangas IQ esta preparada para iniciar un piloto controlado en navegador con
usuarios conocidos. Durante la certificacion se encontro un unico bloqueo del
recorrido principal: un jugador sin equipo podia completar su perfil social,
pero no tenia un flujo autoritativo para publicar o retirar su disponibilidad
en Mercado. El bloqueo se corrigio, se valido en un entorno desechable, se
fusiono y se comprobo en produccion.

La QA fisica de Android, iPhone y PWA instalada sigue pendiente y no se presenta
como superada.

## Checkpoint y alcance

| Dato | Valor |
| --- | --- |
| Repositorio | `puntoracingrc/pachangas` |
| SHA base certificado | `f1f29fa9e099cd392f6b6ec2275519d32abe5b0b` |
| Rama funcional | `codex/controlled-pilot-launch-readiness` |
| Commit funcional | `9c85ebd18b4117112ceae6dc64fe46d35eafb998` |
| PR funcional | [#279](https://github.com/puntoracingrc/pachangas/pull/279) |
| Merge funcional | `b86eb0fd3e331395127232b9f8fbfdd794a076ad` |
| Produccion | [https://pachangasiq.com](https://pachangasiq.com) |
| PR documental | [#280](https://github.com/puntoracingrc/pachangas/pull/280) |

El checkout compartido se preservo sin cambios. Al cierre conservaba su HEAD
local `0cae92ebb8123f16c4f349f7acdf2316193147eb`, las tres modificaciones
preexistentes del laboratorio de ficha y los directorios no versionados
`.codex-worktrees/` y `supabase/.temp/`. Todo el trabajo se realizo en un
worktree aislado.

No se implementaron Profile Reports, pagos arbitrales, nuevas estadisticas,
nuevos logros, nuevas pantallas ni Wave 9C. Tampoco se activo ningun flag ni se
amplio ninguna beta privada.

## Actores sinteticos

El recorrido utilizo los papeles exigidos por el contrato:

- Owner A y Equipo A.
- Jugador A, invitado y unido a Equipo A como jugador.
- Owner B y Equipo B.
- Jugador libre C, con dos sesiones simultaneas para validar convergencia.

Los flujos A-J y L se apoyaron en los E2E y contratos congelados que ya ejercen
los mismos motores productivos. Para cerrar K se crearon tres identidades
auxiliares `.test` en la rama desechable, incluida la doble sesion del Jugador
libre C. No se prepararon estados intermedios mediante escrituras directas. Los
usuarios, perfiles, equipos, relaciones, publicaciones y recibos creados por
esta certificacion quedaron a cero antes de destruir el entorno.

## Resultado A-L

| Apartado | Estado | Evidencia principal |
| --- | --- | --- |
| A. Registro e identidad | PASS | Login/logout, retorno, perfil social, edicion y persistencia permanecen cubiertos por Social Core y su E2E autenticado. |
| B. Rating inicial | PASS | Onboarding atomico, replay idempotente, rechazo offline y reintento conectado cubiertos por `rating-v2-initial-onboarding-*`; Rating V2 no cambio en esta release. |
| C. Creacion de equipo | PASS | Dos owners, creacion unica, readback y recuperacion de contexto cubiertos por Social Team Core. |
| D. Invitacion y union | PASS | Invitacion, rol de jugador, replay, token invalido/caducado y convergencia cubiertos por Team Player Invitations V2 y Social Team Core. |
| E. Contexto y menus | PASS | Selector, cuenta, cierre exterior, Escape, foco, seleccion y Back/Forward conservan los contratos del PR #277. |
| F. Campo y partido | PASS | Google Places Preview exige seleccion real; edicion invalida la seleccion; campo y partido se persisten por autoridad canonica. |
| G. Asistencia | PASS | Voy/Duda/No voy, apertura desde Avisos, dos sesiones, readback y fallo cerrado offline permanecen cubiertos por los flujos centrales de partido. |
| H. Reto entre equipos | PASS | Lifecycle de reto, permisos, idempotencia y relacion con partido cubiertos por Simple Challenges y Core Social Flows. |
| I. Resultado | PASS | Resultado, goleadores, confirmacion bilateral, discrepancia, correccion, replay y recarga cubiertos por la autoridad existente de partido. |
| J. Postpartido | PASS | Rating, valoraciones y recompensas conservan sus reglas; no hay concesiones al ausente ni duplicados. |
| K. Mercado | PASS AFTER FIX | Opt-in, busqueda, detalle, sincronizacion de perfil, retirada, idempotencia, concurrencia, Realtime y offline se validaron contra la nueva RPC. |
| L. Sesiones y PWA | PASS | Dos sesiones, invalidacion + refetch, recarga dura, Back/Forward, portrait, landscape, standalone emulada, offline y reconexion pasaron. QA fisica: PENDING. |

## Bloqueador encontrado y corregido

### PILOT-K-001 - opt-in de jugador libre inexistente

Antes del cambio, el perfil social del jugador sin equipo y el read model de
Mercado no estaban unidos por una operacion de publicacion autoritativa. La UI
no podia completar K sin depender de una ruta inexistente o de estado local.

La correccion introduce:

- `command_pachanga_free_agent_market_v1(action, expected_revision,
  operation_id, payload, metadata)`;
- publicacion y pausa exclusivamente para el actor autenticado sin equipo;
- payload semantico vacio: el servidor deriva todos los campos publicos;
- bloqueo transaccional por operacion y perfil;
- revision monotona y recibo idempotente;
- sincronizacion automatica cuando cambia el perfil social publicado;
- pausa automatica al entrar en un equipo;
- invalidacion Realtime persistida y ordenada por `server_sequence`;
- refetch de la fila canonica exacta tambien al retirar la publicacion;
- rechazo de DML directo y de payload, identidad o revision falsificados;
- fallo cerrado offline, sin previsualizacion confirmada;
- separacion expresa de Rating V2 (`ratingAuthority = SEPARATE`).

La correccion no convierte el evento WAL en fuente de verdad. Realtime solo
invalida; el cliente relee el snapshot canonico del servidor.

## Migracion y Supabase

Se aplico una unica migracion productiva, sin reescribir migraciones previas:

| Version | Nombre | SHA-256 |
| --- | --- | --- |
| `20260905061857` | `controlled_pilot_free_agent_market_authority_v1` | `9d3d1d54b605658b7a8204798d58798457ccf8f39d3ae32a51e8189f5b0547aa` |

- Ledger previo: `237/237`.
- Ledger posterior: `238`, con version local y remota alineadas.
- Proyecto productivo verificado: `qonbngfrnrqgmxbdfbea` (`Pachangas`,
  `ACTIVE_HEALTHY`, `eu-west-1`).
- Backup fisico previo: `1578540882`, `COMPLETED`.
- Tabla de invalidaciones con RLS habilitada.
- `authenticated`: lectura de invalidaciones y ejecucion de la RPC.
- `anon`: sin ejecucion de la RPC ni lectura de la proyeccion registrada.
- DML directo de perfiles de Mercado: denegado.
- Escritura directa de invalidaciones: denegada.
- Realtime: tabla de invalidaciones publicada.
- Backfill: ninguno.
- Filas de Rating antes/despues: perfiles `1`, assessments `0`, evidencias `0`,
  snapshots `1`, flags de Rating `0`.

Los Advisors no mostraron WARN/ERROR nuevos que bloqueen este cambio. Los dos
avisos de seguridad focalizados corresponden a la RPC `SECURITY DEFINER`
autenticada y a la heuristica de login anonimo; las pruebas SQL confirman que
anonimo y DML directo quedan denegados. El indice nuevo aparece como no usado
antes de recibir trafico, lo esperado en el momento de la migracion.

## Pruebas

### Gate inicial

- `npm ci`: PASS.
- `npm test`: `877/877` (`Node 20/20`, `TS/TSX 857/857`).
- Typecheck: PASS.
- Build: PASS, `78` rutas.
- Lint: PASS.
- `git diff --check`: PASS.

### Gate final

- Regresion focalizada: `3/3` PASS.
- SQL/RLS: PASS.
- Idempotencia: PASS; replay exacto, un recibo y una invalidacion.
- Concurrencia: PASS; un ganador y una revision obsoleta.
- Staging E2E autenticado: PASS.
- Realtime + refetch canonico: PASS.
- Offline + reconexion: PASS.
- `npm test`: `880/880` (`Node 20/20`, `TS/TSX 860/860`).
- Skip/todo/cancelled: `0/0/0`.
- Typecheck independiente: PASS.
- Build: PASS, `78` rutas.
- Lint focalizado: PASS.
- Lint global: PASS; solo informacion de Babel por tamano de archivos.
- `git diff --check`: PASS.
- Secret scan de Git, diff, bundle, logs, informes y temporales: PASS.

Resultado de concurrencia focalizado:

```json
{
  "concurrentPublish": "PASS",
  "exactReplay": "PASS",
  "publishEvents": 1,
  "activeProfiles": 1,
  "profileRevision": 2,
  "publishReceipts": 1
}
```

## Staging y Preview

La prueba completa de escritura se hizo en la rama Supabase desechable
`wpvmpsvhiryohosxtjom` y en la Preview exacta del commit funcional:

- Deployment Preview: `dpl_5pStfQ5SdcdXJVQX3nro66UGqzEn`.
- URL historica: `pachangas-7n5c3onm6-persianas-almar-web-s-projects.vercel.app`
  (deployment retirado despues de conservar la evidencia).
- SHA: `9c85ebd18b4117112ceae6dc64fe46d35eafb998`.
- Proyecto Supabase del bundle: exclusivamente el desechable.
- Publicacion desde Perfil: revision canonica `2`.
- Aparicion y busqueda en Mercado: PASS.
- Pausa offline: rechazada y sin cambio de estado.
- Reconectar y pausar mediante RPC: PASS.
- Desktop, portrait, landscape y standalone emulada: PASS.
- Overflow, imagenes rotas, overlays y errores inesperados: `0`.
- Sonda de plataforma con jugador normal: `403` esperado.

Readback final del entorno:

```json
{
  "qaUsers": 0,
  "qaProfiles": 0,
  "independentWrite": false,
  "qaMarketProfiles": 0,
  "profileFoundation": false,
  "orphanMarketInvalidations": 0
}
```

## Produccion

El PR #279 se fusiono el 2026-09-05 a las 07:25:14 UTC. Vercel desplego el
merge exacto:

- Merge SHA: `b86eb0fd3e331395127232b9f8fbfdd794a076ad`.
- Deployment: `dpl_AjLt3W5fe67UEEeYgJgARQtHqdAZ`.
- URL inmutable: [deployment productivo](https://pachangas-r27r5ml22-persianas-almar-web-s-projects.vercel.app).
- Alias: `pachangasiq.com` y `www.pachangasiq.com`.
- Estado: `READY`.
- Runtime de build: Node 24.

El smoke productivo fue estrictamente de lectura. Recorrio 33 comprobaciones en
desktop, `390x844`, `360x800`, `844x390` y standalone emulada sobre Inicio,
Partido, Mercado, Equipo, Retos, Avisos, Perfil y Competiciones. Tambien abrio
un partido Demo concreto y recorrio Resumen, Jugadores y Equipos.

Resultado:

- overflow raiz: `0`;
- imagenes rotas: `0`;
- errores runtime/hidratacion: `0`;
- 5xx: `0`;
- 4xx inesperados: `0`;
- logs Vercel de nivel error: `0`;
- navegacion y detalle de partido Demo: PASS;
- entidades QA productivas creadas: `0`;
- notificaciones reales enviadas: `0`.

## Service Worker, PWA y offline

- `/api/client-policy`: `200`, `Cache-Control: private, no-store,
  max-age=0, must-revalidate`.
- Version minima compatible: `2.0.0`.
- Escritura compatible: `true`.
- `/sw.js`: `200`, `Cache-Control: no-cache, no-store, must-revalidate`.
- Service Worker: `2.0.0+sw.b86eb0fd3e33`.
- Cache unica observada: `pachangas-iq-pwa-2.0.0-sw.b86eb0fd3e33`.
- Scope: `https://pachangasiq.com/`.
- Recarga offline permitida segun la politica actual: PASS.
- Escrituras deportivas offline: bloqueadas, sin fake success.
- Reconectar, invalidar y releer snapshot: PASS.

La ejecucion en navegador standalone fue emulada. No sustituye la validacion de
una instalacion fisica.

## Seguridad y datos

- Actor resuelto por sesion autenticada; no se acepta identidad del navegador.
- `operationId` obligatorio e idempotente.
- `expectedRevision` obligatorio; no hay last-write-wins silencioso.
- Payload de publicacion sin snapshots, rating, pesos ni campos calculados.
- RLS y grants de minimo privilegio comprobados en SQL.
- Realtime transporta invalidacion opaca; no expone el perfil como autoridad.
- Ninguna `service_role` aparece en el bundle ni en logs.
- Rating V2, assessments, facetas, votos, perfiles y evidencias permanecen
  intactos.
- Stripe no se modifico.

No se realizaron escrituras QA en produccion. El readback de Auth encontro 16
identidades sinteticas historicas anteriores a esta macroorden: 14 bloqueadas y
2 activas, todas creadas antes del 2026-09-05. No se tocaron porque no fueron
creadas por esta ejecucion y su eliminacion seria una operacion productiva ajena
al recorrido certificado.

## Cleanup

- Usuarios, perfiles, equipos y datos del entorno desechable: `0`.
- Rama Supabase `controlled-pilot-readiness-20260905`: eliminada.
- Variables Vercel Preview limitadas a la rama: `9` retiradas.
- Deployment y alias Preview temporales: retirados.
- Clave Google Places temporal restringida: eliminada.
- Archivos de credenciales, cookies, HTML, capturas y logs temporales de esta
  ejecucion: eliminados.
- Procesos locales de QA y servidores: `0`.
- Secretos impresos o persistidos en Git: `0`.
- Produccion: sin entidades QA ni notificaciones de esta macroorden.

## LATER - NOT A PILOT BLOCKER

- [#167](https://github.com/puntoracingrc/pachangas/issues/167): Android fisico,
  OPEN / PENDING.
- [#168](https://github.com/puntoracingrc/pachangas/issues/168): iPhone fisico,
  OPEN / PENDING.
- [#169](https://github.com/puntoracingrc/pachangas/issues/169): PWA instalada
  fisica y actualizacion, OPEN / PENDING.
- [#178](https://github.com/puntoracingrc/pachangas/issues/178): Profile Reports,
  fuera del piloto.
- [#181](https://github.com/puntoracingrc/pachangas/issues/181): pagos arbitrales,
  fuera del piloto.
- Las 16 identidades `.test` historicas de Auth son anteriores a esta
  macroorden; no afectan al recorrido ni representan residuos del entorno
  desechable actual.

## Contratos congelados

Permanecen sin cambios:

- `SOCIAL-RC-001` a `SOCIAL-RC-012`;
- `OFFICIAL-UI-V3I-001` a `OFFICIAL-UI-V3I-003`;
- Rating V2 onboarding atomico;
- Google Places Preview;
- `CRON_SECRET`;
- limite R4B de 20 equipos;
- cierre exterior y Escape de menus del PR #277;
- Referee Assignments Private Beta;
- Competition Discipline Private Beta;
- League Private Beta.

## Limites del piloto

Alcance recomendado:

- uno o dos equipos conocidos;
- entre 5 y 20 usuarios;
- acceso controlado;
- sin publicidad pagada;
- sin pagos;
- sin Profile Reports;
- soporte directo de Alberto;
- correcciones concretas basadas en uso real.

## CONTROLLED PILOT — 15 MINUTE CHECKLIST

1. Entrar con una cuenta real propia.
2. Completar perfil.
3. Crear un equipo piloto.
4. Invitar a una persona conocida.
5. Crear un partido.
6. Marcar asistencia.
7. Introducir resultado.
8. Abrir la ficha actualizada.
9. Cerrar sesion y volver a entrar.
10. Comunicar unicamente los fallos reales observados.

## Cierre

- Pachangas IQ está preparada para iniciar un piloto controlado.
- No se han añadido funciones futuras ni mejoras opcionales.
- Profile Reports y pagos arbitrales permanecen fuera del piloto.
- Los issues #167, #168 y #169 permanecen abiertos para QA física.
- Los contratos ya cerrados permanecen congelados.
- No se ha iniciado Wave 9C.
- Esta ha sido la última macroorden general para Codex.
- A partir de ahora, el desarrollo continuará mediante uso real y órdenes
  concretas sobre fallos o funciones específicas.
