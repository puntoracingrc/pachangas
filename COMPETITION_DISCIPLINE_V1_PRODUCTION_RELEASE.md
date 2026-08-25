# Competition Discipline V1 Production Release

## Estado

`LIVE / PRIVATE BETA ACTIVE / PUBLIC DISCIPLINE OFF`

Este informe registra el despliegue coordinado de R5 Competition Discipline
V1, el hotfix forward-only de contabilidad de cumplimiento tras una apelacion
y el cierre de privilegios del helper privado de politica. La beta privada esta
activa; la disciplina publica permanece desactivada.

## Incidencias permanentes

| ID | Clase | Hallazgo | Correccion | Estado |
| --- | --- | --- | --- | --- |
| R5-PROD-001 | SIMULATION_BUG | El fixture transaccional heredado declaraba Competition y Category como publicas y fallaba al ejecutarse con el guard productivo de League Private Beta ya activo. La transaccion aborto antes de crear datos y el readback confirmo cero residuo. | El fixture historico R4C conserva su semantica publica; solo el ensamblado temporal del smoke R5 adapta Competition y Category a la beta privada dentro de la transaccion con rollback. | fixed + regression_verified |
| R5-PROD-002 | SIMULATION_BUG | Las aserciones del catalogo usaban una subconsulta escalar no acotada que solo era determinista en una base vacia; los dos catalogos productivos hacian que devolviera varias filas. La transaccion aborto y no dejo residuo. | Las lecturas se acotan a la Competition sintetica y una regresion exige ambos filtros. | fixed + regression_verified |
| R5-PROD-003 | SIMULATION_BUG | Con Private Beta activa, el fixture no reproducia un bundle beta valido: carecia de capabilities R5, incumplia primero el check estructural y despues su `valid_from` por defecto quedaba posterior al `statement_timestamp` del lote remoto. Todos los intentos abortaron o hicieron rollback y no dejaron residuo. | El bundle rollback-bound conserva 14 capabilities y recibe una ventana temporal explicita que ya esta activa durante la propia transaccion. | fixed + regression_verified |
| R5-PROD-004 | ENVIRONMENT_ISSUE | El primer relanzamiento del runner R4C no tenia `LEAGUE_MATCH_OPERATIONS_DATABASE_URL`; el segundo apunto al puerto local `54322`, que ya no aceptaba conexiones. Ambos terminaron antes de ejecutar SQL. | Relanzamiento sobre la instancia local aislada estable en `55322`; no se cambia configuracion persistente. | fixed + regression_verified |
| R5-PROD-005 | TESTABILITY_GAP | El runner historico R4C bloqueaba cualquier ledger distinto de 131 migraciones y, con las 146 actuales, terminaba antes de ejecutar SQL. | Seleccion por el corte historico exacto de R4C: 127 migraciones previas, cuatro migraciones R4C y exclusion explicita de las posteriores. | fixed + regression_verified |
| R5-PROD-006 | SIMULATION_BUG | La primera adaptacion al guard privado cambio a privada la Competition compartida por el fixture historico R4C y rompio su prueba de standings publicos. | Semantica publica restaurada en R4C; la variante privada se limita al ensamblado transaccional R5 de produccion. | fixed + regression_verified |
| W3-PROD-007 | PRODUCT_BUG | El adaptador HTTP del calendario publico enviaba `page_offset/page_size`, pero la RPC desplegada exige `target_round_from/target_round_limit`; PostgREST rechazaba la firma y la UI mostraba el mensaje tecnico. | El route usa la firma canonica, pagina por jornadas `1..50` y la lectura traduce codigos o errores de infraestructura a copy de producto sin activar el calendario publico. | fixed + regression_verified |
| W3-PROD-008 | TESTABILITY_GAP | La cobertura verificaba la RPC de calendario directamente, pero no el contrato de nombres del adaptador HTTP. | Regresion que acopla firma SQL, argumentos HTTP, limites y sanitizacion del mensaje. | fixed + regression_verified |
| W3-PROD-009 | ENVIRONMENT_ISSUE | Una pestana QA longeva que habia navegado por Preview y dos deployments retuvo un error de evaluacion de modulo y quedo temporalmente sin hidratar. | Una pestana limpia cargo sin error y una recarga controlada recupero la pestana original; consola limpia, Service Worker unico y version final confirmada. | fixed + regression_verified |
| W3-PROD-010 | PRODUCT_BUG | La funcion estatica `private.pachanga_competition_discipline_default_policy_v1()` heredo `EXECUTE` de `PUBLIC`. `anon` y `authenticated` no tienen `USAGE` del esquema privado y la funcion no era alcanzable, pero faltaba el segundo cierre exigido por el contrato. | Migracion aditiva `20260825211825` revoca `EXECUTE` a `PUBLIC`, `anon` y `authenticated`; regresion textual y PostgreSQL temporal exigen el cierre. | fixed + regression_verified |

## Seguridad del smoke

- destino enlazado verificado: proyecto productivo Pachangas;
- `lock_timeout`: `3s`;
- `statement_timeout`: `90s`;
- una unica transaccion con `ROLLBACK` obligatorio;
- cero commits de fixtures, notificaciones o eventos Realtime;
- baseline R5 antes del intento: `0 / 0 / 0 / 0` para eventos, sanciones,
  cumplimiento y apelaciones;
- readback posterior a cada intento y al smoke final: `0 / 0 / 0 / 0`.

Smoke final ejecutado contra PostgreSQL productivo en `10s`:

