# League Roster And Eligibility V1 Report

Estado: `READY FOR REVIEW`

## Plantilla canonica

Cada entry aceptada puede crear una unica `CompetitionRoster`. La plantilla
apunta a categoria y revision de reglas exactas. Su lifecycle es:

`draft -> submitted -> changes_requested -> amended -> submitted -> approved -> locked`

`reopen` y `amend` son acciones explicitas y auditadas. Cada cambio crea una
`RosterRevision` inmutable con numero, checksum determinista, conteo, resumen de
elegibilidad, actor, motivo, secuencia y fecha del servidor. No se modifica una
revision historica.

## Jugadores

`RosterMember` referencia la ficha universal. Guarda solo un snapshot publico
necesario para reconstruir como se presento aquella revision; no duplica ni
convierte la ficha en una segunda autoridad.

Cuando un jugador abandona el Team, el servidor conserva el historial y marca
la elegibilidad vigente como `review_required`. No borra el pasado ni actualiza
Rating. El lock multi-team serializa por jugador/edition/category y considera
todos los estados de roster relevantes: dos clientes concurrentes no pueden
confirmar al mismo jugador en dos equipos incompatibles.

Temporary Players y Match Squad no se implementan en R4A.

## Credenciales y elegibilidad

Estados de credencial:

`unverified`, `pending`, `verified`, `expired`, `rejected`, `revoked`.

La evidencia documental se guarda como referencia opaca en schema `private`.
No sale por RLS, API, Realtime, read model ni logs de producto. El servidor
calcula edad, vigencia, membresia, conflicto multi-team y revision de reglas.

Estados de elegibilidad:

`pending`, `eligible`, `ineligible`, `waived`, `review_required`, `expired`.

Un waiver exige capability del organizador, motivo, vigencia, revision esperada
y audit trail. No modifica la credencial original ni borra el motivo de
ineligibilidad.

## Equipacion y dorsales

- Kits: `HOME`, `AWAY`, `ALTERNATE`.
- Colores validados como hex canonico.
- Patron y asset son referencias acotadas.
- Los dorsales quedan ligados a entry, player y roster revision.
- La unicidad se valida en la revision correspondiente.
- El conflicto de colores queda modelado para validacion futura; R4A no genera
  calendarios ni emparejamientos.

## Disponibilidad

Las restricciones duras (`NO PUEDO JUGAR`) y preferencias blandas
(`PREFERIRIA JUGAR`) se guardan por separado, con vigencia, revision, secuencia
y motivo. R4A no las convierte en fixtures ni promete satisfacer preferencias.

## Read model

El roster devuelve revision actual, historial, miembros paginados, elegibilidad,
credenciales reducidas, kits, dorsales, limites, warnings y siguiente accion.
Los datos privados de evidencia y fechas personales no forman parte del JSON.

## Evidencia

| Gate | Resultado |
| --- | --- |
| Revision inmutable | Trigger y prueba adversarial PASS |
| Lifecycle completo | SQL y staging PASS |
| Credential states | pending/verified/rejected/expired/waived probados |
| Player leaves Team | `review_required`, historia preservada |
| Multi-team | Lock global, un ganador concurrente |
| Scale | 150.000 members y 100.000 credentials |
| Roster read p95 | `0,925 ms` |
| Staging final | 0 rosters efectivos y 0 credenciales activas |
| Rating V2 | Byte-identico / no escrito |

Produccion no fue modificada y no se realizo merge.
