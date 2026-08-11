# Platform Control Center V1

Estado: implementacion en curso

## Trazabilidad

- Fecha de inicio: 2026-08-11 17:00:15 CEST
- Rama: `codex/platform-control-center-v1`
- Base exacta: `851418d688e4078d9fb9166174b961dc5c22d4d9`
- Repositorio: `puntoracingrc/pachangas`
- Worktree: `/Users/macbookpro14/.codex/worktrees/pachangas-platform-control-center-v1`
- Estado inicial: limpio, siguiendo `origin/main`
- Produccion: no modificada
- Demo World V1: fuera de esta rama

## Auditoria inicial

| Capacidad | Estado previo | Evidencia y decision V1 |
| --- | --- | --- |
| Shell global `/admin` | AUSENTE | Solo existen herramientas aisladas. Se creara un shell privado comun. |
| Roles de plataforma | AUSENTE | Los roles de equipo y `pachangas_security_role` no constituyen RBAC global. Se creara autoridad privada separada. |
| `/admin/conduct` | PARCIAL | La UI usa las RPC canonicas de conducta, pero su comprobacion de rol ocurre en cliente. Se integrara sin duplicar moderacion y se protegera en servidor. |
| `/admin/simulation-world` | IMPLEMENTADO COMO LAB | Ya esta protegido por flag de entorno y devuelve 404 cuando esta deshabilitado. Solo se enlazara para `platform_owner` en entornos permitidos. |
| Asistencia y no-show | IMPLEMENTADO | Existen cierres, revisiones, eventos, idempotencia y RPC autoritativas. Se reutilizaran. |
| Conducta y restricciones sociales | IMPLEMENTADO/PARCIAL | Casos, evidencias, triage, warnings, restricciones y apelaciones existen. El rol legado se adaptara al RBAC de plataforma. |
| Usuarios globales | AUSENTE | No hay listado paginado de Auth ni detalle transversal. Se implementara solo en servidor. |
| Equipos, jugadores y partidos | IMPLEMENTADO COMO PRODUCTO | Existen tablas normalizadas y read models, ademas del payload de compatibilidad. El panel leera las fuentes canonicas y paginara en servidor. |
| Retos y Mercado | IMPLEMENTADO COMO PRODUCTO | Existen estados, eventos, recibos y busqueda. Se crearan vistas administrativas de lectura. |
| Rankings/TOPS | PARCIAL | Hay motores y laboratorios, pero no todo es producto. El panel diferenciara `PRODUCT`, `LAB` y `OFF`. |
| Achievements, cajas y cosmeticos | IMPLEMENTADO | Existen catalogos, grants, inventarios, recibos y Team Cosmetic Rewards. Se construira trazabilidad de lectura sin alterar politicas. |
| Notificaciones de usuario | IMPLEMENTADO | Hay preferencias, centro, outbox y deduplicacion. No existe una herramienta global de anuncios segura. |
| Billing por equipo | IMPLEMENTADO | `pachanga_groups` conserva el estado local, y Checkout/Portal/Webhook usan Stripe. No se creara un segundo estado de suscripcion. |
| Observabilidad Stripe | PARCIAL | Existe ledger idempotente de webhooks. Faltan conciliacion y vistas financieras de solo lectura. |
| Telemetria PWA | PARCIAL | `/api/client-telemetry` sanea y escribe en logs, pero no existe historico consultable. |
| Supabase health | AUSENTE | No existe panel. Se mostraran solo metricas verificables y `UNKNOWN` cuando falte acceso. |
| Vercel health | AUSENTE | No existe panel. Se consultaran deployments y uso solo mediante API oficial y token server-only. |
| Audit ledger de plataforma | AUSENTE | Se creara un ledger privado, secuenciado e idempotente para toda mutacion administrativa. |

## Contratos conservados

- El servidor es la unica autoridad; el navegador solo envia intenciones.
- Ningun rol de equipo concede acceso de plataforma.
- No se exponen claves `service_role`, Stripe, Supabase Management ni Vercel.
- Las superficies administrativas y sus APIs usan `private, no-store`.
- Infraestructura, Stripe y billing son lectura y diagnostico en V1.
- No hay borrado de usuarios, equipos o partidos.
- Ningun hallazgo produce una sancion automatica.
- Las integraciones no configuradas devuelven estado `UNKNOWN`, nunca un verde ficticio.

## Fuentes oficiales verificadas

- Supabase Management API: autenticacion, limites de peticiones y endpoints de uso documentados en <https://supabase.com/docs/reference/api/usage>.
- Supabase Auth Admin: `updateUserById` es exclusivamente server-side y soporta `ban_duration`; los access tokens existentes siguen vigentes hasta expirar, por lo que una suspension debe considerar tambien sesiones y guardas de producto. <https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid>
- Stripe: las claves restringidas permiten permisos de lectura por recurso y deben permanecer en servidor. <https://docs.stripe.com/keys-best-practices>
- Vercel: deployments, logs y billing/usage se consultan mediante su REST API autenticada. <https://vercel.com/docs/rest-api>

## Siguiente hito

1. Autoridad privada de roles, bootstrap y audit ledger.
2. Sesion administrativa validada en servidor y contratos de permisos.
3. Read models paginados y shell responsive.
4. Acciones permitidas, conectores de salud y bateria adversarial.

Este informe se actualizara con migraciones, pruebas, Preview, staging y resultado final antes de cerrar el PR.
