# League Operational Exceptions V1 Report

## Estado

`FASE A PASS / RELEASE PRODUCTIVA INACTIVA PENDIENTE`

R4D incorpora una autoridad transaccional para las excepciones posteriores a
la publicacion de un calendario. Opera sobre `CanonicalMatch` y
`CompetitionMatchContext`; conserva el `ScheduleItem` original de R4B y aplica
el estado efectivo mediante revisiones append-only.

## Trazabilidad

| Dato | Valor |
| --- | --- |
| Inicio | `2026-08-24` |
| Cierre de Fase A | `2026-08-25T04:39:22+02:00` |
| Base inicial | `c6efeb72c7bf30456a75873e8e9ff93d7d7c6609` |
| Rama | `codex/league-operational-exceptions-v1` |
| PR | `#184` Draft |
| Node | `v24.16.0` |
| npm | `11.13.0` |
| Supabase CLI | `2.107.0` |
| Ledger base | `131` |
| Ledger R4D | `136` (`131 + 5`) |

## Migraciones forward-only

1. `20260824230726_league_operational_exceptions_schema_v1.sql`
2. `20260824230732_league_operational_exceptions_commands_v1.sql`
3. `20260824230733_league_operational_exceptions_access_v1.sql`
4. `20260824230734_league_operational_exceptions_hardening_v1.sql`
5. `20260825021800_league_operational_exceptions_venue_status_fix_v1.sql`

La quinta migracion es una correccion forward-only descubierta en staging: un
fixture R4B con sede por etiqueta conserva `venue_status=TBD`; una
reprogramacion R4D debe normalizar ese estado heredado a `LABEL`. No se
reescribio ninguna migracion ya aplicada.

Fresh bootstrap y upgrade `131 -> 136` producen esquemas equivalentes. Las
nueve flags nacen en `false`, no se crean datos R4D y no se ejecuta
`canonical.backfill`.

## Autoridad canonica

| Dominio | Autoridad | Regla |
| --- | --- | --- |
| Partido | `CanonicalMatch` + `CompetitionMatchContext` | una identidad deportiva |
| Calendario original | R4B `ScheduleItem` publicado | inmutable tras publicar |
| Estado efectivo | `CompetitionFixtureChange` + revisions | ultima secuencia activa |
| Aplazamiento | request + response + administrative decision | bilateral y atomico |
| Incidencia | late arrival, no-show o suspension normalizada | evidencia privada |
| Resolucion | administrative decision + typed effects | sin SQL ni deltas de cliente |
| Resultado oficial | autoridad R4C | nueva decision y rebuild atomico |
| Cliente | intencion con `operationId` y `expectedRevision` | nunca fuente de verdad |

La RPC `command_pachanga_league_operational_exceptions_v1` resuelve actor,
Entry, permisos, RuleRevision, deadline, hora, secuencia y revision en
PostgreSQL. Repetir una operacion devuelve el mismo receipt sin duplicar
efectos, eventos o notificaciones.

## Producto y read models

Read models:

- `LeagueOperationalMatchView`;
- `LeaguePostponementDesk`;
- `LeagueIncidentDesk`;
- `LeagueAdministrativeDecisionDesk`;
- `MyLeagueExceptionRequests`;
- `PublicLeagueFixtureStatus`.

Superficies:

- `/competiciones/[competition]/partidos/[match]/operaciones`;
- `/competiciones/[competition]/partidos/[match]/estado`;
- `/competiciones/[competition]/gestion/aplazamientos`;
- `/competiciones/[competition]/gestion/incidencias`;
- `/competiciones/[competition]/gestion/decisiones`;
- `/mis-competiciones/solicitudes`;
- `/admin/competitions`;
- `/laboratorio-league-operational-exceptions`.

Las APIs son `no-store`, el laboratorio es `noindex,nofollow`, las pantallas
usan Official UI V2.1 y las rutas productivas quedan gated mientras las flags
esten OFF.

## Feature flags

Las nueve flags quedaron `false` en staging:

- `league_operational_exceptions_foundation_enabled`;
- `league_postponements_enabled`;
- `league_rescheduling_enabled`;
- `league_venue_changes_enabled`;
- `league_late_arrival_enabled`;
- `league_no_show_enabled`;
- `league_match_suspensions_enabled`;
- `league_administrative_decisions_enabled`;
- `league_public_exception_status_enabled`.

Las dependencias fallan cerrado. No-show exige foundation, late-arrival,
no-show y administrative-decisions.

## Staging autenticado

Supabase staging: `iozcjirlfytryzrcmrnq`.

El ensayo construyo mediante las autoridades R1-R4C:

- 6 equipos;
- 15 CanonicalMatches y contextos;
- 5 jornadas;
- resultados y standings canonicos;
- dos usuarios autenticados y dos clientes Realtime.

Historias remotas `PASS`:

1. aplazamiento aceptado y validado;
2. solicitud rechazada;
3. deadline expirado;
4. cambio de sede;
5. retraso dentro del margen;
6. no-show con resultado oficial;
7. no-show rechazado;
8. suspension y reanudacion del mismo partido;
9. repeticion sobre el mismo CanonicalMatch;
10. resultado administrativo con marcador parcial preservado.

