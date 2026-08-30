# Venue And Pitch Foundation V1 Report

Fecha: 2026-08-30 CEST

## Checkpoint

- Base inicial: `056414a8967933c2d839b0e27e39ae00d1fcc572`.
- Rama: `codex/venue-availability-reservations-v1`.
- PR funcional: `#235` (draft durante la certificacion local).
- Autoridad: PostgreSQL/Supabase; el cliente solo envia intenciones.
- Validacion: Simulation World, Demo World saneado y canary reversible.
- Entidades reales, notificaciones reales y Stripe utilizados: `0 / 0 / NO`.

## Modelo canonico

`public.pachanga_club_venues` representa una instalacion administrada por un
Club. `public.pachanga_venue_pitches` representa cada recurso reservable y
mantiene modalidad, entorno, superficie, capacidad, buffers, estado y
`conflict_scope_id` propios. Venue y Pitch tienen revision monotona,
`server_sequence`, `operation_id`, auditoria y lifecycle independientes.

La publicacion exige consentimiento explicito. El read model anonimo solo
expone zona general, modalidades, servicios y tarifa publica consentida. La
direccion exacta, instrucciones, contactos, notas y precio privado permanecen
fuera de la proyeccion publica.

## Autoridad de escritura

La unica ruta de mutacion cliente es
`command_pachanga_venue_reservation_v1(operationId, aggregateId,
expectedRevision, action, payload, clientMetadata)`. El servidor resuelve actor,
Club, capability, revision, reloj y secuencia. Los payloads estan allowlisted y
se ignoran actor, IDs calculados y secuencias aportadas por el navegador.

Acciones V1: `venue.create`, `venue.update`, consentimiento, revision,
activacion, suspension y archivo; `pitch.create`, `pitch.update`, mantenimiento,
restauracion y archivo. Las escrituras directas de `anon` y `authenticated`
estan revocadas.

## Roles y seguridad

- Club owner y `club_venue_manager`: gestion operativa del Venue/Pitch.
- Team owner/admin: lectura publica y solicitudes, sin administrar el Venue.
- Competition staff: solo contexto autorizado de partido.
- Plataforma: supervision mediante capability explicita.
- `SECURITY DEFINER`: `search_path` fijo, tablas cualificadas y `auth.uid()`
  interno.

RLS y RPC no devuelven Auth IDs innecesarios, notas privadas, contactos,
instrucciones ni secretos. Un Venue privado no es enumerable anonimamente.

## Producto

- Directorio publico: `/campos`.
- Ficha publica: `/campos/[slug]`.
- Gestion Club: `/clubes/gestionar/campos`.
- Control Center: `/admin/venues`.
- Home role-aware: solo muestra trabajo de Venue al rol correspondiente.

## Migraciones

| Version | Nombre | SHA-256 |
| --- | --- | --- |
| `20260830145047` | `venue_pitch_foundation_v1` | `2623df4a6a8c1385ceeb1596b29c450592fc580fe0c486af8548af4c7c9631ea` |
| `20260830145100` | `venue_hardening_indexes_flags_v1` | `e06ef1e6a9576e45ca0242e0d49dc412a7bf46a3c41711a78db0c4446bfff7b7` |

Las 212 migraciones base no se modifican. Fresh bootstrap y upgrade llegan a
ledger 220; hash de esquema aislado:
`83c1142de712cdbcb6528794ccf511d9fabf127caecf2c3e27ac2e735e2ee135`.

## Validacion local

- SQL/RLS/idempotencia: PASS.
- Archivo vs solicitud futura y owner transfer vs aceptacion: PASS.
- Directorio a escala, p95 `460.925 ms` con 1.000 Venues y 5.000 Pitches.
- Control Center, p95 `755.617 ms`.
- Root overflow, imagenes rotas y errores de consola: `0 / 0 / 0`.
- Flags nacieron OFF y se activaron mediante RPC de plataforma en el release
  coordinado; no se utilizo `UPDATE` directo.

## Produccion

- PR funcional: `#235`, fusionado en
  `bbef59dd78e13c36b837112290477a1f0193153f`.
- Deployment exacto: `dpl_Dnubnky8y1r2McZrMaoomsDFLhYU`, `READY`.
- Foundation, Management, perfiles publicos y directorio: `ON`.
- Pagos, recurrencia, asignacion masiva e integraciones externas: `OFF`.
- Readback de dominio: cero Venues y cero Pitches tras el canary con rollback.
- Directorio, ficha publica, gestion Club y Control Center forman parte de la
  matriz productiva `96/96` y PWA `12/12`, sin overflow ni errores de consola.
