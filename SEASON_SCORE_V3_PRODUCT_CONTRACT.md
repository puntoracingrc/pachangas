# Season Score V3 Product Contract

Estado: FROZEN para Ranking Productization V1.

Este documento congela la semántica productiva que PostgreSQL aplica. El laboratorio continúa como herramienta de validación, pero no es autoridad ni participa en lecturas de producto.

## Autoridad y límites

La cadena autoritativa es:

```text
Reto y resultado canónicos
-> evidencia SQL elegible
-> snapshot append-only
-> candidato determinista
-> publicación explícita
-> read model provincial
-> RPC pública minimizada
-> UI y caché derivada
```

- PostgreSQL es la única fuente de verdad.
- Rating V2 es una entrada canónica de solo lectura.
- El cliente no calcula ni confirma Season Score.
- Conduct, no-show, reports, sanctions, achievements, boxes, points, Player Cosmetics, Team Cosmetics, Team Rewards y billing no son entradas.
- Ranking integrity nunca crea sanciones ni modifica Rating V2.
- Esta versión no concede premios.

## Registro de fórmula

| Campo | Valor congelado |
| --- | --- |
| `formula_key` | `season_score_v3` |
| `formula_version` | `1` |
| Ventana | `recent_30` |
| Calidad | 55% |
| Competición | 30% |
| Oposición | 15% |
| Checksum | `e7b1788fa2d6d7ce2c37cd00f8fa55d78a87539bfa68c76a383bb3500ac388a4` |

La configuración se guarda en `private.pachanga_season_score_formula_registry`. Una versión no admite `UPDATE` ni `DELETE`; cualquier cambio futuro requiere otra versión y otro checksum.

## Fórmula exacta

Todas las funciones `clamp` limitan al intervalo indicado.

```text
ratingReliability = Rating V2 reliability / 100

quality = clamp(
  currentOverall * (0.72 + 0.28 * ratingReliability),
  0,
  100
)

expectedResult = 1 / (1 + 10 ^ ((opponentRating - teamRating) / 32))

performance = clamp(
  50 + (actualResult - expectedResult) * 85,
  0,
  100
)

competitionEvidence = weightedMean(performance)
competitionConfidence = 1 - exp(-weightedChallenges / 7)
competition = clamp(
  50 * (1 - competitionConfidence)
  + competitionEvidence * competitionConfidence,
  0,
  100
)

opposition = clamp(
  weightedMean(opponentRating) * 0.58
  + 100 * (1 - exp(-scoreWindowLogicalOpponents / 6)) * 0.42,
  0,
  100
)

qualityContribution = quality * 5.5
competitionContribution = competition * 3
oppositionContribution = opposition * 1.5

rawScore = clamp(
  qualityContribution + competitionContribution + oppositionContribution,
  0,
  1000
)

visibleScore = round(rawScore)
```

La posición utiliza `rawScore`; el redondeo solo se presenta en el read model y la UI.

## Evidencia deportiva

Solo entra un Reto externo cuando existe:

- reto aceptado;
- partido externo canónico `confirmed` o `auto_confirmed`;
- versión oficial del resultado;
- participación canónica del jugador en esa versión;
- niveles de ambos equipos entre 0 y 100;
- territorio de campo verificado;
- rival lógico resoluble;
- confianza de campo, participación, independencia y partido de al menos 0.50.

No entran partidos internos, cancelados, resultados pendientes, disputas sin resolver ni fixtures incompletos. Las correcciones crean nueva evidencia y un nuevo snapshot; nunca reescriben el anterior.

## Match competitive confidence

```text
accepted challenge          0.15
agreed time                 0.05
verified venue              0.10 * venueConfidence
confirmed participants      0.35 * participationConfidence
bilateral result            0.17 (0.72 of this for auto-confirmed)
established teams           0.08 * maturity
opponent history            0.04 * history
opponent independence       0.06 * independence
same-day anomaly penalty   -0.28 * anomaly
```

El resultado se limita a `0..1`. No usa GPS personal, IP, fingerprint ni señales de conducta.

El peso graduado es:

```text
confidence < 0.50          -> 0, evidencia excluida
0.50 <= confidence < 0.75 -> 0.35 + ((confidence - 0.50) / 0.25) * 0.65
confidence >= 0.75         -> 1, peso completo
```

## Rivales lógicos e independencia

```text
independence = clamp((
  1
  - rosterOverlap * 0.55
  - sharedAdmin * 0.18
  - sameOwner * 0.08
  - sameOwnerAndSharedAdmin * 0.04
  - bothNew * 0.08
  - closedPairRatio * 0.11
) / logicalClusterSize, 0, 1)
```

