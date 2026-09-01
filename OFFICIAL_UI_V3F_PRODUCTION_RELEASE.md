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

## Pendiente remoto

- Supabase efímero y Preview autenticada con cinco identidades `.test`.
- Realtime, reconexión y offline de dos dispositivos.
- Backup y reconciliación del ledger productivo.
- Aplicación exacta de migraciones con flags OFF.
- Merge, deployment READY y smoke inactivo.
- Activación escalonada mediante RPC de plataforma.
- Canary sintético reversible y readback final a cero.
- Smoke de dominio, manifest, Service Worker y logs.
- Informe final, PR documental y retirada de recursos temporales.

QA física Android/iPhone/PWA instalada: `PENDING`, no presentada como PASS.
