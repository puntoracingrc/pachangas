# Referee Platform V1 Report

Estado: `READY FOR REVIEW`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Rama | `codex/referee-platform-v1` |
| Base real | `da6dace3a1a5d20de9fdba0d34174f916a2b2c61` |
| Commit de implementacion | `ae1f705a4f5a4ba74c3617e0b145e155a17b4e84` |
| PR | [#157](https://github.com/puntoracingrc/pachangas/pull/157) |
| Cierre local | `2026-08-21 22:47 CEST` |
| Entorno | Worktree aislado, Node `24.16.0`, Supabase/PostgreSQL local y staging aislado |
| Supabase staging | `iozcjirlfytryzrcmrnq`, upgrade `110 -> 113` y E2E autenticado completados |
| Preview | [Vercel Preview](https://pachangas-git-codex-refer-9eb6d8-persianas-almar-web-s-projects.vercel.app) |
| Produccion | No modificada |
| Merge | No realizado |

El checkout principal contenia trabajo ajeno y no se utilizo para implementar
R3. El worktree se conserva porque el PR no esta fusionado.

## Resultado

R3 incorpora una identidad arbitral universal e independiente de la ficha de
jugador, relaciones verificables con varios Clubs, Mercado de arbitros,
asignaciones ligadas exclusivamente al partido canonico y estadisticas
derivadas de esas asignaciones. Un usuario puede ser jugador y arbitro, solo
arbitro o solo jugador; ninguna de esas identidades concede permisos de la otra.

No se han creado Rating, GRL, facetas, estrellas, votos, ranking arbitral,
pagos, sanciones, tarjetas ni motores de liga/torneo. Tampoco se modifica Demo
World, Season Score, resultados deportivos, Conduct, rewards o Billing.

## Migraciones forward-only

| Version | Contenido |
| --- | --- |
| `20260821182105` | Foundation, perfiles, modalidades, zonas, disponibilidad, relaciones, asignaciones, estadisticas, events, receipts, RLS, Realtime y flags OFF. |
| `20260821182106` | Autoridad transaccional de perfiles, Club relationships, canonical assignment, reemplazos, reconciliacion y permisos de `club_referee_manager`. |
| `20260821182107` | Control Center, busqueda, health, operaciones administrativas, rate limits, APIs publicas y grants minimos para invalidaciones Realtime. |

No se ha modificado ninguna de las `110` migraciones previas. El bootstrap
local desde cero aplica `113` migraciones. El upgrade comprobado parte del
ledger productivo `110` y aplica unicamente las tres migraciones R3.

Al aplicar inicialmente staging mediante la API de Supabase, el ledger recibio
versiones de reloj distintas. Se reparo exclusivamente el historial del branch
de staging para que sus tres versiones finales coincidan exactamente con el
repositorio; el SQL aplicado no se reescribio y produccion no se consulto para
escritura.

## Entidades

| Dominio | Entidades |
| --- | --- |
| Perfil | `pachanga_referee_profiles`, `pachanga_referee_modalities`, `pachanga_referee_service_areas` |
| Disponibilidad | `pachanga_referee_availability_windows`, `pachanga_referee_availability_exceptions` |
| Red Club | `pachanga_club_referee_relationships`, invitation secrets privados |
| Partido | `pachanga_referee_assignments` sobre `pachanga_canonical_matches` |
| Derivados | `pachanga_referee_statistics_snapshots`, `pachanga_referee_invalidations` |
| Autoridad privada | foundation settings, operation receipts y event ledger |

Events y receipts son inmutables y ordenados por `server_sequence`. Las tablas
de autoridad no admiten INSERT/UPDATE/DELETE directo de `anon` ni
`authenticated`.

## Autoridad central

Toda escritura R3 recibe `operationId`, `expectedRevision`, accion, payload y
metadata cliente saneada. PostgreSQL resuelve `auth.uid()`, permisos, estado,
revision, reloj, secuencia, partido canonico y snapshots de horario. Una
revision obsoleta devuelve `STALE_REVISION`; reutilizar una operacion con otro
payload falla cerrado; el replay identico devuelve el receipt canonico.

El cliente no confirma estado optimista ni mantiene cola offline deportiva.
Solo conserva read models en cache. Realtime entrega una invalidacion acotada
por RLS y el dispositivo vuelve a pedir el snapshot canonico completo de la
entidad afectada. Las APIs privadas usan `private, no-store`.

RPCs principales:

- `command_pachanga_referee_platform_v1`;
- `command_pachanga_club_referee_manager_v1`;
- `command_pachanga_referee_platform_admin_v1`;
- `get_my_pachanga_referee_platform_v1`;
- `search_pachanga_referee_market_v1`;
- `get_pachanga_public_referee_v1`;
- `get_pachanga_referee_assignment_v1`;
- `get_pachanga_platform_referees_v1` y detalle/health de plataforma.

Las funciones `SECURITY DEFINER` fijan `search_path`, no aceptan un actor
autoridad enviado por el navegador y vuelven a validar capabilities dentro de
la transaccion.

## Feature flags

- `referee_foundation_enabled`
- `referee_self_service_enabled`
- `referee_public_profiles_enabled`
- `referee_marketplace_enabled`
- `referee_club_relationships_enabled`
- `referee_assignments_enabled`

Las seis nacen `false`. Los flags subordinados no pueden habilitarse sin
foundation. Staging los activo durante QA y termino otra vez con los seis OFF.

## Superficies

| Ruta | Funcion |
| --- | --- |
| `/perfil/arbitro` | Perfil privado y autogestion canónica. |
| `/arbitros/[slug]` | Perfil publico minimizado, gated y no indexable. |
| `/mercado?tab=arbitros` | Mercado integrado con filtros server-side. |
| `/admin/referees` | Control Center, flags, lifecycle, verificacion, estadisticas y evidencia. |
| `/laboratorio-referee-platform` | Flujo interno completo de R3 en staging. |

Perfil privado, perfil publico, Control Center y laboratorio declaran
`noindex,nofollow`. El perfil publico no devuelve email, telefono, domicilio,
Auth UUID, notas privadas, excepciones privadas, receipts, eventos, motivos de
suspension ni identidad de invitaciones.

## Estado funcional

- Perfil: `draft -> active -> suspended/restored -> archived`.
- Verificacion separada: `unverified`, `pending`, `verified`, `rejected`,
  `revoked`; no activa ni publica por si sola.
- Mercado separado: `not_listed`, `listed`, `paused`.
- Disponibilidad: `AVAILABLE`, `LIMITED`, `UNAVAILABLE`, ventanas IANA y
  excepciones privadas.
- Relaciones: invitacion Club, solicitud arbitro, aceptacion/rechazo,
  cancelacion, finalizacion, visibilidad y multi-Club.
- Asignaciones: propuesta, aceptacion, rechazo, confirmacion, cancelacion,
  reemplazo y reconciliacion por finalizacion canonica.
- Solo `MAIN_REFEREE` es operativo en R3; los roles futuros no se presentan como
  disponibles.
- Estadisticas: refresh incremental y `full_rebuild` con checksum equivalente.
- Disciplina: `NOT_AVAILABLE`; amarillas, rojas y azules permanecen `null`.

## Evidencia local

| Gate | Resultado |
| --- | --- |
| Tests completos | PASS, `326/326`, incluido build |
| Tests R3 TypeScript | PASS, `18/18` |
| SQL/RLS y adversarial | PASS |
| Idempotencia y concurrencia | PASS |
| R1 regression | PASS, `15/15`, DB y concurrencia |
| R2 regression | PASS, `19/19`, DB/adversarial y concurrencia |
| Fresh bootstrap | PASS, `113` migraciones |
| Upgrade | PASS, `110 -> 113` solo R3 |
| Escala exacta | PASS: `10k/50k/20k/100k/100k/10k` |
| E2E staging | PASS, dos clientes y Realtime + refetch |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| ESLint focalizado | PASS |
| ESLint global | Deuda heredada: `43` hallazgos (`23` errores, `20` warnings); ninguno introducido por R3 |
| `git diff --check` | PASS |

La escala exacta representa `10.000` perfiles, `50.000` modalidades,
`50.000` zonas, `20.000` relaciones, `100.000` asignaciones, `100.000`
ventanas de disponibilidad y `10.000` snapshots estadisticos.

## Rendimiento

| Lectura/operacion | p50 | p95 |
| --- | ---: | ---: |
| Admin list | `12.990 ms` | `14.190 ms` |
| Assignment conflict | `0.062 ms` | `0.164 ms` |
| Club relationship lookup | `60.243 ms` | `66.172 ms` |
| Mercado | `31.946 ms` | `33.878 ms` |
| Perfil privado | `3.503 ms` | `4.360 ms` |
| Perfil publico | `0.116 ms` | `0.177 ms` |
| Rebuild query | `0.035 ms` | `0.050 ms` |

EXPLAIN confirma uso de los indices de solapamiento y modalidad. Los avisos de
Advisors sobre FKs auxiliares e indices aun no usados se conservan como
informativos: el contrato exige no crear indices especulativos cuando la carga
representativa no demuestra su necesidad.

## Seguridad y Advisors

Advisors de staging conserva deuda global historica. Para R3 informa RLS sin
policy directa en tablas de autoridad y RPCs `SECURITY DEFINER` ejecutables por
los roles estrictamente necesarios. Es intencionado: las tablas fallan cerradas
y la RPC es la unica frontera de escritura. La policy de invalidaciones solo
entrega eventos dirigidos y nunca el snapshot privado.

Durante staging se detecto que el helper RLS privado de Realtime no tenia grant
explicito en el entorno endurecido. Se corrigio en la primera migracion y se
anadio una regresion estatica. No se abrieron escrituras directas.

## Staging

El E2E autenticado demostro:

- usuario sin equipo crea perfil y usuario con PlayerProfile conserva ambas
  identidades;
- modalidades, zonas, disponibilidad, Mercado y privacidad publica;
- Club invita a usuario registrado y a email, solicitud inversa y multi-Club;
- token alterado/reutilizado rechazado;
- propuesta, accept/decline, confirm/cancel, replace y reconcile;
- binding canonico obligatorio, snapshot de horario y rechazo de solapamiento;
- dos dispositivos reciben invalidacion y convergen por refetch;
- Rating del jugador usado como invariante permanece exactamente igual.

Estado final del branch aislado:

- seis flags R3 OFF;
- perfiles activos/listados fixture `0`;
- relaciones activas `0`;
- asignaciones activas `0`;
- evidencia Rating, Conduct y rewards creada por R3 `0`;
- historia QA archivada sin autoridad puede permanecer.

## QA visual y PWA

Se probaron perfil privado, perfil publico, Mercado, Control Center y
laboratorio en `1440x900`, `1920x1080`, `390x844`, `360x800` y `844x390`:

- `0` overflow horizontal;
- `0` controles visibles recortados;
- `0` imagenes rotas;
- `0` errores o warnings de consola;
- navegacion y datos canonicos presentes en las cinco superficies.

Se comprobaron modo claro del sistema y `prefers-reduced-motion: reduce`. El
manifest mantiene `fullscreen` con fallback `standalone`; el bridge prueba la
clasificacion PWA standalone, version/SW metadata y bloqueo de escrituras
offline. R3 añade sus operaciones al clasificador de escrituras protegidas.

La Preview exacta del commit de implementacion carga el laboratorio y falla
cerrada sin sesion/flags, como exige el contrato. El deployment Vercel y sus
checks estan en verde.

## Invariantes

| Dominio | Resultado |
| --- | --- |
| Rating V2/facetas/assessments | Intacto |
| Resultados y goleadores | Intactos |
| Disciplina y Conduct | Intactos; R3 no crea sanciones ni tarjetas |
| Rewards/cajas/cosmeticos | Intactos |
| Billing/pagos | Intactos |
| Rankings/Season Score | Intactos; `rankings.write` preservado |
| Canonical Match | Reutilizado, no duplicado ni mutado por backfill productivo |
| Demo World | Intacto |

Produccion modificada: **NO**. Supabase produccion: **NO**. Merge: **NO**.
