# League Delegates And Stage Membership V1 Report

Estado: `READY FOR REVIEW`

## Delegados

Un `CompetitionTeamDelegate` pertenece a una entry concreta. No convierte al
usuario en admin global del Team, Club o competicion y no altera
`pachanga_group_members`.

Roles:

- `PRIMARY_DELEGATE`
- `ROSTER_MANAGER`
- `VIEWER`

Estados:

`invited`, `active`, `declined`, `revoked`, `replaced`, `expired`.

El Team owner conserva autoridad prioritaria. Puede invitar incluso a un usuario
externo al Team para esa entry, revocar, transferir el primary delegate y
mantener la trazabilidad de quien fue reemplazado. Un delegado solo puede operar
las acciones de su scope y nunca asumir ownership.

La aceptacion/declinacion se realiza por el usuario invitado. La transferencia
crea la nueva autoridad y marca la anterior como `replaced` dentro de la misma
transaccion. El indice parcial garantiza un solo primary activo.

Si cambia el owner del Team, la resolucion server-side vuelve a consultar el
owner vigente. La migracion de precedencia asegura que `TEAM_OWNER` gana frente
a un scope simultaneo de organizer; no se confia en un rol cacheado por cliente.

## Stage membership

`CompetitionStageMembership` vincula una entry aceptada con un stage existente y,
opcionalmente, una division y un competition group. Conserva revision de reglas,
vigencia, estado, motivo, actor, revision y secuencia.

La reasignacion no sobrescribe silenciosamente: cierra la membresia activa
anterior y crea una nueva fila. El indice parcial impide dos asignaciones activas
para la misma entry. Esto no genera fixture, jornada, partido ni clasificacion.

## Permisos

| Actor | Delegados | Roster | Stage membership |
| --- | --- | --- | --- |
| Team owner | Invitar, revocar y transferir | Gestionar | Leer |
| Primary delegate | Scope delegado | Gestionar si procede | Leer |
| Roster manager | Sin transferir primary | Gestionar | Leer |
| Viewer | Leer | Leer | Leer |
| Organizer autorizado | Revisar segun capability | Revisar | Asignar/reasignar |
| Miembro ordinario | Sin escritura | Sin escritura | Sin escritura |

Todas las decisiones se resuelven en PostgreSQL mediante actor autenticado,
entry, ownership vigente, capability y revision. Las escrituras directas estan
revocadas.

## Concurrencia y Realtime

- `operationId` repetido devuelve el mismo receipt.
- `expectedRevision` obsoleto falla con `PT409`.
- Transferencias simultaneas no crean dos primary delegates.
- Reasignaciones simultaneas no crean dos memberships activas.
- Realtime publica una invalidacion visible solo para el actor autorizado.
- El cliente descarta su cache y solicita el snapshot canonico.

## Evidencia

| Gate | Resultado |
| --- | --- |
| Delegate invitation/accept/decline/revoke | PASS |
| Primary transfer | PASS |
| External delegate scope | PASS |
| Owner precedence | PASS |
| Stage assign/reassign | PASS |
| 9 escenarios concurrentes | Todos convergen |
| Scale delegates | 20.000 |
| Scale stage memberships | 30.000 |
| Delegate p95 | `0,097 ms` |
| Stage membership p95 | `0,070 ms` |
| Staging final | 0 delegates y 0 memberships activas |

Produccion no fue modificada y no se realizo merge.
