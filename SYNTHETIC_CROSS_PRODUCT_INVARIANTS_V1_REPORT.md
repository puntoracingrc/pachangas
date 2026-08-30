# Synthetic Cross-product Invariants V1

| Invariante | Evidencia | Resultado |
| --- | --- | --- |
| CanonicalMatch unico | 128 IDs distintos | PASS |
| Team sin doble horario | indice `teamId + scheduledAt` | PASS |
| Arbitro sin doble horario | indice `refereeId + scheduledAt` | PASS |
| Modalidad arbitral | perfil contra modalidad canonica | PASS |
| Un MAIN_REFEREE | 115 assignment IDs unicos | PASS |
| Standings reconstruibles | oraculo por checkpoint contra snapshot | PASS |
| Bracket reconstruible | cuartos, semifinal, final y tercer puesto | PASS |
| Un campeon por Torneo | dos finales, dos campeones | PASS |
| Disciplina reconstruible | 70 eventos, 5 sanciones y lineage arbitral | PASS |
| Sancionado fuera de squad | 256 MatchSheets | PASS |
| No-show distinguible | 3 MatchSheets `NO_SHOW` | PASS |
| Roster sin duplicados | 480 Player IDs y seleccion por MatchSheet | PASS |
| Team scopes | SOCIAL_ONLY, NEW_ACTIVITY_ONLY y ARCHIVED | PASS |
| Continuidad | toda competicion existente permanece operable | PASS |
| Billing independiente | Team billing INACTIVE conserva ACTIVE | PASS |
| Owner transfer | estado conservado y autoridad anterior retirada | PASS |
| Rating V2 | evidencia R5/R6C `ratingV2Unchanged` | PASS |
| Rewards | `rewardsUnchanged` y 0 grants inesperados | PASS |
| Notificaciones | 66 recipients allowlisted, sink-only | PASS |
| Privacidad | scan de todos los JSON publicados | PASS |
| Demo remota | `remoteWrites = 0` | PASS |

Las invariantes no son booleanos editoriales. El test de regresion corrompe
standings, Match ID disciplinario, scope SOCIAL_ONLY, referee ID, bracket y
MatchSheet sancionada y exige que el verificador falle.

No se ha modificado ninguna formula de Rating, faceta, assessment, voto,
reward, billing o standing productivo.
