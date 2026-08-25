# League Postponements and Rescheduling V1 Report

## Contrato

El calendario original de R4B permanece inmutable. Una excepcion posterior
crea solicitud, respuesta, decision y revision efectiva; nunca reabre un
`SchedulePlan` ni actualiza destructivamente un `ScheduleItem`.

```text
R4B ScheduleItem original
  + CompetitionFixtureChange
  + CompetitionFixtureChangeRevision
  = programacion efectiva actual
```

## Solicitud bilateral

`PostponementRequest` conserva equipo solicitante y receptor, propuesta,
motivo, deadline, RuleRevision, revision y secuencia. Solo owner,
`PRIMARY_DELEGATE` o capability contextual pueden solicitar. Solo el owner o
delegado primario del rival puede responder; el organizador interviene con
capability y policy explicitas.

Estados implementados:

`requested`, `awaiting_response`, `approved`, `denied`, `expired`, `withdrawn`
y `superseded`.

Al aceptar una propuesta valida, request, response, administrative decision,
fixture revision, context revision, notificaciones e invalidaciones se
confirman en una transaccion.

## Deadlines

El servidor deriva horas y policy desde RuleRevision. No existen 24/48/72 h
hardcodeadas. Las tres politicas estan cubiertas en SQL:

- `EXPIRE`: expira;
- `AUTO_DENY`: deniega automaticamente;
- `ESCALATE_TO_ORGANIZER`: conserva la solicitud y la escala.

El procesador es service-only, usa hora de servidor y su replay conserva un
unico receipt.

## Reprogramacion y sede

Tipos normalizados: `RESCHEDULE`, `TIME_CHANGE`, `VENUE_CHANGE`,
`POSTPONEMENT`, `CANCELLATION`, `RESUMPTION` y `REPLAY`.

El servidor valida Edition, Stage, duracion, timezone, descanso, solapamientos
de equipo y recurso, restricciones duras, RuleRevision y expectedRevision. Los
impactos blandos quedan en la revision para auditoria.

La sede puede ser `SAVED`, `LABEL` o `TBD` segun RuleRevision y no depende de
Google Places. La migracion correctiva `20260825021800` normaliza una sede R4B
por etiqueta al reprogramar, manteniendo validacion estricta para un cambio de
sede explicito.

## Evidencia

Staging autentico cubrio:

- solicitud aceptada y validada por organizador;
- rechazo con fecha original vigente;
- deadline vencido;
- cambio de sede;
- original R4B intacto y revision efectiva visible;
- notificaciones acotadas;
- invalidacion Realtime y refetch canonico;
- reschedule vs cancel y venue vs reschedule concurrentes con un ganador y un
  `STALE_REVISION`.

Escala: 10.000 requests y 10.000 fixture changes en base aislada con rollback.
Lecturas: postponement desk 26.684 ms y public fixture status 1.152 ms. Crear,
responder, reprogramar y cambiar sede quedaron entre 10.442 y 42.928 ms.

## Privacidad

El publico ve estado, nueva fecha, cambio de campo y resumen publico. No recibe
evidencia, notas privadas, actor reportante, deliberacion ni documentos. Las
notificaciones no se envian a toda la plantilla.

## Resultado

`PASS / PENDIENTE DE RELEASE PRODUCTIVA INACTIVA`
