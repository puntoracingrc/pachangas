# Team Player Invitations V2

Fecha: 2026-09-02 (Europe/Madrid)

## Resultado

V3F separa definitivamente tres conceptos: compartir un partido, invitar como
admin e invitar como jugador. La nueva invitación ordinaria solo puede conceder
`role=player` y nunca convierte al destinatario en admin u owner.

## Autoridad

- Metadatos: `public.pachanga_team_player_invitations_v2`.
- Secretos: `private.pachanga_team_player_invitation_secrets_v2`.
- Lookup reducido: `lookup_pachanga_team_player_invitation_v2(token)`.
- Command: `command_pachanga_team_player_invitation_v2(...)`.
- Acciones: `team.invitation.create`, `team.invitation.accept`,
  `team.invitation.decline` y `team.invitation.revoke`.

## Token

- PostgreSQL genera el token.
- V3F soporta `SINGLE_USE`.
- El valor raw se devuelve una sola vez al crearlo y solo vive en memoria de la
  pantalla de compartir.
- Persistencia: hash criptográfico, caducidad, revisión, estado y contador.
- El raw token no entra en localStorage, receipts, events, Realtime, logs,
  notificaciones, read models ni Demo.
- Estados: `ACTIVE`, `USED`, `EXPIRED`, `REVOKED`.

## Aceptación y permisos

- Solo owner/admin con capability puede crear o revocar.
- Un jugador ordinario tiene lectura reducida y no puede invitar.
- Aceptar requiere actor autenticado, token válido, revisión vigente, equipo
  activo, scope de membresía permitido y actor no miembro.
- Team code identifica un equipo, pero nunca se acepta como token.
- Aceptación bloquea invitación/equipo, consume el único uso y crea una sola
  membresía player con receipt/event/invalidación.
- Replay exacto devuelve el resultado anterior; las carreras accept/revoke o
  dos accept tienen un único ganador canónico.

## Legacy

La UI V3F no invoca `join_pachanga_team` ni fabrica enlaces con
`pachanga_groups.invite_token`. Las funciones `join_pachanga_team` y
`join_pachanga_group` pierden ejecución para `authenticated`. La invitación de
admin autoritativa permanece separada y activa.

## Validación local

- Hash, expiración, revocación, aceptación, replay y último uso: PASS.
- Código sin membresía, jugador sin capability y DML directo: PASS.
- Privacidad del roster/read models: PASS.
- PostgreSQL runner: PASS con `ROLLBACK`.

Staging autenticado: PASS para crear, aceptar, replay, rechazar, revocar,
carrera de último uso, notificación `.test`, token raw-once y joins legacy
denegados. Producción: pendiente del release coordinado V3F.
