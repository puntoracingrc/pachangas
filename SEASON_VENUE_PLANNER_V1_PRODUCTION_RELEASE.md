# Season Venue Planner V1 Production Release

Estado: `RELEASED / ACTIVE / PRODUCTION VERIFIED`

| Campo | Valor |
| --- | --- |
| fecha | `2026-08-31` |
| main inicial | `592a3dcc1147df41fb05c21703f131e66fc75a0a` |
| HEAD certificado | `0f5d25f0b4bd135f84b9faf7fae58bfcacab5ab7` + cierre documental/test |
| rama | `codex/recurring-venue-bulk-allocation-v1` |
| PR funcional | `#239`, fusionado |
| main funcional | `78551dd6d2edef514c47fe45d8cb2ace3c76e79c` |
| deployment funcional | `dpl_BMxWwYUMnnRNFcjgYrF3zk65oHgF`, `READY` |
| dominio | `https://pachangasiq.com` |
| migraciones | 8 forward-only, `220 -> 228` |
| schema hash | `7b9a69ed794f9f71dc0a0efc91c9ae75b20f79fef9c4261eb5c19a4a1d0fee12` |
| Preview exacta certificada | `0f5d25f`, retirada tras QA |
| staging Supabase | efimero `r9`, certificado y retirado |
| entidades reales | `0` |
| Stripe | `UNTOUCHED` |

## Migraciones candidatas

| Version | Nombre | SHA-256 |
| --- | --- | --- |
| `20260830223000` | `venue_recurring_reservation_series_v1` | `eec9e1bc0414bdf560015a754223d6295ed0cdb6ef975793c03f2c40ae941ff9` |
| `20260830223002` | `competition_venue_pool_authorization_v1` | `0276e1c098d84fcd47aa83285c0f9720e0aaefd92e4602eab7dd29b114cb49e5` |
| `20260830223004` | `competition_venue_allocation_plans_v1` | `d05d57daf9bc6c372a9a95e334a39f22f32dadba9c0d4edd96f7c2fa9dbbf7ee` |
| `20260830223006` | `competition_venue_allocation_constraints_quality_v1` | `42a56d9d6e82461effbef924616bfa84d5ea217325ac24bde5bdcdf439e9886b` |
| `20260830223008` | `competition_venue_allocation_engine_commands_v1` | `31bbc04f54c34daf4301de5c2e02ff228afa4660a25db893bf1a12b02e86a5b5` |
| `20260830223010` | `competition_venue_allocation_publication_v1` | `98623c20f628ce620cc24d7110f1b3fb1158aee5d9dafbde65858e49ff04fe3c` |
| `20260830223012` | `competition_venue_allocation_read_models_v1` | `848707c198f3088a923948ceb888c3af74a20922afc396f5f5adb31661da2aad` |
| `20260830223014` | `competition_venue_allocation_hardening_flags_v1` | `5bb88409be381e517824121ba6e508bfdd4788dbd97ba0af9453c22020f6d036` |

Las 220 migraciones historicas permanecen intactas. Fresh bootstrap y upgrade
producen el mismo esquema. Todos los flags nuevos nacieron OFF y se activaron
despues del deployment mediante la RPC canonica de plataforma.

## Staging autenticado

Rama limpia con ledger 228, hash exacto y dataset sintetico
`3 Clubs / 12 Teams / 120 jugadores / 6 arbitros / 6 Venues / 12 Pitches /
1 Liga / 1 Torneo / 50 Matches`.

Dos usuarios/dispositivos recorrieron pool, serie, materializacion, freeze,
automatico, manual, hibrido, hold concurrente, validacion, publicacion,
reservas, bindings, cancelacion, reemplazo R4D, reconfirmacion arbitral,
Realtime, refetch y reconexion. Resultado: `PASS`, cero duplicados y cero
cambios de horario. La rama Supabase y sus identidades sinteticas se retiraron
despues del release.

## Gates locales

| Gate | Resultado |
| --- | --- |
| `npm ci` | `PASS`; advisories preexistentes, sin cambio de dependencias |
| suite global | Node `20/20` + TS/TSX `689/689` = `709/709 PASS` |
| fail/skipped/todo/cancelled | `0/0/0/0` |
| focal Demo V3.4/V3.5 | `10/10 PASS` |
| focal Wave 9B | `5/5 PASS` |
| typecheck | `PASS` |
| build | `PASS`, 69 paginas estaticas |
| lint focal/global | `PASS / PASS`, 0 errores y 0 warnings |
| SQL/RLS/idempotencia | `PASS` |
| concurrencia | `PASS`, seis carreras y un ganador por carrera |
| escala | `PASS`, no repetida tras cambios solo de test/documentacion |
| secret scan | `PASS`, cero hallazgos en workspace, bundle, diffs y temporales |
| `git diff --check` | `PASS` en el checkpoint previo; se repite antes del commit |

El baseline era `699/699`; Wave 9B anade diez pruebas netas y no elimina
cobertura. El unico Advisor no corregido es el indice redundante del baseline
historico en staging (`W9B-116`), fuera de las ocho migraciones Wave 9B.

## Release productivo

- backup previo recuperable verificado mediante restauracion desechable;
- ocho migraciones aplicadas en orden, con ledger repositorio/local/remoto
  `228/228/228`, ultima version `20260830223014` y cero drift;
- 19 tablas Wave 9B, 37 indices validos, 12 read models autenticados y RLS/ACL
  confirmados directamente en PostgreSQL;
- los diez flags Wave 9B quedaron `ON` mediante
  `set_pachanga_venue_flags_v1`; readback final revision `18`, server sequence
  `121`;
- canary productivo sobre motores reales: `WAVE9B_PRODUCTION_CANARY_PASS`, seis
  Matches, siete revisiones de reserva, seis bindings activos, `ROLLBACK` y
  readback cero en 42 familias;
- Realtime publica invalidaciones canonicas en
  `pachanga_venue_invalidations`; los clientes releen snapshots y no aplican el
  payload WAL como autoridad;
- smoke en `1440x900`, `390x844` y `844x390`: cero overflow, imagenes rotas o
  errores de consola; Demo V3.5 confirma `128` Matches, `127` reservas, `126`
  bindings y `1` no asignado;
- manifest y Service Worker productivos verificados; Demo V3.5 carga desde
  cache offline y converge tras reconexion;
- logs del deployment: solo `200/304`, sin `4xx` o `5xx` inesperados;
- branch Supabase efimero, deployment Preview y variables Preview de rama:
  retirados.

## Estado final

| Superficie | Estado |
| --- | --- |
| recurring series y materialization | `ON` |
| Venue Pools y allocation foundation | `ON` |
| automatic, manual, hybrid, holds y publish | `ON` |
| Demo World V3.5 | `ON` |
| Wave 9A reservations/bindings y R4D | `ON`, preservados |
| joint schedule/venue optimization | `OFF` |
| venue payments, public recurring sales, external calendar/integrations | `OFF` |
| Stripe | `UNTOUCHED` |
| entidades, avisos o cobros reales creados por QA | `0 / 0 / 0` |
| Android, iPhone y PWA instalada fisica | `PENDING` |

No se recalculo ni modifico Rating, Billing, disciplina, resultados, horarios
deportivos ni autoridad arbitral fuera de la reconfirmacion R4D certificada.
