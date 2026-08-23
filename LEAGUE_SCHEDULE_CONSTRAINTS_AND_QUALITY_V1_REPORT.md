# League Schedule Constraints And Quality V1 Report

## Principio

La legalidad y la calidad son dos capas distintas. Una restriccion dura invalida el calendario; una preferencia blanda solo ayuda a ordenar opciones legales. Ningun score puede compensar un conflicto duro o un partido sin slot.

El servidor reconstruye constraints y preferences desde R4A. El cliente no puede enviar pesos, resultados, conflictos ni un score calculado.

## Restricciones duras

| Codigo | Comprobacion |
| --- | --- |
| `TEAM_UNAVAILABLE` | El slot cruza una indisponibilidad vigente del entry. |
| `TEAM_OVERLAP` | El equipo juega en dos slots solapados. |
| `VENUE_OVERLAP` | El mismo `resource_key` esta ocupado; exclusion GiST y validacion. |
| `INSUFFICIENT_SLOT_DURATION` | Duracion del partido mas margen no cabe en el slot. |
| `EDITION_RANGE` | El inicio/fin sale de la ventana de edicion. |
| `STAGE_RANGE` | El inicio/fin sale de la ventana del stage. |
| `MINIMUM_REST` | No se cumple el descanso minimo entre partidos. |
| `MISSING_VENUE` | La revision de reglas exige sede confirmada. |
| `MISSING_SLOT` | El item no tiene slot asignado. |
| `DUPLICATE_PAIRING` | Una pareja aparece mas veces que las vueltas permitidas. |
| `ROSTER_NOT_READY` | El roster R4A no esta preparado. |
| `ENTRY_NOT_ELIGIBLE` | El entry ya no es elegible/aceptado para la fase. |
| `RULE_REVISION_MISMATCH` | La regla vigente no coincide con la congelada. |
| `SCHEDULE_CAPACITY_DEFICIT` | No existen slots legales suficientes. |
| `ROUND_STRUCTURE_MISMATCH` | Conteos o apariciones por jornada no coinciden. |
| `TEAM_DUPLICATED_IN_ROUND` | Un equipo aparece dos veces en una jornada. |
| `BYE_MISMATCH` | Los descansos no coinciden con N y las vueltas. |
| `HOME_AWAY_IMBALANCE` | Balance local/visitante fuera de politica. |
| `SECOND_LEG_NOT_MIRRORED` | La vuelta 2 no invierte exactamente la vuelta 1. |

La asignacion recorre items y slots en orden canonico. Un slot se considera solo si pasa todos los checks duros excluyendo el propio item en ediciones manuales. Si no existe una asignacion completa, se persiste evidencia de conflicto y la validacion falla cerrada; no se publica una liga parcial.

## Preferencias blandas

Las preferencias activas pueden expresar dia, ventana horaria y zona/sede. Cada fila tiene un peso propio. La regla congelada define los pesos de dimension, por defecto:

| Dimension | Peso |
| --- | ---: |
| Dia | 50 |
| Hora | 40 |
| Venue/area | 0 |
| Home/away streak | 10 |

Para una evaluacion `i`, con peso de fila `w_i`:

```text
possible_i = w_i * (dayWeight + timeWeight + applicableVenueWeight)
satisfied_i = w_i * (
  dayMatches * dayWeight
  + timeMatches * timeWeight
  + venueApplicable * venueMatches * venueWeight
)
preferenceScore = round(100 * sum(satisfied_i) / sum(possible_i), 3)
```

Si no hay peso posible, `preferenceScore = 100`.

Sea `S = max(maximumHomeStreak, maximumAwayStreak)` y `M` el maximo permitido:

```text
homeAwayScore = 100                                  si S <= M
homeAwayScore = max(0, 100 - 20 * (S - M))          si S > M
```

El score final es:

```text
preferenceDimensionWeight = dayWeight + timeWeight + venueWeight
softScore = round(
  (preferenceScore * preferenceDimensionWeight
   + homeAwayScore * homeAwayWeight)
  / (preferenceDimensionWeight + homeAwayWeight),
  3
)
```

Si el denominador es cero, el resultado es 100. Si existe al menos una violacion dura o un item sin slot, el resultado final es 0 sin excepciones.

## Snapshot explicable

Cada revision recibe como maximo un `QualitySnapshot` inmutable con:

- hard violations y unassigned items;
- soft score a tres decimales;
- preferencias satisfechas/total y peso satisfecho/total;
- desglose por entry;
- balance home/away por entry;
- maximas rachas home y away;
- distribucion por dia local;
- pesos de politica y trade-offs;
- checksum SHA-256 del snapshot completo.

Intentar recalcular la misma revision con un checksum diferente devuelve `QUALITY_SNAPSHOT_IMMUTABLE`. Una edicion manual crea otra revision y otro snapshot; no reescribe evidencia.

## Conflict model

Los conflictos viven en `private.pachanga_competition_schedule_conflicts`. Cada uno tiene tipo, severidad, fingerprint SHA-256, detalle privado, resumen publico seguro, revision, secuencia y estado. La unicidad `(schedule_revision_id, fingerprint)` evita multiplicacion por reintentos.

El workbench del organizador recibe detalle suficiente para corregir. Equipo y publico reciben solo campos deportivos necesarios; no reciben constraints privadas, disponibilidad sensible ni motivos internos.

## Validacion completa

`schedule.validate` vuelve a obtener el input checksum y reconstruye todos los conflictos. Requiere:

- revision actual y estado `generated`;
- cero hard violations;
- cero items sin slot;
- parejas, jornadas y descansos exactos;
- entries/rosters/regla todavia validos;
- calidad inmutable generada;
- revision esperada vigente.

El recibo de validacion persiste checksum, conteos, resumen, actor, revision y `server_sequence`. Cualquier cambio R4A posterior impide publicar.

## Escala y query plans

La prueba aislada crea en rollback 95.000 items, 95.000 slots, 5.000 constraints y 10.000 preferences. Resultado final: `19.182 ms` de suite completa. Todos los caminos exigidos quedaron por debajo de 100 ms:

| Camino | Plan principal | Indice | Ejecucion |
| --- | --- | --- | ---: |
| Round read | Index Only Scan | `pachanga_schedule_items_revision_round_idx` | `0,013 ms` |
| Pair lookup | Index Scan | unique revision/pairing/leg | `0,028 ms` |
| Constraints | Bitmap Heap Scan | `pachanga_team_availability_entry_idx` | `0,110 ms` |
| Preferences | Bitmap Heap Scan | `pachanga_team_schedule_preference_entry_idx` | `0,267 ms` |
| Team overlap | Bitmap Heap Scan | `pachanga_schedule_items_revision_round_idx` | `0,082 ms` |
| Slot collision | Index Scan | `pachanga_schedule_slot_resource_overlap_excl` | `0,045 ms` |

Tras la pasada del asesor, las tablas nuevas R4B tienen cero foreign keys sin indice. Los indices aun no usados se conservan porque la rama de staging esta vacia tras el cleanup y sus joins protegen integridad/retirement a volumen.
