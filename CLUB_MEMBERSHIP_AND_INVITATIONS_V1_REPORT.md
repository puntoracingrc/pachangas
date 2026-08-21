# Club Membership and Invitations V1 Report

Estado: `STAGING PASS / PREVIEW PENDING`

## Modelo de membership

`pachanga_club_memberships` vincula Club y usuario sin convertir a ese usuario
en platform admin ni admin de los equipos vinculados. Registra role, status,
vigencia, expiracion opcional, revision, secuencia, invitador, aceptacion y
revocacion.

Estados: `invited`, `active`, `declined`, `revoked`, `expired`.

Roles activos:

| Rol | Capacidades R2 |
| --- | --- |
| `club_owner` | read, profile, staff, team links, competition, ownership |
| `club_admin` | read, profile, staff no-owner y team links |
| `club_competition_manager` | read, `competition_create`, `competition_manage` |
| `club_viewer` | read |

`club_venue_manager`, `club_referee_manager` y `club_finance_manager` estan
reservados en schema, pero cualquier intento de activarlos falla
`FEATURE_NOT_AVAILABLE`.

## Ownership

El creador se convierte en `primary_owner_id` y membership `club_owner` dentro
de la misma transaccion. Puede haber varios owners, pero exactamente uno es el
primary owner.

`club.primary_owner.transfer` exige revision vigente, actor con
`ownership_manage` y destino que ya sea owner activo. Registra owner anterior,
nuevo owner, actor, reason, operationId, revision, serverSequence y hora del
servidor. Puede conservar o revocar al owner anterior en la misma transaccion.

Triggers y command impiden eliminar o revocar al ultimo owner y que el primary
owner salga antes de transferir. Las carreras de dos transferencias producen un
ganador y un `STALE_REVISION`; el replay de la ganadora conserva un solo efecto.

## Invitaciones

Se soportan:

- `registered_user`: identidad objetivo resuelta por UUID existente;
- `email_target`: solo acepta una cuenta cuyo email verificado coincide.

El token se genera con 32 bytes aleatorios en PostgreSQL, se devuelve una unica
vez y solo se persiste su SHA-256. Los eventos, read models, notificaciones y
logs no contienen token plano ni email objetivo. Una migracion de hardening
forward-only envuelve la RPC para que ninguna accion salvo `membership.invite`
pueda devolver `oneTimeToken`, `invitationId` o `tokenReturnedOnce`. La
expiracion predeterminada es siete dias y no puede superar treinta dias.

Para email se conserva temporalmente el valor normalizado y su hash en tabla
privada. `retention_until` se fija a expiracion + 90 dias; una funcion de purga
elimina el contacto cuando vence la retencion y conserva la invitacion y el
historial minimo auditable.

## Aceptacion y replay

Aceptar valida en una transaccion:

1. token y hash;
2. estado pendiente;
3. expiracion;
4. usuario o email verificado objetivo;
5. rol permitido;
6. unicidad de membership actual;
7. receipt/event e invalidacion.

La invitacion pasa a `accepted` y la membership queda `active`. Repetir la misma
operacion devuelve el receipt original y no duplica memberships. Reutilizar el
token con otra operationId, alterarlo, inventarlo, revocarlo, expirarlo o usar
otro email falla cerrado.

## Notificaciones y privacidad

La invitacion a usuario registrado reutiliza `pachanga_user_notifications` con
dedupe key basada en operationId y destinatario. El payload solo incluye Club e
invitation ID, un deep link interno y texto no sensible. Las invitaciones por
email no simulan envio automatico.

Un nuevo miembro no recibe eventos historicos: las notificaciones se materializan
al producirse el evento y no se reconstruyen al aceptar. Realtime entrega una
invalidacion RLS-scoped y el cliente hace refetch del snapshot.

## Seguridad probada localmente

- Tabla directa sin INSERT/UPDATE/DELETE cliente.
- Actor resuelto con `auth.uid()`.
- Staff Club A no lee Club B.
- `club_admin` no invita owners ni transfiere ownership.
- `club_competition_manager` no gestiona staff.
- Ultimo owner y primary owner protegidos.
- Token inventado, alterado, expirado, revocado, reutilizado y de otro email
  rechazados.
- Dos aceptaciones concurrentes: un ganador, un stale/conflict y una membership.
- Replay de create/invite/accept/transfer: un efecto canonico.

Durante el primer E2E staging se detecto que la respuesta inicial de
`membership.accept` repetia el token presentado por el propio cliente, aunque
el receipt y el replay ya lo omitian. Se registro y corrigio mediante una
migracion adicional sin alterar las tres migraciones aplicadas. La regresion
exige que primera respuesta y replay de accept sean identicas y no contengan el
token.

El E2E autenticado de staging cubrio invitacion a usuario registrado y por
email, aceptacion, expiracion, revocacion, token inventado/alterado/reutilizado,
replay y carreras concurrentes. Primera respuesta y replay de accept omiten el
token; la membresia se materializa una sola vez. La limpieza final dejo `0`
invitaciones pendientes y `0` staff fixture activo no requerido.
