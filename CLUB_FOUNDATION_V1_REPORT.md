# Club Foundation V1 Report

Estado: `STAGING PENDING`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Rama | `codex/club-foundation-v1` |
| Base real | `82fbb7933b51a5cef3267ae71e1ca8dc9f63cd8c` |
| PR | [#155](https://github.com/puntoracingrc/pachangas/pull/155) (draft) |
| Inicio R2 | `2026-08-21` |
| Cierre local documentado | `2026-08-21 16:08:17 CEST` |
| Entorno local | Worktree aislado, Node 24, PostgreSQL/Supabase local dedicado |
| Supabase staging | `iozcjirlfytryzrcmrnq`, pendiente de aplicar R2 |
| Supabase produccion | `qonbngfrnrqgmxbdfbea`, no modificado |
| Merge | No realizado |

El checkout principal tenia cambios ajenos y no se utilizo para implementar R2.
Este worktree debe conservarse mientras el PR no este fusionado.

## Alcance

R2 crea un agregado `Club` independiente de `pachanga_groups`. Un Club conserva
identidad, perfil, ownership, staff, invitaciones, relaciones con equipos,
estados de verificacion y partnership, entitlements de Competition, read models,
invalidaciones Realtime y auditabilidad propia. No absorbe owners, admins,
jugadores, partidos, Rating ni historial de un equipo.

Permanecen fuera: campos, reservas, arbitros, inscripciones, jornadas,
calendarios, clasificaciones, disciplina, League/Tournament Engine, pagos,
premios y cosmeticos de competicion. R2 tampoco modifica Demo World, ranking,
CRON, Canonical Match ni datos productivos.

## Migraciones forward-only

| Version | Contenido |
| --- | --- |
| `20260821124120` | Entidad Club, ownership, memberships, invitaciones seguras, relaciones Club-Team, receipts, eventos, RLS, read models e invalidaciones. |
| `20260821124124` | Organizer adapter TEAM/CLUB, integridad XOR, entitlements Club y command V2 compatible con R1. |
| `20260821124128` | Flags y operaciones de plataforma, Control Center, busqueda global y capabilities `clubs.read`/`clubs.manage`. |

Las migraciones R1 `20260821054224`, `20260821054225`, `20260821054227`,
`20260821074741`, `20260821075245` y `20260821082136` no se modifican. El
bootstrap local desde cero aplica `109` migraciones y termina en
`20260821124128` con `BOOTSTRAP_COMPLETE`. El upgrade remoto se validara sobre
el ledger staging de `106` antes de declarar R2 revisable.

## Modelo Club

### Identidad y perfil

- Tipos: `FOOTBALL_CLUB`, `SPORTS_CENTER`, `ASSOCIATION`,
  `INDEPENDENT_ORGANIZER`, `OTHER`.
- Estado operativo: `draft`, `pending_review`, `active`, `suspended`,
  `rejected`, `archived`.
- Verificacion independiente: `unverified`, `pending`, `verified`, `rejected`,
  `revoked`.
- Partnership independiente: `none`, `candidate`, `active`, `paused`, `ended`.
- Visibilidad: `private`, `unlisted`, `public`.
- Ubicacion publica limitada a pais, provincia, municipio y zona general.
- `place_id`, web y referencia de logo permanecen datos de perfil; no se crea
  un pipeline de almacenamiento paralelo.

Crear el Club requiere usuario autenticado, email verificado y flags activos.
La transaccion crea el Club draft y su membership `club_owner`, de modo que no
pueda existir sin owner. Se limita a tres Clubs draft/pending por creador y
cinco creaciones en 24 horas; slug, nombre y payload estan acotados.

### Perfil publico y privacidad

`/clubes/[slug]` usa el read model publico minimizado y solo responde cuando el
Club es `active`, `public` y los flags foundation/public estan activos. Expone
nombre, slug, descripcion, tipo, zona general, badges seguros y equipos activos
con `show_on_club_profile=true`.

No expone emails, telefonos, UUID de Auth, staff, invitaciones, tokens,
entitlements, receipts, audit ledger ni motivos internos. La ruta permanece
`noindex,nofollow` y fuera de navegacion publica en R2.

### Flags

- `club_foundation_enabled`
- `club_self_service_creation_enabled`
- `club_team_relationships_enabled`
- `club_public_profiles_enabled`
- `club_competition_organizer_enabled`

Todos nacen `false`; los flags subordinados requieren foundation. Staging los
puede activar durante QA y debe restaurarlos a `false`.

## Autoridad, RLS y sincronizacion

Todas las escrituras usan `operationId`, `expectedRevision`, `action`, `payload`
y `clientMetadata`. PostgreSQL resuelve `auth.uid()`, rol, estado, capability,
entitlement, reloj, revision y secuencia. Una revision obsoleta devuelve
`STALE_REVISION`; reutilizar la clave con otro payload devuelve conflicto.

`anon` y `authenticated` no tienen INSERT/UPDATE/DELETE directo sobre tablas R2.
Las funciones `SECURITY DEFINER` fijan `search_path`, cualifican referencias y
no aceptan actor del navegador. Events y receipts son inmutables y ordenados por
`server_sequence`.

Realtime publica invalidaciones acotadas por RLS. El cliente invalida su cache
y solicita el snapshot canonico; no aplica WAL ni estado optimista como verdad.
Las APIs privadas usan `no-store`. Las operaciones se clasifican como escrituras
protegidas por el bridge PWA y offline nunca confirma acciones deportivas.

## Superficies

| Ruta | Uso |
| --- | --- |
| `/laboratorio-club-foundation` | Recorrido interno del flujo R2 en staging. |
| `/admin/clubs` | Control Center de Clubs, estados, staff, links, grants, competiciones y eventos. |
| `/clubes/[slug]` | Perfil publico minimizado, gated y no indexable en R2. |

La busqueda global de plataforma incorpora nombre, slug, municipio, owner y
equipo vinculado sin buscar ni devolver emails privados.

## Invariantes fuera de alcance

La auditoria estatica y las pruebas SQL confirman que las migraciones R2 no
escriben Rating V2, facetas, fiabilidad, partidos, resultados, participantes,
goleadores, Attendance, rewards, cajas, puntos, cosmeticos, Conduct, Billing,
Season Score, rankings, Canonical Match ni Demo World. Partnership no concede
entitlement implicitamente y una Competition draft de Club no crea partidos.

## Evidencia local

| Gate | Resultado |
| --- | --- |
| Tests de producto | PASS, `308/308` |
| SQL/RLS Club | PASS |
| SQL adversarial | PASS |
| Regresion SQL R1 TEAM | PASS |
| Idempotencia | PASS |
| Concurrencia Club | PASS, un ganador + un stale en seis carreras |
| Concurrencia TEAM R1 | PASS al ejecutarse serialmente |
| Fresh bootstrap | PASS, `109` migraciones |
| Escala | PASS, 1.000 Clubs, 10.100 memberships, 5.000 links, 10.000 invitaciones y 500 Competition drafts |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, incluido en `npm test` |
| ESLint focalizado | PASS |
| DB lint R2 | PASS, `0` findings R2; deuda heredada fuera de alcance |
| `git diff --check` | PASS |

## Rendimiento local

| Medicion | p50 | p95 |
| --- | ---: | ---: |
| Admin Clubs | `15.734 ms` | `26.289 ms` |
| Club read model | `1.638 ms` | `2.164 ms` |
| Organizer CLUB | no registrado | `0.694 ms` |
| Invitation accept | `2.802 ms` | `3.667 ms` |
| Team relationship lookup | no registrado | `0.021 ms` |

Los indices R2 ocupan `6,356,992` bytes en la carga representativa. Los arrays
del read model estan acotados y ordenados de forma estable: memberships e
invitaciones `200`, relaciones `200`, competitions `100`, Clubs del actor `50`
y sus invitaciones pendientes `100`.

## Pendiente antes de READY FOR REVIEW

- Upgrade staging `106 -> 109` y E2E autenticado completo.
- Repeticion del E2E TEAM R1 en el esquema R2.
- Advisors Security/Performance y clasificacion de hallazgos.
- Limpieza y verificacion de fixtures/flags staging.
- Preview Vercel del HEAD final y matriz visual/PWA solicitada.
- Actualizacion de este informe con HEAD, deployment y resultados finales.

Produccion modificada: **NO**. Supabase produccion: **NO**. Merge: **NO**.
