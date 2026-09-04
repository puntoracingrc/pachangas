# R4B Interactive Schedule Limit 20 - Production Release

Release cerrado el 4 de septiembre de 2026.

## 1. Resultado

- Clasificacion inicial permitida: `A. REPRODUCED_UNBOUNDED_SYNCHRONOUS_GENERATION`.
- Resultado final: el defecto se corrigio, fusiono, migro y verifico en
  produccion.
- Limite de producto: `interactiveMaximumTeams = 20` por
  `CompetitionSchedulePlan`.
- Capacidad tecnica interna conservada: 2-32 equipos.
- Opcion asincrona para 21-32: `OUT OF SCOPE`.
- Issue: `#173 R4B LARGE SCHEDULE EXECUTION`, cerrado por el merge funcional.

## 2. Reconciliacion del estado de release

La orden original esperaba los seis flags R4B en `OFF`, pero el readback
productivo demostro que una activacion posterior y autorizada de League Private
Beta habia dejado el vector `ON/ON/ON/ON/OFF/ON`. La cronologia, autoridad y
motivo se registraron antes de continuar en
`R4B_LARGE_SCHEDULE_EXECUTION_RELEASE_RECONCILIATION.md`.

No se modifico ningun flag para hacer coincidir produccion con una precondicion
historica ya superada. El release preservo exactamente el vector vigente y no
amplio el acceso publico.

## 3. Git y Pull Request

| Dato | Valor |
| --- | --- |
| Base real | `39ed4af736b1174625de45e69c4aafd41b2d936e` |
| Commit de plan/reconciliacion | `daa46c46c7f3c7fdf68208b2d641b20e45126c1f` |
| Commit funcional | `44964ce315a95ef9d55228aac9cdf71e52e2e61d` |
| PR | `#274 Enforce R4B interactive schedule limit` |
| Estado PR | `MERGED` |
| Merge commit | `a50a53d724782f69060965c1839867f9fe6eeda5` |
| Rutas del diff funcional | 14 |
| Diff | 1790 inserciones, 20 eliminaciones |

Los checks Vercel del PR finalizaron en `SUCCESS` antes del merge.

## 4. Contrato implementado

PostgreSQL define una unica politica canonica mediante
`private.pachanga_league_schedule_interactive_maximum_teams_v1()`.

La preflight reutiliza `private.pachanga_league_schedule_inputs_v1()`, por lo
que el recuento procede de las entradas elegibles actuales del servidor y no
de un valor enviado por el navegador. El comando publico:

1. identifica al actor autenticado;
2. valida permisos antes de revelar capacidad;
3. aplica idempotencia por `operation_id`;
4. bloquea el plan;
5. valida `expected_revision` y estado;
6. calcula el recuento canonico;
7. rechaza 21-32 antes del generador;
8. delega 2-20 en la implementacion certificada existente.

El error canonico es:

- SQLSTATE: `54000`;
- mensaje tecnico: `SCHEDULE_INTERACTIVE_CAPACITY_EXCEEDED`;
- reason code: `INTERACTIVE_TEAM_LIMIT_EXCEEDED`;
- respuesta HTTP de la API: `422`;
- mensaje visible: texto humano, sin exponer el codigo tecnico.

El workbench devuelve `interactiveGeneration` con `allowed`,
`eligibleTeams`, `maximumTeams`, `reasonCode` y `source`. Las acciones de
generar/regenerar desaparecen cuando el recuento supera 20. Un calendario
historico de 21-32 conserva lectura paginada y usa la revision congelada, sin
recalcular su elegibilidad contra plantillas vivas.

## 5. Autoridad y ACL

El motor 2-32, la preflight y las implementaciones anteriores quedaron en el
schema `private`, sin `EXECUTE` para `anon` ni `authenticated`. El readback
productivo final confirmo:

- funciones esperadas: 10/10;
- fugas de ejecucion privada a clientes: 0;
- comando publico: `authenticated=true`, `anon=false`;
- comando de flags: `authenticated=true`, `anon=false` y payload limitado a
  flags conocidos;
- workbench: `authenticated=true`, `anon=false`.

La ruta platform no es una segunda API de generacion y rechaza claves ajenas
al allowlist de flags.

## 6. Migracion productiva

Se aplico exclusivamente:

`20260904184204_r4b_interactive_schedule_capacity_v1.sql`

