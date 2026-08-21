# Club Foundation V1 - Production Release

Release ejecutada el 2026-08-21 y cerrada documentalmente a las 19:34 CEST.

## Resumen ejecutivo

Club Foundation V1 se ha instalado y desplegado en producción como infraestructura inactiva. La release incorpora la autoridad canónica de Club, membresías, invitaciones, relaciones Club-Team, entitlements y el adaptador de organizador `TEAM xor CLUB`, pero no activa ninguna superficie de producto.

El estado final verificado es:

- Los cinco flags R2 permanecen en `false`.
- Los tres flags R1 permanecen en `false`.
- No existe ningún Club, miembro, invitación, relación, entitlement ni Competition de Club en producción.
- No se ejecutó ningún backfill canónico.
- Rating V2, partidos, resultados, recompensas, conducta, billing, rankings y cosméticos conservan exactamente sus checksums previos.

## Git y PR

| Evidencia | Valor |
| --- | --- |
| `origin/main` inicial | `82fbb7933b51a5cef3267ae71e1ca8dc9f63cd8c` |
| PR funcional | [#155 - Build Club Foundation V1](https://github.com/puntoracingrc/pachangas/pull/155) |
| Estado inicial real | Abierto, fuera de borrador, mergeable y clean |
| HEAD previo a correcciones documentales | `7824cd6b42bfa0e786bbc9876a07a4820ac9ef30` |
| Commit documental previo a release | `b980eed2fc7989aca1b61e6b6d64d6438dad323c` |
| HEAD funcional final | `b980eed2fc7989aca1b61e6b6d64d6438dad323c` |
| Método de integración | Squash merge |
| Merge SHA / `main` funcional | `05a80ed10d2d84c1bb0175e38d6b5196929b7157` |
| Fecha de merge | 2026-08-21 17:15:54 UTC |

Las correcciones documentales aclararon que la creación inicial genera Competition draft, Edition draft, RuleSet inicial y, cuando corresponde, CompetitionStaffAssignment. No genera una RuleRevision vacía: esta se crea después a partir de un documento `competition_rules.v1` válido. También se actualizaron el estado real del PR y la Preview asociada al HEAD final.

El diff final del PR contenía 33 rutas y únicamente el dominio R2 previsto: informes, Club Control Center, API/read models, perfil público gated, laboratorio, clasificador de escrituras PWA, cuatro migraciones y pruebas R2/TEAM. No contenía cambios funcionales en Rating V2, facetas, logros, recompensas, billing, conducta, rankings, Player Cosmetics, Team Cosmetics, Demo World ni motores futuros.

## Validación previa

Toda la batería se ejecutó sobre `b980eed2fc7989aca1b61e6b6d64d6438dad323c`:

| Comprobación | Resultado |
| --- | --- |
| `npm ci` | PASS con Node 24.16 y npm 11.13; lockfile intacto |
| `npm test` | PASS, 308/308 |
| Build incluido en tests | PASS, 35/35 rutas |
| Typecheck independiente | PASS |
| Build independiente | PASS, 35/35 rutas |
| ESLint focalizado | PASS |
| `git diff --check` | PASS |
| SQL/RLS | PASS |
| SQL adversarial | PASS |
| Idempotencia | PASS |
| Concurrencia | PASS |
| Fresh bootstrap | PASS, 110 migraciones |
| Upgrade desde ledger productivo | PASS, 106 a 110 |
| E2E R2 staging | PASS |
| Regresión TEAM R1 | PASS |
| Escala | PASS |

La prueba de volumen cubrió 1.000 Clubs, 10.100 memberships, 5.000 relaciones, 10.000 invitaciones y 500 Competitions. Las 21 vulnerabilidades reportadas por `npm ci` ya existían en el árbol de dependencias y no fueron introducidas ni corregidas dentro de esta release.

## Backup y migraciones

Antes de modificar el esquema se verificó un backup físico recuperable de Supabase con timestamp `2026-08-21 00:20:55 UTC` y acción Restore disponible. El proyecto estaba `ACTIVE_HEALTHY`, en `eu-west-1`, con PostgreSQL `17.6.1.147`.

El ledger previo contenía 106 migraciones, ninguna R2, y no existía un esquema Club parcial fuera del ledger. Se aplicaron secuencialmente y sin edición:

1. `20260821141114_club_foundation_v1.sql`
2. `20260821141121_club_competition_organizer_adapter_v1.sql`
3. `20260821141129_club_platform_access_v1.sql`
4. `20260821142109_club_invitation_response_token_hardening_v1.sql`

Cada migración terminó en su propia transacción y se comprobó antes de continuar. El ledger final contiene 110 migraciones. `supabase migration list --linked` devuelve las 110 parejas local/remoto alineadas, incluidas las cuatro versiones R2.

No se modificó ninguna migración R1, no hubo edición manual de esquema, no se ejecutaron down migrations y no se creó una quinta migración.

## Estado de datos y flags

La lectura final posterior a toda la QA devuelve:

| Estado | Valor |
| --- | ---: |
| Club settings singleton | 1 |
| `club_foundation_enabled` | `false` |
| `club_self_service_creation_enabled` | `false` |
| `club_team_relationships_enabled` | `false` |
| `club_public_profiles_enabled` | `false` |
| `club_competition_organizer_enabled` | `false` |
| Revisión R2 | 1 |
| `foundation_enabled` R1 | `false` |
| `creation_enabled` R1 | `false` |
| `context_binding_enabled` R1 | `false` |
| Revisión R1 | 1 |
| Clubs | 0 |
| Memberships | 0 |
| Invitations | 0 |
| Invitation secrets | 0 |
| Club-Team relationships | 0 |
| Club invalidations | 0 |
| Club operation receipts | 0 |
| Club events | 0 |
| Club organizer states | 0 |
| Club entitlements | 0 |
| Club-organized Competitions | 0 |
| Club Competition staff | 0 |
| Club notifications | 0 |
| TEAM Competitions | 0 |
| TEAM entitlements | 0 |

Canonical Match continúa `NOT_INITIALIZED`, con cero backfills, matches, bindings y reviews. No se importaron los Clubs QA de staging, no se creó un Club productivo, no se concedieron entitlements, no se activó partnership y no se creó ningún producto o precio Stripe.

## Seguridad

### RLS y acceso directo

- Las cinco tablas públicas de Club tienen RLS habilitado.
- `anon` y `authenticated` no pueden hacer SELECT directo sobre las tablas privadas de dominio.
- `authenticated` no puede hacer INSERT, UPDATE ni DELETE directo.
- `authenticated` solo puede leer invalidaciones que pasen la policy; con cero datos obtiene cero filas.
- `private.pachanga_club_invitation_secrets` no es accesible por `anon` ni `authenticated` y no está publicada en Realtime.
- `public.pachanga_club_invalidations` sí está publicada en Realtime y conserva cero filas.

### RPC y ACL

- `command_pachanga_club_foundation_v1`: ejecutable por `authenticated`; no por `anon` ni `service_role` directo.
- Implementación interna R2: ejecución revocada a `PUBLIC`, `anon`, `authenticated` y `service_role`.
- Read model público: invocable por `anon` y `authenticated`, pero devuelve indisponible/null con flags apagados.
- Purga de contactos: `service_role` únicamente.
- Helper de Realtime: `authenticated` sí, `anon` no, con autorización contextual.
- Command V2 de Competition: `authenticated` sí, `anon` no; continúa fail-closed por flags.

Todas las funciones R2 `SECURITY DEFINER` auditadas fijan `search_path=pg_catalog`, usan identidad servidor y referencias cualificadas. No se localizó ningún definer nuevo con `search_path` inseguro.

### Organizer TEAM xor CLUB

La restricción transaccional rechazó y revirtió los cinco casos inválidos: kind desconocido, TEAM sin equipo, TEAM con Club, CLUB con equipo y CLUB sin Club. No quedaron filas ni efectos de secuencia. El wrapper V1 conserva la firma y semántica TEAM. El command V2 existe, está autorizado y rechaza creación CLUB con los flags desactivados. La creación TEAM sin entitlement también sigue rechazada con cero escrituras.

### Hardening de invitaciones

- `membership.invite` es el único comando autorizado a devolver `oneTimeToken`, `invitationId` y `tokenReturnedOnce`, y solo en la primera respuesta.
- `membership.accept`, `membership.decline` y el resto de comandos eliminan esos campos de la respuesta interna.
- En staging, la primera aceptación y su replay fueron idénticos y no contenían token.
- Receipts, events, notificaciones y logs de staging no contenían token plano, hash de token, target email ni campos equivalentes.
- En producción hay cero invitaciones, secrets, receipts, events y notificaciones Club.

## Capabilities y regresiones

Los arrays completos se compararon antes y después. El único cambio permitido fue añadir `clubs.read` y `clubs.manage` a los roles previstos:

- `platform_owner` y `platform_admin`: `clubs.read` + `clubs.manage`.
- `support`: `clubs.read`.
- `moderator`, `finance` y `ops`: sin ampliaciones Club.

Permanecen, entre otras, `rankings.read`, `rankings.write`, `competitions.read`, `competitions.manage`, `billing.read`, `moderation.write`, `flags.write` y `audit.read`. Continúa existiendo un único platform owner esperado y no se modificaron roles productivos.

Los checksums pre/post fueron idénticos para 16 dominios: billing, conduct, ranking, rewards, scorers, Rating V2, attendance, achievements, participants, notifications, Team Cosmetics, Canonical Match, autoridad de grupo, Player Cosmetics, Competition Foundation y partidos/resultados/social.

También permanecieron idénticos los contadores de side effects: 17 reward box grants previos, 7 entradas de Team Reward ledger/inventory, 6 ranking receipts, 1 ranking publication y cero escrituras nuevas en conducta, puntos, Stripe, canonical, season score o loadouts.

Los cinco mappings Team Cosmetic Reward permanecen exactamente:

| Achievement | Cosmetic |
| --- | --- |
| `team.external.clean_sheets.001` | `team.shield.effect.edge_glow` |
| `team.external.matches.010` | `team.shield.ornament.banner` |
| `team.external.wins.001` | `team.shield.border.copper` |
| `team.matches.025` | `team.shield.ornament.laurels` |
| `team.matches.050` | `team.shield.border.silver` |

Premium Ball continúa con cero mappings activos.

## Merge y deployment

PR #155 se fusionó por squash en `05a80ed10d2d84c1bb0175e38d6b5196929b7157`.

El deployment productivo asociado es:

- ID: `dpl_BYVLhuwvAx3rRhffEzcxuSoiJyx8`
- Estado: `READY`
- Target: production
- Git SHA: `05a80ed10d2d84c1bb0175e38d6b5196929b7157`
- Alias canónico: [pachangasiq.com](https://pachangasiq.com)
- URL de deployment: `pachangas-cv04wuscc-persianas-almar-web-s-projects.vercel.app`

El manifest responde 200 y declara `fullscreen` con fallback `standalone`, `minimal-ui` y `browser`. `sw.js` responde 200 con `Cache-Control: no-store`, versión `2.0.0+sw.05a80ed10d2d`, y quedó activo como controller sin worker pendiente. Las rutas administrativas y el perfil público gated responden como privadas/no-store; las rutas Club no forman parte del precache público.

## QA de producción

### Control Center y gates

- `/admin/clubs`: platform owner autenticado, cinco flags OFF, cero Clubs, invitaciones, relaciones, grants, Competitions y eventos; sin overflow, imágenes rotas ni errores.
- `/admin/competitions`: adaptador TEAM/CLUB operativo, cero Competitions y entitlements, canonical `NOT_INITIALIZED`; sin errores.
- Las dos rutas anteriores fallan cerradas sin sesión y no muestran snapshots parciales.
- `/laboratorio-club-foundation`: `noindex,nofollow`, flags OFF, gate de sesión claro y acciones de escritura desactivadas.
- `/clubes/club-inexistente`: no revela datos, informa que el perfil no es público y usa `noindex,nofollow`.
- La navegación pública no muestra Crear Club, Mis Clubs, Clubes, Crear Liga ni Crear Torneo.
- Usuario normal, admin de equipo y owner sin entitlement no obtienen autoridad Club u Organizer; las pruebas fail-closed terminaron con cero escrituras.

### Producto general y responsive

Se verificaron `/`, Inicio, Equipo, Mercado, Retos, Ranking, Partido, `/personalizar-carta`, `/equipo/identidad`, Avisos, `/demo`, `/admin` y los dos Control Centers. Todos renderizaron sin overlay de framework, imágenes rotas, overflow horizontal ni errores de consola.

En un partido real autenticado se recorrieron Próximo, Alineación, Resultado y Admin en viewport horizontal `844x390`; cada botón seleccionó el panel canónico correcto, con cero overflow, cero imágenes rotas y cero errores. También se comprobó el laboratorio Club en `390x844` y `844x390`.

Demo World continúa operativo, aislado y sin datos Club.

### PWA

La Preview exacta del HEAD funcional pasó QA en desktop `1440x900`, portrait `390x844`, landscape `844x390` y una instancia PWA standalone real. En producción se verificaron el mismo código fusionado, manifest, worker activo, portrait, landscape y una recarga con red emulada sin acceso de red servida por el Service Worker, sin errores de consola.

Las pruebas automatizadas confirman que una operación Club offline nunca se presenta como confirmada, que se pausa durante actualización del worker y que el cliente elimina cualquier estado optimista tras un rechazo. No se intentó ninguna escritura Club en producción.

## Advisors y logs

Supabase Security Advisors devolvió 303 avisos globales: 58 INFO y 245 WARN. Los avisos R2 fueron clasificados como intencionados:

- RLS sin policy en cuatro tablas direct-denied: los grants de cliente están revocados y la lectura se realiza por RPC.
- SECURITY DEFINER invocable en wrappers/read models auditados: ACL, identidad, flags y autorización fueron comprobados expresamente.
- Aviso de anonymous sign-in sobre invalidaciones: la policy limita el actor y la fila; con flags apagados no expone datos privados.
- No hay funciones R2 con `search_path` inseguro.

Performance Advisors devolvió 321 avisos: 320 INFO y un WARN de índice duplicado no relacionado. Los INFO R2 de FK sin índice/índice sin uso corresponden a tablas vacías y no se añadieron índices especulativos; la batería de escala pasó.

Referencias de remediación: [RLS sin policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [anon y SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [authenticated y SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [FK sin índice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys) e [índice sin uso](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

Los logs de Supabase API y Realtime no contienen token, target email, error de schema cache, 500 ni error runtime. Postgres solo registra el nombre de campo `oneTimeToken` dentro del SQL de la migración, nunca un valor; los `permission denied` corresponden a las pruebas RLS previstas.

Vercel no muestra logs `error`/`fatal`, token, target email ni schema cache para el deployment. Se observaron dos `503` en `/api/internal/rankings/refresh`, ambos debidos al `CRON_SECRET` ausente y expresamente preexistentes/fuera de R2. No se modificó esa configuración dentro de Club Foundation.

## Rollback

El rollback funcional consiste en mantener los flags en `false` y, si fuese necesario, revertir el deployment de Vercel. Las migraciones son aditivas y pueden permanecer instaladas. No se deben ejecutar down migrations, `DROP TABLE`, borrado de history ni reapertura de escrituras antiguas.

## Estado final

```text
Club Foundation:             DEPLOYED / INACTIVE
Club Self-Service:           OFF
Club-Team Relationships:     OFF
Public Club Profiles:        OFF
Club Competition Organizer:  OFF
Club records:                0
League Engine:               NOT IMPLEMENTED
Tournament Engine:           NOT IMPLEMENTED
Referee Platform:            NOT IMPLEMENTED
Competition Discipline:      NOT IMPLEMENTED
```

R2 queda `DEPLOYED / INACTIVE / READY FOR R3`. La release instala autoridad organizativa, pero ningún usuario productivo puede crear, publicar, vincular o usar un Club, conceder entitlements ni crear una Competition de Club.
