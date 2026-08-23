# League Scheduling Foundation V1 Report

Estado: `READY FOR REVIEW` cuando se complete la Preview final. R4B permanece apagado por defecto y no se ha desplegado en produccion.

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Fecha de cierre | `2026-08-24` |
| Rama | `codex/league-scheduling-canonical-fixtures-v1` |
| Base exacta | `382f919e522af43feda7dc393253d3231ec3c44c` (`origin/main`) |
| PR | [#172](https://github.com/puntoracingrc/pachangas/pull/172), borrador, sin merge |
| Engine | `league-round-robin-v1` |
| Worktree | `/Users/macbookpro14/.codex/worktrees/pachangas-league-scheduling-canonical-fixtures-v1` |
| Entorno | Node `24.16.0`, Next.js `16.2.6`, PostgreSQL local y Supabase branch |
| Supabase staging | `iozcjirlfytryzrcmrnq` (`pwa-bridge-staging`) |
| Supabase produccion | `qonbngfrnrqgmxbdfbea`, no modificada |
| Preview final | `PENDING_FINAL_HEAD_PREVIEW` |

## Resultado

R4B crea una autoridad central para planificar calendarios LEAGUE sobre R4A. El navegador envia intenciones con `operationId` y revision esperada; PostgreSQL decide entradas, reglas, slots, restricciones, revision, secuencia, actor y resultado. La generacion produce un draft revisable e inmutable por revision. Solo una validacion completa permite una publicacion atomica que crea exactamente un `CanonicalMatch` y un `CompetitionMatchContext` por partido.

No se implementan resultados, clasificaciones, disciplina, aplazamientos, reservas de campo, arbitraje operativo ni R4C. No existe una tabla paralela `LeagueMatch`.

## Migraciones forward-only

| Version | Contenido |
| --- | --- |
| `20260823224156` | Planes, revisiones, slots, jornadas, descansos, items, validaciones, conflictos privados y snapshots de calidad. |
| `20260823224218` | Politica, checksums, motor SQL, comandos, revisionado, validacion y publicacion atomica. |
| `20260823224235` | RLS, ACL, read models, Control Center, flags e invalidaciones. |
| `20260823224236` | Guards relacionales, inmutabilidad, cleanup QA e indices medidos/FK. |

El ledger local y el de staging terminan en `123`: 119 migraciones heredadas y 4 R4B. Fresh bootstrap y upgrade exacto `119 -> 123` producen el mismo contrato de esquema.

## Modelo canonico

| Entidad | Autoridad |
| --- | --- |
| `CompetitionSchedulePlan` | Agregado de una edicion, stage, categoria y division/grupo; lifecycle `draft/generated/validated/published/superseded/cancelled`. |
| `ScheduleRevision` | Snapshot inmutable del input, seed, reglas, entradas, checksums, calidad y lineage. |
| `ScheduleSlot` | Ventana temporal zonificada y recurso opcional; exclusion de solapamiento por `resource_key`. |
| `CompetitionRound` | Jornada numerada, vuelta, regla congelada y rango temporal derivado. |
| `RoundBye` | Descanso explicito para numero impar; nunca crea rival ni partido ficticio. |
| `ScheduleItem` | Pareja de entries y slot dentro de una revision; no es autoridad de resultado ni asistencia. |
| `ScheduleValidation` | Evidencia persistida de la validacion completa ligada al checksum vigente. |
| Conflict/Quality | Evidencia privada normalizada; solo resumen seguro y explicable llega a read models autorizados. |

## Autoridad central

- Comando unico de usuario: `command_pachanga_league_scheduling_v1`.
- Comando de plataforma: `command_pachanga_league_scheduling_platform_v1`.
- El servidor obtiene actor, permisos, entries, rosters, reglas, constraints, preferences y secuencia.
- El cliente no puede enviar cruces, scores, conflictos, IDs canonicos, actor ni snapshots de autoridad.
- Todas las escrituras llevan `operationId`, `expectedRevision` y metadatos PWA sin PII.
- Locks de agregado, recibos idempotentes y revision monotona impiden last-write-wins silencioso.
- Un cambio manual clona la revision y conserva diff y lineage; nunca reescribe la anterior.
- Realtime solo invalida; cada cliente vuelve a solicitar el read model canonico.

## Flags

Los seis flags quedan `false` en repositorio y staging:

`league_foundation_enabled`, `league_schedule_generation_enabled`, `league_schedule_editing_enabled`, `league_schedule_publication_enabled`, `league_public_calendar_enabled` y `league_canonical_fixture_creation_enabled`.

Las dependencias fallan cerradas: generar requiere foundation; editar requiere generation; publicar requiere validation, publication y canonical fixture creation; el calendario publico requiere public calendar y una publicacion vigente.

## Superficies

| Ruta | Uso |
| --- | --- |
| `/competiciones/[competition]/gestion/calendario` | Workbench del organizador, slots, generacion, edicion, validacion y publicacion. |
| `/mis-competiciones/calendario` | Calendario privado del equipo inscrito. |
| `/competiciones/[competition]/calendario` | Calendario publico paginado cuando el flag lo permite. |
| `/competiciones/[competition]/jornadas/[round]` | Detalle canonico de jornada. |
| `/laboratorio-league-scheduling` | Escenarios visuales locales, `noindex,nofollow`. |
| `/admin/competitions` | Salud R4B, flags, planes y salud canonica heredada separada. |

## Validacion ejecutada

| Gate | Resultado |
| --- | --- |
| Motor TypeScript | PASS, `23/23` focalizados junto al contrato R4B |
| SQL/RLS/adversarial | PASS sobre DB temporal |
| Fresh bootstrap | PASS, ledger `123` |
| Upgrade | PASS, `119 -> 123` |
| Schema equivalence | PASS |
| Concurrencia | Generate `1 winner / 1 stale`; publish `1 winner / 1 stale` |
| Escala | PASS, 95.000 items, 95.000 slots, 5.000 constraints y 10.000 preferences |
| Staging autenticado | PASS, dos sesiones, Realtime y 15 fixtures canonicos |
| Cleanup staging | PASS: 5 planes QA archivados; 0 planes/slots/rondas/contextos/bindings QA activos |
| Flags staging | PASS, seis OFF |
| Tests globales | PASS, `397/397`, sin skips/todo/cancelled |
| Typecheck | PASS |
| Build | PASS, `43/43` paginas |
| Lint focalizado | PASS, 30 archivos, 0 findings |
| Visual / PWA / Preview | Se fija contra `PENDING_FINAL_HEAD_PREVIEW` |

## Advisors

El asesor de staging no informa niveles `ERROR`. Los avisos `SECURITY DEFINER` son esperados para endpoints que validan actor/capability dentro de la funcion, y las dos lecturas anonimas son deliberadas solo para calendario/jornada publicos publicados. Las tablas privadas no tienen politicas porque no conceden acceso a clientes. Tras el hardening, las tablas nuevas R4B tienen cero foreign keys sin indice. Los avisos `unused_index` son esperables en una rama recien creada. Referencias: [Security Definer](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS sin policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [FK sin indice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).

## Entrega consolidada (100 puntos)

| # | Entrega | Estado / evidencia |
| ---: | --- | --- |
| 1 | `origin/main` inicial | `382f919e522af43feda7dc393253d3231ec3c44c` |
| 2 | Rama | `codex/league-scheduling-canonical-fixtures-v1` |
| 3 | PR | #172, draft durante QA |
| 4 | HEAD final | Se registra al publicar el RC |
| 5 | Migraciones | 4 forward-only |
| 6 | Ledger staging | 123, alineado con filenames locales |
| 7 | SchedulePlan | Implementado y revisionado |
| 8 | ScheduleRevision | Inmutable, con lineage y checksums |
| 9 | ScheduleSlot | Implementado con timezone/recurso |
| 10 | ScheduleItem | Implementado; no duplica Match |
| 11 | CompetitionRound | Implementada y numerada |
| 12 | RoundBye | Explicito, sin partido ficticio |
| 13 | Lifecycle del plan | draft/generated/validated/published/superseded/cancelled |
| 14 | Lifecycle de ronda | draft/published/cancelled |
| 15 | Engine version | `league-round-robin-v1` |
| 16 | Seed | Persistida y validada, 1-160 caracteres |
| 17 | Input checksum | SHA-256 server-side |
| 18 | Una vuelta | N(N-1)/2 fixtures |
| 19 | Dos vueltas | Espejo local/visitante exacto |
| 20 | Equipos pares | 2-32 cubiertos |
| 21 | Equipos impares | Equipo BYE virtual solo en algoritmo |
| 22 | Descansos | Uno por equipo y vuelta si N es impar |
| 23 | Home/away | Balance maximo 1 en una vuelta, 0 en dos |
| 24 | Rachas | Medidas, limitadas y explicadas |
| 25 | Slot assignment | Server-side, determinista por orden canonico |
| 26 | Venue/resource collision | Exclusion DB y conflicto `VENUE_OVERLAP` |
| 27 | Timezone | IANA obligatoria por slot |
| 28 | DST | Europe/Madrid probado en cambios horario |
| 29 | Hard constraints | Prevalecen siempre |
| 30 | Soft preferences | Ponderadas y explicables |
| 31 | Quality score | 0-100, tres decimales, snapshot inmutable |
| 32 | Conflict model | Privado, normalizado, fingerprint SHA-256 |
| 33 | Capacity deficit | Fail closed, no calendario parcial |
| 34 | Reproducibilidad | Mismos inputs+seed, misma firma |
| 35 | Regeneracion | Nueva revision, historia preservada |
| 36 | Diff de revisiones | added/removed/moved/swapped/renamed |
| 37 | Move slot | Clona revision y revalida |
| 38 | Swap slot | Atomico dentro de nueva revision |
| 39 | Swap home/away | Atomico y sujeto a invariantes |
| 40 | Validation | Completa, persistida y checksum-bound |
| 41 | Stale input | Rechazo `STALE_INPUT`/`STALE_REVISION` |
| 42 | Publish | Solo revision VALID vigente |
| 43 | Atomic publication | Una transaccion todo-o-nada |
| 44 | Idempotent publication | Replay devuelve recibo canonico |
| 45 | Concurrency | Un ganador, perdedor obsoleto |
| 46 | CanonicalMatch origin | Binding `competition_generated` |
| 47 | CompetitionMatchContext | Uno por item publicado |
| 48 | Round binding | Context e item ligados a jornada exacta |
| 49 | RuleRevision binding | Congelada en plan/revision/round/context |
| 50 | No LeagueMatch | Confirmado |
| 51 | No legacy backfill | Confirmado; registry heredado no inicializado |
| 52 | Canonical health separado | Legacy y generated se muestran por separado |
| 53 | Organizer workbench | Implementado, paginado y no-store |
| 54 | Team calendar | Scope del entry/delegado |
| 55 | Public calendar | Minimizado y flag-gated |
| 56 | Round detail | Auth o publicacion publica autorizada |
| 57 | Control Center | Salud y seis flags |
| 58 | Laboratory | Local, noindex/nofollow |
| 59 | Official UI V2.1 | Componentes y shell existentes reutilizados |
| 60 | Desktop | Matriz visual contractual |
| 61 | Portrait | Matriz visual contractual |
| 62 | Mobile Game Landscape | Matriz visual contractual |
| 63 | PWA | Writes clasificadas; offline no confirma |
| 64 | Notifications | Resumen de publicacion por equipo |
| 65 | Zero notification storm | 6 equipos -> 6 notificaciones, no 15xN |
| 66 | Realtime | Invalidation + canonical refetch |
| 67 | Feature flags | Seis, todos OFF |
| 68 | RBAC | Organizer/capability y scopes R4A |
| 69 | RLS | Select acotado; private cerrado |
| 70 | ACL | Cero table writes para anon/authenticated |
| 71 | Security Definer | Search path fijo y actor server-side |
| 72 | Idempotency | Recibos por actor+operationId+hash |
| 73 | Concurrency | Generate y publish probados |
| 74 | Fresh bootstrap | 123 PASS |
| 75 | Upgrade | 119 -> 123 PASS |
| 76 | Schema equivalence | Fresh == upgrade |
| 77 | Scale | 95.000 items/slots PASS |
| 78 | Performance | 6/20/32 equipos medidos |
| 79 | Query plans | Indices usados en seis caminos clave |
| 80 | Advisors | Revisados; 0 ERROR y 0 FK R4B sin indice |
| 81 | R4A invariant | Entries/rosters/reglas solo leidos |
| 82 | Rating invariant | 0 escrituras/cambios |
| 83 | Match data invariant | Resultado/asistencia/alineacion = 0 |
| 84 | Standings invariant | 0 |
| 85 | Discipline invariant | 0 |
| 86 | Rewards invariant | 0 |
| 87 | Conduct invariant | 0 |
| 88 | Billing invariant | 0 |
| 89 | Ranking invariant | 0 |
| 90 | Tests | `397/397` PASS |
| 91 | Typecheck | PASS |
| 92 | Build | PASS, 43 paginas |
| 93 | Lint focalizado | PASS, 30 archivos |
| 94 | Visual QA | Matriz final registrada en PR |
| 95 | Preview | URL final registrada en PR |
| 96 | Staging cleanup | 0 autoridades QA activas; historia archivada |
| 97 | Produccion modificada | NO |
| 98 | Merge | NO |
| 99 | R4C iniciado | NO |
| 100 | Worktree final | Conservado mientras #172 siga abierto |

## Decision

R4B queda preparado para revision humana, no para activacion. La siguiente fase solo puede comenzar tras merge/despliegue autorizado de esta base; R4C permanece fuera de alcance.
