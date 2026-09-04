# R4B Large Schedule Execution - Decision Plan

Fecha del readback y reproduccion: 2026-09-04T14:08:04Z.

## 1. SHA base real

- Repositorio: `puntoracingrc/pachangas`.
- Rama aislada: `codex/r4b-interactive-schedule-limit-20`.
- Worktree: `/Users/macbookpro14/.codex/worktrees/pachangas-r4b-interactive-schedule-limit-20`.
- Base auditada: `origin/main` en `39ed4af736b1174625de45e69c4aafd41b2d936e`.
- La base coincide con el SHA esperado por la orden.
- El checkout compartido estaba sucio antes de crear este worktree y no se ha modificado.

## 2. Issue #173

- GitHub issue `#173`, `R4B LARGE SCHEDULE EXECUTION`, permanece `OPEN`.
- El issue documenta que la generacion interactiva puede ejecutar planes de hasta 32 equipos de forma sincrona.
- No tiene comentarios ni evidencia de cierre en el readback realizado.

## 3. Decision Option A

La decision de producto solicitada es limitar `schedule.generate` y
`schedule.regenerate` interactivos a un maximo de 20 equipos elegibles por
`CompetitionSchedulePlan`. El motor determinista inferior conservaria su rango
tecnico de 2 a 32 equipos.

## 4. Motivo de producto

La generacion interactiva debe responder de forma acotada y comprensible. Un
plan de 20 equipos produce 380 partidos a dos vueltas y sigue dentro del gate de
15 segundos; uno de 32 produce 992 partidos y tarda mas de 30 segundos en el
harness actual. El timeout no es un mecanismo de capacidad ni una respuesta de
producto adecuada.

## 5. Alcance por plan, grupo y division

El limite se aplicaria al numero canonico de entradas elegibles del plan, no al
total de equipos de toda la competicion. Una competicion de 32 equipos en dos
grupos de 16 sigue siendo interactiva porque cada grupo tiene su propio plan.
Un unico plan de 21 a 32 equipos no podria generarse ni regenerarse por la ruta
interactiva.

## 6. Opcion B fuera de alcance

No se implementaran jobs, colas, workers, polling, progreso, cancelacion ni
reinicio asincrono para 21 a 32 equipos. Esa capacidad queda expresamente fuera
de alcance y reservada para una fase futura.

## 7. Fuentes revisadas

- Orden de trabajo y contrato de cierre de `#173`.
- Issue GitHub `#173` y PR historico `#172`.
- `COMPETITION_ENGINE_CONTRACT_V1.md`.
- Informes R4B de foundation, motor, constraints, canonical fixtures y release.
- Informe productivo `LEAGUE_PRIVATE_BETA_V1_PRODUCTION_RELEASE.md`.
- Informes dependientes R4C, R4D, disciplina, torneos y venue binding.
- Las cuatro migraciones R4B de `20260823224156` a `20260823224236`.
- `app/league-scheduling-contract.ts`.
- `app/_components/league-scheduling-client.tsx`.
- `app/api/competitions/scheduling/**`.
- Tests R4B Node, TS, SQL, concurrencia, escala y rendimiento.
- Ledger, flags, funciones y conteos del proyecto Supabase productivo `Pachangas`
  mediante consultas estrictamente de lectura.

`app/competition-server.ts`, citado como posible fuente por la orden, no existe
en el `main` auditado.

## 8. Call graph actual

Ruta de escritura interactiva:

1. `LeagueSchedulingClient.submitAction`.
2. `POST /api/competitions/scheduling/command`.
3. `scheduleSession`, validacion del payload y `scheduleWriteGate`.
4. RPC publica `public.command_pachanga_league_scheduling_v1`.
5. Bloqueos y validacion de actor, permisos, `expectedRevision` e idempotencia.
6. `private.pachanga_league_schedule_inputs_v1` reconstruye entradas y slots
   canonicos.
7. `private.pachanga_league_schedule_generate_revision_v1` genera y persiste la
   revision, jornadas, descansos, items, conflictos y calidad.
8. La RPC publica persiste evento, invalidacion y receipt, y devuelve el
   snapshot confirmado.

Ruta de lectura:

1. `GET /api/competitions/scheduling/workbench/[planId]`.
2. `public.get_pachanga_league_schedule_workbench_v1`.
3. Read model canonico consumido por `LeagueSchedulingClient`.

## 9. Funciones SQL finales

