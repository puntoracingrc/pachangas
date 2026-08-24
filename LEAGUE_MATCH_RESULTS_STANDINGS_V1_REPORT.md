# League Match Results & Standings V1 Report

## Estado

`FASE A PASS / RELEASE PRODUCTIVA INACTIVA PENDIENTE`

R4C convierte los fixtures nativos de R4B en partidos de Liga operables sin
crear una segunda identidad deportiva. La autoridad es PostgreSQL y el cliente
solo envia intenciones semanticas con `operationId` y `expectedRevision`.

## Trazabilidad

| Dato | Valor |
| --- | --- |
| Inicio | `2026-08-24T18:55:04+02:00` |
| Base inicial | `57fe285daf4eb57f400c313f20841cff2dff4962` |
| Rama | `codex/league-match-results-standings-v1` |
| PR | `#182` Draft |
| Node | `v24.16.0` |
| npm | `11.13.0` |
| Supabase CLI | `2.107.0` |
| Ledger base | `127` |
| Ledger R4C | `131` (`127 + 4`) |

## Migraciones forward-only

1. `20260824165759_league_match_operations_schema_v1.sql`
2. `20260824165804_league_match_operations_commands_v1.sql`
3. `20260824165810_league_match_operations_access_v1.sql`
4. `20260824165815_league_match_operations_hardening_v1.sql`

Fresh bootstrap y upgrade desde el ledger 127 producen esquemas equivalentes.
Las ocho flags nacen en `false`, no se crean filas R4C y no se ejecuta
`canonical.backfill`.

## Autoridad y read models

| Dominio | Autoridad | Read model |
| --- | --- | --- |
| Partido | `pachanga_canonical_matches` + `pachanga_competition_match_contexts` | `LeagueCanonicalMatchView` |
| Asistencia | `pachanga_match_participants` | incluida en el snapshot canonico |
| Convocatoria | squads y revisiones R4C | match view por actor |
| Resultado | sporting result y revisiones | match view + `LeagueResultDesk` |
| Resultado oficial | decisiones append-only | resultado publico reducido |
| Clasificacion | snapshots y rows materializadas | `LeagueStandingsView` |
| Equipo | Entry, roster y delegados R4A | `MyLeagueMatchOperations` |

No existe `LeagueMatch`, `LeagueAttendance`, `LeaguePlayer`, `LeagueScorer` ni
payload de grupo autoritativo.

## Superficies

- `/competiciones/[competition]/partidos/[match]`
- `/competiciones/[competition]/gestion/resultados`
- `/competiciones/[competition]/clasificacion`
- `/competiciones/[competition]/jornadas/[round]`
- `/mis-competiciones/partidos`
- `/laboratorio-league-match-operations`
- `/admin/competitions`

Todas usan Official UI V2.1, quedan gated con flags OFF y las APIs dinamicas
responden `Cache-Control: no-store`.

## Staging autenticado

Supabase branch: `iozcjirlfytryzrcmrnq`.

El ensayo creo mediante autoridades R1/R2/R4A/R4B:

- 1 Club organizador;
- 1 Liga 2027 con RuleRevision congelada;
- 6 equipos, Entries y rosters;
- 5 jornadas;
- 15 CanonicalMatches y 15 CompetitionMatchContexts;
- 11 historias R4C completas.

Resultado final del arnes:

```text
canonicalMatches=15
officialResults=15
standingsRows=6
miniTableCandidates=3
concurrency=one_result_winner_one_stale
realtime=canonical_refetch_converged
incrementalChecksum=fullChecksum
status=PASS
```

La limpieza retiro toda entidad activa: competiciones, Clubs, contexts,
squads, sporting results y standings QA activas quedaron en cero. Las ocho
flags R4C, R4A, R4B y R1 quedaron OFF.

### Desviacion previa del entorno

El staging ya tenia `canonical_backfill.initialized_at =
2026-08-21T07:49:59.980432Z` antes de este cierre. R4C no ejecuto un backfill:
la marca precede tres dias a la prueba y no se creo ningun nuevo evento de ese
tipo. Se clasifica `ENVIRONMENT_ISSUE`; produccion debe conservar
`NOT_INITIALIZED` y se verificara antes y despues del primer SQL.

## Pruebas

| Gate | Resultado |
| --- | --- |
| R4C focal | `16/16 PASS` |
| Bateria completa | `424/424 PASS` |
| SQL/RLS/adversarial | `PASS` |
| Deadline service-only | `PASS` |
| Fresh bootstrap | `131 migraciones / PASS` |
| Upgrade | `127 -> 131 / PASS` |
| Schema equivalence | `PASS` |
| Idempotencia | `PASS` |
| Concurrencia | 9 carreras, `1 winner / 1 stale` |
| Escala | 380 y 992 fixtures; 10k revisions; 10k decisions; 1k rebuilds |
| Typecheck | `PASS` |
| Build | `PASS` |
| Lint focalizado | `PASS` |
| Lint global | deuda previa: 22 errores y 18 warnings |
| `git diff --check` | `PASS` |

