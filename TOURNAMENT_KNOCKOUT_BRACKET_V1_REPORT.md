# Tournament Knockout Bracket V1

## Estado

- Fase: R6C.
- Alcance activo: eliminatoria a partido único.
- Base auditada: `origin/main` `659511e41cbab57440ba23124f8e339110aed9c5`.
- Rama: `codex/tournament-knockout-bracket-champion-v1`.
- Ledger local: 169 -> 175 migraciones.
- Fuente de verdad: PostgreSQL/Supabase.
- Cliente: intención semántica, `operationId`, revisión esperada y refetch del snapshot confirmado.

## Autoridad

El flujo canónico es:

```text
QualificationSnapshot publicada
  -> BracketTemplate publicada
  -> BracketRevision inmutable
  -> Node + Slot sources
  -> FixtureReservation
  -> CanonicalMatch / CompetitionMatchContext
  -> OfficialResultDecision
  -> AdvanceDecision
  -> posible Invalidation
  -> CompletionSnapshot
```

No se han creado `TournamentMatch`, `TournamentResult`, `TournamentReferee`,
`TournamentDiscipline` ni `TournamentPlayer`.

## Esquema nuevo

- `pachanga_tournament_brackets`
- `pachanga_tournament_bracket_revisions`
- `pachanga_tournament_bracket_nodes`
- `pachanga_tournament_bracket_node_revisions`
- `pachanga_tournament_bracket_node_slots`
- `pachanga_tournament_bracket_fixture_reservations`
- `pachanga_tournament_bracket_round_controls`
- `pachanga_tournament_knockout_result_resolutions`
- `pachanga_tournament_bracket_advance_decisions`
- `pachanga_tournament_bracket_invalidations`
- `pachanga_tournament_bracket_dependency_impacts`
- `pachanga_tournament_completion_snapshots`
- `pachanga_tournament_knockout_read_models`

Las revisiones, decisiones e invalidaciones son append-only. El estado actual
se selecciona por revisión/secuencia más identificador estable, nunca solo por
`created_at`.

## Política RuleRevision

`knockoutPolicy` se normaliza y firma dentro de la RuleRevision publicada:

| Campo | V1 |
| --- | --- |
| `tieFormat` | `SINGLE_MATCH` |
| `extraTimePolicy` | `NO_EXTRA_TIME` o `EXTRA_TIME_THEN_PENALTIES` |
| `extraTimeHalfMinutes` | 1..60, por defecto 15 |
| `extraTimeHalfCount` | 1..4, por defecto 2 |
| `extraTimeBreakMinutes` | 0..30, por defecto 5 |
| `penaltyShootoutPolicy` | directa, tras prórroga o desactivada |
| `byePolicy` | `EXPLICIT_ADVANCE` |
| `roundSchedulePolicy` | reserva antes de conocer participantes |
| `qualificationSourcePolicy` | snapshot publicado únicamente |
| `winnerAdvancementPolicy` | decisión oficial únicamente |

Permanecen fail-closed: ida/vuelta, doble eliminación, loser bracket,
consolation, replay y away goals.

## Fuentes y lifecycle

Fuentes soportadas: `GROUP_POSITION`, `EXTRA_QUALIFIER`, `DRAW_SEED`,
`WINNER_OF`, `LOSER_OF` y `BYE`.

Lifecycle de bracket: `template -> seeded -> ready -> active -> completed ->
locked`, con `administrative_review` como salida controlada desde activo.

Estados de nodo: `awaiting_sources`, `ready`, `scheduled`, `match_created`,
`in_progress`, `result_pending`, `official`, `advanced`, `cancelled`,
`invalidated` y `administrative_review`.

Un bye crea una decisión de avance explícita y cero partidos, resultados,
goles o recompensas.

## API, RBAC y RLS

- Orquestador: `command_pachanga_tournament_knockout_v1`.
- Lectura: `get_pachanga_tournament_knockout_v1` y Hub extendido.
- Control de plataforma: `command_pachanga_tournament_knockout_platform_v1`.
- Rol nuevo: `competition_bracket_manager`.
- `anon` y `authenticated`: 0 `INSERT`, 0 `UPDATE`, 0 `DELETE` directos.
- Las evidencias privadas, deliberaciones, términos arbitrales e impactos
  internos no forman parte del read model participante.
- El navegador no puede enviar ganador, perdedor, campeón, secuencia de
  servidor ni timestamps autoritativos.

## Verificación local

| Gate | Resultado |
| --- | --- |
| Contrato R6C | 13/13 PASS |
| R6B + R6C focalizado | 27/27 PASS |
| Formatos | 4, 8, 16 y 14/16 con dos byes; tercer puesto ON/OFF |
| Negativos | 16/16 fail-closed |
| Concurrencia | 11 carreras, `ONE_WINNER_ONE_CONFLICT` |
| Invariantes | 0 ganadores inválidos, matches/contextos/avances/completions duplicados |
| Escala | 10.000 brackets, 100.000 nodes y 100.000 slots; rollback |
| Migraciones | fresh/upgrade/equivalencia PASS; schema hash `c75464ec12235e07a3e2c02a40a26b6f7ee04f88b7c6b7a310d3a8d42150ee0f` |
| Batería global | 20 Node + 551 TS/TSX = 571/571 PASS |
| Build/typecheck/lint focalizado | PASS |

El lint global conserva 40 incidencias preexistentes en `app/legal-data.tsx`,
`app/mercado/page.tsx` y `app/page.tsx`; ningún archivo R6C añade errores.

## Límites V1

- Solo partido único.
- Sin lanzamiento individual de penaltis.
- Sin premios automáticos, dinero, cajas, cosméticos, Season Score o ranking.
- Discovery público y pagos permanecen desactivados.
- Android/iPhone físicos continúan pendientes y no se presentan como PASS.

El detalle de fallos y regresiones está en
`R6C_TOURNAMENT_KNOCKOUT_INCIDENTS.md`.