Concurrencia remota: `one_winner_one_stale`. Realtime recibio invalidacion y
ambos clientes convergieron despues de releer el snapshot canonico. La Preview
protegida respondio correctamente mediante acceso temporal de QA, sin exponer
el token en Git ni en los informes.

La limpieza archivo las autoridades QA preservando historia. Readback final:

```text
migration_count=136
latest_migration=20260825021800
all_nine_r4d_flags_off=true
active_r4d_rows=0
r1_r4a_r4b_r4c=off
```

## Pruebas y rendimiento

| Gate | Resultado |
| --- | --- |
| R4D focal | `19/19 PASS` |
| R4B focal | `23/23 PASS` |
| Bateria completa | `443/443 PASS` |
| SQL/RLS/adversarial | `PASS` |
| Fresh bootstrap | `136 / PASS` |
| Upgrade | `131 -> 136 / PASS` |
| Schema equivalence | `PASS` |
| Idempotencia | `PASS` |
| Concurrencia | 9 carreras, `1 winner / 1 stale` |
| Escala | 34.000 filas de dominio, rollback `PASS` |
| Typecheck | `PASS` |
| Build | `PASS` |
| Lint focalizado | `PASS` |
| Lint global | deuda previa: 22 errores y 18 warnings |
| `git diff --check` | `PASS` |

Rendimiento local, frente a un umbral de parada de 2.000 ms:

| Operacion | Tiempo |
| --- | ---: |
| Crear solicitud | 41.888 ms |
| Responder solicitud | 10.442 ms |
| Reprogramar | 42.928 ms |
| Cambiar sede | 34.807 ms |
| Confirmar no-show | 21.986 ms |
| Resolver suspension | 4.752 ms |
| Decision administrativa | 10.768 ms |
| Rebuild standings | 20.232 ms |

Con 10.000 fixture changes, 10.000 postponements, 5.000 late arrivals, 2.000
no-shows, 2.000 suspensions y 5.000 decisiones, las lecturas medidas quedaron
entre 1.152 y 26.684 ms. El rollback final fue correcto.

## Advisors y logs

Supabase Advisors de staging no mostro errores criticos:

- Security: 13 INFO R4D `rls_enabled_no_policy`, intencionados porque el acceso
  directo esta revocado y las lecturas/escrituras pasan por RPC;
- Performance: 53 INFO R4D sobre FK sin indice; los planes y volumen medidos
  pasan. Se registran como deuda no bloqueante, sin crear indices especulativos;
- el unico WARN de performance pertenece a indices duplicados preexistentes de
  Rating V2 y no se toca.

API staging: 100 entradas, 0 respuestas 5xx; las R4D fueron 25 `200`, 3 `204`
y un `409` esperado por revision obsoleta. Realtime: 92 entradas, 0 mensajes de
error. Los errores PostgreSQL observados corresponden a negativos intencionales
de permisos, stale revision y una ejecucion previa al fix de sede; no hubo
errores nuevos despues del E2E final.

## Incidencias permanentes

| ID | Clasificacion | Hallazgo | Correccion | Estado |
| --- | --- | --- | --- | --- |
| R4D-001 | SIMULATION_BUG | La suscripcion Realtime podia declararse lista antes de que el slot frio estuviera operativo | Se suscribe antes de publicar y se exige invalidacion + refetch | fixed + regression_verified |
| R4D-002 | TESTABILITY_GAP | La carrera remota ocultaba el codigo SQL real al fallar | Diagnostico saneado por codigo y mensaje | fixed + regression_verified |
| R4D-003 | PRODUCT_BUG | Una sede R4B por etiqueta heredaba `TBD` y bloqueaba reprogramar | Quinta migracion normaliza solo `RESCHEDULE` a `SAVED/LABEL/TBD` | fixed + regression_verified |
| R4D-004 | ENVIRONMENT_ISSUE | La clave service-role de staging en Vercel estaba obsoleta | Rotacion limitada a la rama Preview | fixed + regression_verified |
| R4D-005 | ENVIRONMENT_ISSUE | `vercel env pull` devuelve `(Sensitive)` para secretos | El arnes obtiene la clave desde el keychain de Supabase sin imprimirla | fixed + regression_verified |
| R4D-006 | ENVIRONMENT_ISSUE | La Preview protegida devolvia HTML SSO al arnes | Acceso temporal protegido y sin persistir tokens | fixed + regression_verified |
| R4D-007 | SIMULATION_BUG | El runner de concurrencia conservaba el ledger 135 | Ledger 136 y lista exacta de cinco migraciones | fixed + regression_verified |
| R4D-008 | ENVIRONMENT_ISSUE | Dos ensayos fallidos dejaron 28 autoridades QA activas | Archivado canonico por IDs etiquetados y readback global a cero | fixed + regression_verified |

## Invariantes

R4D no modifica Rating V2, facets, assessments, rewards, cosmetics, Conduct,
disciplina, Billing, Season Score, TOPS, Clubs/Referees ni Referee Assignments.
No crea un segundo CanonicalMatch para reanudar o repetir. R5 y Tournament
Engine no se han iniciado.

## Gate de release

Fase A cumple. La release autorizada debe capturar backup y baselines, aplicar
las cinco migraciones exactas, confirmar ledger 136, nueve flags OFF y cero
datos R4D, fusionar `#184`, verificar Vercel/PWA/laboratorio y publicar el
informe productivo en un PR separado.