El repositorio mantiene deliberadamente `[db.migrations].enabled = false` para
el bootstrap firmado. Por eso `db push --dry-run` conecta pero omite el
descubrimiento. Se utilizo la ruta existente documentada para bases ya
creadas: `supabase migration up --linked`.

Readback final:

| Dato | Resultado |
| --- | --- |
| Proyecto | `qonbngfrnrqgmxbdfbea` |
| Ledger | 237 |
| Ultima version | `20260904184204` |
| Ultimo nombre | `r4b_interactive_schedule_capacity_v1` |
| Local/remote | alineados hasta `20260904184204` |
| Maximo interactivo | 20 |
| Planes/revisiones/items/jornadas/BYEs | 0 |
| Slots/validaciones/conflictos/quality | 0 |
| Wizards beta activos | 0 |

No se reescribio ninguna migracion ejecutada, no se realizo backfill, no se
crearon jobs/colas y no se insertaron entidades QA en produccion.

## 7. Flags finales

| Flag | Readback final |
| --- | --- |
| `league_scheduling_foundation_enabled` | `ON` |
| `league_schedule_generation_enabled` | `ON` |
| `league_schedule_editing_enabled` | `ON` |
| `league_schedule_publication_enabled` | `ON` |
| `league_public_calendar_enabled` | `OFF` |
| `league_canonical_fixture_creation_enabled` | `ON` |

League Private Beta permanece:

- beta `ON`;
- creacion privada `ON`;
- descubrimiento publico `OFF`;
- maximo de una edicion activa por organizador;
- cap ordinario 12 y override concedido hasta 20;
- invite-only y dependiente de grant.

## 8. Rendimiento

Harness PostgreSQL aislado, misma bateria para 6, 20, 21 y 32 equipos:

| Caso | Resultado |
| --- | --- |
| 6 equipos, una vuelta | 15 partidos; generacion 94.891 ms; publicacion 457.956 ms |
| 20 equipos, dos vueltas | 380 partidos; warm-up 4680.119 ms |
| 20, tres medidas posteriores | 916.274 / 921.070 / 910.635 ms |
| p95 conservador 20 | 921.070 ms, menor que 15 s |
| 21, comando user | rechazo 41.182 ms |
| 21, rol platform | rechazo 39.290 ms |
| 21, regenerate | rechazo 41.455 ms |
| 32, comando user | rechazo 46.960 ms |
| 32, rol platform | rechazo 43.826 ms |
| Motor interno 32 | 992 partidos |
| Historico 32, lectura | 75.290 ms |

Los rechazos consumen cero revision, items, jornadas, snapshots, eventos y
receipts de exito. La secuencia del servidor no avanza. Las ejecuciones de seis
equipos se repitieron entre baseline, bateria posterior y staging remoto
aislado.

## 9. Concurrencia e idempotencia

- Dos clientes sobre revision 18: un ganador y un `STALE_REVISION`.
- Dos peticiones simultaneas sobre 21: ambas rechazadas y cero escritura.
- Repetir el mismo `operation_id`: mismo resultado, sin aplicacion duplicada.
- Publicacion concurrente: un ganador y un stale, sin fixtures duplicados.
- Cambio de roster 21 a 20: workbench y comando convergen sobre 20.
- Restauracion a 21: `schedule.regenerate` vuelve a rechazarse sin alterar la
  revision generada de 20.
- Desconexion/error RPC: no existe fake success ni cola deportiva offline.

## 10. Validaciones

| Comprobacion | Resultado |
| --- | --- |
| Baseline global | 874/874: Node 20, TS/TSX 854 |
| Final global | 876/876: Node 20, TS/TSX 856 |
| Failed / skipped / todo / cancelled | 0 / 0 / 0 / 0 |
| Scheduling focalizado | 26/26 |
| Fresh bootstrap / upgrade | PASS, schema equivalente y flags nuevos OFF por defecto |
| SQL/RLS | PASS |
| Concurrencia | PASS |
| Escala R4B | PASS, 95 000 items |
| R4A / R4C / R4D / Private Beta | PASS |
| PWA focalizada | 17/17 |
| Typecheck | PASS |
| Build | PASS |
| Lint focalizado | PASS |
| Lint global | PASS; solo nota informativa Babel por fichero grande |
| `git diff --check` | PASS |
| Secret scan | PASS |

