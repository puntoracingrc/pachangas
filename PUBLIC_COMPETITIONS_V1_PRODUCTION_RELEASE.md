# Public Competitions V1 - Production Release

## Estado

`PRE-PRODUCTION GATES COMPLETE / PRODUCTION PENDING`

Este documento se incorpora al PR funcional para conservar el plan y la
evidencia previa. Se cerrara mediante un follow-up documental con SHA, ledger,
deployment, activacion, canary y cleanup realmente leidos de produccion. Ningun
campo pendiente de esta version se presenta como hecho.

## Baseline

| Dato | Valor |
| --- | --- |
| Main inicial | `8807ed66548b4b2ea749f46c27f71dcf855057f0` |
| PR funcional | `#215` |
| Branch | `codex/public-competitions-registration-v1` |
| Supabase | `Pachangas`, `qonbngfrnrqgmxbdfbea`, PostgreSQL 17.6, `ACTIVE_HEALTHY` |
| Ledger inicial esperado | `176` |
| Migraciones Wave 7A | `7`, forward-only |
| Ledger objetivo | `183` |
| Schema hash fresh/upgrade | `7273cef0f24cc4881179475c81c7196dde8d084c9af39316ecf250a33e8e708d` |
| Backup fisico previo | `1499793836`, `COMPLETED`, `2026-08-28T00:18:34.331Z` |
| Dump logico previo | `5,088,476 bytes`, SHA-256 `841d39ca9b5d0b1bbb3266ce220f9f5ee48364461ba110c4750aa590fa2a837a` |
| Produccion | `NO MODIFICADA AUN POR WAVE 7A` |

## Migraciones candidatas exactas

| Version | Archivo | SHA-256 local |
| --- | --- | --- |
| `20260828072045` | `tournament_knockout_fk_index_hardening_v1` | `db8d7a7bffc1b62da6ad2dec6b5ee15d1ad79109cded21dbfe3ae96535d6b8ba` |
| `20260828072047` | `public_competition_publication_consent_v1` | `5b3af13d8c06ef81fd12775a3fc6832039d6d605dfdd0d786feb24fd81e83354` |
| `20260828072048` | `competition_registration_requests_waitlist_v1` | `a7ca9f1eecbcc92a921d430604535708ca3a569193e0863f74a6a2bb69d4fdb0` |
| `20260828072049` | `public_competition_read_models_directory_v1` | `e843355c3a2451b8a5ec0d456acf60650330335ce7256e8dfc5f0faf75b50f1f` |
| `20260828072051` | `public_competition_commands_authority_v1` | `2be871788dbdddc48f9146bdb13c9ff3b201720a92c2883a72101ab17751478b` |
| `20260828072052` | `public_competition_access_realtime_v1` | `b260bd893692f49872f679f83eaa9d7d06f7af56a22bbc0fd3c16b42d1ccfc09` |
| `20260828072053` | `public_competition_product_flags_hardening_v1` | `843c10208a7f8de8b3564c6a4fb713f2f636efb45e6319b764bd29b6ccc076b5` |

## Gates previos

- local: 593/593, typecheck/build/focused lint/diff-check PASS;
- staging ledger: 176 -> 183;
- League y Tournament E2E autenticados: PASS;
- RLS, privacy, idempotency, concurrencia y Realtime: PASS;
- escala solicitada y rollback: PASS;
- Preview exacta `dpl_Bsfej2bpJrpWETSXLKPozFcbS6kV`: READY;
- Service Worker exacto: `2.0.0+sw.15049e0ee32f`;
- visual: ocho viewports, 0 overflow raiz, 0 imagenes rotas, 0 consola;
- PWA instalada fisica: PENDING, no es bloqueo autorizado de esta release.

## Baseline productivo protegido

El readback por Management API confirma database `postgres`, 176 migraciones y
ultima version `20260828045324`. Existen tres Competitions y tres Editions, con
cero CompetitionEntries y cero canonical match contexts.

| Dominio protegido | Filas | Digest previo |
| --- | ---: | --- |
| Rating snapshots | 1 | `ce838b082d476871c05aa6df5cdf589c` |
| Reward grants | 17 | `f8c950d847b867804d4b51b9cee70971` |
| Player cosmetic loadouts | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Team cosmetic inventory | 7 | `e5a3c62aa06218156930e31eab7cab7d` |
| Team reward mappings | 5 | `43ec6570d18b53b719152b81445a991e` |
| Conduct reports | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Billing webhooks | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Provincial ranking entries | 0 | `d41d8cd98f00b204e9800998ecf8427e` |

PITR esta deshabilitado; WAL-G y backups fisicos estan disponibles. El backup
fisico anterior y el dump logico se conservaran hasta terminar canary y
readback final.

## Secuencia de produccion

1. Conciliar `supabase migration list --linked`.
2. Crear backup recuperable y registrar baseline.
3. Aplicar exactamente las siete migraciones con flags naciendo OFF.
4. Confirmar ledger 183, hashes, ACL, indices y Advisors.
5. Fusionar PR #215 y esperar deployment READY del SHA exacto.
6. Hacer smoke inactivo.
7. Activar escalonadamente mediante `set_pachanga_public_competition_flags_v1`.
8. Mantener discipline, autoaccept, payments, billing, two-leg y double
   elimination OFF.
9. Ejecutar canary unlisted/noindex/closed sin usuarios reales y limpiarlo.
10. Verificar Demo World V2.7, dominio, Service Worker y readback final.

## Rollback

No hay down migration. Antes de activar, rollback es mantener objetos instalados
con flags OFF. Despues de activar, desactivar via RPC de plataforma y hacer
roll-forward; no reabrir tablas ni convertir read models en autoridad. El
backup previo se conserva hasta cerrar smoke y readback.

## Campos a cerrar tras produccion

- main final y merge SHA;
- backup y baseline exactos;
- ledger remoto y hashes;
- deployment Vercel y dominio;
- operacion/revision/secuencia de flags;
- canary y conteos finales;
- Demo V2.7 LIVE;
- cleanup de staging, Preview, temporales y worktree.
