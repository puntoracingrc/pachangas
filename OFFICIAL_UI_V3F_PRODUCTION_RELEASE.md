# Official UI V3F - Production Release

Estado: `RELEASED`
Fecha de cierre técnico: 2026-09-02 (Europe/Madrid)

Official UI V3F Social Team Core está fusionada, migrada, activada y
verificada en producción. La autoridad deportiva y social permanece en
PostgreSQL; el cliente conserva únicamente read models derivados y nunca
confirma escrituras offline.

## Trazabilidad Git y Vercel

| Evidencia | Resultado |
| --- | --- |
| Main inicial | `bb95b056a018ab8868d1b80d3479873a630b832b` |
| HEAD funcional certificado | `799b2e185810e281676691e79343e1060dc2efde` |
| PR funcional | [#253](https://github.com/puntoracingrc/pachangas/pull/253), fusionado |
| Merge funcional | `72f2cec03305ff5564b7afe2117231185fa28e8b` |
| Hotfix landscape | `8909a02831a6f5b8ec985ad7fedaca0891ac8205` |
| PR hotfix | [#254](https://github.com/puntoracingrc/pachangas/pull/254), fusionado |
| Código productivo final | `dd0825b083d968dce201b53ac205ac0cc8be85ef` |
| Deployment productivo | `dpl_BV1gEmjUXD15TLRyL858sGNUZ42B`, `READY` |
| Dominio | [pachangasiq.com](https://pachangasiq.com) |

El hotfix corrige únicamente el recorte del logo público en `844x390`, añade
su regresión y amplía el ledger de incidencias. No cambia autoridad, datos,
RPC, migraciones ni producto social.

## Gates de código

| Gate | Resultado |
| --- | --- |
| Baseline anterior | Node 20/20 + TS/TSX 747/747 = 767/767 |
| V3F funcional | Node 20/20 + TS/TSX 780/780 = 800/800 |
| Cierre con regresión landscape | Node 20/20 + TS/TSX 781/781 = 801/801 |
| Skipped/todo/cancelled | 0/0/0 |
| Build | PASS, 76/76 rutas dentro de `npm test` |
| Typecheck | PASS |
| Lint global | PASS; solo nota Babel informativa por tamaño de `app/page.tsx` |
| `git diff --check` | PASS |

## Staging autenticado

La rama Supabase efímera `v3f-social-team-core-qa`
(`lhusningjrsanfzwmhiw`) partió de esquema canónico sin filas ni PII. Su
ledger se reconcilió primero con las 228 migraciones existentes y después con
las cinco migraciones V3F. No se copiaron datos productivos.

| Historia | Resultado |
| --- | --- |
| Identidades | 5 cuentas sintéticas `.test`; ninguna identidad real |
| Dispositivos | 2 sesiones autenticadas simultáneas del mismo owner |
| Perfil | Crear y actualizar sin equipo: PASS; Rating y Mercado separados |
| Equipo | Creación atómica, owner, `ACTIVE`, escudo base y readback: PASS |
| Invitaciones | `ACTIVE`, `USED`, `REVOKED`, `DECLINED`; secreto raw-once |
| Idempotencia | Perfil, equipo, invitación y aceptación: PASS |
| Concurrencia | 1 ganador y 1 stale; una sola membresía canónica |
| Código compartido | Solo lookup; nunca concede membresía |
| RBAC y RLS | Jugador no invita; DML directo y joins legacy denegados |
| Privacidad | Roster sin Auth UUID, email ni teléfono |
| Realtime | ACK, invalidación, refetch canónico y reconexión: PASS |
| Offline | Escritura rechazada; 0 éxitos optimistas |
| PWA | SW `no-store`, SHA exacto y rutas sociales precacheadas |
| Efectos reales | 0 usuarios, notificaciones, equipos o pagos reales |

## Migraciones productivas

Backup previo, ledger y proyecto se comprobaron antes de aplicar SQL. El
proyecto afectado fue exclusivamente `qonbngfrnrqgmxbdfbea` (Pachangas,
`eu-west-1`).

| Versión | Nombre |
| --- | --- |
| `20260901214523` | `social_profile_foundation_v1` |
| `20260901214524` | `social_team_core_evidence_v1` |
| `20260901214525` | `atomic_social_team_creation_v1` |
| `20260901214526` | `team_player_invitations_v2` |
| `20260901214527` | `social_team_read_models_rls_flags_v1` |

Readback final: ledger `233`, exactamente cinco entradas V3F y ninguna versión
extra. RLS está activa, los clientes no tienen DML directo, los joins legacy
no son ejecutables y `pachanga_social_invalidations_v1` está publicada para
Realtime. Todos los índices V3F son válidos y ninguna foreign key V3F carece
de índice de cobertura.

## Activación canónica

Los siete flags se activaron mediante
`command_pachanga_social_team_settings_v1`, nunca con `UPDATE` directo. El
readback final devuelve revisión `7`, secuencia de servidor `77` y todos estos
valores en `true`:

- `social_profile_foundation_enabled`
- `social_profile_independent_write_enabled`
- `social_team_creation_enabled`
- `social_team_invitation_v2_enabled`
- `social_team_membership_v2_enabled`
- `social_team_home_v3f_enabled`
- `demo_social_team_journey_enabled`

La evidencia persistida contiene seis recibos y seis eventos de configuración.

## Canary productivo

Siete canaries sintéticos se ejecutaron dentro de transacciones con rollback:

1. perfil social separado de Rating y sin fabricar perfil deportivo;
2. creación atómica de equipo;
3. Home canónico de equipo;
4. invitación, replay idempotente y secreto raw-once;
5. aceptación e idempotencia;
6. privacidad del roster;
7. lookup por código sin alta implícita.

Resultado: `7/7 PASS`. El readback global posterior confirmó `0` usuarios QA,
grupos QA, perfiles QA, membresías QA, invitaciones QA, secretos QA, recibos QA,
eventos QA e invalidaciones QA.

Las únicas filas V3F persistentes son derivaciones legítimas de los 12 grupos
ya existentes: 12 estados de equipo y 12 revisiones iniciales. Permanecen en
cero perfiles sociales, revisiones de perfil, invitaciones, secretos,
revisiones de invitación e invalidaciones.

## Autoridades protegidas

Los conteos y digests permanecieron idénticos antes y después de migración,
activación y canaries:

| Autoridad | Filas | Digest |
| --- | ---: | --- |
| Grupos | 12 | `4422c8dde77781cb22cf66aa17c8c2b3` |
| Miembros | 20 | `4a7f269e38244ba7000b89ce3a6be738` |
| Reward grants | 17 | `8acd3680f8c086a40db21bedd8f7095c` |
| Perfil deportivo | 1 | `e90de1ffaed4297fcd1e879b6ac96e17` |
| Rating evidence | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Rating snapshots | 1 | `72d5658b0b153bbcc2e999a08a5beb4e` |
| Team shield | 6 | `0e7d804555f9c348b6287b733d00f9f3` |
| Achievement grants | 17 | `acdbd1738bcaf3ba0a91ae17c269e5ce` |
| Conduct | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Match rating snapshots | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| Team cosmetic inventory | 7 | `7ca6b285a7f9f7f9d582644c8fada584` |
| Achievement definitions | 222 | `d53c07fefb65f08fe0aa874da4148ee9` |
| Player cosmetic loadouts | 0 | `d41d8cd98f00b204e9800998ecf8427e` |

Rating V2, rewards, Conduct, billing, Player Cosmetics y Team Cosmetics no se
modificaron.

## Producción y PWA

Smoke HTTP: `/`, `/perfil`, `/equipo`, `/equipo/plantilla`,
`/equipo/invitaciones`, `/mercado`, `/demo`, manifest y Service Worker
respondieron `200`. El Service Worker usa `Cache-Control: no-store`, contiene
el SHA productivo corto `dd0825b083d9` y precachea las superficies de lectura V3F sin cachear
commands.

QA visual completada:

- desktop `1440x900`;
- portrait `390x844`;
- compact landscape `844x390`;
- Home pública, Perfil, Equipo, Plantilla, Invitaciones, Mercado y Demo;
- escenarios Demo player, free agent y team owner.

Resultado: `0` overflow horizontal, `0` imágenes rotas y navegación correcta.
En el smoke posterior al hotfix, el logo compacto mide `240x42`, conserva su
arte visible dentro del viewport y aplica la traslación proporcional esperada.

Logs posteriores a la activación: `0` errores PostgreSQL, `0` respuestas 4xx
inesperadas, `0` respuestas 5xx y `0` runtime errors Vercel. Los errores SQL
anteriores pertenecían exclusivamente a consultas diagnósticas/canaries
fallidos antes de mutar y están registrados en
`V3F_SOCIAL_TEAM_CORE_INCIDENTS.md`.

## Backup y reversión

Se verificaron siete backups físicos Supabase en estado `COMPLETED`. Antes de
la migración se generaron dumps locales protegidos por permisos de sistema
(`0600`) de esquema, datos y roles; sus hashes se registraron sin exponer PII.
La reversión preferente sigue siendo roll-forward o flags canónicos. Ninguna
reversión convierte payloads locales en autoridad ni reabre escrituras legacy.

## Cleanup

| Recurso | Resultado |
| --- | --- |
| Rama Supabase efímera | Eliminada; el listado posterior contiene solo `main` |
| Variables Preview | Las dos variables branch-scoped eliminadas; listado de la rama vacío |
| Deployments Preview V3F | Tres Previews exactas eliminadas; Producción conservada |
| Dumps locales | Tres dumps retirados después de registrar hashes y verificar backups |
| Directorio de migración | `/tmp/pachangas-v3f-release-push` eliminado con `find -depth -delete` |
| Configuración local temporal | `.env.local` y `.vercel` retirados sin exponer valores |
| Navegador QA | Viewport restaurado y pestaña productiva cerrada |

El worktree se conserva hasta fusionar este informe y verificar su deployment.
Después se retirará mediante `git worktree remove` y `git worktree prune`,
conforme a `AGENTS.md`.

## QA física

- Android físico: `PENDING`.
- iPhone físico: `PENDING`.
- PWA instalada en dispositivo físico: `PENDING`.

No se presentan como PASS. No bloquean este release web autorizado, pero deben
mantenerse como deuda de QA física.
