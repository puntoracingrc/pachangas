# League Registration V1 Report

Estado: `READY FOR REVIEW`

## Alcance

Este informe cubre Competition Category, ventanas de inscripcion y Competition
Entry de R4A. La autoridad es PostgreSQL y la operacion queda restringida a
competiciones `LEAGUE` con flags apagados por defecto.

## Categoria

Cada categoria pertenece a una edition y enlaza una `rule_revision_id` exacta.
Conserva nombre, slug, modalidad, nivel informativo, edades minima/maxima, fecha
de referencia, policy JSON acotada, visibilidad, estado, revision y secuencia.

Lifecycle:

`draft -> active -> closed -> archived`

No contiene documentos completos, datos privados de jugador ni una copia de las
reglas. Las edades se validan contra la fecha de referencia y la credencial
canonica; no se confia en una edad calculada por el navegador.

## Modos y ventana

El modelo admite:

- `PUBLIC_APPROVAL`
- `INVITE_ONLY`
- `CLOSED`
- `PRIVATE_CODE`
- `AUTO_ACCEPT`

R4A implementa el flujo aprobado y devuelve `REGISTRATION_MODE_NOT_AVAILABLE`
para variantes aun no activadas como producto. Abrir la inscripcion fija inicio,
cierre, modo y revision de reglas. Cerrar puede fallar si quedan pendientes o,
mediante `registration.close_and_expire_pending`, resolverlos de forma explicita.
`registration.notify_closing` es idempotente y no duplica el aviso.

## Entry

Fuentes:

- `PUBLIC_APPLICATION`
- `ORGANIZER_INVITATION`
- `PRIVATE_CODE`
- `MIGRATION`
- `PLATFORM_GRANT`

Estados:

`draft`, `submitted`, `invited`, `accepted`, `rejected`, `withdrawn`,
`declined`, `expired`, `active`, `completed`, `disqualified`.

Solo puede existir una entry vigente por edition, category y Team. Un Club
organizador administra la competicion, pero no actua en nombre del Team: enviar,
aceptar, retirar o delegar exige owner/delegado real del Team segun la accion.

## Historias probadas

| Historia | Resultado |
| --- | --- |
| Solicitud publica | Team owner envia; organizer acepta; snapshot converge |
| Invitacion privada | Organizer invita; owner acepta o declina |
| Rechazo | Motivo privado visible solo a quien corresponde |
| Duplicado concurrente | Un ganador; el segundo recibe conflicto canonico |
| Cierre con pendientes | Falla o expira/rechaza mediante accion explicita |
| Regla incorrecta | Revision o modo no vigente falla cerrado |
| Tournament | `FEATURE_NOT_AVAILABLE` |

## Read models

- Publico: categoria, ventana, reglas publicas, capacidad y estado reducido.
- Usuario: sus entries, proximas acciones y warnings.
- Organizer desk: entries paginadas, contadores, pendientes y acciones validas.
- Entry: Team, categoria, delegados, roster, stage y constraints segun ACL.

Las consultas ordenan por `server_sequence` y un ID estable; ninguna seleccion
de ultimo estado depende solo de `created_at`.

## Seguridad

No existe INSERT/UPDATE/DELETE directo para clientes. La API acepta un payload
semantico permitido y nunca actor, permisos, revision calculada ni clave de
servicio. RLS, ownership, capabilities y revision se comprueban en servidor.

## Evidencia

- Tests R4A: `20/20`.
- SQL/RLS/adversarial: PASS.
- Concurrencia: una entry vigente por Team/category.
- Staging autenticado: public application, invitation, rejection y close PASS.
- Cleanup: 0 entries R4A activas; fixtures historicos cancelados conservados.
- Produccion: no modificada.
- Merge: no realizado.
