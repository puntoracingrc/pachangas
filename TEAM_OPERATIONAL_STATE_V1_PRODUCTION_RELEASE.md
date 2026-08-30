# Team Operational State V1 Production Release

Status: release en curso

## Checkpoint

- `main` inicial: `9270f3a398622e0e9bc43d001beec6d6bf338b99`.
- PR funcional: #227.
- Migraciones previstas: `20260829221256` a `20260829221312`, ocho exactas.
- Ledger productivo inicial esperado: 204.
- Staging sintético: PASS.
- Producción: todavía no modificada en este checkpoint documental.
- Stripe tocado: NO.
- Cargos reales: 0.

## Gates ya cerrados

- npm ci: PASS.
- tests: 649/649, skip/todo/cancelled 0/0/0.
- typecheck/build: PASS.
- lint focal propio: PASS.
- SQL/RLS/idempotencia: PASS.
- concurrencia: PASS.
- escala: PASS con rollback/cleanup.
- Supabase branch efímero: ledger 212 y E2E autenticado PASS.
- Demo World V3.1: snapshot saneado, remote writes 0.

## Pendiente de completar en release

Este apartado debe sustituirse por evidencia real, no por una previsión:

1. `supabase migration list --linked` y conciliación del ledger productivo.
2. backup recuperable y baselines.
3. aplicación exacta de las ocho migraciones con flags OFF.
4. merge SHA de #227 y deployment Vercel `READY` del mismo SHA.
5. smoke inactivo.
6. activación secuencial mediante RPC de plataforma.
7. canary sintético con `ROLLBACK` y readback final a cero.
8. publicación y smoke de Demo World V3.1.
9. logs, Service Worker y responsive productivos.
10. destrucción del branch Supabase, variables Preview, deployments temporales,
    procesos y worktree.

No se considerará cerrado mientras esta sección siga pendiente.