El escaneo de las 236 migraciones localizo una unica definicion activa de cada
funcion R4B relevante; no hay un `CREATE OR REPLACE` posterior:

- `private.pachanga_league_schedule_inputs_v1`, migracion `20260823224218`,
  linea 222. Conserva el limite tecnico inferior de 32.
- `private.pachanga_league_schedule_generate_revision_v1`, misma migracion,
  linea 1315.
- `public.command_pachanga_league_scheduling_v1`, misma migracion, linea 2103.
- `public.get_pachanga_league_schedule_workbench_v1`, migracion
  `20260823224235`, linea 203.
- `public.command_pachanga_league_scheduling_platform_v1`, misma migracion,
  linea 629.

Hashes MD5 leidos en produccion, sin alterar funciones:

- generator privado: `406ccaeb83a5f6cd3a0b92f97894a6ce`.
- inputs privados: `a12008f30eeedaf9090f959ef7cf135a`.
- command publico: `dfa959ad52b3b4975dc7ff7655ca1fc7`.
- workbench publico: `8369219117097648fcde9627dfdbb184`.
- command de plataforma: `c42905b68f19baf246f77f19fcd70a57`.

## 10. Endpoints

- Escritura: `POST /api/competitions/scheduling/command`.
- Workbench por plan: `GET /api/competitions/scheduling/workbench/[planId]`.
- Workbench por competicion:
  `GET /api/competitions/scheduling/workbench/competition/[competitionId]`.
- Lecturas relacionadas: round, team y public calendar bajo
  `/api/competitions/scheduling/`.

No existe endpoint ni proceso asincrono de generacion.

## 11. Read model

El workbench actual devuelve plan, revision, slots, jornadas, items, descansos,
conflictos, calidad y `nextValidActions`. Expone `engine.capacity = 32`, pero no
incluye `interactiveGeneration`, ni distingue la capacidad del motor de la
capacidad del flujo interactivo.

El contrato previsto, si se desbloquea la release, es:

```json
{
  "interactiveGeneration": {
    "allowed": false,
    "eligibleTeams": 21,
    "maximumTeams": 20,
    "reasonCode": "INTERACTIVE_TEAM_LIMIT_EXCEEDED"
  }
}
```

## 12. Estado de UI

La UI actual obtiene acciones desde `nextValidActions`, pero ofrece generar o
regenerar mientras el lifecycle lo permita. No representa un limite interactivo
de 20 y muestra el mensaje SQL recibido cuando falla el comando. No existe un
mensaje de producto claro para un plan de 21 a 32 equipos.

## 13. Flags productivos

El estado esperado por esta tarea era que los seis flags R4B estuvieran `OFF`.
El readback real encontro:

| Flag | Valor productivo |
| --- | --- |
| foundation | `ON` |
| generation | `ON` |
| editing | `ON` |
| publication | `ON` |
| public calendar | `OFF` |
| canonical fixture creation | `ON` |

No se ha ejecutado DML directo ni se ha cambiado ningun flag.

## 14. Ledger

- Ledger productivo: 236 migraciones.
- Ultima version: `20260903211715`.
- Coincide con el repositorio auditado.
- No se ha creado la hipotetica migracion 237 porque el gate de release esta
  bloqueado antes de SQL.

## 15. Datos R4B productivos

Readback agregado, sin publicar IDs ni nombres:

- planes: 0;
- revisiones: 0;
- slots: 0;
- jornadas: 0;
- descansos: 0;
- items: 0;
- validaciones, conflictos y calidad: 0;
- contextos `competition_generated`: 0;
- jobs o colas R4B: 0;
- canonical backfill: `NOT_INITIALIZED`.

Existe evidencia canonica de la activacion de flags, no de generaciones de
calendario.

## 16. Calendarios existentes con mas de 20 equipos

Produccion contiene cero planes o revisiones R4B y, por tanto, cero calendarios
con mas de 20 equipos. El diseño previsto seguiria tratando cualquier revision
historica ya generada como legible e inmutable; el limite solo afectaria a
nuevos comandos interactivos de generar y regenerar.

## 17. Reproduccion actual

La reproduccion se ejecuto desde la RPC publica real en bases PostgreSQL
temporales, restauradas desde el baseline y las 236 migraciones. Los flags se
activaron solo dentro de esas bases desechables. Resultado:

