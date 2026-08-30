# Venue Operations V1 Production Release

Estado: `LOCAL_AND_STAGING_CERTIFIED / PRODUCTION_PENDING`

| Campo | Valor |
| --- | --- |
| fecha | `2026-08-30` |
| main inicial | `056414a8967933c2d839b0e27e39ae00d1fcc572` |
| rama | `codex/venue-availability-reservations-v1` |
| PR funcional | `#235` / draft |
| migraciones | 8 forward-only, ledger aislado/staging 220 |
| schema hash | `83c1142de712cdbcb6528794ccf511d9fabf127caecf2c3e27ac2e735e2ee135` |
| staging Supabase | `zqrmuamcikcmbhnopfqx`, efimero |
| Preview | `READY`, protegida por Vercel SSO |
| deployment productivo | PENDING |
| canary productivo | PENDING |
| entidades reales | 0 |
| Stripe | UNTOUCHED |
| Wave 9B | NOT STARTED |

## Gates locales finales

| Gate | Resultado |
| --- | --- |
| test focal Wave 9A | 17/17 PASS |
| suite global | Node 20/20 + TS/TSX 679/679 = 699/699 PASS |
| fail/skipped/todo/cancelled | 0/0/0/0 |
| typecheck | PASS |
| build | PASS, 66 paginas estaticas |
| lint focal/global | PASS / PASS |
| git diff --check | PASS |
| SQL/RLS/idempotencia | PASS |
| concurrencia | 12/12 PASS, 0 dobles reservas |
| escala | PASS, rollback completo |
| QA local desktop/portrait/landscape | PASS |

El baseline contractual era 682 tests. El total actual es 699: 20 pruebas
Node y 679 TS/TSX, sin presentar ningun subtotal como total. Wave 9A aporta 17
regresiones netas y no elimina cobertura. `npm test` incluye un build completo;
ademas se repitieron `npm run typecheck`, `npm run build`, lint focal y lint
global sobre el arbol exacto de release.

## Migraciones certificadas

| Version | Nombre | SHA-256 local | Digest remoto staging |
| --- | --- | --- | --- |
| `20260830145047` | `venue_pitch_foundation_v1` | `2623df4a6a8c1385ceeb1596b29c450592fc580fe0c486af8548af4c7c9631ea` | `f16afbe6346343bc80336a1e41b89389a267b6260752384848ede958b2e19c8e` |
| `20260830145049` | `venue_availability_templates_exceptions_v1` | `65cad385bdd6558d67db17cbcd44532d93c29f8ee02d4a3840a333a74390655e` | `f4c371ed81678eb6481d39e8f1ef87a83e131238c61e1442924965c71e154d47` |
| `20260830145051` | `venue_reservation_requests_holds_v1` | `9e4bce7145ca3f71c246f4be8a23cc4e50e77a791d348901444f1f3add99e018` | `2053dcb1be658dad978f13e9b4126ff111b6f0b08a3b9c5239fc5a55aa19843c` |
| `20260830145053` | `venue_canonical_match_binding_r4d_v1` | `1f5490529fa6ea9b3b0008218f1d9821280e603e8f6555c7d740a285fa72d6fe` | `d18c964f212cb80338f554f2b37ea51156fd0a0514c6e8067c2695601b99b3ce` |
| `20260830145054` | `venue_command_receipts_events_v1` | `68c7fb07f57a78bd828405f8acda1539a77e7582f42977b6d1ae6c73ca5ccdfb` | `6077b7fc6f9f55409b67f48fb64f82f16a5153bdacc55c104d065e5865566905` |
| `20260830145056` | `venue_read_models_control_center_v1` | `8465fe3fe4be003fb49c565017d1479c6ce90adb2636fbfaf269310b3014caf6` | `b3b2f7cb19280b0c3689fabff8932832cb6b05ba1a81630b0e4cf5db75eab247` |
| `20260830145058` | `venue_rls_realtime_notifications_v1` | `7157dd0dafc3a005def0a4a367f47c9b7701f78b930dc86eff9ebc01ecfdc4db` | `3cdc6fd1e516913559c1772d861d38010466108323e6cdce03a4ef921d61f11f` |
| `20260830145100` | `venue_hardening_indexes_flags_v1` | `e06ef1e6a9576e45ca0242e0d49dc412a7bf46a3c41711a78db0c4446bfff7b7` | `34b5595f4863dd3c2267f7c2b81af7e82701a6fe723085798a3b6e3a42bc53a8` |

Las 212 migraciones base permanecen intactas. Fresh bootstrap, upgrade
`212 -> 220` y staging reconstruido convergen al mismo esquema normalizado.
Antes de produccion se repetira `supabase migration list --linked`; cualquier
divergencia detendra el push.

