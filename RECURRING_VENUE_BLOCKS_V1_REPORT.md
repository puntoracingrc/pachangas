# Recurring Venue Blocks V1 Report

Estado: `RELEASE CANDIDATE / STAGING CERTIFIED`

Fecha: 2026-08-31 CEST

## Alcance

Wave 9B extiende la autoridad de reservas de Wave 9A con series recurrentes
finitas. No crea una segunda reserva ni modifica horarios deportivos. Cada
serie se materializa en ocurrencias deterministas que pueden alimentar un pool
de competicion, un hold y finalmente una reserva canonica.

Finalidades activas:

- `TEAM_RECURRING_BLOCK`;
- `COMPETITION_RECURRING_BLOCK`.

Quedan fuera `TRAINING_RECURRING_BLOCK`, venta recurrente publica, calendarios
externos y RRULE arbitrarias.

## Modelo canonico

- `pachanga_venue_recurring_series`: agregado revisionado de Venue/Pitch,
  proposito, propietario, frecuencia, zona horaria y horizonte.
- `private.pachanga_venue_recurring_series_revisions`: historial append-only.
- `pachanga_venue_recurring_occurrences`: slots materializados con checksum,
  estado y vinculo opcional a reserva.
- `pachanga_venue_recurring_exceptions`: cancelaciones y excepciones explicitas
  sin borrar historia.

Frecuencias V1: `WEEKLY` y `BIWEEKLY`. Toda serie exige `start_date` y
`end_date`, admite hasta 52 semanas y solo una capacidad de plataforma puede
autorizar el maximo absoluto de 104. No existe recurrencia infinita.

## Autoridad y lifecycle

La unica escritura cliente pasa por
`command_pachanga_competition_venue_allocation_v1` con actor autenticado,
`operationId`, revision esperada, accion y payload allowlisted. PostgreSQL
resuelve permisos, reloj, secuencia, conflictos y resultado.

Lifecycle cubierto:

`draft -> validated -> offered -> accepted -> published -> completed`, con
cancelacion previa, pausa/reanudacion y finalizacion. Una actualizacion crea
otra revision; no edita ocurrencias pasadas, reservas consumidas ni bindings
historicos.

La materializacion repetida conserva IDs, fechas y checksums. Un cambio futuro
no cancela silenciosamente reservas ni partidos: produce impacto explicito y,
si afecta a un Match vinculado, deriva a Wave 9A/R4D.

## Seguridad y producto

- escrituras directas `anon`/`authenticated`: revocadas;
- lectura: Club autorizado, staff de Competition, requester y plataforma;
- direcciones, contactos, precios privados y Auth IDs: fuera del read model;
- offline: lectura cacheada permitida, mutaciones bloqueadas sin fake success;
- UI: `/clubes/gestionar/campos/bloques`, `/reservas/recurrentes` y detalle de
  serie, integradas en la navegacion existente.

## Validacion

- SQL/RLS/idempotencia y fresh/upgrade: `PASS`;
- serie solapada: un ganador y un conflicto explicito;
- materialize vs update: un ganador y una revision stale;
- escala certificada: 1.000 series y 25.000 ocurrencias, rollback total;
- staging: creacion, oferta, aceptacion, materializacion y publicacion
  autenticadas con datos `.test`;
- datos reales, notificaciones reales y Stripe: `0 / 0 / NO`.

Produccion permanece pendiente del release coordinado de Wave 9B.