## Performance

| Operacion | p50 | p95 |
| --- | ---: | ---: |
| Squad validation | 0.080 ms | 0.134 ms |
| Result submit | 2.470 ms | 3.099 ms |
| Result accept | 10.739 ms | 20.991 ms |
| Official decision + standings | 12.427 ms | 14.532 ms |
| Match view (32 equipos) | 0.371 ms | 2.674 ms |
| Result desk (32 equipos) | 12.899 ms | 19.033 ms |
| Public standings | 3.039 ms | 3.722 ms |
| Full rebuild (992 partidos) | 15.841 ms | 19.310 ms |
| Incremental rebuild (992 partidos) | 16.508 ms | 19.554 ms |

Los planes criticos usan los indices medidos. Supabase Advisors no encontro
errores R4C: registro 14 INFO de tablas RLS sin policy porque los grants directos
estan revocados, 10 WARN de RPC `SECURITY DEFINER` intencionalmente expuestas
con actor/permisos internos y 64 INFO de performance. Los 61 FK sin indice no
participan en los planes calientes medidos; no se anaden indices especulativos.

## QA visual y PWA

La matriz local cubrio `1440x900`, `1920x1080`, `390x844`, `360x800`,
`667x375`, `740x360`, `844x390`, `932x430` y standalone. Resultado:

- cero overflow;
- cero controles cortados;
- cero imagenes rotas;
- cero errores runtime o hidratacion;
- una sola navegacion en Mobile Game Landscape;
- modo PWA controlado por Service Worker;
- offline permite lectura cacheada, pero ninguna escritura deportiva confirma.

## Incidencias permanentes

| ID | Clasificacion | Hallazgo | Correccion | Estado |
| --- | --- | --- | --- | --- |
| R4C-001 | PRODUCT_BUG | El guard terminal de R4B bloqueaba el lifecycle R4C de jornada | Se amplian transiciones R4C sin abrir estados futuros | fixed + regression_verified |
| R4C-002 | PRODUCT_BUG | `round.lock` podia competir con una correccion oficial | Lock coordinado por jornada y revision observada | fixed + regression_verified |
| R4C-003 | PRODUCT_BUG | Una correccion administrativa prematura podia saltar la disputa | Se exige estado valido y autoridad de resultados | fixed + regression_verified |
| R4C-004 | PRODUCT_BUG | El batch de deadlines tomaba locks en orden incompatible | Jornada primero, despues contextos, con receipts | fixed + regression_verified |
| R4C-005 | PRODUCT_BUG | El archive QA de R4B no retiraba contexts `official` | Archive service-only preserva toda evidencia R4C | fixed + regression_verified |
| R4C-006 | PRODUCT_BUG | Dos `UPDATE` temporales globales fallaban con `safeupdate` | Se anade predicado explicito estable | fixed + regression_verified |
| R4C-007 | PRODUCT_BUG | Auto-official no invalidaba standings ni jornada | Invalidaciones dependen de la decision creada, no solo del nombre de accion | fixed + regression_verified |
| R4C-008 | SIMULATION_BUG | El test reducia goles del rival al proponer un cambio | La propuesta solo modifica goleadores propios | fixed + regression_verified |
| R4C-009 | SIMULATION_BUG | El test confundia revision del agregado con version del marcador | Verifica historia `INITIAL -> CHANGE -> ACCEPTANCE` y lineage | fixed + regression_verified |
| R4C-010 | SIMULATION_BUG | Un supuesto actor no autorizado podia ser Club owner por seleccion dinamica | Se usa el outsider garantizado | fixed + regression_verified |
| R4C-011 | TESTABILITY_GAP | El arnes R4B no generaba el consentimiento Club ahora obligatorio | Usa la RPC real de consentimiento | fixed + regression_verified |
| R4C-012 | ENVIRONMENT_ISSUE | Staging arrastraba canonical backfill inicializado desde el 21/08 | Registrado; produccion se validara limpia y no se modifica el historial | open / non-R4C |

## Invariantes

Las baterias antes/despues confirman cero mutaciones en Rating V2, facetas,
assessments, rewards, cosmetics, Conduct, disciplina, Billing, Season Score,
TOPS, Clubs/Referees y Referee Assignments. R5 y Tournament Engine no se han
iniciado.

## Gate de release

El codigo y staging cumplen Fase A. La release autorizada debe:

1. capturar backup y baselines productivos;
2. aplicar las cuatro migraciones en orden;
3. confirmar ledger `131`, ocho flags OFF y cero filas R4C;
4. fusionar PR #182 y esperar Vercel READY;
5. verificar laboratorio, rutas gated, PWA y regresiones productivas;
6. publicar el informe de produccion separado.
