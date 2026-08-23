# League Round Robin Engine V1 Report

## Contrato

`league-round-robin-v1` es un motor determinista para stages `LEAGUE_STAGE`, `GROUP_STAGE` y `SPLIT` de competiciones `LEAGUE`. Acepta entre 2 y 32 entries, una seed no vacia de hasta 160 caracteres y `legs` igual a 1 o 2. Cualquier otro tipo o capacidad falla con `FEATURE_NOT_AVAILABLE` o un error de dominio especifico.

El motor TypeScript es una referencia pura y testeable. PostgreSQL reconstruye los inputs autoritativos y persiste la salida; el navegador nunca envia cruces ni orden de equipos.

## Formulas

Sea `N` el numero de equipos reales, `L` las vueltas y `N' = N` si N es par o `N + 1` si es impar:

| Resultado | Formula |
| --- | --- |
| Jornadas por vuelta | `N' - 1` |
| Jornadas totales | `(N' - 1) * L` |
| Partidos por vuelta | `N * (N - 1) / 2` |
| Partidos totales | `N * (N - 1) / 2 * L` |
| Partidos por jornada | `floor(N / 2)` |
| Descansos por jornada | `N mod 2` |
| Descansos por equipo | `L` si N es impar; `0` si es par |
| Balance home/away | diferencia maxima `1` con L=1 y `0` con L=2 |

Ejemplos contractuales:

| Equipos | Vueltas | Jornadas | Partidos | Descansos |
| ---: | ---: | ---: | ---: | ---: |
| 5 | 1 | 5 | 10 | 5 |
| 6 | 1 | 5 | 15 | 0 |
| 6 | 2 | 10 | 30 | 0 |
| 20 | 2 | 38 | 380 | 0 |
| 32 | 2 | 62 | 992 | 0 |

## Orden y reproducibilidad

1. Se normalizan y validan IDs unicos.
2. Cada entry se ordena por FNV-1a de `seed:entryId`, con el ID como desempate estable.
3. Si N es impar se anade un marcador BYE interno, nunca persistido como equipo.
4. Se usa el circle method: el primer indice queda fijo y el ultimo rota a la posicion 1.
5. La orientacion inicial alterna el primer cruce por jornada y el resto por indice de pareja.
6. Para N impar se invierten cruces concretos hasta dejar el balance dentro del limite.
7. La segunda vuelta copia cada jornada e invierte home/away exactamente.
8. La firma es FNV-1a de engine, seed y estructura completa de jornadas.

Mismos inputs congelados, misma seed y misma version producen el mismo orden, cruces, descansos, orientacion y firma. Cambiar seed puede cambiar el orden, pero no las invariantes matematicas.

## Validacion estructural

La validacion comprueba:

- conteo exacto de partidos y jornadas;
- una sola aparicion por equipo y jornada, contando BYE;
- una aparicion de cada pareja por vuelta;
- cero parejas duplicadas;
- un descanso por equipo y vuelta cuando N es impar;
- cero descansos cuando N es par;
- balance local/visitante;
- espejo exacto de la segunda vuelta;
- IDs pertenecientes al snapshot congelado.

El validador devuelve `fixtureCount`, `expectedFixtures`, `roundCount`, `byeCount`, `byesPerEntry`, `duplicatePairings`, `balanceMaximum` y `mirrorValid`.

## Persistencia y revisionado

La seed, engine, orden de entries y checksums se almacenan en `ScheduleRevision`. Una regeneracion crea una revision `regenerated` que apunta a `supersedes_revision_id`; la revision anterior queda `superseded`. Move, swap, home/away swap y round rename crean del mismo modo revisiones inmutables con un diff reconstruible.

El `input_checksum` combina reglas, entries, rosters preparados, slots, constraints y preferences en orden canonico. Si cualquier input R4A cambia antes de validar/publicar, el servidor devuelve `STALE_INPUT`; no intenta conciliar silenciosamente.

## Evidencia

| Gate | Resultado |
| --- | --- |
| Capacidades 2-32 | PASS para una y dos vueltas |
| 32 equipos / 2 vueltas | 62 jornadas y 992 partidos |
| 5 equipos | 5 jornadas, 10 partidos, 5 descansos, 0 rivales ficticios |
| 6 equipos | 5 jornadas y 15 partidos |
| Reproducibilidad | PASS con misma seed; seed alternativa conserva invariantes |
| IDs duplicados/vacios | Fail closed |
| Capacidad fuera de rango | Fail closed |
| Segunda vuelta | Espejo exacto PASS |
| Home/away | Limites PASS en toda la matriz |
| Focal engine/contract | `23/23` PASS |

## Rendimiento final local

| Equipos | Vueltas | Partidos | Generacion SQL | Workbench |
| ---: | ---: | ---: | ---: | ---: |
| 6 | 1 | 15 | `84,061 ms` | `40,114 ms` |
| 20 | 2 | 380 | `4.794,329 ms` | `71,434 ms` |
| 32 | 2 | 992 | `31.150,127 ms` | `97,033 ms` |

La prueba usa `statement_timeout = 180000 ms` y bases temporales eliminadas al terminar. No mide latencia de red ni supone activacion productiva.
