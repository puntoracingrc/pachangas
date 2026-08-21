# Competition Entitlements V1 Report

Estado: `DESIGN IN PROGRESS`

## Trazabilidad

Base auditada: `0ea46f1cfa797a253678b68a3ffb8d7456856c81`.

## Politica R1

- El organizador concreto de R1 es un `TEAM`, implementado por
  `pachanga_groups`.
- El entitlement pertenece al grupo organizador, no al usuario.
- Solo el owner actual del grupo con `competition_create` activo puede crear una
  Competition.
- Un admin ordinario del grupo no puede crearla.
- El cambio de owner conserva el entitlement en el grupo y transfiere la
  autoridad ultima al owner nuevo.
- El owner anterior solo conserva acceso si tiene una asignacion explicita de
  staff.
- Ningun cliente autenticado puede concederse un entitlement.

## Capacidades

| Capacidad | R1 | Uso |
| --- | --- | --- |
| `competition_create` | Activa en staging controlado | Crear una Competition draft |
| `competition_manage` | Implementada | Administrar el agregado existente segun RBAC |
| `competition_staff` | Implementada | Asignar y retirar staff permitido |
| `competition_rules` | Implementada | Crear, validar, publicar y congelar reglas segun estado |
| `competition_referees` | Reservada | Falla cerrado; R3 |
| `competition_discipline` | Reservada | Falla cerrado; R5 |

## Origenes

El modelo admitira `subscription`, `partnership`, `promotion` y
`platform_grant`. R1 solo utilizara `platform_grant` en staging. No se crean
productos, precios, suscripciones ni cambios de billing.

## Expiracion y revocacion

Una concesion expirada o revocada impide crear nuevas competiciones. Una
Competition draft ya existente sigue siendo visible y conserva historia. En R1
se permiten lectura y mantenimiento de borradores existentes segun el rol, pero
se bloquean nueva Competition y publicacion futura sin entitlement activo.

## Matriz RBAC pendiente de verificacion

| Actor | Crear Competition | Leer propia | Administrar propia | Conceder entitlement |
| --- | ---: | ---: | ---: | ---: |
| Visitor | No | No | No | No |
| Usuario normal | No | No | No | No |
| Jugador del equipo | No | No | No | No |
| Admin del equipo | No | Segun staff | Segun staff | No |
| Owner sin entitlement | No | Si, si existe | Draft segun politica | No |
| Owner con entitlement | Si | Si | Si | No |
| Staff de competicion | No | Si | Segun rol | No |
| Platform admin autorizado | No como team owner | Global | Global | Si |
| Platform owner | No como team owner | Global | Global | Si |

La matriz se actualizara con evidencia SQL/RLS, owner transfer, expiry,
revocation, idempotencia y concurrencia antes del cierre.