El `db lint --level error` del clon fresco encontro siete errores de tipado ya
existentes y no relacionados con esta migracion. Ninguno referencia las
funciones R4B nuevas o modificadas; no se ocultaron como correcciones del
release.

## 11. Staging desechable

No existia un proyecto hosted staging independiente disponible. Se creo una
pila Supabase completamente aislada con puertos y volumen propios, se aplico
el bootstrap fresco de 237 migraciones y se ejecuto el E2E extendido real.

Resultado:

- generacion permitida: PASS;
- rechazo autoritativo: PASS;
- una generacion ganadora y una stale: PASS;
- Realtime como invalidacion y refetch canonico: PASS;
- flags restaurados a su snapshot inicial: PASS;
- drafts/planes/competiciones QA activas: 0 tras cleanup.

La pila y su volumen se destruyeron al terminar. El Synthetic World compartido
de otra tarea no se detuvo ni modifico.

## 12. Advisors y logs

Los Advisors antes y despues de la migracion son identicos:

- seguridad: 654 avisos preexistentes;
- rendimiento: 1108 avisos preexistentes;
- nuevos avisos R4B de rendimiento: 0;
- incremento total: 0.

Las RPC publicas `SECURITY DEFINER` siguen apareciendo en el advisor de
seguridad porque su exposicion a `authenticated` es intencional; validan actor,
capability, revision y scope internamente. No hay ejecucion anonima ni acceso a
las funciones privadas. Referencia de remediacion del advisor:
https://supabase.com/docs/guides/database/database-linter

Los logs PostgreSQL posteriores muestran la aplicacion completa como `LOG` y
cero `ERROR`, `FATAL` o `PANIC`. Vercel no registra errores runtime ni logs de
nivel warning/error/fatal para el deployment en la ventana del smoke.

## 13. Deployment y smoke productivo

| Dato | Valor |
| --- | --- |
| Deployment | `dpl_72AR65fjJCgNscyQHuNpoz86gNrD` |
| Estado | `READY` |
| Target | `production` |
| Metadata SHA | `a50a53d724782f69060965c1839867f9fe6eeda5` |
| URL deployment | `https://pachangas-fh7akhngl-persianas-almar-web-s-projects.vercel.app` |
| Dominio | `https://pachangasiq.com` |

Se comprobo `/laboratorio-league-scheduling?scenario=six` en:

- desktop 1440x900;
- portrait 390x844;
- landscape 844x390, incluido el drawer `Herramientas`.

En los tres casos:

- 0 overflow raiz;
- 0 imagenes rotas;
- 0 overlay de error;
- 0 errores o warnings de consola;
- heading correcto;
- copia `Maximo interactivo 20 - motor tecnico 32` visible en su superficie
  correspondiente.

El carrusel de jornadas en portrait conserva desplazamiento horizontal
intencional dentro de su propio contenedor y no ensancha el documento.

## 14. PWA

- Manifest: HTTP 200, scope `/`, start URL `/`.
- Display: `fullscreen` con fallbacks `standalone`, `minimal-ui`, `browser`.
- Iconos `any`, `maskable` y `monochrome` presentes.
- Service Worker: HTTP 200, `Service-Worker-Allowed: /`.
- Cache del worker: `no-cache, no-store, must-revalidate`.
- Version servida: `2.0.0+sw.a50a53d72478`.

Las issues fisicas siguen correctamente abiertas/pending:

- `#167` Android fisico;
- `#168` iPhone fisico;
- `#169` PWA instalada fisicamente.

No se reinterpretan emulaciones como QA fisica.

## 15. Rollback

No existe rollback destructivo. Ante una regresion posterior:

1. bloquear temporalmente solo la accion afectada mediante la autoridad de
   plataforma;
2. corregir con una migracion nueva forward-only;
3. conservar revisiones, eventos, receipts y calendarios historicos;
4. no reabrir la operacion interactiva 21-32 mediante DML manual;
5. verificar ledger, ACL y flags tras el roll-forward.

## 16. Cierre

El limite de 20 se decide con entradas canonicas, antes del trabajo costoso y
sin una segunda fuente de verdad. El motor 32 sigue disponible solo como
primitiva interna. No se iniciaron R4C, R4D, Wave 9C, jobs asincronos ni las
issues de QA fisica.

`#173`: CLOSED / FIXED / PRODUCTION VERIFIED.
