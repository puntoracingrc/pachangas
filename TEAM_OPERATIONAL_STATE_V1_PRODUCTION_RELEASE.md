# Team Operational State V1 Production Release

Status: COMPLETE / ACTIVE

Fecha de cierre: 2026-08-30 (Europe/Madrid)

## Alcance y politica permanente

Wave 8B se valido exclusivamente con:

- Simulation World aislado y determinista;
- Demo World saneado, sin PII, Auth IDs ni escritura publica;
- canary productivo sintetico dentro de una transaccion terminada con
  `ROLLBACK`.

No se utilizaron Clubs, equipos, arbitros, organizadores ni usuarios reales
para QA. No se enviaron notificaciones QA a personas reales, no se publicaron
competiciones QA, no se crearon pagos o Customers y no quedaron sesiones,
fixtures ni entidades sinteticas. Wave 8C no se inicio.

## Version publicada

- `main` inicial: `9270f3a398622e0e9bc43d001beec6d6bf338b99`.
- HEAD funcional: `213a086665e0f7f1266215039126e4301c34d814`.
- PR funcional: [#227](https://github.com/puntoracingrc/pachangas/pull/227).
- merge SHA productivo: `f8c543c68c6730f85f3990cf323392d64ef3e06f`.
- deployment Vercel: `dpl_GXqGPW3MPpAEw5egF65LDxE4f3ZL`.
- deployment exacto: `https://pachangas-hrv38jxxl-persianas-almar-web-s-projects.vercel.app`.
- dominio productivo: `https://pachangasiq.com`.
- estado Vercel: `READY`, target `production`, SHA exacto confirmado.

## Migraciones y readback

El baseline productivo tenia 204 migraciones y terminaba en
`20260829152250`. Antes de aplicar Wave 8B se comprobo un backup fisico
`COMPLETED`, cero transacciones largas, cero esperas de lock y cero residuos
sinteticos.

Se aplicaron exactamente estas ocho migraciones, sin reescribir ninguna ya
ejecutada:

| Version | Migracion | SHA-256 |
| --- | --- | --- |
| `20260829221256` | `team_operational_state_revisions_v1` | `7754814c811a56bb4cf6be99f9ab8ea500f77cbb61d3db433f3ea745440296a4` |
| `20260829221258` | `team_operational_restrictions_continuity_v1` | `df86de2c8ca6313f3bd2c34e2b2112b251fba7990a9c01a7a6dbf14f98ced450` |
| `20260829221300` | `team_operational_reviews_appeals_v1` | `5b05573b030108fc81fca90ef55e27e7c80524c3f8cd1aaee2ec78cf75c1133d` |
| `20260829221302` | `team_operational_command_authority_v1` | `1d33ddac13af531f4e1bda937759f50e1538dc26074002a0d80f041b0492f302` |
| `20260829221304` | `team_operational_cross_product_guards_v1` | `c04688eb39b24cad2ea5c4e369fc6e3706255bd85b6620b51175d7100a773eb6` |
| `20260829221306` | `team_operational_read_models_control_center_v1` | `d02d8c3960c6f16a61bb99c676afa05f7eae748016a6dd5e9ef4474c23374a22` |
| `20260829221309` | `team_operational_rls_realtime_notifications_v1` | `4ab46276f48264eac6fe546cbe71a22c17de238ed25b54057733303c6c5fa839` |
| `20260829221312` | `team_operational_hardening_indexes_flags_v1` | `d3335bd87e95bbc7088104ea26a52333034358ed7813e2c3fc441641a87e0c22` |

Readback final:

- ledger: 212;
- ultima migracion: `20260829221312`;
- `supabase migration list --linked`: local y remoto conciliados, pendientes 0;
- Team states inicializados: 12/12, todos validos;
- RLS de invalidaciones y ACL privada: activas;
- publicacion Realtime: activa;
- claves foraneas Wave 8B sin indice de cobertura: 0;
- waiting locks: 0;
- transacciones `idle in transaction`: 0.

## Activacion autoritativa

Las migraciones nacieron con los ocho flags en `OFF`. La activacion se realizo
solo mediante `command_pachanga_team_operational_settings_v1`; no hubo
`UPDATE` directo.

Readback canonico final:

- revision de settings: 9;
- server sequence: 21;
- Foundation: ON;
- Enforcement: ON;
- Restrictions: ON;
- Continuity: ON;
- Appeals: ON;
- Cross-product guards: ON;
- Public projection: ON;
- Demo World V3.1: ON.

## Validaciones

### Local y staging

- `npm ci`: PASS; deuda previa de dependencias sin cambios.
- tests: 649/649, separados en Node 20/20 y TS/TSX 629/629.
- skip/todo/cancelled: 0/0/0.
- typecheck: PASS.
- build: PASS.
- lint focal Wave 8B: PASS.
- lint global: deuda previa de 22 errores y 18 warnings; cero hallazgos Wave 8B.
- `git diff --check`: PASS.
- SQL/RLS/idempotencia/concurrencia: PASS.
- escala: 10.000 Teams, 50.000 restricciones y 100.000 invalidaciones, con
  rollback/cleanup.
- staging autenticado: 9 identidades sinteticas, 11 dispositivos, Realtime y
  convergencia canonica; destinatarios externos 0.

### Canary productivo

El canary creo dentro de una unica transaccion seis Teams y nueve identidades
sinteticas. Ejecuto los motores productivos reales y valido:

- `ACTIVE`, `UNDER_REVIEW`, `LIMITED`, `SUSPENDED` y `ARCHIVED`;
- idempotencia con un unico receipt;
- rechazo de revision obsoleta;
- restriccion de Mercado y Retos;
- continuidad de competiciones ya iniciadas;
- transferencia de owner sin perder la restriccion;
- Billing independiente del estado operativo;
- historia deportiva preservada;
- cero destinatarios de notificaciones fuera del namespace sintetico.

La transaccion termino con `ROLLBACK`. El readback posterior devolvio:

- usuarios sinteticos: 0;
- Teams sinteticos: 0;
- Team states sinteticos: 0;
- competiciones sinteticas: 0;
- receipts sinteticos: 0;
- notificaciones sinteticas: 0;
- partidos publicos sinteticos: 0;
- retos sinteticos: 0.

### Demo World V3.1 y responsive

En `https://pachangasiq.com/demo?tab=estado-equipo` se comprobaron los siete
casos saneados:

1. Activo.
2. En revision.
3. Social limitado.
4. Actividad suspendida.
5. Archivado.
6. Cambio de owner.
7. Billing independiente.

La matriz productiva cubrio `/`, `/equipo/estado`, `/admin/teams` y Demo World
en 1440x900, 390x844 y 844x390: 12/12 rutas sin overflow raiz, imagenes rotas
ni errores de consola.

### PWA y logs

- manifest: `display: fullscreen`, fallback `standalone/minimal-ui/browser`.
- Service Worker: `2.0.0+sw.f8c543c68c67`.
- shell y Demo World precacheados; API/Auth/Supabase/Stripe excluidos del cache.
- errores runtime Vercel desde el deployment: 0.
- errores de build Vercel: 0.
- API Supabase reciente: solo 2xx; expiracion Team Operational: 200.
- PostgreSQL durante migracion, activacion y canary: 0 `ERROR/FATAL/PANIC`.
- Realtime: sin errores recientes; la convergencia autenticada ya quedo
  certificada en staging.

Android fisico, iPhone fisico y PWA instalada fisica no se presentan como
`PASS`; siguen siendo QA fisica pendiente y no bloquean esta release sintetica.

## Integridad y limpieza

- Rating V2, Conduct, rewards, Player Cosmetics y Team Cosmetics: intactos.
- Stripe: no modificado; cargos y Customers reales: 0.
- branch Supabase efimero Wave 8B: destruido.
- variables Vercel Preview de la rama: 0.
- deployments Preview Wave 8B retirados: 6.
- produccion conserva exclusivamente su deployment `READY`.
- archivos temporales y secretos: ninguno versionado.
- el worktree se retira solo despues de fusionar este informe y verificar su
  deployment, conforme a la politica de cierre.

## Estado final

Team Operational State V1: `ACTIVE / STABLE`.

Demo World V3.1: `ACTIVE`, saneado y sin escritura publica.

Entidades reales utilizadas en QA: 0.

Wave 8C: `NOT STARTED`.
