# Team Operational State V1 Report

Fecha: 2026-08-30 CEST

## Checkpoint

- Base inicial: `9270f3a398622e0e9bc43d001beec6d6bf338b99`.
- Rama: `codex/team-operational-state-v1`.
- PR: #227.
- Identidad canónica del equipo: `public.pachanga_groups`.
- Autoridad de estado: PostgreSQL/Supabase.
- Stripe, Rating V2, Rewards, Cosmetics, Billing y Conduct: no modificados.
- Validación: solo Simulation World, Demo World saneado y canary reversible.

## Modelo canónico

| Dimensión | Valores | Regla |
| --- | --- | --- |
| Lifecycle | `ACTIVE`, `ARCHIVED` | Lo administra el owner dentro de las restricciones permitidas. |
| Enforcement | `CLEAR`, `UNDER_REVIEW`, `LIMITED`, `SUSPENDED` | Solo decisión humana y explícita de plataforma. |
| Effective status | `ACTIVE`, `UNDER_REVIEW`, `LIMITED`, `SUSPENDED`, `ARCHIVED` | Se deriva en PostgreSQL; el cliente no lo envía. |
| Preset | `SOCIAL_ONLY`, `NEW_ACTIVITY_ONLY`, `COMPETITION_ONLY`, `FULL_PLATFORM_SUSPENSION`, `CUSTOM` | Se copia a scopes versionados. |
| Continuity | cuatro políticas canónicas | Nunca se infiere de Billing, Conduct o actividad. |

Existe una sola fila vigente por Team en
`private.pachanga_team_operational_states_v1`. Cada cambio crea revisión,
evento, receipt, secuencia de servidor e invalidación. La inicialización es
idempotente, `ACTIVE + CLEAR`, usa `MIGRATION_INITIALIZATION` y no notifica.

## Precedencia

1. `pachanga_groups` conserva identidad y owner.
2. lifecycle y enforcement se resuelven por la autoridad Team V1.
3. restrictions determinan scopes bloqueados.
4. continuity determina únicamente operaciones de competiciones existentes.
5. Billing, estado del owner, Conduct, Triage e inactividad son señales
   independientes y nunca escriben el estado Team.

Archivar no equivale a sancionar. Suspender al owner no suspende el Team. Un
Billing `past_due` no suspende el Team. Conduct no puede aplicar, levantar ni
expirar una medida Team.

## Escritura y lectura

La única autoridad de mutación es
`command_pachanga_team_operational_state_v1`. Recibe `operationId`, Team,
`expectedRevision`, acción, payload allowlisted y metadatos saneados. El
servidor resuelve actor, owner actual, capability, estado, reloj, secuencia y
snapshot confirmado.

Acciones owner:

- `team.lifecycle.archive`;
- `team.lifecycle.restore`;
- `team.appeal.create`;
- `team.appeal.submit`;
- `team.appeal.withdraw`.

Acciones de plataforma con capability exacta:

- review open/close;
- restriction apply/modify/lift;
- suspend/restore;
- continuity set;
- appeal review/resolve.

`team.expire` queda limitado a `service_role`. Las escrituras directas de
`anon` y `authenticated` están revocadas. Las tablas canónicas privadas no son
accesibles por esquema o ACL; la invalidación pública tiene RLS y una policy
de lectura para miembros/owner/plataforma.

## Producto

- Gestión owner: `/equipo/estado`.
- Home: aviso compacto solo cuando el estado requiere atención.
- Control Center: `/admin/teams` y `/admin/teams/[teamId]`.
- APIs: no-store, same-origin, write gate PWA y sin `service_role` en cliente.
- Realtime: invalidación exclusivamente; `SUBSCRIBED`, evento y reconexión
  siempre terminan en refetch canónico.
- Offline: puede leer el último read model; nunca archiva, apela o confirma una
  operación y no existe cola deportiva offline.

## Migraciones

| Versión | Nombre | SHA-256 |
| --- | --- | --- |
| `20260829221256` | `team_operational_state_revisions_v1` | `7754814c811a56bb4cf6be99f9ab8ea500f77cbb61d3db433f3ea745440296a4` |
| `20260829221258` | `team_operational_restrictions_continuity_v1` | `df86de2c8ca6313f3bd2c34e2b2112b251fba7990a9c01a7a6dbf14f98ced450` |
| `20260829221300` | `team_operational_reviews_appeals_v1` | `5b05573b030108fc81fca90ef55e27e7c80524c3f8cd1aaee2ec78cf75c1133d` |
| `20260829221302` | `team_operational_command_authority_v1` | `1d33ddac13af531f4e1bda937759f50e1538dc26074002a0d80f041b0492f302` |
| `20260829221304` | `team_operational_cross_product_guards_v1` | `c04688eb39b24cad2ea5c4e369fc6e3706255bd85b6620b51175d7100a773eb6` |
| `20260829221306` | `team_operational_read_models_control_center_v1` | `d02d8c3960c6f16a61bb99c676afa05f7eae748016a6dd5e9ef4474c23374a22` |
| `20260829221309` | `team_operational_rls_realtime_notifications_v1` | `4ab46276f48264eac6fe546cbe71a22c17de238ed25b54057733303c6c5fa839` |
| `20260829221312` | `team_operational_hardening_indexes_flags_v1` | `d3335bd87e95bbc7088104ea26a52333034358ed7813e2c3fc441641a87e0c22` |

Las 204 migraciones anteriores permanecen sin cambios. Fresh bootstrap y
upgrade terminan en ledger 212 y el esquema reproducible tiene hash
`11af8ca0694dbb4373cb58c52509adbf70689d0c563467cf4ed86f60dbf73423`.

## Validación

- Contratos focales: 11/11.
- Suite global: Node 20/20 + TS/TSX 629/629 = 649/649.
- Skip/todo/cancelled: 0/0/0.
- SQL/RLS/idempotencia: PASS; cleanup PASS.
- Concurrencia: PASS, incluida review close vs restriction.
- Escala: 10.000 Teams, 50.000 restrictions, 100.000 invalidations; rollback y
  cleanup PASS.
- Typecheck/build: PASS.
- Lint propio: PASS.
- Lint global: 22 errores y 18 avisos preexistentes; cero hallazgos Wave 8B.

## Staging sintético

Branch efímero `uhrrsjpyeefgeabthswj`, ledger 212. La ejecución final creó 9
cuentas sintéticas, 7 Teams y 11 sesiones, probó dos dispositivos, Realtime,
owner transfer, apelación, caducidad, Billing/Conduct independientes, Mercado,
Retos y carrera de revisión. Resultado:

- `TEAM_OPERATIONAL_STATE_V1_STAGING_PASS`;
- un ganador y un `STALE_REVISION`;
- cero usuarios o Teams no sintéticos;
- cero destinatarios externos de notificación;
- cero PII o notas privadas en proyecciones públicas;
- destrucción completa del branch requerida al cerrar Preview QA.

## Estado

La implementación y staging están completos. Merge, migraciones productivas,
activación secuencial, canary con rollback, deployment y cleanup se registran
en `TEAM_OPERATIONAL_STATE_V1_PRODUCTION_RELEASE.md`.
