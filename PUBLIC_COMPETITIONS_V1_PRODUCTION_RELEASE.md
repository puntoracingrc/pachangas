# Public Competitions V1 - Production Release

## Estado

`LIVE / MERGED / DEPLOYED / CANARY CLEAN`

Wave 7A esta activa en produccion con autoridad PostgreSQL, publicacion
moderada, directorio y solicitudes controladas por flags. La evidencia que
sigue procede de GitHub, Vercel y readbacks directos de PostgreSQL; no presenta
como realizada la QA fisica que sigue pendiente.

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
| Main funcional final | `a8fa127901fcb32e60bd5cc096770f5ee1737a3d` |
| Produccion | `SCHEMA 183 / FLAGS WAVE 7A ACTIVE / revision 21` |

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

## Merge y deployment

- PR funcional: `#215`, fusionado sin reescribir migraciones;
- merge SHA: `a8fa127901fcb32e60bd5cc096770f5ee1737a3d`;
- deployment Vercel: `dpl_DGfk1Q9M5X9QXPmk2BMqmsdvikve`;
- URL exacta: `pachangas-phre49c5g-persianas-almar-web-s-projects.vercel.app`;
- target/estado: `production / READY`;
- aliases: `pachangasiq.com` y `www.pachangasiq.com`;
- Service Worker productivo: `2.0.0+sw.a8fa127901fc`;
- manifest y Service Worker: `200`, con politica `no-cache/no-store` para el
  worker y controller activo tras recarga.

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

## Activacion escalonada

Toda activacion paso por la RPC de plataforma con `operationId`, revision
esperada y secuencia de servidor. Cada ID aparece exactamente una vez en el
ledger de plataforma.

| Etapa | Operation ID | Revision | Sequence |
| --- | --- | --- | ---: |
| Foundation + publication | `e9cd07e2-1592-4937-bf67-310556c6da9b` | `17 -> 18` | 2611 |
| Discovery | `cefe548c-9172-4b29-9095-9974e27bf593` | `18 -> 19` | 2612 |
| Requests + waitlist | `a178595e-64e2-46d4-a408-b50244def6f2` | `19 -> 20` | 2613 |
| Read models publicos seguros | `b9e897f1-9a44-46c8-a929-db0ff996e971` | `20 -> 21` | 2614 |

Flags ON: foundation, publication, discovery, registration requests, waitlist,
calendar, results, standings, bracket, exception status y referees. Permanecen
OFF: discipline y autoaccept. Payments, billing, two-leg y double elimination
no se activaron.

El smoke previo devolvio el `503 PUBLIC_COMPETITION_DIRECTORY_UNAVAILABLE`
esperado con flags OFF. Tras discovery, el mismo endpoint devolvio `200` y un
directorio canonico vacio.

## Canary productivo

El canary uso un Team QA/demo sin usuarios nuevos. El bundle beta temporal,
Competition, Edition, regla, categoria, publicacion y cleanup pasaron por sus
RPC canonicas con revision esperada e IDs idempotentes distintos.

- ciclo: create -> submit -> approve -> publish -> anonymous read -> unpublish
  -> archive -> cancel -> revoke;
- separacion: propietario organizador y platform owner distintos;
- visibilidad: `UNLISTED`, `noindex` y ausente del directorio/sitemap;
- registro: `CLOSED`;
- privacidad anonima: sin email, telefono, attendance, evidencias ni motivos
  privados;
- resultado final: Competition `cancelled`, publication `archived`;
- evidencia: 16 eventos de Competition ordenados por `server_sequence`;
- residuos activos: 0 fixtures, 0 requests, 0 Entries, 0 slugs indexables y 0
  bundles/grants activos;
- notificaciones QA: tres avisos historicos, marcados como leidos mediante RPC;
- intentos fallidos previos: transacciones revertidas o Competition incompleta
  cancelada y grant revocado; cero superficie activa.

