# Competition Configuration Center V1 - Production Release

## Estado

`PRODUCTION RELEASE CLOSED / PRIVATE BETA ACTIVE`

La release coordinada termino sin ampliar alcance. Las migraciones se aplicaron
forward-only, los gates privados se activaron mediante RPC de plataforma y el
smoke efimero termino con revocacion y cleanup verificados.

## Baseline

| Dato | Valor |
| --- | --- |
| Main inicial | `4fa505fd7323d72398e4ee637e818205b0d6fdab` |
| Ledger remoto esperado antes de Wave 5A | `152` |
| PR | `#202` |
| Migraciones previstas | `6`, forward-only |
| Main funcional final | `aafd4f8816374bd8ab67951ee9f30d6c8bdbcbf0` |
| Ledger final | `158` |
| Deployment Vercel | `dpl_GtWUh6s1h5EzkyNVVAYzAiqcQiCk` / `READY` |
| Artifacto Vercel | `https://pachangas-jeu9lctc6-persianas-almar-web-s-projects.vercel.app` |
| Dominio | `https://pachangasiq.com` |
| Staging Preview | `4688f08af778d7488e9435ce40563a8817a8e83f` / `READY` |
| Backup previo | `COMPLETED`, `2026-08-26T00:21:15.764Z` |
| Produccion | `MODIFICADA DE FORMA COORDINADA / SMOKE PASS` |

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

- Node `20/20`, TS/TSX `505/505`, total agregado `525/525`;
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

### Reconciliacion de tests

El baseline informado `509` corresponde a `20 Node + 489 TS/TSX`. Los numeros
`504` y `505` vistos despues eran subtotales TS/TSX, no totales de `npm test`.
La rama anade 20 pruebas y reemplaza cuatro contratos anteriores, neto `+16`:

| Revision | Node | TS/TSX | Total | Skip/todo/cancelled |
| --- | ---: | ---: | ---: | --- |
| Base `4fa505f` | 20 | 489 | 509 | `0/0/0` |
| Intermedia `cfa47bb` | 20 | 504 | 524 | `0/0/0` |
| Final funcional `9f8c266` | 20 | 505 | 525 | `0/0/0` |

Los 20 nombres nuevos cubren 15 contratos del Configuration Center, dos de
Demo World V2.3 y tres contratos actualizados de League Private Beta. Los
cuatro nombres retirados fueron reemplazados por equivalentes V2.3/Wizard V2;
no se perdio cobertura funcional. El paso `504 -> 505` es la regresion E2E de
staging anadida en `bbd0be7`.

## Evidencia de staging

- ledger reconciliado e instaladas exactamente siete migraciones: la
  `20260826105132` que faltaba en la rama y las seis de Wave 5A;
- flags de Configuration Center y Wizard V2 nacieron `false`;
- E2E autenticado `PASS` con organizer Team y Club, Wizard V2, preset sencillo,
  autoria avanzada, freeze, revision futura, 15 partidos y 5 jornadas;
- carrera de dos dispositivos: un ganador y un `STALE_REVISION`;
- Realtime: invalidacion seguida de refetch canonico;
- Preview y API autenticada conectadas al Supabase de staging mediante
  variables limitadas a la rama;
- cleanup: competicion cancelada, cero bundles QA activos, cero drafts activos y
  todos los flags restaurados.

Incidencias cerradas durante staging: orden explicito League Beta -> Referee
Assignments -> Configuration Center, fixture F11 acotado al grant y al motor
de calendario QA, ruta canonica `/demo`, y eliminacion del cruce accidental
entre JWT de staging y API Preview con autoridad distinta. No se borro historial
auditable para sortear rate limits.

## Ledger productivo

El readback remoto confirma 158 entradas y estas seis versiones finales. El
hash remoto es el digest canonico de statements del ledger; el SHA-256 local
corresponde al archivo SQL versionado.

