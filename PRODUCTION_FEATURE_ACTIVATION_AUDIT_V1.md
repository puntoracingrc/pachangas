# Production Feature Activation Audit V1

Estado: auditoria en curso. Este documento no autoriza por si solo ninguna activacion.

## Trazabilidad inicial

- Inicio: 2026-08-12 (Europe/Madrid).
- Base exacta: `origin/main` en `97fb945850b0b843050cd5b4288e24d7397a339b`.
- Rama: `codex/production-feature-activation-audit-v1`.
- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-production-feature-activation-audit-v1`.
- Checkout principal: no utilizado porque contiene cambios ajenos del laboratorio.
- Supabase produccion: no modificado al abrir esta auditoria.
- Vercel produccion: no modificado al abrir esta auditoria.

## Contrato de la fase

La auditoria distingue siempre:

```text
codigo desplegado != funcion productiva != flag activo
```

Clasificaciones permitidas:

- `ACTIVE_PRODUCT`
- `READY_FOR_ACTIVATION`
- `READY_WITH_GUARDS`
- `SHADOW_ONLY`
- `LAB_VALIDATED`
- `NEEDS_PRODUCTIZATION`
- `BLOCKED`
- `OBSOLETE`

Activaciones autorizadas solo si pasan todos los gates:

1. Attendance.
2. Smoke y observacion.
3. Conduct/report intake.
4. Smoke y observacion.

Estados finales obligatorios de esta fase:

- Social Restrictions: `OFF`.
- Conduct triage: `SHADOW_ONLY` / laboratorio, sin autoridad automatica.
- Season Score: laboratorio.
- Ranking provincial: laboratorio.
- Premios provinciales: `OFF`.
- Premium Ball: `OFF`.

Attendance y Conduct no pueden provocar backfill, sanciones automaticas, restricciones automaticas, cambios en Rating V2, recompensas ni billing. Los cambios productivos, si proceden, pasaran por la RPC administrativa autoritativa con `operationId`, revision esperada, fecha del servidor y audit ledger.

## Matriz canonica

Pendiente del inventario completo de PostgreSQL, variables de entorno, configuracion server-side, runtime policy, laboratorios, gates y referencias legadas.

## Gates pendientes

- Auditoria local de consumidores, escrituras, notificaciones y dependencias.
- Valores y revisiones reales de staging y produccion.
- Ensayo staging de Attendance, Conduct, triage shadow y Social Restrictions con cierre final `OFF`.
- Zero backfill y zero notification storm.
- Invariantes Rating, rewards, cosmetics y billing.
- RLS, ACL, Realtime, PWA y compatibilidad de cliente.
- Synthetic World soak aislado.
- Tests, typecheck, build, lint focalizado y `git diff --check`.
- Backup productivo inmediatamente anterior a cualquier activacion.
- Activacion escalonada y smoke productivo, solo si la evidencia lo permite.
