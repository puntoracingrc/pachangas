# Competition Venue Pools V1 Report

Estado: `RELEASE CANDIDATE / STAGING CERTIFIED`

Fecha: 2026-08-31 CEST

## Contrato

Un Venue publico no queda disponible automaticamente para una competicion.
Wave 9B introduce una autorizacion explicita y revisionada entre Competition,
Edition, Club, Venue, Pitches, modalidades, fechas y franjas.

Fuentes validas de autorizacion:

- campo propio del Club organizador con decision explicita;
- autorizacion del Club propietario;
- bloque recurrente confirmado;
- reserva confirmada previa;
- acuerdo de disponibilidad especifico para la Competition.

Un Team organizer no puede reservar un campo externo por aparecer en el
directorio.

## Modelo

- `pachanga_competition_venue_pools`;
- `private.pachanga_competition_venue_pool_revisions`;
- `pachanga_competition_venue_authorizations`;
- `pachanga_competition_venue_pool_memberships`.

El snapshot conserva modalidad, Pitches, ventana temporal, franjas, capacidad,
prioridad, finalidad, visibilidad, expiracion, actor, revision y secuencia.
Lifecycle: `draft -> offered -> accepted -> active -> exhausted/expired/revoked`.
Las autorizaciones consumidas se preservan.

## Self-managed y Club externo

El Club que organiza en sus propias instalaciones dispone de un flujo
simplificado, pero sigue creando decision, revision, rango, Pitches, franjas,
receipt y evento. Para un Club externo se exige aceptacion bilateral; no se
transfiere autoridad del Venue ni se concede partnership por usar el planner.

## RBAC y privacidad

`competition_venue_manager` puede leer, configurar, generar, editar draft,
crear holds, validar y publicar dentro de su Competition. No puede modificar
Rating, resultados, disciplina, Billing ni flags globales.

Las tablas rechazan escrituras directas. Las funciones sensibles fijan
`search_path`, resuelven `auth.uid()` y no exponen coordenadas privadas,
contactos, notas, precios privados ni identidades Auth. Las distancias privadas
solo pueden participar internamente en quality para actores autorizados.

## Read models y producto

- `get_pachanga_competition_venue_pool_v1`;
- catalogo saneado de temporada;
- overview/desk de competicion;
- `/clubes/gestionar/campos/pools`;
- `/competiciones/[competition]/gestion/campos`;
- Control Center de Season Venue Allocation.

## Evidencia

- autorizacion propia y externa: `PASS`;
- Pitch privado/no autorizado/modalidad incompatible: rechazo canonico;
- oferta/aceptacion/replay: idempotentes;
- escala: 1.000 pools, reads p50/p95 certificados y rollback completo;
- staging: pool ofrecido, aceptado y usado por Liga/Torneo sinteticos;
- PII, Auth IDs, coordenadas privadas y Stripe en Demo/staging: `0`.

Produccion permanece pendiente del release coordinado de Wave 9B.
