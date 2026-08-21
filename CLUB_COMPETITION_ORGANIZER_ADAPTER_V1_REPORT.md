# Club Competition Organizer Adapter V1 Report

Estado: `STAGING PASS / PREVIEW PENDING`

## Evolucion del organizer

R2 conserva las entidades R1 `Competition`, `Edition`, `RuleSet`, rules,
staff, receipts y events. No crea `ClubCompetition`.

La integridad usa dos FKs reales y una constraint XOR:

| `organizer_kind` | `organizer_group_id` | `organizer_club_id` |
| --- | --- | --- |
| `TEAM` | requerido | nulo |
| `CLUB` | nulo | requerido |

La base rechaza referencias mixtas, ausentes o incompatibles. No se usa un ID
polimorfico de texto sin FK.

## Resolver comun

`private.resolve_pachanga_competition_organizer_v2` concentra identidad,
revision, estado activo, rol/capacidades del actor y entitlement vigente para
TEAM y CLUB. La creacion generica usa ese contrato en vez de repartir ramas por
las funciones de producto.

Para CLUB se exige:

- Club `active`;
- flags R1 foundation/creation y flag R2 organizer activos;
- entitlement `competition_create` vigente del Club;
- actor `club_owner` o `club_competition_manager`.

`club_admin` no crea Competition por defecto. Partnership activo no concede el
entitlement: plataforma debe ejecutar un grant auditable con source
`partnership`. En R2 staging tambien se permite `platform_grant`; no hay Stripe.

Expiry o revocation bloquean nuevas Competitions, pero no eliminan perfil,
staff, relaciones, historial ni drafts. Suspender el Club bloquea creacion.

## Compatibilidad TEAM

`command_pachanga_competition_foundation_v2` es el contrato generico. El
contrato V1 y su envelope TEAM se conservan; la via TEAM delega sin cambiar el
significado de `command_pachanga_competition_foundation_v1`.

Las constraints, read models y funciones de plataforma aceptan ambos organizer
types. La regresion R1 confirma owner + entitlement, rechazo de team admin,
cambio de autoridad por owner transfer y bloqueo tras expiry/revocation.

## Competition creada por Club

Una creacion confirmada produce exactamente los objetos R1:

- Competition draft `LEAGUE` o `TOURNAMENT`;
- Edition draft;
- RuleSet y revision inicial;
- operation receipt;
- event e invalidacion.

Si crea un `club_competition_manager`, la misma transaccion le asigna
`competition_director`. No se convierte en owner y la gestion posterior sigue
el scope `CompetitionStaffAssignment`.

## Entitlements

Los grants se vinculan por XOR a Team o Club, conservan source, fechas,
revocacion, motivo, actor, revision y secuencia. Fuentes soportadas por el
contrato: `subscription`, `partnership`, `promotion`, `platform_grant`; R2 solo
ejercita las dos ultimas en staging.

Partnership y grant son operaciones separadas. Dos grants concurrentes de la
misma capability producen un ganador y un stale/conflict. El replay conserva un
solo grant.

## Read models y Control Center

Los snapshots de Competition incluyen `organizerKind`, `organizerGroupId` o
`organizerClubId` y la identidad resuelta. El Club read model lista sus
Competitions y grants autorizados; el Control Center puede filtrar y abrir
organizers TEAM/CLUB sin exponer entitlements publicamente.

## Evidencia local

| Caso | Resultado |
| --- | --- |
| CLUB owner/manager con grant crea Competition | PASS SQL/contrato |
| Manager queda `competition_director` | PASS |
| Club admin | REJECT |
| Club suspended | REJECT |
| Sin entitlement | REJECT |
| Entitlement expired/revoked | REJECT |
| Partnership sin grant explicito | REJECT |
| Staff Club A sobre Club B | REJECT |
| TEAM path R1 | PASS |
| Competition create replay | PASS |
| Grant race | un ganador + un stale |
| Organizer CLUB scale p95 | `0.703 ms` |

Staging se actualizo de `106` a `110` con cuatro migraciones forward-only. El
recorrido CLUB autenticado creo una Competition draft R1 y materializo al
manager como `competition_director`; despues revoco el assignment durante la
limpieza. El E2E TEAM R1 volvio a pasar sobre ese mismo schema, incluidos owner,
admin rechazado, transfer, expiry y revocation. Produccion y Canonical Match
permanecen sin modificar.