- 6 equipos / 1 vuelta: 15 partidos, generacion correcta.
- 20 equipos / 2 vueltas: 380 partidos, generacion correcta.
- 21 equipos / 2 vueltas: 420 partidos; entra en el generador sincrono.
- 32 equipos / 2 vueltas: 992 partidos; entra en el generador sincrono.

Esto reproduce el defecto tecnico de `#173`. Las bases temporales se eliminan
al terminar cada escenario.

## 18. Benchmarks historicos

Mediciones documentadas sobre PostgreSQL 17.6 y `statement_timeout = 180s`:

| Evidencia | 6 / 1 | 20 / 2 | 32 / 2 |
| --- | ---: | ---: | ---: |
| Informe original | 84.061 ms | 4.794 s | 31.150 s |
| Revalidacion de release | 232.485 ms | 7.175 s | 42.560 s |

## 19. Benchmark actual

Entorno: MacBook Apple M1 Pro, 16 GiB, macOS 15.7.7, Docker, servidor
PostgreSQL 17.6, cliente `psql` 18.4, Node 24.16.0 y npm 11.13.0.

| Escenario | Medidas de generacion |
| --- | --- |
| 6 / 1 | 135.281 ms, 238.876 ms, 95.667 ms |
| 20 / 2 warmup | 4,880.119 ms |
| 20 / 2 medidas | 4,710.823 ms, 4,704.384 ms, 4,706.430 ms |
| 21 / 2 | 6,244.406 ms |
| 32 / 2 | 31,754.618 ms |

Para las tres medidas validas de 20, maximo y p95 por nearest-rank son
4,710.823 ms. Ninguna supera 15 segundos y no hubo timeout.

Un intento inicial sobre una imagen PostgreSQL desnuda carecia de `auth.jwt()`;
se descarto como `ENVIRONMENT_ISSUE` y se repitio sobre infraestructura Supabase
local compatible. No produjo ninguna escritura remota.

## 20. Clasificacion provisional

`C. BLOCKED_BY_RELEASE_STATE_OR_DATA_DIVERGENCE`.

Aunque el defecto de generacion sincrona ilimitada queda reproducido, el estado
productivo contradice un precondicion explicita de esta orden. Cinco de los seis
flags R4B estan activos mediante autoridad canonica. La activacion no es un DML
accidental: el evento `league_scheduling_flags.set`, con revision de settings 21
y secuencia de servidor 2614, registra como motivo
`League Private Beta V1 production phase 5` el 2026-08-25T11:38:45Z. El informe
de release confirma `R4B ACTIVE / PRIVATE BETA`.

Desactivar esos flags violaria una release posterior activa; dejarlos activos
violaria el estado final obligatorio de esta tarea. Por el contrato de `#173`,
no existe una cuarta clasificacion ni se puede resolver silenciosamente.

## 21. Punto exacto de enforcement

Si el bloqueo de release se resuelve, la proteccion debe entrar en
`public.command_pachanga_league_scheduling_v1` despues de autenticar, validar
permisos, bloquear el plan, comprobar `expectedRevision` y reconstruir los
inputs canonicos, pero antes de llamar a
`private.pachanga_league_schedule_generate_revision_v1` y antes de cualquier
revision, jornada, item, evento o receipt de exito.

`private.pachanga_league_schedule_inputs_v1` y el motor determinista no deben
reducir su limite tecnico de 32.

## 22. Error canonico

- Reason code: `INTERACTIVE_TEAM_LIMIT_EXCEEDED`.
- HTTP previsto: 422.
- Debe incluir el recuento canonico y el maximo, sin aceptar un recuento enviado
  por el cliente.
- Un replay identico debe producir el mismo rechazo sin efectos.

## 23. Representacion UI

El workbench debe ser la unica fuente del recuento y del maximo. La UI debe:

- retirar `schedule.generate` o `schedule.regenerate` de las acciones cuando
  `allowed` sea falso;
- explicar en lenguaje de producto que la generacion interactiva admite hasta
  20 equipos por grupo o plan;
- indicar el numero elegible actual;
- no mostrar SQLSTATE ni el reason code tecnico al usuario;
- mantener visibles las lecturas de calendarios historicos.

## 24. Timeout

Se conserva `statement_timeout = 180s` en el harness historico para comparar
mediciones. No se aumentara ni se usara como sustituto del limite. Una prueba de
timeout debe demostrar rollback completo.

## 25. Cancelacion

