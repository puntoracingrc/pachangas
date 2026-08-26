# Competition Configuration Center V1 - Production Release

## Estado

`PRE-RELEASE GATE COMPLETE / STAGING AND PRODUCTION PENDING`

Este informe se actualizara con readbacks remotos, SHA final, deployment y
cleanup despues de ejecutar el release coordinado. No interpreta el gate local
como evidencia de produccion.

## Baseline

| Dato | Valor |
| --- | --- |
| Main inicial | `4fa505fd7323d72398e4ee637e818205b0d6fdab` |
| Ledger remoto esperado antes de Wave 5A | `152` |
| PR | `#202` |
| Migraciones previstas | `6`, forward-only |
| Main final | `PENDING` |
| Ledger final | `PENDING` |
| Deployment Vercel | `PENDING` |
| Produccion | `NO MODIFICADA EN EL GATE LOCAL` |

## Secuencia autorizada

1. Readback de `supabase migration list --linked` y conciliacion del ledger.
2. Backup recuperable y baseline de flags/datos protegidos.
3. Aplicar las seis migraciones en staging.
4. E2E autenticado con organizer Club y organizer Team.
5. Cleanup de staging: cero drafts, grants y datos pendientes; flags restaurados.
6. Fusionar PR #202 sobre el main vigente.
7. Aplicar las mismas migraciones forward-only a produccion.
8. Esperar deployment Vercel `READY` del SHA exacto.
9. Activar solo Configuration Center y Wizard V2 privados.
10. Mantener public registration/calendar/standings/discipline, pagos,
    Tournament Engine y manual/hybrid pairing OFF.
11. Smoke productivo con grant y draft efimeros.
12. Cancelar draft, revocar grant y confirmar cero residuos.
13. Publicar Demo World V2.3 y repetir smoke GET-only.
14. Registrar readbacks finales y retirar el worktree solo tras cumplir AGENTS.

## Criterios de parada

Detener antes de cualquier paso destructivo ante:

- perdida, mutacion o corrupcion de RuleRevision;
- aplicacion retroactiva silenciosa;
- exposicion de configuracion o tarifa privada;
- RLS abierta o direct writes autenticados;
- ledger divergente o migracion no reproducible;
- cambios en Rating, Rewards, Conduct o Billing;
- contradiccion que permita publicar un reglamento invalido.

## Rollback

No se usaran down migrations. Antes de activar flags, el rollback es conservar
los objetos instalados e inactivos. Despues de activar, la primera respuesta es
desactivar los flags privados y mantener los datos auditables. Cualquier cambio
de reglas publicado se revierte mediante una RuleRevision posterior, nunca
reescribiendo historia.

## Evidencia local previa

- 504/504 tests funcionales;
- 15/15 Configuration Center;
- 18/18 Wizard V2;
- siete carreras con un unico ganador;
- fresh bootstrap y upgrade 152->158 equivalentes;
- SQL/RLS y Advisors focales limpios;
- build de 50 rutas y typecheck PASS;
- lint focalizado PASS;
- PWA standalone controlada por Service Worker;
- matriz visual requerida sin overflow ni controles cortados;
- Demo V2.3 determinista y `remoteWrites=0`.

## Readback final

`PENDING REMOTE RELEASE`.
