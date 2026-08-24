# League Canonical Fixture Publication V1 Report

## Contrato de publicacion

`schedule.publish` transforma una revision validada en partidos del registro canonico existente. No crea una autoridad paralela y no reutiliza el payload local del navegador.

Por cada `ScheduleItem` se obtiene exactamente:

```text
1 ScheduleItem
  -> 1 CanonicalMatch
  -> 1 CanonicalMatchBinding(source_kind = competition_generated)
  -> 1 CompetitionMatchContext(source_kind = COMPETITION_GENERATED)
```

El context conserva competition, edition, category, stage, division/group, round, rule revision, home/away entry, slot, horario, timezone, venue y estado inicial `scheduled`. El partido canonico no contiene resultado, asistencia, alineacion ni disciplina.

## Prechecks

Antes de escribir, PostgreSQL exige:

- actor autenticado con capability `schedule_publish`;
- competition type `LEAGUE` y stage soportado;
- plan y revision actuales con revision esperada exacta;
- flags foundation, generation, publication y canonical creation activos;
- plan `validated`, revision `validated` y validation status `VALID`;
- recibo de validacion para el checksum vigente;
- input checksum recalculado sin cambios R4A;
- cero conflictos duros y cero items sin slot;
- todos los slots/entries/rosters/regla todavia validos;
- cero IDs canonicos o contexts aportados por el cliente.

## Atomicidad e idempotencia

La publicacion usa una sola transaccion, lock advisory del plan y `FOR UPDATE`. Inserta o reutiliza por binding canonico, crea el context, enlaza el item, publica rounds/revision/plan, registra evento, invalidacion, notificaciones y recibo. Una excepcion revierte todo.

El `operationId` se combina con actor, accion, agregado y hash de request. Un replay identico devuelve el snapshot confirmado sin crear otra fila. Reusar el mismo ID con otro payload falla. Dos clientes sobre la misma revision producen un ganador y un `STALE_REVISION`; nunca last-write-wins.

La prueba concurrente produjo:

| Carrera | Cliente A/B | Resultado canonico |
| --- | --- | --- |
| Generate | misma revision | 1 winner / 1 stale |
| Publish | misma revision validada | 1 winner / 1 stale |
| Conteo final | 15 items | 15 CanonicalMatches y 15 contexts |

## Inmutabilidad posterior

Tras publicar:

- no se puede regenerar, mover, swapear, renombrar ni volver a publicar;
- items, rounds, revision, plan, context y binding quedan protegidos por guards;
- un intento directo de tabla falla por ACL/RLS;
- una nueva operacion deportiva futura debera actuar sobre `CanonicalMatch`, no reabrir el schedule;
- R4B no implementa aplazamiento ni correccion de fixture publicado; eso queda para una fase posterior explicita.

## Read models

| Read model | Audiencia | Datos |
| --- | --- | --- |
| Workbench | Organizer autorizado | inputs, slots, revision, diff, validation, calidad y conflictos seguros |
| Team calendar | Owner/delegado/miembro con scope R4A | sus fixtures publicados, rival, round, hora, sede y IDs canonicos |
| Public calendar | Anon/auth cuando competition publica y flag ON | calendario minimizado, paginado, sin datos privados |
| Round detail | Actor autorizado o jornada publica | fixtures y descansos de una jornada |
| Control Center | Platform admin | flags, planes, conteos, stale/draft y salud generated separada |

Las respuestas API son `Cache-Control: no-store` en superficies autenticadas/de gestion. Las lecturas canonicas pueden usar cache local derivada; invalidaciones por `server_sequence`, revision y entidad fuerzan refetch solo del read model afectado.

## Notificaciones y Realtime

La publicacion no envia una notificacion por partido y jugador. Agrupa una notificacion por equipo participante con enlace a su calendario. En el escenario de 6 equipos se crearon 6 notificaciones, no 90.

Los eventos Realtime contienen entidad, ID, revision y secuencia; no incluyen constraints privadas. El segundo dispositivo observado recibio la invalidacion y recupero el snapshot canonico. En el branch aislado el primer arranque de replication necesito hasta 60 segundos; una vez inicializado, la convergencia fue correcta.

## Staging autenticado

Historia ejecutada en `iozcjirlfytryzrcmrnq`:

```text
6 teams accepted
-> registration closed
-> rosters ready
-> 21 slots
-> concurrent generate
-> 5 rounds / 15 items
-> quality and conflicts evaluated
-> manual rename revision
-> full validation
-> Realtime invalidation to second session
-> atomic publish
-> 15 CanonicalMatches
-> 15 CompetitionMatchContexts
-> 6 deduplicated notifications
```

Tambien se probaron: outsider forbidden, direct write forbidden, post-publish regenerate forbidden, unauthorized QA archive forbidden, replay idempotente y seleccion canonica por secuencia/revision estable.

## Invariantes

| Subsistema | Cambios R4B durante QA |
| --- | ---: |
| Results | 0 |
| Standings | 0 |
| Attendance/lineups | 0 |
| Cards/sanctions | 0 |
| Rating V2 | 0 |
| Rewards/cosmetics | 0 |
| Conduct | 0 |
| Billing/Stripe | 0 |
| Ranking/Season Score | 0 |
| Legacy canonical backfill | No inicializado |

## Cleanup y estado final

El helper service-only `archive_pachanga_league_schedule_qa_v1` acepta solo slugs `r4b-qa-%`, es idempotente y conserva historia. Retira slots, cancela rounds/revision/plan y retira contexts, bindings y CanonicalMatches generados sin borrar evidencia.

Resultado verificado tras staging:

| Dato | Valor |
| --- | ---: |
| Planes QA totales/archivados | 9 / 9 |
| Planes QA activos | 0 |
| Slots QA activos | 0 |
| Rondas QA actuales activas | 0 |
| Contexts QA activos | 0 |
| Bindings QA activos | 0 |
| Flags R4B activos | 0 de 6 |

Produccion Supabase no se consulto para escribir ni se modifico. No hubo merge, deployment productivo, canonical backfill ni inicio de R4C.