No se anade cancelacion porque no se crea un job asincrono. Si el navegador se
desconecta, el cliente no puede mostrar exito sin la respuesta canonica; debe
releer el workbench. Esta politica no convierte el cierre de la conexion en una
cancelacion SQL.

## 26. Idempotencia

Se mantiene `operationId` y el receipt canonico existente. El rechazo por
capacidad debe ocurrir sin receipt de exito y una repeticion no puede crear
estado. Un `operationId` reutilizado con payload distinto sigue siendo invalido.

## 27. Concurrencia

Se conservan bloqueos de plan y `expectedRevision`. Las pruebas previstas
incluyen dos generaciones simultaneas de 20 equipos con un ganador y un stale,
dos rechazos simultaneos de 21 equipos sin efectos, y generate frente a cambios
de entradas o revision. No se admite last-write-wins.

## 28. Compatibilidad historica

La migracion prevista seria aditiva y no reescribiria planes, revisiones ni
items. Las lecturas de un calendario publicado con mas de 20 equipos seguirian
usando su snapshot congelado. El limite se evaluaria solo al emitir una nueva
intencion interactiva.

## 29. Migracion prevista

Solo si se resuelve el bloqueo se crearia una migracion forward-only, generada
por Supabase CLI, que:

1. defina una unica constante SQL autoritativa `interactiveMaximumTeams = 20`;
2. reemplace de forma compatible el command publico para preflight;
3. amplie el workbench con `interactiveGeneration`;
4. preserve grants, RLS y firmas existentes;
5. no edite ninguna de las 236 migraciones aplicadas.

La migracion no se ha creado en este estado bloqueado.

## 30. Archivos previstos

Si la release se reconcilia, el cambio minimo previsto seria:

- una nueva migracion en `supabase/migrations/`;
- `app/_components/league-scheduling-client.tsx`;
- posiblemente estilos focalizados del mismo componente;
- contrato TypeScript de scheduling si necesita tipado del read model;
- tests R4B SQL, TS/TSX, rendimiento y concurrencia;
- informe final de decision/release.

No se modificaria el motor round-robin.

## 31. Tests

Cobertura prevista tras desbloqueo:

- 2, 6 y 20 permitidos desde la RPC publica;
- 21 y 32 rechazados antes del generador en menos de 1 segundo;
- cero estado parcial, eventos o receipts de exito;
- conteo canonico por scope;
- idempotencia y stale revision;
- concurrencia;
- timeout y desconexion sin fake success;
- workbench y UI con mensaje humano;
- lectura historica mayor de 20;
- motor directo de 32 conserva 992 partidos y checksum;
- tests globales, typecheck, build, lint focalizado/global y
  `git diff --check`.

## 32. Staging

La orden pide fresh bootstrap, upgrade exacto y branch Supabase desechable. El
fresh bootstrap local previo al fix ha sido reproducido. No se ha creado ni
modificado staging porque la lectura productiva activa la clasificacion C y
prohibe continuar hacia produccion hasta reconciliar el release state.

## 33. Produccion

No se aplicara una migracion, no se cambiaran flags y no se desplegara frontend
mientras coexistan estas dos condiciones incompatibles:

- la tarea exige seis flags R4B `OFF` al finalizar;
- la release Private Beta posterior exige y mantiene cinco flags R4B `ON`.

Produccion permanece sin cambios.

## 34. Rollback

No hay nada que revertir en produccion. Para una futura migracion desbloqueada,
el rollback preferido seria roll-forward: retirar la accion interactiva desde
la UI o feature authority y reemplazar las funciones mediante una nueva
migracion versionada. Nunca se reescribiria el ledger ni se reabriria una ruta
sin limite mediante DML manual.

## 35. Criterio para cerrar #173

`#173` solo puede cerrarse cuando una decision explicita reconcilie el estado
de la Private Beta con el requisito de flags, y despues se demuestre:

- enforcement PostgreSQL antes del generador;
- read model y UI coherentes;
- 20 equipos bajo 15 segundos en tres medidas tras warmup;
- 21 y 32 rechazados bajo 1 segundo y sin estado parcial;
- motor inferior de 32 intacto;
- fresh bootstrap, upgrade, staging y produccion verificados;
- deployment del SHA exacto y smoke final;
- flags finales acordes con el estado de producto autorizado.

Hasta entonces la clasificacion final es
`BLOCKED_BY_RELEASE_STATE_OR_DATA_DIVERGENCE` y el issue debe permanecer abierto.
