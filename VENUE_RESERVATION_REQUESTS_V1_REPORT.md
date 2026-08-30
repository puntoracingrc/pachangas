# Venue Reservation Requests V1 Report

Fecha: 2026-08-30 CEST

## Lifecycle canonico

`DRAFT -> SUBMITTED -> UNDER_REVIEW -> COUNTER_PROPOSED | HELD | REJECTED |
WITHDRAWN -> ACCEPTED -> PENDING_CONFIRMATION -> CONFIRMED -> CANCELLED |
CONSUMED`.

Un hold es temporal y no equivale a reserva confirmada. La expiracion es una
operacion de servidor idempotente. La aceptacion convierte el claim en reserva
canonica; repetir la misma `operationId` devuelve el mismo receipt, IDs y
revision sin emitir una segunda notificacion.

## Autoridad y privacidad

El cliente envia objetivo, accion, payload semantico allowlisted,
`operationId`, `expectedRevision` y metadatos no autoritativos. PostgreSQL
resuelve actor, Team/Club, disponibilidad, tarifa permitida, reloj, secuencia y
snapshot completo.

El requester solo ve terminos e informacion operativa autorizada. La ubicacion
exacta se libera tras confirmacion segun consentimiento; contactos, notas e
instrucciones no entran en cache publica ni en eventos Realtime.

## Producto

- Team: `/reservas` y `/reservas/[reservation]`.
- Club booking desk: `/clubes/gestionar/reservas`.
- APIs: `Cache-Control: no-store`, same-origin, sesion autenticada, gate PWA y
  sin `service_role` en el cliente.
- Offline: lectura cacheada; cero cola y cero fake success para escrituras.

## Migraciones

| Version | Nombre | SHA-256 |
| --- | --- | --- |
| `20260830145051` | `venue_reservation_requests_holds_v1` | `9e4bce7145ca3f71c246f4be8a23cc4e50e77a791d348901444f1f3add99e018` |
| `20260830145054` | `venue_command_receipts_events_v1` | `68c7fb07f57a78bd828405f8acda1539a77e7582f42977b6d1ae6c73ca5ccdfb` |
| `20260830145056` | `venue_read_models_control_center_v1` | `8465fe3fe4be003fb49c565017d1479c6ce90adb2636fbfaf269310b3014caf6` |

## Concurrencia e idempotencia

Doce carreras reales pasaron con un unico ganador canonico, 12 resultados
stale/conflict explicitos y cero doble reserva. Incluyen ultimo slot, dos
accepts, accept/reject, hold/hold, expiry/accept, counter/withdraw,
cancel/binding y edicion de disponibilidad.

El corpus aislado uso 100.000 requests y 50.000 reservas:

| Camino | p50 | p95 |
| --- | ---: | ---: |
| request submit | 3.665 ms | 8.405 ms |
| hold | 61.366 ms | 119.891 ms |
| accept | 60.660 ms | 63.657 ms |
| reservation desk | 12.445 ms | 28.500 ms |

Rollback y cleanup: PASS. Notificaciones reales: 0.