## Staging Supabase

El branch efimero limpio se reconstruyo hasta ledger `220` y paso:

- schema bootstrap, SQL/RLS bootstrap y dataset en orden canonico;
- topologia exacta `3 Clubs / 6 Teams / 6 Venues / 12 Pitches / 1 League /
  1 Tournament / 20 CanonicalMatches`;
- dos cuentas sinteticas y dos dispositivos autenticados;
- una carrera con un ganador y un `STALE`, revision canonica final `8`;
- replay idempotente, escritura directa denegada y cero `service_role` cliente;
- Realtime `SUBSCRIBED`, invalidacion, refetch y reconexion;
- flags nacidas OFF antes de activar exclusivamente el escenario sintetico.

ACL/readback: diez tablas Venue/Club Venue con RLS, cero grants de escritura
directa para clientes, invalidaciones de solo lectura con politicas anon/auth,
una publicacion Realtime, una exclusion de rango y dos indices parciales de
binding actual. Los comandos y flags solo tienen execute para
`authenticated/postgres/service_role`; el helper generico conserva cero execute
cliente y el helper estrecho de invalidacion tiene uno.

El control plane de dos branches efimeros conserva el rotulo
`MIGRATIONS_FAILED` de la primera automatizacion, aunque PostgreSQL esta
`ACTIVE_HEALTHY` y todos los readbacks pasan. Se registra como W9A-063,
incidencia externa no bloqueante, sin ocultarla ni mutar metadatos por rutas no
soportadas.

## Advisors

- Performance: 1.187 hallazgos, 1.186 INFO y 1 WARN.
- El unico WARN es un indice duplicado preexistente de
  `pachanga_player_rating_snapshots`; Wave 9A no toca Rating V2.
- Security: 612 hallazgos, 173 INFO, 439 WARN y 0 ERROR.
- Los WARN Wave 9A corresponden a RPC `SECURITY DEFINER` endurecidas o tablas
  cerradas con RLS y escritura cliente revocada; no se relajo ninguna ACL.
- Remediacion consultable en
  `https://supabase.com/docs/guides/database/database-linter` y
  `https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys`.

No existe una consulta Wave 9A que seleccione el ultimo snapshot solo mediante
`ORDER BY created_at DESC`; las selecciones usan secuencia, revision y/o ID
estable.

## Preview y PWA

La Preview reconstruida usa exactamente tres variables cifradas, limitadas a
la rama y al entorno Preview: URL Supabase, publishable key y marcador staging.
No existe variable Wave 9A en Production ni se agrego `service_role`.

La Preview protegida por SSO paso cinco rutas mediante transporte autenticado
de Vercel: manifest, Service Worker, manifest Demo V3.4, `/campos` y
`/reservas`. El Service Worker real responde `no-cache, no-store,
must-revalidate`, incluye V3.4/Campos/Reservas y no contiene cola offline de
escrituras. El mismo E2E completo certifico Auth, Realtime y convergencia.

## Rendimiento aislado

Corpus: 1.000 Venues, 5.000 Pitches, 50.000 reglas/excepciones, 100.000
requests, 50.000 reservas y 100.000 invalidaciones. P95: directorio 460.925 ms,
availability 5.079 ms, submit 8.405 ms, hold 119.891 ms, accept 63.657 ms,
conflict 64.711 ms, desk 28.500 ms, binding 4.653 ms, health 571.974 ms y
Control Center 755.617 ms. Rollback y cleanup: PASS. No se repitio tras cambios
solo documentales/tests porque SQL, autoridad e indices no cambiaron.

## Activacion prevista

Todas las flags nacen OFF. El release remoto seguira este orden: migraciones,
merge, deployment READY del SHA exacto, smoke inactivo, Venue Foundation,
Management, Availability, Requests, Counteroffers, Holds, Canonical
Reservations, Match Binding, R4D, perfiles/directorio publicos y Demo V3.4.
Pagos, recurrencia, asignacion masiva e integraciones externas permaneceran
OFF. La activacion se realizara solo mediante la RPC de plataforma.

## Pendiente para RELEASED

- reconciliar ledger productivo con `migration list --linked` y backup;
- aplicar exactamente las ocho migraciones y confirmar flags nacidas OFF;
- fusionar el PR y esperar deployment READY del SHA exacto;
- smoke con flags OFF, activacion por RPC y canary transaccional con ROLLBACK;
- readback final a cero, Demo V3.4, logs, Service Worker y responsive;
- retirar variables Preview, branches Supabase, procesos, temporales y worktree.

No se presentara este informe como `RELEASED` hasta disponer de esas evidencias.
