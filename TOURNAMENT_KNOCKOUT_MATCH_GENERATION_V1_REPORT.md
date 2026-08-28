# Tournament Knockout Match Generation V1

## Responsabilidad

R6C decide quién juega. R4B conserva autoridad sobre cuándo y dónde. R6C solo
materializa un partido cuando el nodo tiene dos participantes resueltos, una
reserva vigente, RuleRevision exacta y cero conflictos.

Resultado atómico:

```text
1 BracketFixtureReservation
  -> 1 CanonicalMatch
  -> 1 CompetitionMatchContext
  -> vínculo inmutable en el node
```

No se genera un partido para un bye ni para un nodo con fuentes pendientes.

## Reserva futura

`bracket.reserve_slot` acepta únicamente:

- `nodeId`;
- fecha/hora y timezone;
- sede;
- duración;
- intención de slot;
- `operationId` y revisión esperada en el envelope.

Puede reservarse antes de conocer los equipos. La reserva se versiona y el
cliente muestra solo la respuesta canónica confirmada.

## Generación

`bracket.node.generate_match`:

1. bloquea bracket, node, reserva y revisión;
2. valida flags, grant, RuleRevision, participantes y conflictos;
3. reutiliza la autoridad R4B de slot/sede/horario;
4. crea exactamente un `CanonicalMatch` y un contexto;
5. enlaza el node mediante revisión monotónica;
6. persiste receipt/evento e invalida read models;
7. devuelve snapshot confirmado.

Un replay con el mismo `operationId` devuelve los mismos identificadores y
receipt. Publicaciones concurrentes producen un ganador y un conflicto stale.

## Integraciones reutilizadas

- R4C: resultado deportivo y decisión oficial.
- R4D: aplazamiento, sede, retraso, no-show, suspensión y reanudación.
- R5: tarjetas, sanciones y elegibilidad según RuleRevision.
- Referee Assignments: propuesta, aceptación, confirmación y reemplazo.
- Realtime: invalida por entidad y después relee el snapshot; el WAL nunca es
  autoridad.

Una corrección anterior al inicio no reescribe el match previo: lo retira,
preserva lineage y crea replacement. Si el descendiente ya empezó, se rechaza
con `DOWNSTREAM_MATCH_ALREADY_STARTED` y exige decisión administrativa.

## Seguridad

- API `no-store`, misma procedencia y sesión autenticada.
- Sin `service_role` en bundle o navegador.
- Sin cola offline deportiva.
- PWA bloquea `generate_match`, resultado, avance, corrección y completion
  offline; no presenta optimistic state como confirmado.
- Direct table writes: 0.

## Idempotencia y concurrencia

Probados: dos activaciones, dos reservas, dos generaciones, dos avances,
resultado contra corrección, avance contra invalidación, avance contra R4D,
corrección de cuarto contra generación de semifinal, dos completions,
completion contra corrección final y tercer puesto contra corrección de
semifinal.

Resultado común: `ONE_WINNER_ONE_CONFLICT` y cero duplicados en node matches,
context bindings, advance revisions y completion revisions.

## Escala y rendimiento local

Escala rollback: 20.000 `CanonicalMatch` knockout dentro de una carga con
10.000 brackets, 100.000 nodes, 100.000 slots, 50.000 advances y 10.000
completions.

| Operación | p50 | p95 | muestras |
| --- | ---: | ---: | ---: |
| Activación | 86,15 ms | 104,50 ms | 11 |
| Resolución de node | 56,13 ms | 65,61 ms | 11 |
| Generación de match | 66,46 ms | 85,55 ms | 11 |
| Invalidación downstream | 62,78 ms | 71,42 ms | 11 |

`statement_timeout` de migración/operación: 120 s. La prueba de escala usa un
límite aislado de 240 s y revierte todo.

## Estado remoto

Staging, Supabase producción y canario se consignan en
`TOURNAMENT_KNOCKOUT_V1_PRODUCTION_RELEASE.md` cuando se ejecutan.
