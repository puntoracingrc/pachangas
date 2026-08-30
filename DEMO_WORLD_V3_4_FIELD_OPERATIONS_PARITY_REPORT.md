# Demo World V3.4 Field Operations Parity Report

Fecha: 2026-08-30 CEST

## Snapshot

Demo World V3.4 es una capa read-only saneada derivada de Simulation World.
Preserva V2.1-V3.3 y no altera el authority hash de V3.2:
`763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1`.

Hash de Field Operations V3.4:
`c44b327f4ea0296ca6843f389dd043eaca06901ef14a5426ad877c989d3c3def`.

## Inventario

- 4 Venues ficticios.
- 8 Pitches ficticios.
- 16 historias operativas.
- Perspectivas: Team owner, Club booking manager, Competition organizer,
  Player, Referee y Platform reviewer.
- Estados: Venue publico/privado, mantenimiento, recurrencia, cierre,
  solicitud, contrapropuesta, hold, expiracion, aceptacion, confirmacion,
  cancelacion, binding, cambio R4D, reconfirmacion y snapshot historico.

## Integridad y privacidad

| Control | Resultado |
| --- | --- |
| overlaps confirmados | 0 |
| auto-cancel Match | no |
| auto-forfeit | no |
| PII | 0 |
| Auth IDs | 0 |
| ubicacion privada anticipada | 0 |
| remote writes | 0 |
| Stripe calls / Customers / Charges | 0 / 0 / 0 |

La interfaz informa siempre `Pago fuera de Pachangas IQ.` y solo usa `GRATIS`,
`PRECIO ORIENTATIVO`, `NEGOCIABLE` o `CONTACTAR CON CLUB`.

## Producto y PWA

V3.4 se integra en `/demo`, conserva las perspectivas anteriores y reutiliza
los componentes productivos. Manifest y snapshot estan precacheados por el
Service Worker. Navegacion offline: PASS por contrato, build y respuesta HTTP;
PWA instalada en dispositivo fisico permanece PENDING.

QA local en 1440x900, 390x844 y 844x390: cero overflow global, imagenes rotas,
warnings de hidratacion o errores de consola. La matriz ampliada de staging y
produccion se incorporara al cierre del release.

