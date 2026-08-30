# Venue Operations V1 Production Release

Estado: `RELEASED / ACTIVE / CANONICAL / CLEAN`

| Campo | Valor |
| --- | --- |
| fecha | `2026-08-30` |
| main inicial | `056414a8967933c2d839b0e27e39ae00d1fcc572` |
| HEAD funcional | `c79a0d90c77fab030f1f64fda700381ac34de792` |
| merge funcional | `bbef59dd78e13c36b837112290477a1f0193153f` |
| PR funcional | `#235`, fusionado `2026-08-30T19:43:12Z` |
| migraciones | 8 forward-only, ledger productivo `220` |
| schema hash | `83c1142de712cdbcb6528794ccf511d9fabf127caecf2c3e27ac2e735e2ee135` |
| deployment | `dpl_Dnubnky8y1r2McZrMaoomsDFLhYU`, `READY` |
| URL exacta | `https://pachangas-5ei6jvjcy-persianas-almar-web-s-projects.vercel.app` |
| dominio | `https://pachangasiq.com` |
| settings | revision `8`, server sequence `14` |
| entidades reales | `0` |
| Stripe | `UNTOUCHED` |
| Wave 9B | `NOT STARTED` |

## Secuencia de release

1. Se certifico el upgrade aislado `212 -> 220` y el fresh bootstrap `220`.
2. Las ocho migraciones se aplicaron una sola vez en produccion, sin reescribir
   ni modificar ninguna migracion ejecutada.
3. PR `#235` se fusiono y Vercel publico el SHA exacto de merge como deployment
   productivo `READY`.
4. El smoke inicial confirmo las dieciseis flags nacidas OFF y cero datos Wave
   9A.
5. Siete operaciones idempotentes de la RPC
   `set_pachanga_venue_flags_v1` activaron el producto por fases. No se uso
   `UPDATE` directo.
6. El canary sintetico recorrio el lifecycle completo dentro de una transaccion
   y termino con `ROLLBACK`; el readback independiente devolvio cero entidades.
7. Se repitieron logs, responsive, PWA, secreto cliente y limpieza externa.

## Migraciones productivas

| Version | Nombre | SHA-256 local |
| --- | --- | --- |
| `20260830145047` | `venue_pitch_foundation_v1` | `2623df4a6a8c1385ceeb1596b29c450592fc580fe0c486af8548af4c7c9631ea` |
| `20260830145049` | `venue_availability_templates_exceptions_v1` | `65cad385bdd6558d67db17cbcd44532d93c29f8ee02d4a3840a333a74390655e` |
| `20260830145051` | `venue_reservation_requests_holds_v1` | `9e4bce7145ca3f71c246f4be8a23cc4e50e77a791d348901444f1f3add99e018` |
| `20260830145053` | `venue_canonical_match_binding_r4d_v1` | `1f5490529fa6ea9b3b0008218f1d9821280e603e8f6555c7d740a285fa72d6fe` |
| `20260830145054` | `venue_command_receipts_events_v1` | `68c7fb07f57a78bd828405f8acda1539a77e7582f42977b6d1ae6c73ca5ccdfb` |
| `20260830145056` | `venue_read_models_control_center_v1` | `8465fe3fe4be003fb49c565017d1479c6ce90adb2636fbfaf269310b3014caf6` |
| `20260830145058` | `venue_rls_realtime_notifications_v1` | `7157dd0dafc3a005def0a4a367f47c9b7701f78b930dc86eff9ebc01ecfdc4db` |
| `20260830145100` | `venue_hardening_indexes_flags_v1` | `e06ef1e6a9576e45ca0242e0d49dc412a7bf46a3c41711a78db0c4446bfff7b7` |

Readback final: ledger `220`, ultima version `20260830145100` y los ocho
nombres exactos en el mismo orden. Las 212 migraciones base permanecen
intactas.

## Flags finales

Activas:

- Venue Foundation y Management;
- perfiles y directorio publicos con consentimiento;
- Availability;
- Reservation Requests y Counteroffers;
- Reservation Holds y Canonical Reservations;
- CanonicalMatch Venue Binding y R4D;
- Demo World V3.4.

Desactivadas:

- pagos;
- reservas recurrentes;
- asignacion masiva de competiciones;
- integraciones externas.

La configuracion final esta en revision `8`, server sequence `14`. Las siete
operaciones de activacion generaron exactamente siete receipts, siete eventos y
siete invalidaciones, ordenadas por secuencia `2, 4, 6, 8, 10, 12, 14`.

## Autoridad y canary

PostgreSQL/Supabase es la autoridad unica. El cliente envia intencion,
`operationId` y revision esperada; no calcula disponibilidad definitiva, no
confirma reservas localmente y no mantiene una cola offline deportiva.
Realtime invalida y obliga a releer el read model canonico.

