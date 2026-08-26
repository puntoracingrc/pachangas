# Referee Assignments Private Beta V1 - Production Release

## Release

- Cierre: 2026-08-26 13:37 CEST.
- Proyecto: Pachangas IQ.
- Base inicial de Wave 4: `2ae6fd46ad0247f0e7b33d4175ad309c68dea50b`.
- HEAD funcional del PR: `c2a49fa`.
- PR funcional: [#197](https://github.com/puntoracingrc/pachangas/pull/197).
- Merge funcional en `main`: `f6b1686d11759030612e491aec4b03d49e4e77db`.
- Tournament Engine: no iniciado.

## Migraciones

Se aplicaron forward-only cuatro migraciones funcionales y un hotfix aditivo de
índices:

1. `20260826014905_referee_assignment_private_beta_schema_v1`
2. `20260826014910_referee_assignment_private_beta_authority_v1`
3. `20260826014916_referee_match_officiating_commands_v1`
4. `20260826014920_referee_assignment_private_beta_access_v1`
5. `20260826105132_referee_assignment_fk_index_hardening_v1`

Readback productivo:

- ledger local/remoto: `152 / 152`, sin drift;
- última versión: `20260826105132`;
- última migración: `referee_assignment_fk_index_hardening_v1`;
- backup físico previo: `1480277773`, `COMPLETED`;
- 13/13 índices del hotfix encontrados, `valid/ready`;
- 0 sesiones bloqueadas y 0 sesiones de migración activas al cerrar.

La migración de índices terminó en 7,4 s. El CLI avisó que sus dos `SET LOCAL`
no se aplicaron fuera de una transacción; se conserva como `W4-ENV-038`, sin
reescribir una migración ya ejecutada. El readback operativo posterior fue
correcto.

## Deployment

- Deployment: `dpl_AFNt4wrc1wkVjmxtDMDKLJFN31D3`.
- URL inmutable:
  `https://pachangas-4v9ik9dmz-persianas-almar-web-s-projects.vercel.app`.
- Dominio: [https://pachangasiq.com](https://pachangasiq.com).
- Estado: `READY`.
- Target: `production`.
- Git ref: `main`.
- Git SHA exacto: `f6b1686d11759030612e491aec4b03d49e4e77db`.
- Alias productivos: `pachangasiq.com` y `www.pachangasiq.com`.

## Activación escalonada

La activación usó exclusivamente
`command_pachanga_referee_assignment_beta_admin_v1`, con actor autenticado,
`operationId`, revisión esperada y recibo canónico:

1. Revisión 4 -> 5: `assignmentPrivateBetaEnabled=true` y
   `assignmentsEnabled=false`.
2. Readback: revisión 5, un recibo y 0 Assignments.
3. Revisión 5 -> 6: beta privada y Assignments `true`.
4. Readback final: revisión 6, secuencia de estado 54 y dos recibos.

Estado final:

| Flag | Valor |
| --- | --- |
| `referee_foundation_enabled` | `true` |
| `referee_assignment_private_beta_enabled` | `true` |
| `referee_assignments_enabled` | `true` |
| disciplina pública | `false` |
| Payments | `NOT_IMPLEMENTED` |
| Tournament | `NOT_IMPLEMENTED` |
| canonical backfill | 0 eventos / no inicializado |

## Smoke canónico

El smoke productivo se ejecutó dentro de una transacción explícita con fixtures
sintéticas efímeras. Las precondiciones se prepararon dentro de esa transacción;
propuesta, replay, aceptación, confirmación y cancelación pasaron por las RPC
canónicas. El cierre fue `ROLLBACK`.

Resultado:

- `status=PASS`;
- replay de propuesta idéntico;
- 4 recibos para 4 operaciones distintas;
- estado terminal `cancelled`, revisión 4;
- 8 invalidaciones canónicas;
- revisión obsoleta rechazada;
- escritura directa de `authenticated` cerrada;
- digests protegidos estables dentro del escenario;
- residuo posterior: 0 usuarios, grupos, perfiles, Assignments, recibos e
  invalidaciones sintéticas;
- total productivo de Assignments al cerrar: 0.

Realtime conserva `pachanga_referee_invalidations` en `supabase_realtime`. El
payload WAL solo invalida; cada cliente relee el snapshot canónico. Los logs de
Realtime revisados contienen 0 errores.

## ACL y Advisors

- `authenticated` no puede insertar, actualizar ni borrar Assignments.
- Los términos privados no tienen acceso directo de cliente.
- Las revisiones no admiten escritura directa de cliente.
- La RPC de comando está concedida a `authenticated` y resuelve permisos en
  servidor.
- Performance Advisors: 0 FK Wave 4 sin índice y 0 warnings/errors Wave 4; los
  índices nuevos aparecen como `unused_index` informativo porque todavía no hay
  tráfico real.
- Security Advisors: dos avisos informativos por tablas RLS sin políticas, que
  están cerradas por grants, y dos warnings conocidos por la RPC de lectura
  `SECURITY DEFINER` autenticada y la configuración global de anonymous sign-in.
  ACL/RLS y la matriz adversarial confirman que no existe escritura o lectura
  privada directa nueva.

Referencias de Advisors:

- [Unindexed foreign keys](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys)
- [RLS enabled without policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
- [Authenticated SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)

## Invariantes protegidos

Readback final de filas y digest:

| Dominio | Filas | Digest |
| --- | ---: | --- |
| Rating snapshots | 1 | `ce838b082d476871c05aa6df5cdf589c` |
| Assessments | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Reward grants | 17 | `f8c950d847b867804d4b51b9cee70971` |
| Conduct reports | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Billing events | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Player cosmetic loadouts | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Team cosmetic inventory | 7 | `e5a3c62aa06218156930e31eab7cab7d` |
| Team Cosmetic Reward mappings activos | 5 | `43ec6570d18b53b719152b81445a991e` |

Los cinco mappings siguen siendo exactamente:

- `team.matches.050 -> team.shield.border.silver`;
- `team.external.wins.001 -> team.shield.border.copper`;
- `team.external.clean_sheets.001 -> team.shield.effect.edge_glow`;
- `team.external.matches.010 -> team.shield.ornament.banner`;
- `team.matches.025 -> team.shield.ornament.laurels`.

No se modificaron fórmulas, facetas, GRL, assessments, Rating, Rewards,
Conduct, Billing, Player Cosmetics ni Team Cosmetics.

## Producto y Demo

Smoke productivo en `pachangasiq.com`:

- portada: 0 overflow, 0 imágenes rotas y 0 logs de consola;
- Demo World V2.2: navegación correcta;
- Árbitros Demo: contenido arbitral y estados completado, cancelado y
  sustituido visibles;
- Demo Árbitros: 0 overflow documental, 0 imágenes rotas y 0 logs;
- `/api/referee-assignments/me` sin sesión: `401` y `private, no-store`;
- `/mis-asignaciones-arbitrales`: `200`;
- Vercel Runtime Errors, última hora: 0.

Los `503` observados antes del cierre pertenecían exclusivamente al CRON
preexistente `/api/internal/rankings/refresh` sin `CRON_SECRET`; no afectan Wave
4 y permanecen como deuda separada.

PWA técnica:

- manifest y Service Worker: PASS;
- modo standalone emulado: PASS;
- recarga offline visible y sin fake success: PASS;
- reconexión/refetch: PASS en la certificación autenticada;
- Android físico: PENDING;
- iPhone físico: PENDING;
- PWA instalada física: PENDING.

## Gates

Los gates de código ejecutados antes del merge funcional fueron:

- `npm test`: PASS, build + 20 Node + 489 TS/TSX;
- typecheck: PASS;
- build: PASS;
- lint focal Wave 4: PASS;
- lint global: deuda heredada de 22 errores y 18 warnings, sin delta Wave 4;
- SQL/RLS/idempotencia: PASS sobre las cuatro migraciones funcionales;
- concurrencia: PASS, 10 carreras;
- escala: PASS sobre el corpus contractual;
- regresión focal tras el hotfix de índices: 27/27;
- `git diff --check`: PASS.

No se repitió escala ni la batería global por los cambios exclusivamente
documentales de este informe.

## Cleanup

- Branch Supabase `wave4-referee-assignments-index-certification`: eliminado.
- Readback de branches: solo `main` y el branch histórico
  `pwa-bridge-staging` permanecen.
- Cuatro variables Vercel Preview limitadas a la rama Wave 4: eliminadas.
- Readback Vercel de esa rama: `envs=[]`.
- Datos sintéticos productivos: 0.
- Procesos y temporales Wave 4: 0.
- Worktree Wave 4: se conserva hasta que el PR documental esté fusionado, su
  deployment esté READY y el HEAD sea ancestro de `origin/main`.

## Estado final

- Referee Assignments Private Beta V1: `ACTIVE`.
- Producción modificada: sí, de forma coordinada y autoritativa.
- Supabase producción: ledger 152, flags revisión 6.
- Demo World V2.2: productiva.
- Tournament Engine: no iniciado.
- Hotfix adicional necesario: no.
- Incidencias abiertas no bloqueantes: `W4-ENV-020` (sin nueva ejecución local
  sobre ledger 152) y `W4-ENV-038` (timeouts `SET LOCAL` no efectivos en el
  push CLI); ambas tienen readback remoto satisfactorio y están documentadas.
