# Competition Registration Requests V1 - Implementation Report

## Estado

`RELEASE CANDIDATE / AUTHORITY VERIFIED IN STAGING`

## Contrato

V1 soporta `INVITE_ONLY`, `REQUEST_APPROVAL` y `CLOSED`. `AUTO_ACCEPT_PUBLIC`
permanece deshabilitado. Solo el Team owner actual o un actor con capability
expresa puede solicitar inscripcion; un usuario anonimo, jugador ordinario,
arbitro o actor de otro equipo no puede hacerlo.

Estados canonicos:

`draft`, `submitted`, `under_review`, `accepted`, `rejected`, `waitlisted`,
`withdrawn`, `expired`, `cancelled`.

## Escrituras autoritativas

`command_pachanga_competition_registration_request_v1` valida en servidor:

- actor y autoridad sobre Team;
- Competition/Edition publicadas y modo de registro;
- ventana, modalidad, RuleRevision y revision esperada;
- ausencia de Entry y de opinion activa duplicada;
- capacidad bajo bloqueo;
- rate limit, `operationId` y replay idempotente.

El cliente no envia actor, capacidad calculada, posicion de waitlist, Entry,
resultado de moderacion ni secuencia. Cada respuesta devuelve el snapshot
canonico confirmado.

## Waitlist y capacidad

La posicion de waitlist es explicita, estable, versionada y ordenada por
autoridad del servidor. Un cambio de orden queda auditado. Liberar una plaza no
acepta silenciosamente a nadie.

La capacidad deriva de RuleRevision, Competition/Edition y Entries activas. No
cuenta solicitudes rechazadas, retiradas, expiradas o en espera. La aceptacion
crea o activa CompetitionEntry atomica; si Entry falla, request no queda
aceptada.

## Privacidad

El Team owner puede leer su solicitud; el organizador autorizado puede leer la
cola sanitizada. El directorio, el hub publico y otros equipos no reciben
mensaje privado, nota interna, owner UUID ni identidad reversible. La
moderacion de plataforma utiliza identificadores y motivos separados.

## Concurrencia verificada

| Carrera | Resultado |
| --- | --- |
| Dos solicitudes del mismo Team | un estado canonico, replay sin duplicado |
| Dos Teams por la ultima plaza | un accepted, un stale/conflict |
| Accept vs withdraw | un ganador canonico |
| Accept vs registration close | un ganador canonico |
| Waitlist reorder vs accept | revision obsoleta rechazada |
| Publish vs suspend | un lifecycle vigente |
| Public edit vs approval | fingerprint/revision protegidos |
| Archive vs submit | submit rechazado o archive canonico |

Staging uso ocho usuarios y nueve dispositivos autenticados. Se verificaron
accepted, rejected, waitlisted, withdrawn, ultima plaza, RLS, notificaciones,
Realtime y refetch canonico.

## Notificaciones y PWA

Los eventos idempotentes cubren solicitud recibida, aceptada, rechazada,
waitlist, plaza disponible y retirada. Realtime invalida; no convierte el WAL
en autoridad. Offline puede conservar texto como borrador visual, pero no
solicitar, retirar, aceptar, rechazar ni mostrar fake success.

## Evidencia

- SQL/RLS/RBAC: PASS;
- idempotencia: PASS;
- concurrencia: PASS;
- staging autenticado: PASS;
- escala: 100001 requests, 20000 waitlisted y 10001 Entries dentro del rollback;
- p95 submit: `33.958 ms`;
- p95 accept: `22.664 ms`;
- p95 reorder: `15.784 ms`;
- cleanup staging: PASS.

