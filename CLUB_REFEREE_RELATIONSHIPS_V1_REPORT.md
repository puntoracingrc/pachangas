# Club Referee Relationships V1 Report

Estado: `READY FOR REVIEW`

## Modelo

`pachanga_club_referee_relationships` vincula un `RefereeProfile` universal con
un Club sin convertir al arbitro en staff del Club, admin de plataforma, owner
de Team ni jugador de ningun grupo.

Tipos: `REGULAR`, `COLLABORATOR`, `PREFERRED`.

Origen: Club invita (`CLUB`) o arbitro solicita (`REFEREE`).

Estados: invitada/solicitada, activa, rechazada, cancelada, finalizada o
expirada. El read model conserva revision, secuencia, vigencia, actor creador y
visibilidad independiente para el perfil del arbitro y el perfil del Club.

Un arbitro puede mantener relaciones activas con varios Clubs. Un Club no
obtiene exclusividad implicita.

## Invitaciones

Se soportan dos destinos:

- usuario registrado: la identidad objetivo se resuelve en servidor y puede
  aceptar sin token externo;
- email: exige email verificado coincidente y un token de un solo uso.

El token usa aleatoriedad criptografica, solo se devuelve en la respuesta
inicial autorizada y se persiste exclusivamente como SHA-256 en tabla privada.
No aparece en events, receipts, notificaciones, Realtime ni read models. Token
alterado, expirado, revocado, reutilizado o presentado por otra identidad falla
cerrado.

R3 no simula envio automatico de email. Devuelve el enlace de un solo uso para
el canal externo que se implemente despues.

## Permisos Club

El rol R2 reservado `club_referee_manager` queda activado solo para este
dominio. Puede leer el contexto arbitral del Club, invitar/gestionar relaciones
y proponer asignaciones cuando la autoridad del partido lo permite. No puede:

- editar identidad o ownership del Club;
- gestionar staff general;
- administrar Teams vinculados;
- modificar Rating, resultados, disciplina, rewards, billing o ranking;
- ver datos privados de otro Club.

Owner y admin de Club conservan la autoridad superior prevista por R2. Las
pruebas adversariales separan Club A y Club B y rechazan cualquier acceso
cruzado.

## Operaciones

- `relationship.invite`;
- `relationship.request`;
- `relationship.accept` / `relationship.reject`;
- `relationship.cancel`;
- `relationship.end`;
- `relationship.visibility.set`.

Cada operacion requiere `operationId`, revision esperada y actor autenticado.
Las carreras de dos respuestas o dos invitaciones equivalentes producen un
estado canonico unico. El replay no duplica la relacion ni su peso estadistico.

Las notificaciones de usuario registrado usan destinatario y dedupe canonicos.
Realtime publica invalidacion RLS-scoped; ambos clientes refetchan la relacion.

## Privacidad publica

Una relacion solo aparece en el perfil del arbitro cuando esta activa y
`show_on_referee_profile=true`; el perfil del Club exige ademas su propia marca
de visibilidad. No se publican UUID de Auth, email objetivo, token, notas
privadas, motivo de finalizacion ni historial de invitaciones.

## QA

Se probaron Club invita, email invita, solicitud del arbitro, accept/reject,
cancel/end, visibilidad, expiracion, token alterado/reutilizado, multi-Club,
RBAC `club_referee_manager`, idempotencia, concurrencia y Realtime. La carga de
`20.000` relaciones produjo p95 `66.172 ms` para el lookup representativo.

La limpieza de staging dejo `0` invitaciones pendientes y `0` relaciones
activas fixture. No se modificaron memberships R2 ajenas al recorrido QA.
