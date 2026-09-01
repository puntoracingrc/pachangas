# Official UI V3F - Production Release

Estado: `RELEASE IN PROGRESS`  
Fecha de apertura: 2026-09-02 (Europe/Madrid)

Este documento se completará únicamente con evidencia obtenida del PR,
Supabase y Vercel. No se marcará como released mientras falten migraciones,
flags, canary, deployment, smoke, informe documental o cleanup.

## Checkpoint local certificado

| Evidencia | Resultado |
| --- | --- |
| Main inicial | `bb95b056a018ab8868d1b80d3479873a630b832b` |
| Rama | `codex/official-ui-v3f-social-team-core` |
| PR funcional | [#253](https://github.com/puntoracingrc/pachangas/pull/253) (draft) |
| HEAD local certificado | Pendiente del commit documental previo a staging |
| Migraciones V3F | 5, `20260901214523` a `20260901214527` |
| Baseline | Node 20/20 + TS/TSX 747/747 = 767/767 |
| Resultado V3F | Node 20/20 + TS/TSX 780/780 = 800/800 |
| Skipped/todo/cancelled | 0/0/0 |
| Typecheck | PASS |
| Build | PASS dentro de `npm test` |
| Lint global | 0 errores, 0 warnings; nota Babel informativa |
| PostgreSQL | PASS con rollback |
| Demo remote writes | 0 |
| Entidades reales | 0 |
| Stripe | NO TOCADO |

## Supabase efímero

| Evidencia | Resultado |
| --- | --- |
| Proyecto padre verificado | `qonbngfrnrqgmxbdfbea` (Pachangas, `eu-west-1`) |
| Rama efímera | `v3f-social-team-core-qa` / `lhusningjrsanfzwmhiw` |
| Datos productivos copiados | 0 |
| Bootstrap | Esquema canónico sin filas ni PII; SHA-256 `4e172e42c1e86036bdb95dc33ee534710efff5565731f0aba97c4f226f6e7725` |
| Ledger inicial | 228 versiones, idénticas a producción |
| Ledger con V3F | 233 versiones exactas; `20260901214523`–`20260901214527`, sin versiones extra |
| Flags V3F | 7/7 en `false`, revisión 1 |
| Filas V3F iniciales | 0 en las seis tablas de actividad |
| Realtime | `pachanga_social_invalidations_v1` publicada |
| Legacy join | `join_pachanga_team` y `join_pachanga_group` sin `EXECUTE` autenticado |
| DML directo | Sin privilegios de escritura para clientes |
| SQL/RLS remoto | PASS dentro de transacción con rollback |
| Advisors V3F | 0 foreign keys sin índice; avisos genéricos documentados en `V3F_SOCIAL_TEAM_CORE_INCIDENTS.md` |

El historial previo no es reproducible desde una base completamente vacía
porque una migración de 2026-07 presupone una tabla del bootstrap consolidado.
V3F no reescribe esa historia: la rama se levantó desde un dump exclusivamente
de esquema y se reconcilió contra las 228 versiones canónicas. La reparación
fresh-install queda como deuda separada y no bloquea el upgrade productivo
`228 -> 233`.

## Staging autenticado certificado

| Evidencia | Resultado |
| --- | --- |
| Preview exacta | `https://pachangas-q1osyi32l-persianas-almar-web-s-projects.vercel.app`, SHA `c8ff3b05b17b591b11cfd37dd7fb2ac9d61d8e20` |
| Identidades | 5 cuentas sintéticas `.test`; ninguna identidad real |
| Dispositivos | 2 sesiones autenticadas simultáneas para el mismo owner |
| Perfil | Crear sin equipo y actualizar: PASS; Rating separado y Mercado no publicado |
| Equipos | 2 Teams canónicos; owner, estado `ACTIVE`, escudo base y creación atómica: PASS |
| Invitaciones | `ACTIVE`, `USED`, `REVOKED`, `DECLINED`; raw token una sola vez y sin persistencia pública |
| Idempotencia | Perfil, Team y aceptación: PASS |
| Concurrencia | 1 ganador y 1 `STALE_INVITATION_REVISION`; una sola membresía |
| Código | Identifica el Team y no concede membresía |
| RBAC/DML | Jugador no invita; DML directo y joins legacy denegados |
| Privacidad roster | Claves opacas; sin Auth UUID, email ni teléfono |
| Realtime | `SUBSCRIBED`, ACK de binding, invalidación, refetch canónico y reconexión: PASS |
| Offline | Escritura rechazada; 0 Teams confirmados localmente |
| Notificaciones | Solo in-app a cuentas `.test`; token ausente; 0 destinatarios reales |
| Preview/PWA | 6 rutas HTTP 200; SW `no-store`, SHA exacto y rutas sociales precacheadas |
| Salida | Código 0; canales, sockets y sesiones locales cerrados |
| Flags al terminar | 7/7 en `false` |
| Cleanup | Rama efímera completa pendiente de destrucción tras cerrar el release |

## Pendiente remoto

- Backup y reconciliación del ledger productivo.
- Aplicación exacta de migraciones con flags OFF.
- Merge, deployment READY y smoke inactivo.
- Activación escalonada mediante RPC de plataforma.
- Canary sintético reversible y readback final a cero.
- Smoke de dominio, manifest, Service Worker y logs.
- Informe final, PR documental y retirada de recursos temporales.

QA física Android/iPhone/PWA instalada: `PENDING`, no presentada como PASS.
