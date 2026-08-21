# Canonical Match Binding V1 Report

Estado: `READY FOR REVIEW`

## Trazabilidad

| Campo | Valor |
| --- | --- |
| Base auditada | `0ea46f1cfa797a253678b68a3ffb8d7456856c81` |
| Rama | `codex/competition-organizer-foundation-v1` |
| PR | [#153](https://github.com/puntoracingrc/pachangas/pull/153) |
| Produccion | No modificada |
| Backfill | Solo local y staging |

## Autoridades deportivas auditadas

| Source kind | Fuente actual | Identidad de procedencia | Relacion demostrable | Decision R1 |
| --- | --- | --- | --- | --- |
| `GROUP_MATCH` | `pachanga_match_read_model` | `(group_id, match_id)` | Partido interno de grupo | Se registra como procedencia de un `CanonicalMatch` sin modificar el payload del grupo. |
| `OPEN_MATCH` | `pachanga_open_matches` | `id` | `source_group_id + source_match_id` apunta exactamente al `GROUP_MATCH` | Comparte el mismo `canonical_match_id`; nunca crea otro encuentro. |
| `EXTERNAL_MATCH` | `pachanga_external_matches` | `id` | `challenge_id` identifica el reto que lo origino | Se registra como procedencia deportiva del encuentro externo. |
| `TEAM_CHALLENGE` | `pachanga_team_challenges` | `id` | La relacion exacta se obtiene por `pachanga_external_matches.challenge_id` | Comparte el canonical del `EXTERNAL_MATCH`; no es un segundo partido. |

Invitaciones, accesos de invitado, snapshots y read models son superficies de
acceso o lectura. No se clasifican como encuentros deportivos.

No existe una relacion estructural que permita afirmar que un `GROUP_MATCH`
arbitrario y un `EXTERNAL_MATCH` arbitrario sean el mismo encuentro. R1 no los
fusiona por fecha, participantes, equipos o marcador.

## Modelo implementado

| Concepto R0 | Implementacion R1 | Funcion |
| --- | --- | --- |
| `CanonicalMatch` | `pachanga_canonical_matches` | Identidad estable de un unico encuentro deportivo real. |
| `CanonicalMatchBinding` | `pachanga_canonical_match_bindings` | Relacion versionada entre una procedencia y su canonical. |
| `binding_review_required` | `pachanga_canonical_match_binding_reviews` | Evidencia no destructiva de origen ambiguo o no enlazable. |
| `CompetitionMatchContext` | `pachanga_competition_match_contexts` | Contexto opcional de Competition sobre un canonical ya existente. |

Restricciones autoritativas:

- una procedencia activa solo puede tener un binding activo;
- un canonical puede recibir varias procedencias solo cuando la relacion es
  demostrable;
- un canonical solo puede tener un contexto competitivo activo;
- el contexto referencia Competition, Edition, Stage y RuleRevision, con
  Division/Group opcionales;
- no se duplican participantes, asistencia, alineacion, resultado, goleadores,
  Rating ni Achievements;
- tablas directas revocadas a `anon` y `authenticated`; las escrituras pasan por
  comandos server-authoritative.

## Backfill y ambiguedad

`canonical.backfill`:

1. enumera las cuatro procedencias conocidas;
2. reutiliza bindings existentes;
3. une `OPEN_MATCH` con su `GROUP_MATCH` por la clave exacta;
4. une `TEAM_CHALLENGE` con su `EXTERNAL_MATCH` por `challenge_id`;
5. crea canonical separado cuando solo existe una procedencia valida;
6. registra review si la relacion no puede demostrarse;
7. ordena y versiona mediante secuencia de servidor;
8. es idempotente y devuelve receipt canonico.

No se usan heuristicas por proximidad. El caso huerfano de staging se conservo
sin fusionar y genero una revision pendiente.

## Comandos y lecturas invocados

| Operacion | Autoridad | Evidencia |
| --- | --- | --- |
| `canonical.backfill` | `command_pachanga_competition_platform_v1` | Ejecutado dos veces local y staging; segunda ejecucion no crea filas nuevas. |
| `canonical.bind` | `command_pachanga_competition_platform_v1` | Ejecutado con `operationId` y revision esperada. |
| `canonical.binding_review.create` | `command_pachanga_competition_platform_v1` | Ruta implementada para ambiguedades no destructivas. |
| `competition_match_context.bind` | `command_pachanga_competition_platform_v1` | Ejecutado sobre canonical existente, con flag y permiso de plataforma. |
| Health | `get_pachanga_platform_canonical_match_health_v1` | Snapshot materializado, revisionado e invalidable. |
| Detalle | `get_pachanga_platform_canonical_match_v1` | Lectura restringida a plataforma autorizada. |

## Evidencia de staging

Lectura final tras dos backfills y el E2E autenticado:

| Metrica | Resultado |
| --- | ---: |
| Source records | `48` |
| Bindings activos | `48` |
| Canonical matches | `26` |
| Contexts vinculados | `1` |
| Fuentes sin binding | `1` |
| Reviews ambiguas | `1` |
| Conflictos duplicados | `0` |
| Canonical huerfanos | `0` |

El fixture `GROUP_MATCH + OPEN_MATCH` converge al mismo canonical
`af546825-5791-4f6a-b947-8ace313e9595`. El origen huerfano permanece como
review pendiente. Repetir el backfill no cambia los recuentos ni los IDs.

## Invariantes deportivas

La migracion y el E2E no escribieron en resultados, participantes, Rating,
Achievements, Rewards, Conduct, Billing ni Ranking. Los checksums de staging
comparados antes y despues permanecen identicos; el detalle consolidado esta en
`COMPETITION_ORGANIZER_FOUNDATION_V1_REPORT.md`.

## Escala

Synthetic World local:

- `10.000` procedencias/bindings y `10.000` canonical matches;
- lookup de binding p50 `0.285 ms`, p95 `0.438 ms`;
- el plan usa `pachanga_canonical_match_active_source_idx`;
- el health de plataforma se materializa y solo se refresca al invalidarse;
- indices medidos en la base local inicializada: `6.750.208 bytes`.

## Conclusion

R1 introduce una unica identidad canónica sin sustituir las autoridades
deportivas existentes. Los motores futuros deben adjuntar contexto al canonical
y no crear `LeagueMatch`, `TournamentMatch`, `RefereedMatch` ni resultados
paralelos.
