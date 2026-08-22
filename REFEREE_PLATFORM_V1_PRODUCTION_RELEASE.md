# Referee Platform V1 - Production Release

## Estado

- Fecha UTC: `2026-08-22`.
- Resultado: `DEPLOYED / INACTIVE`.
- Proyecto Supabase: `qonbngfrnrqgmxbdfbea` (`Pachangas`, `eu-west-1`, `ACTIVE_HEALTHY`).
- PostgreSQL: `17.6` (`17.6.1.147`).
- Produccion web: <https://pachangasiq.com>.
- Official UI V2 incluida en esta release: **NO**.
- Datos R3 creados para QA en produccion: **NO**.

## Git y despliegue

| Evidencia | Valor |
| --- | --- |
| `main` inicial | `da6dace3a1a5d20de9fdba0d34174f916a2b2c61` |
| PR funcional | [#157](https://github.com/puntoracingrc/pachangas/pull/157) |
| HEAD funcional | `557423b4b9ed6e0eac65bc5184d520f26c83610e` |
| Metodo de merge | squash |
| Merge SHA / `main` funcional | `0131675725988b04c9876553407bffd50120d3d1` |
| Deployment Vercel | `dpl_CGzJECgarR59JW58KPcRUfa1UUVt` |
| Deployment URL | `pachangas-5jj3dr4k1-persianas-almar-web-s-projects.vercel.app` |
| Estado / alias | `READY` a `2026-08-22T04:30:22Z`; `pachangasiq.com` y `www.pachangasiq.com` |
| PR documental | Pendiente de asignacion al crear este informe |

La rama remota y el worktree funcional R3 se conservaron tras el merge porque
Official UI V2 (#158) seguia apilada sobre `codex/referee-platform-v1`.

## Backup y ledger

Antes de aplicar DDL se verifico el backup fisico recuperable de produccion:

- backup id `1441599482`;
- `status=COMPLETED`;
- `is_physical_backup=true`;
- timestamp `2026-08-22T00:17:26.153Z`;
- WAL-G habilitado; PITR no habilitado en el plan actual.

`supabase migration list --linked` y la API de Management coincidieron antes y
despues. No existia divergencia entre repositorio y remoto.

| Paso | Ledger | Resultado |
| --- | ---: | --- |
| Previo | 110 | Ninguna version R3 presente |
| `20260821182105_referee_platform_foundation_v1.sql` | 111 | Aplicada en su propia transaccion |
| `20260821182106_referee_club_assignment_authority_v1.sql` | 112 | Aplicada en su propia transaccion |
| `20260821182107_referee_platform_access_v1.sql` | 113 | Aplicada en su propia transaccion |

SHA-256 byte a byte:

- `20260821182105`: `2052a818ba981bcca39d722649a61b5715b175abe0b790de3ede8e24d6382493`;
- `20260821182106`: `23a30eca0218cc153f5ef0df70310a0d0337ae67f9b8d71fe7e3c76e1a4181f5`;
- `20260821182107`: `7d7d1bdff0e4957b45c5aceb9379f46d303b6fa3f45c9e450fbdfd4ff6cf787d`.

No se edito, renombro ni reordeno ninguna de las tres migraciones.

## Revalidacion del HEAD

Validaciones ejecutadas sobre `557423b4b9ed6e0eac65bc5184d520f26c83610e`:

- `npm ci`: PASS, Node `v24.16.0`;
- `npm test`: PASS, `326/326`; build integrado PASS, 37 rutas;
- `npm run typecheck`: PASS;
- `npm run build`: PASS;
- R3 focal: `18/18`;
- SQL/RLS, adversarial, idempotencia y concurrencia R3: PASS;
- R1 regression: TypeScript `15/15`, DB y concurrencia PASS;
- R2 regression: TypeScript `19/19`, DB/adversarial y concurrencia PASS;
- PWA focal: `14/14`;
- fresh bootstrap desde cero: 113 migraciones PASS;
- upgrade desde el ledger productivo: `110 -> 113` PASS;
- escala: 10k perfiles, 50k modalidades, 50k zonas, 20k relaciones,
  100k assignments, 100k ventanas y 10k snapshots dentro de umbrales;
- lint focalizado R3: PASS;
- lint global: 43 incidencias preexistentes (23 errores y 20 warnings), sin
  incremento atribuible a R3;
- `git diff --check`: PASS;
- diff funcional: 43 rutas, sin Official UI V2 ni cambios ajenos al dominio R3.

## Flags y datos

Los seis flags quedaron en `false`, revision 1:

- `referee_foundation_enabled`;
- `referee_self_service_enabled`;
- `referee_public_profiles_enabled`;
- `referee_marketplace_enabled`;
- `referee_club_relationships_enabled`;
- `referee_assignments_enabled`.

| Entidad R3 | Filas finales |
| --- | ---: |
| Perfiles | 0 |
| Modalidades | 0 |
| Zonas de servicio | 0 |
| Ventanas de disponibilidad | 0 |
| Excepciones de disponibilidad | 0 |
| Listados de Mercado | 0 |
| Relaciones Club-arbitro | 0 |
| Invitaciones | 0 |
| Secretos de invitacion | 0 |
| Assignments | 0 |
| Snapshots estadisticos | 0 |
| Receipts | 0 |
| Events | 0 |
| Invalidations | 0 |

No se creo perfil, relacion, invitacion, propuesta, assignment, partido
canonico, estadistica ni invalidacion de prueba en produccion.

## Canonical Match y disciplina

- `canonical.backfill` no se ejecuto.
- Estado: `NOT_INITIALIZED` (`initialized_at=null`).
- Canonical matches: 0.
- Bindings: 0.
- Reviews: 0.
- Backfills: 0.
- DisciplinaryEvent, amarillas, rojas, azules y sanciones: 0.
- El contrato de snapshots mantiene `discipline_stats_status=NOT_AVAILABLE` y
  contadores disciplinarios `null`.

## RLS, ACL y RPC

- Todas las tablas R3 publicas tienen RLS habilitado.
- `anon` y `authenticated` tienen 0 permisos directos INSERT/UPDATE/DELETE.
- `anon` y `authenticated` tienen 0 acceso SELECT al schema privado.
- Ambos roles carecen de `USAGE` sobre `private`.
- La unica policy de invalidaciones es SELECT para `authenticated`, acotada por
  usuario, perfil, Club, grupo o capability.
- Las RPC de escritura R3 tienen `anon execute = false`.
- Las RPC cliente previstas tienen `authenticated execute = true`; la purga de
  contactos permanece solo para autoridad de servicio.
- Las 35 funciones R3 `SECURITY DEFINER` tienen `search_path=pg_catalog`.
- Actor, capabilities, revision, binding canonico, idempotencia y reloj se
  resuelven en servidor; ninguna RPC de escritura acepta `actorId` autoritativo.

Las dos lecturas anonimas intencionales son los flags publicos y el perfil
publico. Con flags OFF devuelven un gate cerrado; no exponen escritura.

## Seguridad de invitaciones

- El secreto se almacena solo como `token_hash` de 64 caracteres.
- La tabla privada no concede SELECT a `anon` ni `authenticated`.
- No existe ninguna columna token en tablas R3 fuera de la tabla de secretos.
- Events y receipts contienen 0 claves token.
- El token plano solo puede aparecer en la primera respuesta autorizada del
  comando de invitacion; no entra en Realtime, notificaciones ni replay.
- Produccion termino con 0 invitaciones y 0 secretos.

## Realtime y capabilities

`public.pachanga_referee_invalidations` esta incluida en
`supabase_realtime`, con RLS y 0 filas.

No se elimino ninguna capability previa. Cambios:

- `platform_owner`: añade `referees.read`, `referees.manage`,
  `referees.health.read`;
- `platform_admin`: añade las mismas tres;
- `support`: añade `referees.read`;
- `ops`: añade `referees.health.read`;
- `moderator` y `finance`: sin cambios.

`rankings.write`, Ranking, Competition, Club, Billing, moderacion, flags y
auditoria permanecen presentes en sus roles previos. La cuenta
`puntoracingrc@gmail.com` continua activa como unico `platform_owner` previsto
y no recibio perfil arbitral, relacion ni assignment.

## Baseline antes/despues

Se ejecuto exactamente la misma consulta reproducible antes y despues. Las 19
filas coinciden en conteo y checksum:

| Dominio | Filas | Checksum |
| --- | ---: | --- |
| achievements | 509 | `dfd6c6c1b12ac6031279279a3ee3477e` |
| attendance | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| billing | 11 | `d418069c108550668a90279aa49236dd` |
| canonical_match | 1 | `3c2cf6f48ce0dadb5c0182e1fe09431b` |
| club_foundation | 1 | `536ce7790e4a43b596be2c57cdfd75ca` |
| competition_foundation | 1 | `b27f97c3d789b373a6c7976e2689727f` |
| conduct | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| facets_reliability | 1 | `5486c765ebdb770f4b5a38fd59a7a6df` |
| matches | 22 | `6b2e21d99a9ed1b88fb84db6a34f1fa0` |
| participants | 4 | `0c24244b8e8c066ceef0927513592ef1` |
| player_cosmetics | 1 | `42a0d8a56dfc041ce3c2f7abe0402c00` |
| ranking_provincial | 17 | `1c0b5c08dde30ac0e6d5fa711ff43f40` |
| rating_v2 | 12 | `24e451a94f7f49c98a227df56fd56b41` |
| results | 1 | `187e9ecbedd970410dbed79442cc81e5` |
| reward_boxes | 42 | `d8f52013c926180c107870435236e123` |
| scorers | 4 | `cfea5353ac3393bdc2401e08732eb3db` |
| season_score | 1 | `fc636bd085666fa101a544fdf67c9b78` |
| team_cosmetics | 32 | `c01ffb322c935f4bb14d7eda0b645c2e` |
| team_reward_mappings | 14 | `d65424e1e4f0507bc153c42ba1ad36e7` |

Ademas, los cinco mappings activos Team Cosmetic Rewards se comprobaron uno a
uno y Premium Ball sigue definido con `enabled=false`.

## QA web y PWA en produccion

QA de solo lectura contra el deployment exacto:

- `/admin/referees` como `platform_owner`: seis flags desmarcados; perfiles,
  activos, Mercado, relaciones pendientes y assignments activos a 0;
- anonimo en `/admin/referees`: `Sesion necesaria`, `noindex,nofollow`;
- `/mercado?tab=arbitros`: la pestaña arbitral no aparece y la vista cae en
  Jugadores, sin producto vacio ni operaciones;
- `/perfil/arbitro`: alta cerrada y controles deshabilitados;
- `/arbitros/arbitro-inexistente`: `Ficha arbitral cerrada`, noindex/nofollow;
- `/laboratorio-referee-platform`: fuera de navegacion publica,
  `noindex,nofollow`, alta cerrada y sin escrituras;
- 0 errores o warnings de consola y 0 overflow horizontal en 1280, 390x844 y
  844x390;
- Service Worker activo en `/sw.js`, `Cache-Control: no-cache, no-store`,
  version `2.0.0+sw.013167572598`;
- manifest productivo: `display=fullscreen`, fallback `standalone`, 5 iconos;
- offline: se sirvio el shell cacheado sin controles R3 ni exito falso;
  al reconectar se recupero la ficha canonica cerrada.

La ventana standalone instalada y los dispositivos fisicos no se afirmaron
como probados:

- Android fisico: `PHYSICAL_QA_PENDING`;
- iPhone fisico: `PHYSICAL_QA_PENDING`.

No bloquea esta release porque los seis flags R3 permanecen OFF.

## Advisors y logs

Supabase Advisors no devolvio incidencias de nivel error atribuibles a R3. Los
avisos R3 son los ya documentados por el modelo de autoridad:

- Security: 8 INFO `rls_enabled_no_policy` en tablas fail-closed, 2 WARN por
  lecturas publicas anonimas intencionales, 15 WARN por RPCs
  `SECURITY DEFINER` autenticadas y 1 aviso global de anonymous sign-ins sobre
  la policy authenticated de invalidaciones;
- Performance: 19 INFO de FK sin indice dedicado y 12 indices sin uso, esperado
  con cero filas R3.

Tras migracion/deployment:

- Vercel: 0 logs error/fatal/warning; las rutas R3 observadas fueron 200 o el
  404 esperado para el slug inexistente;
- Supabase API: 0 respuestas 5xx;
- PostgreSQL: 0 eventos ERROR/FATAL/PANIC;
- Realtime: 0 errores;
- 0 tokens, JWT, claves Supabase o emails objetivo detectados en logs.

## Cierre

Referee Platform V1 queda instalada como autoridad server-side, pero no es un
producto visible ni admite escrituras mientras sus flags sigan OFF. Rating V2,
facetas, assessments, partidos, resultados, goleadores, Attendance, Conduct,
Achievements, cajas, Player/Team Cosmetics, Team Rewards, Billing, Season
Score, Ranking, Competition, Club Foundation y Canonical Match permanecen
intactos.

