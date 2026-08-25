# Competition Discipline V1 Production Release

## Estado

`RELEASE CANDIDATE / HOTFIX REMOTO APLICADO`

Este informe registra el despliegue coordinado de R5 Competition Discipline
V1 y su hotfix forward-only de contabilidad de cumplimiento tras una apelacion.
Los SHA, PR, deployment y smoke visual definitivos se completan al cerrar la
release.

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
| W3-PROD-010 | PRODUCT_BUG | La funcion estatica `private.pachanga_competition_discipline_default_policy_v1()` heredo `EXECUTE` de `PUBLIC`. `anon` y `authenticated` no tienen `USAGE` del esquema privado y la funcion no era alcanzable, pero faltaba el segundo cierre exigido por el contrato. | Pendiente de migracion aditiva que revoque `EXECUTE` a `PUBLIC`, `anon` y `authenticated`, con regresion SQL y readback remoto. | open |

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

## Ledger y migracion

- migracion forward-only:
  `20260825203500_competition_discipline_appeal_service_accounting_v1.sql`;
- ledger local/remoto: `146 / 146`, sin versiones exclusivas de ningun lado;
- backup previo: `3,950,638 bytes`, SHA-256
  `531cd5ca5c3aa4ee3e32c353528ddffcc4d530a4770ea2857d86f8e02b503e69`;
- funciones privadas `security definer`, `search_path=pg_catalog` y ejecucion
  revocada a `public`, `anon` y `authenticated`;
- triggers activos y sin filas disciplinarias sinteticas persistentes.

## Gates del release candidate

| Gate | Resultado |
| --- | --- |
| R5 focal | `14/14 PASS` |
| Bateria completa | `507/507 PASS` |
| SQL/RLS/idempotencia/adversarial | `PASS` |
| Concurrencia | `7/7 PASS` |
| Volumen | `10.000 / 2.000 / 5.000 / 1.000`, rollback `PASS` |
| Demo V2.1 determinista | `11/11 PASS`, snapshot identico |
| Typecheck / build / lint focal | `PASS / PASS / PASS` |
| Lint global | deuda heredada: `22 errores / 18 warnings` |
| `git diff --check` | `PASS` |

## Pendiente de cierre

- fusionar el release candidate a `main`;
- desplegar Demo World V2.1;
- QA productiva y Service Worker;
- readback final y limpieza local.
