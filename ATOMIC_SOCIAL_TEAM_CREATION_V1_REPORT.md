# Atomic Social Team Creation V1

Fecha: 2026-09-02 (Europe/Madrid)

## Resultado

`command_pachanga_social_team_v1` elimina las dos escrituras antiguas de
creación. La acción `team.create` se ejecuta dentro de una sola transacción y
devuelve un snapshot canónico únicamente cuando todos sus invariantes existen.

## Transacción

La operación crea conjuntamente:

1. un `pachanga_groups` canónico con ID y código generados en servidor;
2. una membresía `owner` del actor;
3. estado social `ACTIVE`;
4. Team Operational State inicial `ACTIVE / CLEAR`;
5. configuración mínima sin publicación en Mercado;
6. escudo base permitido;
7. receipt inmutable, event e invalidación;
8. read model de respuesta con revisión y secuencia confirmadas.

El cliente solo puede enviar nombre, modalidad, zona general, escudo inicial y
objetivo orientativo. No puede elegir ID, owner, código, estado, timestamps,
secuencia, permisos o entitlements.

## Garantías

- Advisory lock por actor y bloqueo transaccional de los agregados afectados.
- `operationId` idempotente y fingerprint del payload.
- Repetición exacta: mismo equipo, owner, revisión y receipt.
- Mismo `operationId` con otro payload: conflicto.
- Error en cualquier paso: cero equipo parcial y cero membresía huérfana.
- El owner del grupo y la membresía owner nacen juntos.
- No crea Club, competición, partido, Venue, Organizer grant, Billing ni
  publicación de Mercado.
- No escribe Rating V2, carta, facetas ni logros.

## Seguridad y compatibilidad

- DML directo de equipos/membresías queda revocado para clientes.
- La creación exige perfil social confirmado y flags V3F activos.
- Las restricciones Wave 8B de membresía se respetan.
- Gestión avanzada y transferencia de owner continúan en sus autoridades
  existentes; V3F no concede esas capacidades a un admin.

## Validación local

- Creación, replay, payload distinto, owner y código: PASS.
- Atomic rollback: PASS.
- Estado operativo y escudo inicial: PASS.
- Usuario/owner/team ID forjados: rechazados.
- PostgreSQL runner: PASS con `ROLLBACK`.

Producción: pendiente del release coordinado V3F.
