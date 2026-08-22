# League Participation Foundation V1 Report

Estado: `READY FOR REVIEW`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Fecha de cierre | `2026-08-22` |
| Rama | `codex/league-participation-roster-v1` |
| Base real | `a4f2468d9b779db6a4391df7cec4cc34e4162fbe` (`origin/main`) |
| PR | [#162](https://github.com/puntoracingrc/pachangas/pull/162), borrador y sin merge |
| HEAD previo al commit de cierre | `620ec694b5682bde07131557bbda9ba5f359842b` |
| Worktree | `/Users/macbookpro14/.codex/worktrees/pachangas-league-participation-roster-v1` |
| Entorno | Node `24`, Next.js `16.2.6`, Supabase CLI `2.107.0`, PostgreSQL local y Supabase staging |
| Staging | `iozcjirlfytryzrcmrnq` (`pwa-bridge-staging`) |
| Produccion Supabase | `qonbngfrnrqgmxbdfbea`, no modificada |
| Preview final | [Vercel Preview de la rama](https://pachangas-git-codex-leagu-ff144a-persianas-almar-web-s-projects.vercel.app), revalidada contra el HEAD final del PR #162 |

El checkout principal contenia trabajo ajeno y no se utilizo para implementar R4A.
El worktree se conserva porque el PR permanece abierto y sin fusionar.

## Resultado

R4A incorpora una autoridad generica de participacion en competiciones, operable
exclusivamente para `LEAGUE`: categorias, inscripcion de equipos, delegados,
membresias de fase, plantillas versionadas, credenciales, elegibilidad, waivers,
equipaciones, dorsales, restricciones duras y preferencias blandas.

No crea el motor de liga. Jornadas, fixtures, partidos, convocatorias por partido,
resultados, clasificaciones, disciplina, pagos, rewards y ranking siguen fuera de
alcance. Cualquier intento de usar estos comandos con `TOURNAMENT` devuelve
`FEATURE_NOT_AVAILABLE`.

## Migraciones forward-only

| Version | Contenido |
| --- | --- |
| `20260822192929` | Esquema, flags, entidades R4A, indices, RLS, grants cerrados y Realtime. |
| `20260822192935` | Comandos LEAGUE, autoridad, snapshots, revisiones, idempotencia y eventos. |
| `20260822192941` | Read models publicos/privados/plataforma y ACL de lectura. |
| `20260822193624` | Bridge de reglas para organizers `TEAM` y `CLUB`. |
| `20260822194325` | Bridge de entitlements `competition_create` y `competition_manage`. |
| `20260822195054` | Precedencia de `TEAM_OWNER` frente a scopes solapados. |

El ledger local y el remoto de staging contienen exactamente `119` migraciones y
coinciden en nombre y version. R4A parte del ledger `113`; no modifica ni reescribe
ninguna migracion ejecutada con anterioridad.

## Autoridad central

Todas las mutaciones pasan por `command_pachanga_league_participation_v1` o su
variante de plataforma. El navegador envia solo `operationId`, `aggregateId`,
`expectedRevision`, accion semantica, payload acotado y metadata de cliente. La
base resuelve actor, ownership, delegacion, capability, reglas vigentes, reloj,
secuencia, revisiones y resultado canonico.

- El replay del mismo `operationId` y payload devuelve el receipt canonico.
- Reutilizarlo con otro payload falla con `IDEMPOTENCY_KEY_REUSED`.
- Una revision obsoleta falla con `STALE_REVISION` y SQLSTATE `PT409`.
- No existe last-write-wins silencioso.
- Realtime solo invalida la entidad autorizada; el cliente vuelve a pedir el read
  model canonico y nunca aplica `payload.new` como autoridad.
- La cache local es opcional, acotada y solo de lectura.
- Offline no confirma ni encola operaciones deportivas.

## Seguridad y privacidad

`anon` y `authenticated` no tienen escrituras directas sobre las tablas R4A.
Las funciones privilegiadas fijan `search_path`, resuelven `auth.uid()` en
servidor y no aceptan identidades ni autoridad calculada por el navegador.

Los read models no exponen fecha de nacimiento, email, documentos, evidencia de
credenciales ni motivos privados a actores sin permiso. La evidencia se conserva
en `private.pachanga_competition_credential_evidence`; la API tampoco contiene
`service_role` ni claves secretas.

Las tablas de autoridad directa tienen RLS activa y sin politicas de escritura de
cliente. El advisor informa `rls_enabled_no_policy` como INFO en esas tablas: es
el cierre intencional RPC-only. Una funcion de lectura autenticada
`SECURITY DEFINER` aparece como WARN; valida actor y scope dentro de PostgreSQL.

Referencias de advisor:

- https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys
- https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Flags

Los seis flags nacen y terminan apagados:

- `league_participation_foundation_enabled`
- `league_registration_enabled`
- `league_public_registration_enabled`
- `league_delegates_enabled`
- `league_rosters_enabled`
- `league_schedule_preferences_enabled`

Las dependencias se validan por constraint. Staging tambien termino con todos los
flags de R1, R2 y R3 apagados.

## Superficies

| Ruta | Uso |
| --- | --- |
| `/competiciones/[competition]/inscripcion` | Solicitud o invitacion de equipo. |
| `/mis-competiciones/inscripciones` | Inscripciones del usuario y proximas acciones. |
| `/competiciones/[competition]/gestion/inscripciones` | Mesa del organizador. |
| `/competiciones/[competition]/equipos/[entry]` | Ficha canonica del equipo inscrito. |
| `/laboratorio-league-participation` | Fixtures de QA visual, `noindex,nofollow`. |
| `/admin/competitions` | Extension del Control Center existente. |

Las seis vistas del laboratorio son: indice, registro publico, mis
inscripciones, mesa, entry y roster. Reutilizan Official UI V2 y distinguen
claramente `NO PUEDO JUGAR` de `PREFERIRIA JUGAR`.

## Validacion

| Gate | Resultado |
| --- | --- |
| Tests globales | PASS, `363/363` |
| Tests R4A focalizados | PASS, `20/20` |
| Build | PASS, `40/40` paginas |
| Typecheck | PASS |
| Lint focalizado | PASS, 0 findings |
| Lint global | Deuda heredada: `43` (`23` errores, `20` warnings), ninguno R4A |
| SQL/RLS/adversarial | PASS sobre DB temporal |
| Bootstrap fresh | PASS, ledger `119` |
| Upgrade | PASS, `113 -> 119`, esquema identico al fresh |
| Idempotencia/concurrencia | PASS, 9 escenarios, todos los clientes convergen |
| Escala | PASS, rollback completo |
| Staging autenticado | PASS, 7 usuarios, 2 sesiones, Realtime y cleanup |
| `git diff --check` | PASS antes de documentar; se repite al cierre |

### Escala y rendimiento

La prueba crea dentro de una transaccion: 1.000 editions, 10.000 categories,
20.000 entries, 20.000 delegates, 150.000 roster members, 100.000 credentials,
30.000 stage memberships y 100.000 filas de constraints/preferences. Termina
con `ROLLBACK`.

| Medicion | p50 | p95 |
| --- | ---: | ---: |
| Delegate lookup | `0,038 ms` | `0,097 ms` |
| Duplicate player | `0,030 ms` | `0,132 ms` |
| Eligibility | `0,049 ms` | `0,213 ms` |
| Entry detail | `0,268 ms` | `1,248 ms` |
| Multi-team conflict | `0,175 ms` | `0,251 ms` |
| Organizer list | `17,528 ms` | `22,256 ms` |
| Public registration | `18,149 ms` | `36,676 ms` |
| Roster detail | `0,219 ms` | `0,925 ms` |
| Stage membership | `0,030 ms` | `0,070 ms` |

Los indices R4A ocuparon `198 MB` en el dataset sintetico. No se añadieron
indices especulativos para silenciar INFOs de advisor cuando el p95 ya cumple.

## Staging final

El E2E autenticado cubrio solicitud publica, invitacion privada, rechazo,
delegacion, revisiones de plantilla, credenciales, conflicto multi-team,
reasignacion de stage, restricciones/preferencias, cierre de inscripcion,
concurrencia y Realtime con refetch canonico.

Readback final:

| Dato | Valor |
| --- | ---: |
| Entries activas R4A | 0 |
| Delegados activos/invitados | 0 |
| Stage memberships activas | 0 |
| Rosters asociados a entry activa | 0 |
| Credenciales activas | 0 |
| Entitlements QA activos | 0 |
| Clubs QA activos | 0 |
| Competiciones QA canceladas | 16 |
| Credenciales QA revocadas | 23 |
| Canonical matches antes/despues | 30 / 30 |
| Competition match contexts antes/despues | 1 / 1 |

Las filas canceladas/revocadas permanecen como historial auditable. Un intento de
Realtime sufrio un timeout transitorio; el `finally` limpio el fixture y la
repeticion completa paso sin cambios de producto.

## QA visual

La matriz final cubre `1440x900`, `1920x1080`, `390x844`, `360x800`,
`667x375`, `844x390`, `932x430`, tablet y PWA standalone real. Resultado:

- 0 runtime errors.
- 0 console warnings en superficies R4A.
- 0 requests fallidas ni imagenes rotas.
- 0 overflow de raiz.
- 0 controles R4A fuera del viewport.
- PWA con `display-mode: standalone`, manifest y Service Worker controlador.

El ajuste visual final corrigio la quinta tarjeta fuera de pantalla en landscape
y elevo `Abrir plantilla` a un objetivo tactil de 40 px.

La primera Preview de cierre revelo una discrepancia de hidratacion: Vercel
renderizaba las fechas en UTC y el navegador en Europe/Madrid. Se corrigio
fijando `timeZone: "Europe/Madrid"` en el formateador compartido y se anadio una
regresion focalizada. La Preview del HEAD final se volvio a recorrer con consola
limpia.

## Invariantes

Las migraciones y pruebas no escriben en Rating V2, facetas, evidencias de
rating, participantes, goleadores, resultados, disciplina, rewards, cajas,
Conduct, Billing, Season Score, rankings ni cosmeticos. No crean canonical
matches, rounds, fixtures ni standings. Premium Ball y los cinco mappings de
Team Cosmetic Rewards quedan intactos.

## Entrega consolidada (82 puntos)

| # | Entrega | Estado / evidencia |
| ---: | --- | --- |
| 1 | `origin/main` inicial real | `a4f2468...` |
| 2 | Rama | `codex/league-participation-roster-v1` |
| 3 | PR | #162, draft |
| 4 | HEAD final | El SHA publicado queda en PR y cierre de la tarea |
| 5 | Migraciones | 6 forward-only |
| 6 | Ledger staging | 119, alineado |
| 7 | CompetitionCategory | Implementado |
| 8 | Category lifecycle | draft/active/closed/archived |
| 9 | Registration modes | 5 modos modelados; operacion gated |
| 10 | Edition registration lifecycle | open/notify/close/expire |
| 11 | CompetitionEntry | Implementado |
| 12 | Entry lifecycle | Completo y auditable |
| 13 | Public application | Probada en staging |
| 14 | Private invitation | Probada en staging |
| 15 | Owner-only authority | PostgreSQL, probado |
| 16 | TEAM organizer | Conservado |
| 17 | CLUB organizer | Bridge probado |
| 18 | Duplicate protection | Indice + lock + concurrencia |
| 19 | CompetitionTeamDelegate | Implementado |
| 20 | Delegate roles | Primary/roster manager/viewer |
| 21 | Delegate invitation | Implementada |
| 22 | Primary delegate transfer | Implementada |
| 23 | Team owner transfer | Precedencia owner preservada |
| 24 | CompetitionStageMembership | Implementada |
| 25 | Division/group assignment | Implementado |
| 26 | Reassignment history | Cierra anterior y crea nueva |
| 27 | CompetitionRoster | Implementado |
| 28 | Roster revisions | Inmutables |
| 29 | Roster lifecycle | draft a locked/amended |
| 30 | RosterMember | Implementado |
| 31 | Player snapshot | Snapshot publico, sin copiar perfil |
| 32 | Player leaving Team | Marca review_required |
| 33 | Multi-team policy | Conflicto serializado |
| 34 | PlayerCompetitionCredential | Implementada |
| 35 | Credential privacy | Evidencia en schema private |
| 36 | Eligibility status | Server-calculated |
| 37 | Eligibility waiver | Auditable y revisionado |
| 38 | Kit model | HOME/AWAY/ALTERNATE |
| 39 | Jersey numbers | Versionados y unicos por revision |
| 40 | Availability constraints | Duras |
| 41 | Schedule preferences | Blandas |
| 42 | Hard vs soft UI | Diferenciadas |
| 43 | RuleRevision binding | Exacta e inmutable |
| 44 | Notifications | Eventos y destinos acotados |
| 45 | Realtime | Invalidate/refetch |
| 46 | Feature flags | 6, todos OFF |
| 47 | Read models | Canonicos y paginados |
| 48 | Public read model | Minimizado |
| 49 | Organizer desk | Implementado |
| 50 | Team Entry UI | Implementada |
| 51 | Roster UI | Implementada |
| 52 | Control Center | Extiende `/admin/competitions` |
| 53 | Mobile Game Landscape | QA aprobada |
| 54 | PWA | Escrituras protegidas, standalone probado |
| 55 | RLS | PASS |
| 56 | ACL | PASS |
| 57 | Security Definer | Acotado, actor server-side |
| 58 | Idempotency | Replay canonico |
| 59 | Concurrency | 9 escenarios PASS |
| 60 | Bootstrap | Fresh 119 PASS |
| 61 | Upgrade | 113 a 119 PASS |
| 62 | Scale | Volumen contractual PASS |
| 63 | Performance | p95 max 36,676 ms |
| 64 | Advisors | Revisados; deuda heredada documentada |
| 65 | Rating invariant | Intacto |
| 66 | Match invariant | Intacto |
| 67 | Discipline invariant | Intacto |
| 68 | Rewards invariant | Intacto |
| 69 | Conduct invariant | Intacto |
| 70 | Billing invariant | Intacto |
| 71 | Ranking invariant | Intacto |
| 72 | Canonical Match invariant | 30 -> 30 en staging |
| 73 | Tests | 363/363 |
| 74 | Typecheck | PASS |
| 75 | Build | PASS, 40/40 |
| 76 | Lint focalizado | PASS |
| 77 | Visual QA | Matriz completa PASS |
| 78 | Preview | PASS sobre HEAD final del PR, incluida regresion de hidratacion |
| 79 | Staging limpio | Flags OFF, entidades activas 0 |
| 80 | Produccion modificada | NO |
| 81 | Merge | NO |
| 82 | Worktree final | Conservado por PR abierto |

## Decision

R4A queda `READY FOR REVIEW`. No autoriza merge, activacion de flags ni
despliegue productivo. R4B debera construir jornadas, fixtures y calendario
encima de estas autoridades sin reabrir el payload local como fuente de verdad.
