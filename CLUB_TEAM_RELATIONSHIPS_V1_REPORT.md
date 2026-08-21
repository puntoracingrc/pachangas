# Club-Team Relationships V1 Report

Estado: `READY FOR REVIEW`

## Separacion de autoridades

`pachanga_club_team_relationships` describe una relacion organizativa entre un
Club y un `pachanga_group`. No convierte el Club en Team, no transfiere owners,
admins ni jugadores y no concede acceso a Rating, partidos, datos privados,
inscripciones o rewards.

Tipos descriptivos: `MEMBER`, `AFFILIATED`, `HOSTED`.

Estados: `invited`, `requested`, `active`, `rejected`, `cancelled`, `ended`.
Las filas terminadas se conservan; un nuevo intento crea una nueva relacion
trazable y no recicla una rechazada.

## Flujos autoritativos

### Club invita a Team

1. `club_owner` o `club_admin` crea una invitacion.
2. Solo el owner actual del Team puede aceptar o rechazar.
3. Al aceptar se registra `started_at` y la relacion pasa a `active`.

### Team solicita Club

1. Solo el owner actual del Team crea la solicitud.
2. `club_owner` o `club_admin` puede aceptar o rechazar.
3. Al aceptar se conserva el iniciador TEAM y comienza la relacion.

El owner del Team o el Club autorizado pueden cancelar una operacion pendiente
y terminar una activa. Se conservan `started_at`, `ended_at`, `ended_by`, reason,
revision, secuencia, actor, receipt y evento.

## Owner transfer y multi-Club

La autoridad Team se resuelve contra el owner actual en cada comando. Si cambia
el owner, la relacion permanece; el owner anterior pierde capacidad y el nuevo
puede responder o finalizar. Un team admin ordinario no acepta ni administra el
vinculo.

No existe `primary_club` ni exclusividad: un Team puede mantener relaciones
activas con varios Clubs. La integridad solo impide duplicar una relacion actual
equivalente entre el mismo Club y Team.

## Perfil publico y privacidad enlazada

`show_on_club_profile` nace `false`. Solo el owner del Team puede cambiar el
consentimiento y desactivar su aparicion. El read model publico incluye
exclusivamente equipos activos y consentidos.

Un owner de Team vinculado sin acceso al Club ve identidad basica del Club y la
relacion de su propio Team; memberships, invitaciones, entitlements,
competitions y estados privados permanecen vacios o nulos. No obtiene datos de
otros equipos vinculados.

## Notificaciones y Realtime

Se reutiliza el centro productivo para invitacion Club-Team, solicitud
Team-Club, aceptacion, rechazo y fin. Dedupe keys ligan operationId y audiencia.
No se envian emails, tokens ni motivos privados.

Las invalidaciones llegan al staff autorizado del Club y al owner actual del
Team afectado. Cada cliente invalida y hace refetch del read model; no aplica el
payload de Realtime como estado.

## Evidencia local

- Invitacion, solicitud, aceptacion, rechazo, cancelacion y finalizacion: PASS.
- Owner-only response y Team admin denegado: PASS.
- Fin por ambos lados e historial preservado: PASS.
- Owner transfer Team cambia autoridad sin romper la relacion: PASS.
- Multi-Club: PASS.
- Privacidad del Team owner vinculado: PASS.
- Dos respuestas concurrentes: un ganador y un stale/conflict: PASS.
- Tabla directa protegida y RLS por actor: PASS.
- Lookup de relacion a escala p95: `0.023 ms` con 5.000 relaciones.

El E2E de staging con dos clientes autenticados confirmo audiencia de
notificaciones, privacidad, invalidacion Realtime seguida de refetch y
convergencia. Tambien ejercito invitacion, solicitud, rechazo, cancelacion,
finalizacion por ambos lados, owner transfer y multi-Club. La limpieza final
dejo `0` relaciones actuales y conserva unicamente historia archivada de QA.
