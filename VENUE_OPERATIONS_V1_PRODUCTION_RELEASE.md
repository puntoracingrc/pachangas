# Venue Operations V1 Production Release

Estado: `LOCAL_GATES_COMPLETE / STAGING_PENDING`

| Campo | Valor |
| --- | --- |
| fecha | `2026-08-30` |
| main inicial | `056414a8967933c2d839b0e27e39ae00d1fcc572` |
| rama | `codex/venue-availability-reservations-v1` |
| PR funcional | `#235` / draft |
| migraciones | 8 forward-only, ledger local 220 |
| schema hash | `83c1142de712cdbcb6528794ccf511d9fabf127caecf2c3e27ac2e735e2ee135` |
| deployment | PENDING |
| canary | PENDING |
| entidades reales | 0 |
| Stripe | UNTOUCHED |
| Wave 9B | NOT STARTED |

## Gates locales

| Gate | Resultado |
| --- | --- |
| test focal Wave 9A | 16/16 PASS |
| suite global | Node 20/20 + TS/TSX 678/678 = 698/698 PASS |
| fail/skipped/todo/cancelled | 0/0/0/0 |
| typecheck | PASS |
| build | PASS, 66 paginas estaticas |
| lint focal/global | PASS / PASS |
| git diff --check | PASS |
| SQL/RLS/idempotencia | PASS |
| concurrencia | 12/12 PASS, 0 dobles reservas |
| escala | PASS, rollback completo |
| QA local desktop/portrait/landscape | PASS |

El baseline contractual era 682 tests. El conteo actual exacto es 698: se
separan 20 pruebas Node y 678 TS/TSX, sin skip, todo o cancelled. El incremento
neto es de 16 pruebas Wave 9A y las regresiones previas fueron actualizadas sin
eliminar cobertura.

## Rendimiento aislado

Corpus: 1.000 Venues, 5.000 Pitches, 50.000 reglas/excepciones, 100.000
requests, 50.000 reservas y 100.000 invalidaciones. P95: directorio 460.925 ms,
availability 5.079 ms, submit 8.405 ms, hold 119.891 ms, accept 63.657 ms,
conflict 64.711 ms, desk 28.500 ms, binding 4.653 ms, health 571.974 ms y
Control Center 755.617 ms. Rollback y cleanup: PASS.

## Estado de activacion

Todas las flags nacen OFF. El release remoto seguira este orden: migraciones,
smoke inactivo, Venue Foundation, Management, Availability, Requests,
Counteroffers, Holds, Canonical Reservations, Match Binding, R4D, perfiles y
directorio publicos, Demo V3.4. Pagos, recurrencia, asignacion masiva e
integraciones externas permaneceran OFF.

## Pendiente antes de RELEASED

- staging Supabase efimero y Preview con dos dispositivos autenticados;
- Realtime `SUBSCRIBED`, refetch y reconexion;
- PWA standalone automatizada y QA responsive ampliada;
- backup/readback productivo y `migration list --linked` 220/220;
- merge, deployment READY del SHA exacto y smoke con flags OFF;
- activacion mediante RPC, canary con ROLLBACK y readback final a cero;
- Demo V3.4 productiva, logs, Service Worker y cleanup.

No se presentara este informe como `RELEASED` hasta disponer de esas evidencias.