El canary productivo sintetico valido:

- create y replay idempotente;
- activacion de Venue, Pitch, disponibilidad y consentimiento publico;
- rechazo de revision obsoleta;
- solicitud, revision, contrapropuesta, hold, aceptacion y confirmacion;
- privacidad del read model;
- binding a CanonicalMatch;
- cancelacion con binding `ACTION_REQUIRED / VENUE_ACTION_REQUIRED`.

Resultado: `PASS_ROLLED_BACK`. Readback posterior: `0` Venues, Pitches,
templates, excepciones, requests, claims, holds, reservas, bindings, usuarios,
Teams, Clubs, Matches y operaciones sinteticas. No se contacto a usuarios ni
entidades reales.

## Validacion

| Gate | Resultado |
| --- | --- |
| test focal Wave 9A | `17/17 PASS` |
| suite global | Node `20/20` + TS/TSX `679/679` = `699/699 PASS` |
| fail/skipped/todo/cancelled | `0/0/0/0` |
| typecheck | `PASS` |
| build | `PASS`, 66 paginas estaticas |
| lint focal/global | `PASS / PASS` |
| git diff --check | `PASS` |
| SQL/RLS/idempotencia | `PASS` |
| concurrencia | `12/12 PASS`, cero dobles reservas |
| escala | `PASS`, corpus y escrituras revertidos |
| staging autenticado | dos usuarios, dos dispositivos, `PASS` |
| Realtime | subscribe, invalidacion, refetch y reconexion, `PASS` |

El baseline contractual era 682 tests. Wave 9A aporta 17 regresiones netas y
no elimina cobertura. El corpus aislado uso 1.000 Venues, 5.000 Pitches, 50.000
reglas/excepciones, 100.000 requests, 50.000 reservas y 100.000 invalidaciones.
No se repitio la certificacion de escala tras cambios documentales porque SQL,
indices y autoridad no cambiaron.

## Produccion visual y PWA

La matriz productiva final cubrio doce superficies en ocho viewports:
1440x900, 1920x1080, 390x844, 360x800, 667x375, 740x360, 844x390 y
932x430. Resultado agregado: `96/96 PASS`, cero errores de consola, warnings,
requests fallidas, imagenes rotas, overflow, controles fuera del viewport o
violaciones de game chrome.

La pasada PWA independiente recorrio las doce superficies en 390x844:
`12/12 PASS`, todas en `standalone` y controladas por el Service Worker. El
worker no confirma escrituras offline ni contiene una cola deportiva.

Android fisico, iPhone fisico y PWA instalada en dispositivo fisico permanecen
`PENDING`; no se presentan como PASS.

## Seguridad, logs y Advisors

- RLS esta activa en las diez tablas publicas Wave 9A.
- `anon` y `authenticated` no tienen escritura directa de tablas.
- La exclusion GiST impide solapamientos y los bindings actuales tienen dos
  indices unicos parciales.
- Ninguna lectura de ultimo snapshot depende solo de `created_at DESC`.
- El escaneo exacto del service-role devolvio cero coincidencias en Git, bundle
  cliente, artefactos QA y catorce assets productivos; cero ficheros temporales.
- Vercel no mostro runtime errors posteriores al release.
- Los logs finales de API, PostgreSQL, Realtime y Auth no mostraron una
  regresion Wave 9A; los errores QA previos estan trazados en el ledger.
- Security Advisors: cero `ERROR`.
- Performance Advisors: un unico WARN preexistente de indice duplicado en
  Rating V2; Wave 9A no toca Rating.

## Demo, limpieza y limites

Demo World V3.4 esta activo y muestra casos saneados de Venue, Pitch,
disponibilidad, solicitud, hold, reserva, binding, cambio R4D y Venue historico.
No contiene PII, Auth IDs ni escritura publica remota.

Limpieza externa completada:

- los dos branches Supabase efimeros fueron eliminados; solo queda `main`;
- las tres variables Preview limitadas a la rama fueron retiradas;
- el secreto de servicio productivo permanece server-only y `sensitive`;
- el workspace temporal de migration push fue retirado sin tocar el metadata
  Supabase preexistente del repositorio;
- los canaries y filas QA tienen readback cero.

El worktree del informe se conserva solo hasta que su PR documental quede
fusionado y el deployment correspondiente este `READY`; entonces se retira con
`git worktree remove` y `git worktree prune`, conforme a `AGENTS.md`.

No se inicio Wave 9B, no se activo Stripe y no se modificaron Rating V2,
Player Cosmetics, Team Cosmetics, rewards, Conduct, billing ni motores de Liga
o Torneo ajenos al binding expresamente contratado.
