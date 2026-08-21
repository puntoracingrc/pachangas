# Club Foundation V1 Report

Estado: `PREVIEW PENDING`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Rama | `codex/club-foundation-v1` |
| Base real | `82fbb7933b51a5cef3267ae71e1ca8dc9f63cd8c` |
| PR | [#155](https://github.com/puntoracingrc/pachangas/pull/155) (draft) |
| Inicio R2 | `2026-08-21` |
| Cierre local documentado | `2026-08-21 16:45 CEST` |
| Entorno local | Worktree aislado, Node 24, PostgreSQL/Supabase local dedicado |
| Supabase staging | `iozcjirlfytryzrcmrnq`, upgrade `106 -> 110` y E2E completados |
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
| `20260821141114` | Entidad Club, ownership, memberships, invitaciones seguras, relaciones Club-Team, receipts, eventos, RLS, read models e invalidaciones. |
| `20260821141121` | Organizer adapter TEAM/CLUB, integridad XOR, entitlements Club y command V2 compatible con R1. |
| `20260821141129` | Flags y operaciones de plataforma, Control Center, busqueda global y capabilities `clubs.read`/`clubs.manage`. |
| `20260821142109` | Hardening forward-only: el token de invitacion solo puede salir de `membership.invite`. |

Las migraciones R1 `20260821054224`, `20260821054225`, `20260821054227`,
`20260821074741`, `20260821075245` y `20260821082136` no se modifican. El
bootstrap local desde cero aplica `110` migraciones y termina en
`20260821142109` con `BOOTSTRAP_COMPLETE`. Al aplicar inicialmente por la API de
Supabase, staging asigno estas tres versiones UTC; los archivos locales
provisionales se renombraron antes de continuar para que repositorio y ledger
remoto sean identicos. No se altero el SQL ya ejecutado.

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
| Fresh bootstrap | PASS, `110` migraciones y `BOOTSTRAP_COMPLETE` |
| Upgrade desde ledger productivo | PASS en staging, `106 -> 110` forward-only |
| E2E autenticado Club staging | PASS, dos clientes, permisos, privacidad, notificaciones y Realtime/refetch |
| E2E TEAM R1 sobre staging R2 | PASS, compatibilidad completa |
| Escala | PASS, 1.000 Clubs, 10.100 memberships, 5.000 links, 10.000 invitaciones y 500 Competition drafts |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, Next.js genera `35/35` paginas |
| ESLint focalizado | PASS |
| ESLint global | Deuda heredada: `43` hallazgos (`23` errores, `20` warnings), ninguno en rutas R2 |
| DB lint R2 | PASS, `0` findings R2; deuda heredada fuera de alcance |
| `git diff --check` | PASS |

## Rendimiento local

| Medicion | p50 | p95 |
| --- | ---: | ---: |
| Admin Clubs | `16.631 ms` | `26.271 ms` |
| Club read model | `1.591 ms` | `2.031 ms` |
| Organizer CLUB | no registrado | `0.703 ms` |
| Invitation accept | `2.787 ms` | `3.447 ms` |
| Team relationship lookup | no registrado | `0.023 ms` |

Los indices R2 ocupan `6,275,072` bytes en la carga representativa. Los arrays
del read model estan acotados y ordenados de forma estable: memberships e
invitaciones `200`, relaciones `200`, competitions `100`, Clubs del actor `50`
y sus invitaciones pendientes `100`.

## Staging y limpieza

El recorrido autenticado cubrio alta, aprobacion, staff registrado/email,
tokens invalidos/expirados/revocados/reutilizados, invitacion y solicitud de
Team, rechazo, cancelacion, finalizacion, multi-Club, transferencia de owner,
partnership, grants, expiry/revocation y creacion CLUB. Realtime entrego una
invalidacion y ambos clientes convergieron mediante refetch. La repeticion R1
TEAM paso despues de la limpieza R2.

Estado final del staging aislado:

- flags R1 y R2: todos `false`;
- Clubs fixture activos: `0`;
- invitaciones pendientes: `0`;
- relaciones actuales: `0`;
- grants Club activos: `0`;
- assignments Competition fixture activos: `0`;
- `32` Clubs de ejecuciones QA quedan archivados, sin autoridad ni capacidad.

## Advisors

Security mantiene hallazgos informativos intencionados para tablas R2 con RLS
sin politicas de escritura directa: los grants cliente estan revocados y el
acceso se realiza exclusivamente por RPC canonica. Las funciones
`SECURITY DEFINER` autenticadas son la frontera autoritativa, fijan
`search_path` y resuelven actor/capabilities en servidor. La policy de
invalidaciones solo entrega eventos RLS-scoped y no snapshots privados.

Performance informa FKs auxiliares sin indice e indices todavia no usados. La
carga representativa no justifico indices especulativos: todos los p95 R2
quedaron por debajo de `27 ms`; se conserva el warning para observarlo cuando
exista trafico real.

## Pendiente antes de READY FOR REVIEW

- Preview Vercel del HEAD final y matriz visual/PWA solicitada.

Produccion modificada: **NO**. Supabase produccion: **NO**. Merge: **NO**.
