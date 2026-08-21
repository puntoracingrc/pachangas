# Competition Entitlements V1 Report

Estado: `READY FOR REVIEW`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Base auditada | `0ea46f1cfa797a253678b68a3ffb8d7456856c81` |
| Rama | `codex/competition-organizer-foundation-v1` |
| PR | [#153](https://github.com/puntoracingrc/pachangas/pull/153) |
| Organizador R1 | `TEAM` -> `pachanga_groups` |
| Produccion | No modificada |

## Politica congelada

- El entitlement pertenece al grupo organizador, no a una persona.
- Solo el owner actual del grupo, con `competition_create` vigente y flags
  activos, puede crear una Competition.
- Ser admin o jugador del grupo no concede `competition_create`.
- Transferir el ownership no mueve ni duplica el entitlement: el nuevo owner
  recibe la autoridad ultima y el anterior la pierde salvo staff explicito.
- Expirar o revocar el grant bloquea nuevas competiciones y publicaciones
  futuras, pero conserva borradores, receipts, eventos y lecturas autorizadas.
- Un cliente autenticado nunca puede conceder o revocar grants directamente.
- La extension futura `CLUB` queda prevista por el contrato de organizer, pero
  R1 no crea una entidad Club ficticia.

## Modelo autoritativo

| Entidad | Proposito |
| --- | --- |
| `pachanga_competition_organizer_states` | Revision monotona del agregado TEAM. |
| `pachanga_competition_entitlement_grants` | Grants versionados, fechados y revocables. |
| `pachanga_competition_staff_assignments` | Delegaciones acotadas a una Competition. |
| `private.pachanga_competition_operation_receipts` | Idempotencia y respuesta confirmada. |
| `private.pachanga_competition_events` | Auditoria ordenada por secuencia de servidor. |

Origenes soportados: `subscription`, `partnership`, `promotion` y
`platform_grant`. Solo `platform_grant` fue usado en staging; R1 no crea planes,
productos, precios ni suscripciones.

Capacidades activas: `competition_create`, `competition_manage`,
`competition_staff` y `competition_rules`. `competition_referees` y
`competition_discipline` estan reservadas y fallan cerrado.

## Staff y capacidades

| Rol | Read | Manage | Staff | Rules |
| --- | ---: | ---: | ---: | ---: |
| `competition_owner` | Si | Si | Si | Si |
| `competition_director` | Si | Si | Si | Si |
| `competition_admin` | Si | Si | No | No |
| `rules_manager` | Si | No | No | Si |
| `viewer` | Si | No | No | No |

El staff no se convierte en owner/admin del grupo. Al revocarlo pierde acceso
futuro, pero `created_by`, receipts y eventos historicos permanecen.

## Matriz RBAC verificada

| Actor | Crear Competition | Leer | Administrar | Conceder entitlement |
| --- | ---: | ---: | ---: | ---: |
| `anon` / visitor | No | No | No | No |
| Usuario normal | No | No | No | No |
| Jugador del grupo | No | No, salvo staff | No | No |
| Admin del grupo | No | Solo como staff | Solo como staff | No |
| Owner sin entitlement | No | Si sobre organizador propio | Borrador existente | No |
| Owner con entitlement | Si | Si | Si | No |
| Staff de competicion | No | Si | Segun rol | No |
| `platform_admin` autorizado | No como owner TEAM | Global | Global/plataforma | Si |
| `platform_owner` | No como owner TEAM | Global | Global/plataforma | Si |
| `service_role` | Autoridad interna | Global | Global | Si |

La concesion/revocacion requiere rol de plataforma con
`competitions.manage`, `operationId`, `expectedRevision`, motivo, receipt y
evento. Las tablas no conceden escritura directa a `authenticated`.

## Expiracion, revocacion y reloj

El resolver usa una unica muestra `clock_timestamp()` materializada por
invocacion. Esto evita que un grant creado dentro del mismo comando aparezca
temporalmente como programado frente a un `statement_timestamp()` anterior.

Casos probados:

- grant inmediato devuelve `canCreate=true` en su propio receipt;
- grant expirado rechaza una nueva Competition;
- revocacion rechaza nueva creacion y conserva la Competition existente;
- una revision publicada no se altera al revocar;
- owner transfer conserva el grant en el grupo y cambia la autoridad personal;
- owner anterior sin staff deja de leer; staff explicito permanece;
- revocar staff no elimina historia.

## Idempotencia y concurrencia

- mismo actor + `operationId` + payload devuelve el mismo receipt;
- reutilizar el `operationId` con payload distinto devuelve
  `IDEMPOTENCY_KEY_REUSED`/`PT409`;
- dos comandos sobre la misma revision producen un ganador y un
  `STALE_REVISION`;
- la revision monotona confirmada se devuelve en el snapshot y se usa para el
  siguiente compare-and-swap.

## RLS, Realtime y privacidad

- las tablas R1 directas estan cerradas a `anon` y `authenticated`;
- las lecturas pasan por RPCs con actor resuelto mediante `auth.uid()`;
- Realtime publica solo invalidaciones acotadas por RLS;
- el helper privado de la policy puede ejecutarse por `authenticated` para que
  Realtime aplique RLS, pero permanece revocado a `anon`;
- el payload de invalidacion no contiene documentos de reglas ni secretos;
- el cliente invalida su copia y refetch el snapshot canonico.

## Evidencia de staging

El E2E autenticado demostro con dos grupos y siete actores sinteticos:

- Owner A con grant crea la historia completa R1;
- Admin A, Jugador A y Owner B sin grant son rechazados;
- expiry y revocation bloquean nueva Competition;
- staff solo ve y opera en la Competition asignada;
- owner transfer y retorno usan la revision actual del servidor;
- el historial sobrevive a revocar entitlement y staff;
- el cierre deja `0` grants fixture activos y `0` staff fixture activo;
- los feature flags vuelven a `OFF` (`revision 21`).

## Advisors

Los avisos R1 de seguridad son esperados y documentados:

- tablas directas con RLS y sin policies de acceso general;
- RPCs `security definer` intencionadamente ejecutables por autenticados, con
  actor/RBAC resueltos dentro de PostgreSQL;
- anonymous sign-ins habilitado a nivel de proyecto, mientras las rutas R1
  exigen `auth.uid()` y `anon` fue rechazado.

Los avisos de rendimiento son FKs sin indice y tres indices aun no usados por
el dataset remoto. El ensayo de 500 competitions/10.000 bindings y sus planes
no justifico añadir indices especulativos.

## Conclusion

El entitlement R1 es organizacional, temporal, revocable, auditable e
idempotente. No altera Billing ni activa un producto comercial. La autoridad
ultima permanece en el owner actual del grupo y las delegaciones siguen
limitadas a cada Competition.
