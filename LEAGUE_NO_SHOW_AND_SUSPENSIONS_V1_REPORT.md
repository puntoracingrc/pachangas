# League No-show and Suspensions V1 Report

## Retraso y periodo de cortesia

`LateArrivalIncident` registra responsable, hora programada, reporte, llegada,
grace deadline, evidencia privada, RuleRevision, revision y secuencia.

Estados: `reported`, `arrived_within_policy`, `arrived_late`,
`escalated_to_no_show` y `dismissed`.

El margen procede de RuleRevision y de la hora del servidor. Un cambio normal
de asistencia de `voy` a `no voy` no crea un no-show.

## Incomparecencia

`CompetitionNoShowIncident` exige partido valido, obligacion vigente, grace
deadline vencido, evidencia, actor autorizado y RuleRevision. Sus estados son
`reported`, `under_review`, `confirmed`, `rejected` y `resolved`.

Una confirmacion puede crear una decision oficial `NO_SHOW` o `FORFEIT` solo
cuando la policy define outcome y marcador. El cliente no puede enviar el
resultado calculado. La decision oficial, standings, jornada, receipt e
invalidaciones se confirman atomicamente.

No-show no crea tarjetas, sanciones, multas, restricciones sociales ni casos de
Conduct. Una denuncia rechazada no crea resultado oficial.

## Suspension, reanudacion y repeticion

`MatchSuspension` conserva minuto, marcador parcial, motivo, evidencia,
RuleRevision, actores, revision y secuencia. Un resultado parcial nunca entra
automaticamente en standings.

Estados implementados: `reported`, `confirmed`, `resume_scheduled`, `resumed`,
`replay_ordered`, `administrative_resolution`, `abandoned` y `cancelled`.

La reanudacion conserva minuto y marcador inicial. La repeticion aplica la
politica elegida por el producto: mismo encuentro deportivo, mismo
`CanonicalMatch`, nueva revision del contexto operativo. No se duplica el
partido.

## Evidencia

Staging autentico cubrio:

- llegada dentro del margen sin no-show;
- grace vencido, no-show confirmado y resultado oficial por RuleRevision;
- no-show rechazado sin nuevo resultado;
- suspension en minuto 37 con marcador 1-0;
- reanudacion del mismo CanonicalMatch;
- repeticion del mismo CanonicalMatch;
- resolucion administrativa con marcador parcial preservado;
- standings incremental igual al full rebuild;
- arrival vs no-show, dos confirmaciones y resume vs replay: un ganador y un
  `STALE_REVISION`.

Escala: 5.000 late arrivals, 2.000 no-shows y 2.000 suspensiones con rollback.
Confirmar no-show midio 21.986 ms y resolver suspension 4.752 ms.

## Round state y lectura publica

Una jornada no completa mientras exista `postponed`, `suspended`,
`result_pending` o `administrative_review`. Un partido cancelado necesita una
decision que determine si no computa o si genera resultado oficial.

El publico solo ve `Aplazado`, `Suspendido`, `Cancelado` o `Pendiente de
decision`, junto al resultado efectivo cuando exista. Evidencia y actores
permanecen privados.

## Resultado

`PASS / PENDIENTE DE RELEASE PRODUCTIVA INACTIVA`
