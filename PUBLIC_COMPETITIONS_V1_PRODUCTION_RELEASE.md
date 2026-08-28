# Public Competitions V1 - Production Release

## Estado

`MIGRATIONS APPLIED / FLAGS OFF / MERGE PENDING`

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
| Produccion | `SCHEMA 183 / FLAGS WAVE 7A OFF` |

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

## Migracion productiva

El push vinculado aplico una sola vez las siete migraciones revisadas y termino
con codigo cero. El aviso posterior del cache opcional `pg-delta` no se uso
como evidencia ni provoco un reintento. El readback independiente confirma:

- ledger `176 -> 183`, ultima version `20260828072053`;
- las siete versiones aparecen emparejadas en
  `supabase migration list --linked`;
- los siete indices R6C estan `valid` y `ready`;
- las nueve tablas nuevas estan vacias y con RLS activa;
- `anon` y `authenticated` no tienen lectura ni escritura directa en ellas;
- invalidaciones Realtime y diez triggers de refresco canonico presentes;
- cero locks en espera y cero locks exclusivos;
- todos los flags Wave 7A nacieron OFF.

| Version | Nombre remoto | Sentencias | Hash remoto de sentencias |
| --- | --- | ---: | --- |
| `20260828072045` | `tournament_knockout_fk_index_hardening_v1` | 11 | `24540e86ab6d0dd9f3deb75de703361413b5199bcb9a1e5552a8bcf994220d4d` |
| `20260828072047` | `public_competition_publication_consent_v1` | 17 | `2dd031853b5de562e236e394bb1b4ec2a84d3d294095f971362230809e80aa32` |
| `20260828072048` | `competition_registration_requests_waitlist_v1` | 18 | `4881909abd2b193c4b7aedff30dcd0c66dbb85a2d3f58288743e544dc8075412` |
| `20260828072049` | `public_competition_read_models_directory_v1` | 39 | `e3d88c3c3daa0a873e46570783d843cab370beef7a88f6ecacded9916572430d` |
| `20260828072051` | `public_competition_commands_authority_v1` | 45 | `6730867af9f2aba8b173e946168c4e98419948114760fde28e4f2c31340296f3` |
| `20260828072052` | `public_competition_access_realtime_v1` | 28 | `b504e40c9e89b047a04d4ed36af9b55eca1aa232829f6dda29950133c3bc5cb6` |
| `20260828072053` | `public_competition_product_flags_hardening_v1` | 20 | `03a1443f3df6847c083e58160280e55f6bf49b365db5a1ee5972ce2bd09ede25` |

## Advisors productivos

El Advisor de rendimiento devuelve 820 avisos globales preexistentes o
informativos: 588 FK sin indice, 230 indices aun sin uso, un indice duplicado y
un aviso de conexiones Auth. Para Wave 7A aparecen 18 FK informativas y 12
indices nuevos aun sin uso, coherente con tablas vacias y flags OFF.

Los dos avisos R6C residuales corresponden a `source_group_id` y
`resolved_entry_id` de `pachanga_tournament_bracket_slots`. No existe una ruta
productiva que entre por esas columnas: los flujos auditados filtran primero
por `bracket_template_id`, cuyo indice ya cubre el acceso. Por tanto, la deuda
R6C accionable permanece en `0`; no se crean indices redundantes para maquillar
el Advisor.

Los avisos de seguridad RPC-only permanecen revisados: RLS deny-by-default,
grants directos revocados, `auth.uid()` y capabilities resueltos en PostgreSQL,
`search_path` fijo y read models publicos sin PII. Referencias de remediacion:
[RLS sin policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[Security Definer anon](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) y
[Security Definer authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

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
