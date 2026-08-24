# League Standings Engine V1 Report

## Fuente de verdad

La clasificacion consume exclusivamente la `OfficialResultDecision` activa de
cada partido. Un SportingResult pendiente, confirmado pero no oficial o
disputado no suma puntos.

Los valores `pointsForWin`, `pointsForDraw` y `pointsForLoss` proceden de la
RuleRevision congelada. Para cada Entry:

```text
basePoints = wins * pointsForWin
           + draws * pointsForDraw
           + losses * pointsForLoss

effectivePoints = basePoints + adjustmentPoints
goalDifference = goalsFor - goalsAgainst
```

R4C mantiene `adjustmentPoints = 0`; las decisiones disciplinarias esperan R5.

## Persistencia

- `CompetitionStandingState`: puntero y health de la vista actual.
- `CompetitionStandingSnapshot`: revision fuente, engine version y checksum.
- `CompetitionStandingRow`: posicion y acumulados por Entry.
- `CompetitionTieBreakExplanation`: criterio, candidatos, valores y resolucion.
- `CompetitionStandingsRebuildReceipt`: operacion, duracion y checksums.
- `CompetitionPersistedDrawLot`: seed, algoritmo, candidatos y orden decidido.

El orden canonico del ultimo snapshot usa revision/secuencia e ID estable; nunca
depende solo de `created_at`.

## Desempates

Soportados en el orden declarado por RuleRevision:

- `POINTS`;
- `GOAL_DIFFERENCE`;
- `GOALS_FOR`;
- `WINS`;
- `HEAD_TO_HEAD_POINTS`;
- `HEAD_TO_HEAD_GOAL_DIFFERENCE`;
- `HEAD_TO_HEAD_GOALS_FOR`;
- `PERSISTED_DRAW_LOT`.

Los head-to-head reconstruyen una mini-tabla solo con el grupo empatado. Cada
paso persiste una explicacion. `FAIR_PLAY`, cards y disciplinary points fallan
con `FEATURE_NOT_AVAILABLE_UNTIL_R5`.

Si el empate no se resuelve y no existe sorteo persistido, se devuelve
`TIE_REQUIRES_DECISION`; UUID, slug, fecha y orden de SELECT nunca deciden una
posicion deportiva.

## Rebuild y atomicidad

La oficializacion, supersession, annulment o confirmacion de sorteo reconstruye
standings dentro de la misma transaccion. Si el rebuild falla, la decision
oficial tampoco queda aplicada.

Se implementan:

- incremental rebuild;
- full rebuild de auditoria;
- checksum estable sobre filas ordenadas;
- receipt con duracion;
- invalidacion Realtime de standings y jornada.

En staging ambos modos produjeron exactamente el mismo checksum y las mismas
seis filas.

## Jornada

```text
published -> in_progress -> completed -> locked
```

`round.complete` exige todos los partidos oficiales. `round.lock` exige cero
disputas y standings `CURRENT`. Una correccion oficial posterior se coordina
con el lock por advisory lock de jornada y revision esperada.

## Escala y planes

Escenarios aislados con rollback:

- 20 equipos / 380 fixtures / 380 resultados oficiales;
- 32 equipos / 992 fixtures / 992 resultados oficiales;
- 1.000 rebuilds historicos.

P95 medido:

| Operacion | p95 |
| --- | ---: |
| Match view | 2.674 ms |
| Result desk | 19.033 ms |
| Standings view | 4.494 ms |
| Public standings | 3.722 ms |
| Full rebuild | 19.310 ms |
| Incremental rebuild | 19.554 ms |

Los planes cubren resultados activos, resultados por stage, head-to-head,
squad members, snapshot vigente y round completion. No se anaden indices para
foreign keys fuera de los caminos medidos solo por aparecer como INFO en
Advisors.
