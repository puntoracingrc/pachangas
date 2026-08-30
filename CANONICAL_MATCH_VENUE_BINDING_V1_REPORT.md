# Canonical Match Venue Binding V1 Report

Fecha: 2026-08-30 CEST

## Autoridad

`CanonicalMatch` continua siendo la unica autoridad deportiva. Wave 9A no crea
un segundo partido: vincula una reserva confirmada mediante
`pachanga_venue_match_bindings`. Solo puede existir un binding activo por
partido y una reserva no puede quedar vinculada simultaneamente a dos partidos.

## Lifecycle y R4D

- `reservation.bind_match`: crea el binding versionado y actualiza la reserva.
- `reservation.unbind_match`: libera el vinculo sin borrar historia.
- `reservation.replace_venue`: conserva lineage, marca historico el binding
  anterior, libera su claim, vincula la nueva reserva y eleva
  `refereeReconfirmationRequired`.
- Cancelar la reserva marca `ACTION_REQUIRED`; no cancela el partido, no declara
  no-show y no produce forfeit.
- Un partido consumido conserva Venue/Pitch, revision y snapshot historicos.

## Integraciones

La seccion canónica `Campo y reserva` esta integrada en Match Hub. Muestra
Venue, Pitch, horario, estado, ubicacion permitida, accion pendiente y
reconfirmacion arbitral. Los cambios generan invalidacion Realtime y el cliente
refetchea `get_pachanga_match_venue_v1`.

## Migracion

| Version | Nombre | SHA-256 |
| --- | --- | --- |
| `20260830145053` | `venue_canonical_match_binding_r4d_v1` | `1f5490529fa6ea9b3b0008218f1d9821280e603e8f6555c7d740a285fa72d6fe` |

## Validacion local

- Binding unico y Match inexistente/finalizado: PASS.
- Cancelacion vs binding concurrentes: PASS.
- Cambio de Venue vs confirmacion arbitral: PASS.
- Reserva cancelada no auto-cancela Match ni crea forfeit: PASS.
- Match binding p50/p95 a escala: `2.955 / 4.653 ms`.
- Demo V3.4 incluye binding de Liga, cambio R4D, reconfirmacion y Venue
  historico consumido.