| Version y nombre remoto | Statements | Hash remoto | SHA-256 archivo |
| --- | ---: | --- | --- |
| `20260826123000 competition_configuration_center_schema_v1` | 36 | `0cc0738413014702f8fd3e3e67f0d3fcffe9abc610132927f53fa43a9745a33a` | `03990cfe5c0ceafe068a228a968ad79a7c0da105d41acbc3c7c35c8c9ea5e1a7` |
| `20260826123100 competition_configuration_rules_v1` | 25 | `3e96dead5dd448af696984634bb1ad2ef730897f601261a4cb33b3fd7df40e6d` | `484ec5c4afd467cedce41686479a98ca3bc9952fe517a77621f5d101ce52d6d1` |
| `20260826123200 league_wizard_v2_commands` | 21 | `5465256a83eadd0fac2179105ffa8c402ad61b2ef939b818758fc36d60494366` | `78fb01f05ddc35666ca7d64991d73f9cac19d3e2eaf9fb0fba7e93b35b49e36d` |
| `20260826123300 competition_configuration_commands_v1` | 27 | `d46eac72f358a4fefc120d2108c83512fe3c65bd0b10183dc491a407d5f0996a` | `58dad56edcc5cd8c1dd6c5fe8f6b32468ca1d851df507a5fbe6142ca064cb709` |
| `20260826123400 competition_configuration_engine_policy_v1` | 54 | `9be6e85aa231a0dccc401bd008c3c735d027ee2cfc61809c154eb2e188c06b15` | `152a4c4a3792f2d5c069e02fcb0827272ccd613566526007ffeab045bda23570` |
| `20260826123500 competition_configuration_control_center_v1` | 13 | `b4d82c3ee69c6b0b7b04406e05ac05e7ba0d55330e84d2c5d37e3eb40c5ad675` | `26303f36e515762d5b74a86b5e6a0c232bbf96b373758335ad353b7c13f06941` |

Hash de esquema fresh/upgrade:
`37fd6dd7fd8f7e62caf4faf7defff5844ba062d1d4b93477c7a54f3cdb06d1e2`.

## Activacion y flags

Los flags Wave 5A nacieron OFF. La activacion se realizo solo mediante
`command_pachanga_competition_configuration_platform_v1`, operacion
`5cb4970c-8117-42ca-b3ca-152d346234d3`, revision `9 -> 10`, secuencia de
servidor `1101`. No se uso `UPDATE` directo.

| Flag/capacidad | Readback final |
| --- | --- |
| Configuration Center | `true` |
| League Wizard V2 | `true` |
| League Private Beta / Creation | `true` / `true` |
| Discovery publico | `false` |
| Registro/calendario/standings publicos | `false` / `false` / `false` |
| Excepciones/disciplina publicas | `false` / `false` |
| Pagos | `OFF` |
| Tournament Engine | `NOT STARTED / OFF` |
| Pairing manual/hibrido | `OFF / OFF` |

## Smoke productivo efimero

El flujo real concedio temporalmente autoridad QA, creo Competition/Edition y
Wizard V2, aplico preset, guardo disciplina avanzada (`YELLOW 4`, `BLUE 7
minutos`), exigio arbitro principal, valido las doce secciones y obtuvo el
resumen canonico. Despues cancelo draft y Competition, revoco los 14 grants y
desactivo el rol temporal mediante RPC.

| Readback QA final | Conteo |
| --- | ---: |
| Drafts activos / cancelados | 0 / 1 |
| Competiciones activas / canceladas | 0 / 1 |
| Grants activos / revocados | 0 / 14 |
| Roles temporales activos | 0 |
| Wizard drafts | 0 |
| Entries / plans / slots / rounds | 0 / 0 / 0 / 0 |
| Match contexts / canonical matches | 0 / 0 |
| Resultados / eventos / assignments | 0 / 0 / 0 |
| Sesiones auth QA | 0 |

Las identidades sinteticas retenidas son FKs historicas inertes: no conservan
rol, sesion, grant ni capacidad activa.

## Demo, PWA y responsive

- Demo World V2.3 productiva: dos RuleRevision, disciplina personalizada,
  arbitro obligatorio, tarifa privada y capacidades futuras OFF;
- desktop `1440x900`, portrait `390x844` y landscape `844x390`: 0 overflow
  raiz, 0 imagenes rotas y 0 errores de consola;
- `/sw.js`: `200`, `no-cache, no-store, must-revalidate`, version
  `2.0.0+sw.aafd4f881637`, controller activo y sin worker esperando;
- reload offline y reconexion: `PASS`, sin fake success;
- manifest fullscreen con fallbacks standalone/minimal-ui/browser;
- `/api/client-policy`: `200`, `private, no-store`, minimo `2.0.0`.

## Observabilidad y deuda

No hubo errores `fatal/error` del deployment exacto. Se observaron seis `503`
periodicos en `/api/internal/rankings/refresh`, todos correspondientes a la
deuda preexistente `CRON_SECRET`; no pertenecen a Wave 5A. Advisors focales no
detectaron una apertura RLS nueva. Permanecen dos avisos informativos de indices
FK sobre observaciones privadas de incidentes arbitrales y warnings genericos
de funciones `SECURITY DEFINER` ya revisadas; no justifican otra migracion en
este cierre.

## Readback final

`PASS`. Rating V2, assessments, Rewards, Player Cosmetics, Team Cosmetics,
Conduct y Billing permanecen intactos. No se inicio R6 ni Tournament Engine.