## Advisors productivos

El Advisor de seguridad devuelve 551 avisos globales revisados; las superficies
Wave 7A mantienen RLS y grants directos cerrados y exponen solo RPC/read models
intencionales. El Advisor de rendimiento devuelve 820 avisos globales preexistentes o
informativos: 588 FK sin indice, 230 indices aun sin uso, un indice duplicado y
un aviso de conexiones Auth. Para Wave 7A aparecen 18 FK informativas y 12
indices nuevos aun sin uso, coherente con su estreno sin datos publicos reales.

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

El readback posterior al canary devolvio exactamente los mismos ocho conteos y
digests. Rating V2, Rewards, Player Cosmetics, Team Cosmetics, Conduct, Billing
y Ranking no fueron modificados por Wave 7A.

PITR esta deshabilitado; WAL-G y backups fisicos estan disponibles. El backup
fisico anterior y el dump logico quedaron verificados como evidencia previa al
release; no fue necesario restaurar ni ejecutar rollback.

## Secuencia ejecutada

1. Se concilio `supabase migration list --linked`.
2. Se creo backup recuperable y se registro el baseline.
3. Se aplicaron exactamente las siete migraciones con flags naciendo OFF.
4. Se confirmaron ledger 183, hashes, ACL, indices y Advisors.
5. Se fusiono PR #215 y se espero el deployment READY del SHA exacto.
6. Se ejecuto el smoke inactivo.
7. Se activo escalonadamente mediante RPC de plataforma.
8. Discipline, autoaccept, payments, billing, two-leg y double elimination
   permanecieron OFF.
9. Se ejecuto y limpio el canary unlisted/noindex/closed sin usuarios nuevos.
10. Se verificaron Demo World V2.7, dominio, Service Worker y readback final.

## QA productiva

- `/`, `/competiciones` y `/demo`: HTTP/navegacion correctos;
- `/competiciones`: 1440x900, 390x844 y 844x390 sin overflow raiz, controles
  cortados, imagenes rotas, errores de consola ni excepciones de pagina;
- Demo V2.7: portrait y landscape limpios; escenarios Directorio, Liga publica,
  Torneo, Solicitudes, Waitlist, No listada, Organizador y Participante
  accesibles, con Liga publica navegable;
- PWA: manifest presente, Service Worker controller activo, shell recargable
  offline, fetch `no-store` bloqueado sin red y `200` tras reconexion;
- instalacion fisica Android/iPhone/PWA: `PENDING`, no declarada como PASS;
- Vercel: cero clusters de runtime error en dos horas;
- logs del deployment: `200/304`; el unico 503 del directorio corresponde al
  smoke deliberado con flags OFF. Los 503 restantes son la deuda separada y
  preexistente de Ranking `CRON_SECRET`.

## Rollback

No hay down migration. Antes de activar, rollback es mantener objetos instalados
con flags OFF. Despues de activar, desactivar via RPC de plataforma y hacer
roll-forward; no reabrir tablas ni convertir read models en autoridad. El
backup previo se conserva hasta cerrar smoke y readback.

Rollback ejecutado: **NO**. La ruta disponible sigue siendo desactivar mediante
RPC de plataforma y hacer roll-forward; nunca reabrir tablas ni convertir read
models en autoridad.

## Cierre

- Demo World V2.7: `LIVE`, hash de snapshot
  `e4830ff25db5318a169e0e8da5cf7ffb8820beee8616cc6e88e8cf6a05a2b7dd`;
- remote writes de Demo: `0`;
- ledger remoto: `183`, ultima migracion `20260828072053`;
- QA activa: 0 Competitions, 0 publications, 0 requests, 0 Entries, 0 slugs
  indexables y 0 grants/bundles del canary;
- locks finales: 0 waiting, 0 exclusive;
- Wave 7B: **NO INICIADA**;
- formatos avanzados: **NO INICIADOS**.