`independence < 0.50` excluye la evidencia. Diez Team IDs conectados pueden colapsar a un solo `logical_opponent_id`.

Dentro de `recent_30`, los encuentros contra el mismo rival lógico pesan:

```text
1.00, 1.00, 0.50, 0.25, 0.00 desde el quinto
```

## Elegibilidad

Ranking durante temporada:

- al menos 15 Retos válidos;
- al menos 6 rivales lógicos;
- fiabilidad Rating V2 >= 0.45;
- actividad válida en las últimas 12 semanas;
- territorio provincial verificado.

Estados canónicos:

```text
eligible
provisional
pending_integrity_review
not_eligible
```

La UI recibe únicamente códigos seguros como `ranking_evidence_incomplete`, `rating_reliability_incomplete`, `recent_activity_required`, `ranking_territory_pending` y `ranking_review_pending`.

## Readiness futuro de trofeo

Se persiste, pero no concede ningún grant:

- 25 Retos válidos;
- 10 rivales lógicos;
- match competitive confidence >= 0.72;
- network diversity >= 0.68;
- fiabilidad Rating V2 >= 0.55;
- actividad válida en las últimas 12 semanas;
- sin dependencia elevada de evidencia débil ni revisión pendiente.

`trophy_readiness != award`. `provincial_awards_enabled` tiene un `CHECK` que impide activarlo en V1.

## Integridad B+C

La política congelada es:

```text
B: excluir evidencia deportiva no fiable
+
C: retener certificación para revisión humana
```

No existe score alternativo ni penalización secreta. Un jugador `pending_integrity_review` conserva su posición y no promociona automáticamente al siguiente. La revisión es append-only, versionada e idempotente; puede confirmar evidencia, excluirla o mantenerla pendiente sin borrar historial.

## Desempate

Solo después de empate exacto:

1. `raw_score` descendente.
2. `match_competitive_confidence` descendente.
3. `logical_opponents` descendente.
4. `rating_reliability` descendente.
5. `valid_challenges` descendente.
6. `score_reached_at` ascendente.
7. `player_profile_id` como identificador estable.

Nunca se usa únicamente `created_at` para seleccionar el último snapshot o desempatar.

## Territorio

Territorio significa dónde compite el jugador. Se deriva del `placeId` canónico del campo mediante un mapping versionado y auditable; no representa nacionalidad, domicilio ni ubicación personal.

La provincia con más evidencia válida gana. En empate se conserva la provincia anterior si sigue empatada; después se usa la fecha de evidencia y el código provincial de forma determinista. Los snapshots históricos conservan su provincia.

- Infraestructura: multiprovincia.
- Producto V1: provincia.
- Piloto inicial allowlisted: Barcelona, código `08`.
- Comunidad autónoma: LAB.
- España: LAB.

## Temporada y publicación

```text
draft -> open -> frozen -> closed -> archived
```

Las transiciones son explícitas desde Control Center, autorizadas para roles de plataforma, transaccionales, versionadas e idempotentes. Solo puede existir una temporada `open` compatible.

- `open`: acepta refresh ordinario.
- `frozen`: solo reconciliación, correcciones autorizadas e integridad.
- `closed`: ranking final, cero premios.
- `archived`: histórico de solo lectura.

Un rebuild genera candidato y checksum. No publica hasta una acción administrativa compare-and-publish con revisión y checksum esperados.

## Lineage y orden canónico

Cada snapshot append-only conserva:

- jugador, temporada y provincia;
- revisión de snapshot, `server_sequence` y fecha del servidor;
- fórmula y checksum;
- revisión de evidencia y lote del grafo;
- clave de entrada Rating V2 y snapshot Rating seleccionado;
- componentes, score raw/visible, elegibilidad e integridad;
- evidencia resumida, lineage, checksum y `operation_id`.

Las lecturas de “último” usan revisión, `server_sequence` e ID estable. Los snapshots Rating V2 empatados en `created_at` usan también ID estable.

## Lectura cliente

- RPC Top 10 minimizada y paginada.
- RPC autenticada para la posición propia.
- IDs públicos opacos SHA-256; no se exponen UUID, riesgo, grafo ni lineage.
- Realtime observa solo la revisión de publicación e invalida esa entidad.
- Caché local versionada por `seasonId + provinceCode + publicationRevision`.
- Una caché nunca confirma una escritura ni compite con PostgreSQL.
