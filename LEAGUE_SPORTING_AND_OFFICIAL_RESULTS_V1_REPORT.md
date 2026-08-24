# League Sporting and Official Results V1 Report

## Resultado deportivo versionado

`CompetitionSportingResult` mantiene el estado del agregado y apunta a una
cadena append-only de `CompetitionSportingResultRevision`:

```text
INITIAL -> CHANGE -> ACCEPTANCE
```

El marcador previo nunca se reescribe. Cada revision conserva version,
`previous_revision_id`, actor, Entry, motivo, checksum, operacion y secuencia.

Lifecycle:

```text
none -> submitted -> confirmed -> official
                  -> change_proposed -> confirmed
                  -> disputed -> administrative_review -> official
```

## Goleadores

Los goleadores son hijos de la revision deportiva, no una autoridad
`LeagueScorer`. Cada equipo solo puede sustituir sus propios goleadores. El
servidor valida roster member, squad locked, Entry y suma de goles segun la
policy `REQUIRED`, `OPTIONAL` o `DISABLED`. Un desconocido usa un slot explicito
y nunca fabrica PlayerProfile.

Shootout, goleadores rivales y score negativo fallan cerrado.

## Confirmacion y disputa

Acciones bilaterales:

- `sporting_result.submit`;
- `sporting_result.accept`;
- `sporting_result.propose_change`;
- `sporting_result.dispute`.

La respuesta guarda Entry, actor, fecha servidor, revision origen, marcador y
motivo. Una pareja concurrente accept/dispute obtiene un ganador y un
`STALE_REVISION`.

La fecha limite se lee de la RuleRevision. El procesador de expiraciones es
service-only, idempotente y no depende del navegador. Solo autoacepta cuando la
regla declara `AUTO_CONFIRM_AFTER_DEADLINE`.

## Decision oficial

`CompetitionOfficialResultDecision` implementa:

- `MIRROR_SPORTING_RESULT`;
- `CORRECTED_EFFECTIVE_SCORE`;
- `ANNULLED`.

`NO_SHOW`, `FORFEIT`, suspension, disciplina y `POINTS_DEDUCTION` devuelven
`FEATURE_NOT_AVAILABLE`. `pointsAdjustments` debe estar vacio.

Cuando la regla permite auto-official y ambos equipos confirman, la decision
mirror, el cambio del partido y el rebuild de standings ocurren en una sola
transaccion. Una disputa solo la resuelve un result manager/director con reason
code y evidencia privada.

Una correccion oficial crea una nueva decision con
`supersedes_decision_id`; nunca edita la anterior. Annulment mantiene la misma
lineage y reconstruye standings.

## Privacidad y notificaciones

La lectura publica muestra marcador efectivo, estado, jornada y explicacion
publica. No muestra evidencia, notas privadas, actor interno ni deliberacion.

Las notificaciones idempotentes cubren squad enviada/validada/rechazada,
resultado recibido, propuesta, disputa, resultado oficial/corregido y jornada
completada. Se dirigen a owners/delegados y organizador, sin tormenta por cada
rebuild.

## Validacion

- Historia confirmada y auto-official: PASS.
- Propuesta `2-1 -> 2-2` y cadena de tres revisiones: PASS.
- Disputa + resolucion con evidencia privada: PASS.
- Correccion oficial con supersession: PASS.
- Private evidence ausente del snapshot de jugador: PASS.
- Dos submissions, official decisions y officialize/scorer correction:
  `1 winner / 1 stale`.
- 10.000 revisiones y 10.000 decisiones en rollback: PASS.
