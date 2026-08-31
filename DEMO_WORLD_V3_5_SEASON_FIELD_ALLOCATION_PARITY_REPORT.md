# Demo World V3.5 Season Field Allocation Parity Report

Estado: `RELEASE CANDIDATE / PREVIEW VERIFIED`

Fecha: 2026-08-31 CEST

## Autoridad preservada

Demo World V3.5 anade una capa read-only de asignacion de temporada sin
modificar los snapshots anteriores:

| Autoridad | Hash |
| --- | --- |
| V3.2 sporting season | `763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1` |
| V3.4 field operations | `c44b327f4ea0296ca6843f389dd043eaca06901ef14a5426ad877c989d3c3def` |
| V3.5 season allocation | `7b882e1e62ace05d388f1a0b88bcc71362ae3a2a0a0c1a5ceac65987cc44b61f` |

## Inventario

- 6 Clubs, 32 Teams y 4 competiciones;
- 128 CanonicalMatches durante 16 semanas;
- 4 Venues y 8 Pitches;
- 8 planes: 4 automaticos y 4 hibridos;
- 3 locks hibridos;
- 127 reservas y 126 bindings activos;
- 16 asignaciones preservadas desde binding existente;
- 1 Match explicitamente `UNASSIGNED`.

Los 128 `scheduledBefore` son identicos a `scheduledAfter`. Hay cero overlaps,
cero bindings activos duplicados y cero hard violations publicadas.

## Historias

La capa presenta bloques recurrentes, pools, automatico, hibrido, conflictos,
reservas, bindings y utilizacion desde perspectivas de Club booking manager,
League/Tournament organizer, Team owner, player, referee y platform reviewer.

Conflictos representados: mantenimiento, occurrence cancelada, hold expirado,
competencia por un Pitch, Match sin campo, reserva cancelada tras publicacion,
cambio R4D y reconfirmacion arbitral. Ninguno provoca sancion, no-show,
cancelacion de Match ni cambio horario automatico.

## Privacidad y efectos

| Control | Resultado |
| --- | --- |
| PII | `0` |
| Auth IDs | `0` |
| coordenadas privadas | `0` |
| remote writes | `0` |
| Stripe calls | `0` |
| hard violations publicadas | `0` |
| Match times modificados | `0` |

Los manifests y snapshots son content-addressed y cacheables. La UI no contiene
RPC ni POST y no fabrica estado deportivo.

## QA visual y PWA

Exact Preview `0f5d25f`:

- home: `1440x900`, `1920x1080`, `390x844`, `360x800`, `667x375`,
  `740x360`, `844x390` y `932x430`;
- ocho capas V3.5: desktop, portrait y landscape;
- resultado: cero root/body overflow, clipping inesperado, imagenes rotas,
  warnings o errores de consola;
- manifest: `fullscreen` con fallbacks `standalone`, `minimal-ui`, `browser`;
- Service Worker: snapshot V3.5 precacheado, escritura offline bloqueada y
  respuesta exacta `200 + no-store` en E2E autenticado.

Android fisico, iPhone fisico y PWA instalada fisica permanecen `PENDING`.
Produccion permanece pendiente del release coordinado de Wave 9B.