| Evidencia dentro de la transaccion | Conteo |
| --- | ---: |
| Eventos disciplinarios | `4` |
| Sanciones | `2` |
| Cumplimientos | `4` |
| Apelaciones | `3` |

El escenario valido autoridad beta, RuleRevision, catalogo, acumulacion,
elegibilidad, idempotencia, RLS/direct write, correccion append-only, servicio,
reversion, apelacion y la reduccion posterior a una unidad ya cumplida. El
readback posterior al `ROLLBACK` devuelve de nuevo `0 / 0 / 0 / 0`; las seis
flags R5 privadas siguen `true` y `competition_public_discipline_enabled`
sigue `false`.

## Integracion y deployments

| Hito | Evidencia |
| --- | --- |
| R5 inicial | PR [#191](https://github.com/puntoracingrc/pachangas/pull/191), merge `00dc908be0cb87ed0814becdc7ec06c48ec8102b` |
| Demo V2.1 + hotfix de servicio | PR [#192](https://github.com/puntoracingrc/pachangas/pull/192), merge `f96b49d06d43725abdec8ef4fc6b1a0d9e69be0d` |
| Calendario publico | PR [#193](https://github.com/puntoracingrc/pachangas/pull/193), merge `30a4fef063e99c2757ab7c676c033d05ffb36dda` |
| Cierre ACL R5 | PR [#194](https://github.com/puntoracingrc/pachangas/pull/194), merge `0401a127ebd910ccad799b466ad3327782067b37` |
| Cierre documental | PR [#195](https://github.com/puntoracingrc/pachangas/pull/195), solo cuatro informes Markdown |
| Deployment productivo final de codigo | `dpl_DEugDYDWVWYAnkKehr3syFHmqEnx` |
| Artefacto | `pachangas-l1qw0r10v-persianas-almar-web-s-projects.vercel.app` |
| Dominio | [pachangasiq.com](https://pachangasiq.com) |

## Ledger y migraciones

- migraciones forward-only de cierre:
  `20260825203500_competition_discipline_appeal_service_accounting_v1.sql`;
  `20260825211825_competition_discipline_private_policy_revoke_v1.sql`;
- ledger local/remoto: `147 / 147`, sin versiones exclusivas de ningun lado;
- backup previo: `3,950,638 bytes`, SHA-256
  `531cd5ca5c3aa4ee3e32c353528ddffcc4d530a4770ea2857d86f8e02b503e69`;
- funciones privadas `security definer`, `search_path=pg_catalog` y ejecucion
  revocada a `public`, `anon` y `authenticated`;
- triggers activos y sin filas disciplinarias sinteticas persistentes.

## Gates del release candidate

| Gate | Resultado |
| --- | --- |
| R5 focal | `15/15 PASS` |
| Bateria completa | `508/508 PASS` (`20 Node + 488 TSX`) |
| SQL/RLS/idempotencia/adversarial | `PASS` |
| Concurrencia | `7/7 PASS` |
| Volumen | `10.000 / 2.000 / 5.000 / 1.000`, rollback `PASS` |
| Demo V2.1 determinista | `11/11 PASS`, snapshot identico |
| Typecheck / build / lint focal | `PASS / PASS / PASS` |
| Lint global | deuda heredada: `22 errores / 18 warnings` |
| `git diff --check` | `PASS` |

## Readback productivo final

| Evidencia | Resultado |
| --- | --- |
| Flags R5 privadas | `foundation/events/counters/sanctions/service/appeals = true` |
| Disciplina publica | `false` |
| Revision / server sequence de flags | `9 / 115` |
| Catalogos de reglas historicos | `2` |
| Eventos / counters / ciclos | `0 / 0 / 0` |
| Sanciones / servicio / apelaciones | `0 / 0 / 0` |
| Player states / evidencia privada | `0 / 0` |
| `EXECUTE` helper privado PUBLIC/anon/auth | `false / false / false` |
| `USAGE` esquema privado anon/auth | `false / false` |
| Escrituras deportivas directas de cliente | `0` |
| Triggers R5 | `11 activos / 0 deshabilitados` |

Los dos catalogos pertenecen a competiciones QA privadas ya canceladas y se
conservan como evidencia canonica inmutable. No tienen hechos disciplinarios.

## QA productiva

- Demo disciplina muestra 20 eventos con jugador y minuto en `390x844` y
  `844x390`, sin overflow, imagenes rotas ni errores de consola.
- manifest V2.1: `0eae1613e2d84fdd5f0821cfc2f7ad77b7bc4193a6c50ee3d58c0431ee493a51`.
- Service Worker: `2.0.0+sw.0401a127ebd9`, una registration activa, sin
  worker waiting/installing.
- offline conserva el snapshot confirmado; la reconexion recupera red y no
  crea fake success ni cola deportiva.
- el calendario publico apagado devuelve copy controlada y no filtra la firma
  PostgREST.
- Vercel: cero runtime errors; unico 5xx, el `503` heredado de
  `/api/internal/rankings/refresh` por `CRON_SECRET` pendiente.
- PostgreSQL registra el `REVOKE` sin error; API y Realtime no muestran una
  regresion asociada a R5.

## Resultado

R5 queda fusionado, migrado y desplegado en [pachangasiq.com](https://pachangasiq.com)
como beta privada. Disciplina publica, Referee Assignments, pagos y Tournament
Engine permanecen OFF. Rating V2, Rewards, Conduct, Billing, Ranking y
cosmeticos permanecen intactos.
