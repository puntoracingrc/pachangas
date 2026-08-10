# Synthetic World V1.1 - Auditoría del embudo de ranking

## Trazabilidad

- Mundo preservado: `3df9494d-3b8c-4447-96e8-d5244892af78`.
- Revisión auditada: `313`.
- Secuencia de servidor: `69458`.
- Checkpoint local: `audit_checkpoint / ranking-funnel-v1.1-pre`.
- Reglas de producto: sin cambios; Rating V2 y facetas: solo lectura.
- Conducta/reportes/no-show: pausados.

> Continuación: [`NETWORK_DIVERSITY_V3_1_REPORT.md`](./NETWORK_DIVERSITY_V3_1_REPORT.md) audita el blocker dominante sin modificar V3 ni Rating V2. La comparación concluye sin candidato V3.1 aceptado.

## Significado exacto de los estados

Las 135 filas son los jugadores que ya superaron **ranking eligibility** (15 evidencias aceptadas por B, 6 rivales lógicos, fiabilidad 0,45 y actividad reciente). Dentro de esas filas, `eligible`, `not_eligible` y `pending_integrity_review` son estados de **certificación/trofeo provincial**, no de aparición en ranking.

- `eligible`: Aparece en ranking y cumple certificación/trofeo provincial sin hold.
- `not_eligible`: Aparece en ranking, pero no cumple uno o más gates no-integrity de certificación provincial.
- `pending_integrity_review`: Aparece en ranking y cumple los gates no-integrity; el trofeo queda retenido por diversidad, dependencia de evidencia débil o riesgo.

Resultado persistido: **135 ranking eligible**, **1 trophy eligible**, **54 pending**. El único trophy eligible depende de nueve partidos de control; sin ellos el mundo orgánico produce **0**.

## Funnel de 640 jugadores

| Etapa | Count | % 640 | Pérdida | Motivo principal |
| --- | --- | --- | --- | --- |
| Registrados | 640 | 100 | 0 | none |
| Jugaron al menos un partido | 543 | 84.8 | 97 | sin_partidos_confirmados |
| Jugaron al menos un Reto | 528 | 82.5 | 15 | sin_retos_confirmados |
| Jugaron 5 Retos | 490 | 76.6 | 38 | menos_de_5_retos |
| Jugaron 10 Retos | 424 | 66.3 | 66 | menos_de_10_retos |
| 15 evidencias Season Score | 192 | 30 | 232 | evidencia_B_excluida |
| 6 rivales lógicos válidos | 166 | 25.9 | 26 | menos_de_6_rivales_logicos |
| Fiabilidad >= 0,45 | 135 | 21.1 | 31 | fiabilidad_rating |
| Actividad <= 12 semanas | 135 | 21.1 | 0 | none |
| Entran en ranking | 135 | 21.1 | 0 | none |
| Llegan a 20 Retos | 132 | 20.6 | 3 | menos_de_20_retos |
| Llegan a 25 Retos | 112 | 17.5 | 20 | insufficient_challenges |
| 10 rivales lógicos | 101 | 15.8 | 11 | insufficient_logical_opponents |
| Confidence >= 0.72 | 57 | 8.9 | 44 | insufficient_competitive_confidence |
| Diversity >= 0.68 | 1 | 0.2 | 56 | insufficient_network_diversity |
| Fiabilidad >= 0.55 | 1 | 0.2 | 0 | none |
| Actividad <= 12 semanas | 1 | 0.2 | 0 | none |
| Sin retención de integridad | 1 | 0.2 | 0 | none |
| Certificables provinciales | 1 | 0.2 | 0 | none |

## Gates e intersecciones

| Gate | Falla solo | Falla + otros | Total falla | Pasa |
| --- | --- | --- | --- | --- |
| challenges | 1 | 22 | 23 | 112 |
| logical_opponents | 0 | 14 | 14 | 121 |
| confidence | 0 | 52 | 52 | 83 |
| network_diversity | 16 | 117 | 133 | 2 |
| reliability | 0 | 30 | 30 | 105 |
| recent_activity | 0 | 0 | 0 | 135 |
| integrity | 0 | 95 | 95 | 40 |

Patrones completos: `{"network_diversity+integrity":38,"network_diversity":16,"logical_opponents+confidence+network_diversity+reliability+integrity":1,"confidence+network_diversity+reliability+integrity":16,"confidence+network_diversity+integrity":18,"challenges":1,"confidence+network_diversity":5,"logical_opponents+network_diversity+integrity":9,"challenges+confidence+network_diversity+reliability+integrity":3,"challenges+network_diversity":8,"challenges+network_diversity+integrity":6,"challenges+logical_opponents+network_diversity+integrity":2,"challenges+confidence+network_diversity+reliability":2,"confidence+network_diversity+reliability":5,"network_diversity+reliability":2,"passes_all":1,"challenges+logical_opponents+confidence+network_diversity+reliability+integrity":1,"logical_opponents+confidence+network_diversity+integrity":1}`.

### Leave-one-gate-out

| Gate eliminado | Certificables |
| --- | --- |
| none | 1 |
| challenges | 2 |
| logical_opponents | 1 |
| confidence | 1 |
| network_diversity | 17 |
| reliability | 1 |
| recent_activity | 1 |
| integrity | 1 |

El cuello dominante es `network_diversity`: 133/135 rankeados la fallan y retirarla aisladamente eleva el contrafactual estricto de 1 a 17. No es una recomendación para quitarla.

## Qué significan las 950 evidencias

Las 950 son **partidos de Reto confirmados/autoconfirmados marcados como no excluidos en el generador**, no filas player-match. El detalle real es:

- 1100 partidos de Reto con resultado canónico.
- 950 partidos marcados válidos y 150 marcados excluidos.
- 14484 evidencias fuente jugador-partido.
- 9347 evidencias aceptadas por B.
- 5137 evidencias jugador-partido excluidas por B.
- 0 source matches elegibles sin evidencia derivada.

No aparece pérdida de integración player → match → evidence.

## Participación

- Participaciones totales en partidos cerrados: 18955.
- Registrados: 18597; invitados: 358.
- Retos: 14721; internos: 4234.
- Retos por jugador p10/p25/p50/p75/p90/p95/max: 0 / 6 / 15 / 26 / 41 / 52 / 492.

| Retos/jugador | Total | Barcelona | Madrid | Valencia | Sevilla | Girona | Otros |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 112 | 34 | 7 | 12 | 22 | 9 | 28 |
| 1-4 | 38 | 15 | 9 | 1 | 1 | 11 | 1 |
| 5-9 | 66 | 21 | 22 | 6 | 6 | 8 | 3 |
| 10-14 | 95 | 39 | 20 | 9 | 10 | 10 | 7 |
| 15-19 | 81 | 26 | 24 | 10 | 10 | 7 | 4 |
| 20-24 | 64 | 20 | 15 | 12 | 9 | 4 | 4 |
| 25-29 | 51 | 15 | 13 | 11 | 4 | 3 | 5 |
| 30+ | 133 | 25 | 45 | 30 | 13 | 2 | 18 |

## Rivales lógicos

58 jugadores tuvieron >=10 team IDs rivales pero <10 rivales lógicos. Clasificación: `{"correct_collapse":58}`. Los colapsos observados corresponden al anillo sintético de equipos falsos; no se encontró un false positive estructural de colapso.

## Confidence y exclusión B

| Confidence | Partidos | Evidencia normal | Evidencia atacante | Total jugador-partido |
| --- | --- | --- | --- | --- |
| <0.25 | 0 | 0 | 0 | 0 |
| 0.25-0.49 | 3 | 66 | 1 | 67 |
| 0.50-0.74 | 148 | 1941 | 227 | 2168 |
| >=0.75 | 949 | 11406 | 843 | 12249 |

Motivos multi-label de exclusión: opponent_independence_below_0_50=3756, participation_below_0_50=2136, source_marked_excluded=2135, venue_below_0_50=2135, same_day_frequency_penalty=273, competitive_confidence_below_0_50=67.

## Holds C

| Matriz | HOLD | NO HOLD |
| --- | --- | --- |
| attacker | 4 | 40 |
| legitimate | 50 | 546 |

Los 54 pending incluyen 50 agentes etiquetados como legítimos y 4 atacantes. Todos fallan diversidad; 38 dependen además de evidencia débil. En la cohorte ranking-eligible hay 4 atacantes sin hold, pero no son trophy eligible por otros gates.

## Densidad y actividad

- Retos medios/equipo: 44.
- Rivales únicos medios/equipo: 14.08.
- Plantilla media: 14.
- Participación media de plantilla por Reto: 48.9%.
- Retos/jugador p50: 1.51/mes; p90: 4.13/mes.

La rotación no se considera demostrablemente defectuosa: aproximadamente media plantilla participa en cada Reto, coherente con plantillas superiores al equipo de campo. El mundo sí concentra volumen extremo en pocos agentes (máximo 492 Retos) y deja 112 registrados sin Reto.

## Top 50 candidatos

| # | Jugador | Provincia | Score | Retos | Rivales | Conf. | Diversidad | Fiabilidad | Estado | Bloqueo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SIM · Alex F. 609 | 08 | 749.05 | 41 | 19 | 0.7573 | 0.5254 | 0.78 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 2 | SIM · Pablo G. 029 | 08 | 744.63 | 12 | 10 | 0.7947 | 0.604 | 0.92 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 3 | SIM · Paula N. 416 | 08 | 743.1 | 20 | 14 | 0.844 | 0.637 | 0.9 | not_eligible | insufficient_challenges, insufficient_network_diversity |
| 4 | SIM · Hugo A. 064 | 28 | 741.6 | 43 | 14 | 0.6561 | 0.5198 | 0.78 | not_eligible | insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 5 | SIM · Sofía F. 054 | 08 | 736.56 | 27 | 9 | 0.7764 | 0.4151 | 0.83 | not_eligible | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 6 | SIM · Lina T. 306 | 46 | 731.44 | 32 | 5 | 0.6234 | 0.4035 | 0.77 | not_eligible | ranking_not_eligible, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 7 | SIM · Irene B. 586 | 15 | 725.99 | 79 | 28 | 0.7985 | 0.4814 | 0.92 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 8 | SIM · Lina R. 173 | 08 | 725.23 | 23 | 12 | 0.781 | 0.6155 | 0.76 | not_eligible | insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 9 | SIM · Marc G. 042 | 28 | 723.78 | 17 | 8 | 0.6903 | 0.6086 | 0.93 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 10 | SIM · Sergio N. 274 | 46 | 720.66 | 405 | 39 | 0.6555 | 0.4929 | 0.61 | not_eligible | insufficient_competitive_confidence, insufficient_network_diversity |
| 11 | SIM · Alex N. 170 | 41 | 720.03 | 24 | 9 | 0.7797 | 0.4857 | 0.84 | not_eligible | insufficient_challenges, insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 12 | SIM · Bruno B. 127 | 17 | 719.47 | 26 | 14 | 0.8228 | 0.578 | 0.9 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 13 | SIM · Hugo G. 430 | 28 | 716.94 | 56 | 20 | 0.7309 | 0.5392 | 0.8 | pending_integrity_review | insufficient_network_diversity |
| 14 | SIM · Sofía A. 533 | 17 | 716.85 | 22 | 12 | 0.7714 | 0.5993 | 0.92 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 15 | SIM · Hugo V. 445 | 08 | 715.82 | 37 | 10 | 0.7456 | 0.5412 | 0.68 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 16 | SIM · Marc N. 163 | 28 | 712.27 | 13 | 9 | 0.7326 | 0.7202 | 0.8 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, low_confidence_dependency |
| 17 | SIM · Lina N. 061 | 08 | 712.18 | 35 | 14 | 0.7955 | 0.5998 | 0.9 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 18 | SIM · Paula T. 019 | 17 | 711.52 | 17 | 11 | 0.749 | 0.5938 | 0.77 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 19 | SIM · Leo D. 391 | 28 | 710.58 | 42 | 9 | 0.7944 | 0.4193 | 0.85 | not_eligible | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 20 | SIM · Vera C. 159 | 15 | 709.89 | 29 | 15 | 0.7332 | 0.5829 | 0.74 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 21 | SIM · Paula M. 280 | 08 | 708.95 | 29 | 16 | 0.7017 | 0.549 | 0.91 | not_eligible | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 22 | SIM · Hugo M. 069 | 28 | 704.16 | 26 | 13 | 0.8023 | 0.5867 | 0.85 | pending_integrity_review | insufficient_network_diversity |
| 23 | SIM · Marc R. 205 | 08 | 703.89 | 56 | 20 | 0.8289 | 0.5647 | 0.89 | pending_integrity_review | insufficient_network_diversity |
| 24 | SIM · Marc G. 226 | 08 | 703.86 | 9 | 5 | 0.7068 | 0.5685 | 0.72 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 25 | SIM · Rai V. 421 | 28 | 703.31 | 25 | 14 | 0.7414 | 0.5741 | 0.67 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 26 | SIM · Marta M. 503 | 08 | 703.23 | 27 | 10 | 0.8141 | 0.4234 | 0.89 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 27 | SIM · Irene F. 147 | 28 | 701.53 | 11 | 9 | 0.7571 | 0.7265 | 0.61 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 28 | SIM · Vera S. 192 | 15 | 700.03 | 38 | 20 | 0.7647 | 0.5285 | 0.79 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 29 | SIM · Irene F. 138 | 28 | 699.06 | 36 | 9 | 0.7932 | 0.4758 | 0.83 | not_eligible | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 30 | SIM · Bruno N. 513 | 08 | 698.12 | 34 | 18 | 0.6615 | 0.5821 | 0.79 | not_eligible | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 31 | SIM · Sofía R. 045 | 41 | 698.06 | 27 | 9 | 0.6227 | 0.4919 | 0.93 | not_eligible | ranking_not_eligible, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 32 | SIM · Rai R. 343 | 28 | 697.96 | 29 | 9 | 0.8114 | 0.4761 | 0.93 | not_eligible | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 33 | SIM · Leo C. 382 | 08 | 697.69 | 13 | 5 | 0.7124 | 0.6413 | 0.66 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 34 | SIM · Eva D. 351 | 08 | 696.42 | 9 | 8 | 0.7811 | 0.7615 | 0.79 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 35 | SIM · Nico V. 337 | 28 | 695.87 | 39 | 17 | 0.7977 | 0.5476 | 0.85 | pending_integrity_review | insufficient_network_diversity, low_confidence_dependency |
| 36 | SIM · Alex D. 236 | 28 | 693.53 | 23 | 14 | 0.806 | 0.5987 | 0.91 | not_eligible | insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 37 | SIM · Dani R. 366 | 15 | 693.14 | 34 | 18 | 0.7005 | 0.5712 | 0.48 | not_eligible | insufficient_competitive_confidence, insufficient_network_diversity, insufficient_rating_reliability |
| 38 | SIM · Eva S. 281 | 08 | 692.98 | 0 | 0 | 0 | 0 | 0.89 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, insufficient_recent_activity |
| 39 | SIM · Eva R. 271 | 28 | 691.73 | 26 | 15 | 0.6756 | 0.5803 | 0.45 | not_eligible | insufficient_competitive_confidence, insufficient_network_diversity, insufficient_rating_reliability, low_confidence_dependency |
| 40 | SIM · Joel D. 348 | 28 | 690.87 | 32 | 16 | 0.6874 | 0.5904 | 0.84 | not_eligible | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 41 | SIM · Eric N. 026 | 28 | 690.46 | 17 | 11 | 0.6808 | 0.6223 | 0.68 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 42 | SIM · Lina S. 488 | 28 | 688.3 | 29 | 9 | 0.7745 | 0.4229 | 0.76 | not_eligible | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 43 | SIM · Hugo M. 310 | 28 | 688.25 | 47 | 20 | 0.7077 | 0.5272 | 0.55 | not_eligible | insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 44 | SIM · Vera F. 051 | 41 | 687.65 | 0 | 0 | 0 | 0 | 0.89 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, insufficient_recent_activity |
| 45 | SIM · Sara S. 208 | 28 | 686.32 | 14 | 8 | 0.607 | 0.6648 | 0.73 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 46 | SIM · Pablo V. 617 | 28 | 686.24 | 10 | 10 | 0.8363 | 0.7326 | 0.9 | not_eligible | ranking_not_eligible, insufficient_challenges |
| 47 | SIM · Vera S. 269 | 15 | 684.01 | 48 | 20 | 0.6453 | 0.5485 | 0.37 | not_eligible | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, insufficient_rating_reliability, low_confidence_dependency |
| 48 | SIM · Víctor R. 515 | 28 | 683.78 | 10 | 8 | 0.7526 | 0.7507 | 0.62 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 49 | SIM · Sara T. 476 | 08 | 682.76 | 4 | 4 | 0.8693 | 0.8129 | 0.8 | not_eligible | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 50 | SIM · Pablo F. 632 | 28 | 681.44 | 25 | 7 | 0.7629 | 0.4259 | 0.92 | not_eligible | ranking_not_eligible, insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |

## Top 20 Barcelona, lectura derivada

- SIM · Alex F. 609, MC, nivel 92.0. trayectoria positiva: 18V/6E/17D en 41 Retos, 19 rivales lógicos y Season Score 749.0. Estado pendiente de integridad: insufficient_network_diversity, low_confidence_dependency.
- SIM · Pablo G. 029, MC, nivel 84.5. trayectoria positiva: 5V/4E/3D en 12 Retos, 10 rivales lógicos y Season Score 744.6. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_network_diversity, low_confidence_dependency.
- SIM · Paula N. 416, DEL, nivel 87.3. trayectoria positiva: 8V/6E/6D en 20 Retos, 14 rivales lógicos y Season Score 743.1. Estado no certificable: insufficient_challenges, insufficient_network_diversity.
- SIM · Sofía F. 054, DEL, nivel 87.6. trayectoria positiva: 14V/2E/11D en 27 Retos, 9 rivales lógicos y Season Score 736.6. Estado no certificable: insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency.
- SIM · Lina R. 173, DEF, nivel 93.4. trayectoria adversa: 6V/4E/13D en 23 Retos, 12 rivales lógicos y Season Score 725.2. Estado no certificable: insufficient_challenges, insufficient_network_diversity, low_confidence_dependency.
- SIM · Hugo V. 445, DEL, nivel 85.0. trayectoria positiva: 19V/5E/13D en 37 Retos, 10 rivales lógicos y Season Score 715.8. Estado pendiente de integridad: insufficient_network_diversity, low_confidence_dependency.
- SIM · Lina N. 061, MC, nivel 84.5. trayectoria adversa: 11V/9E/15D en 35 Retos, 14 rivales lógicos y Season Score 712.2. Estado pendiente de integridad: insufficient_network_diversity, low_confidence_dependency.
- SIM · Paula M. 280, DEF, nivel 82.8. trayectoria positiva: 13V/9E/7D en 29 Retos, 16 rivales lógicos y Season Score 709.0. Estado no certificable: ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency.
- SIM · Marc R. 205, DEF, nivel 78.1. trayectoria positiva: 19V/20E/17D en 56 Retos, 20 rivales lógicos y Season Score 703.9. Estado pendiente de integridad: insufficient_network_diversity.
- SIM · Marc G. 226, MC, nivel 82.4. trayectoria equilibrada: 4V/1E/4D en 9 Retos, 5 rivales lógicos y Season Score 703.9. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency.
- SIM · Marta M. 503, POR, nivel 77.1. trayectoria positiva: 11V/8E/8D en 27 Retos, 10 rivales lógicos y Season Score 703.2. Estado pendiente de integridad: insufficient_network_diversity, low_confidence_dependency.
- SIM · Bruno N. 513, DEF, nivel 82.7. trayectoria positiva: 15V/12E/7D en 34 Retos, 18 rivales lógicos y Season Score 698.1. Estado no certificable: ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency.
- SIM · Leo C. 382, DEL, nivel 90.4. trayectoria adversa: 4V/0E/9D en 13 Retos, 5 rivales lógicos y Season Score 697.7. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency.
- SIM · Eva D. 351, DEF, nivel 83.2. trayectoria adversa: 3V/2E/4D en 9 Retos, 8 rivales lógicos y Season Score 696.4. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents.
- SIM · Eva S. 281, DEL, nivel 93.7. trayectoria equilibrada: 0V/0E/0D en 0 Retos, 0 rivales lógicos y Season Score 693.0. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, insufficient_recent_activity.
- SIM · Sara T. 476, DEL, nivel 84.8. trayectoria equilibrada: 2V/0E/2D en 4 Retos, 4 rivales lógicos y Season Score 682.8. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents.
- SIM · Joel A. 349, DEF, nivel 79.4. trayectoria adversa: 6V/4E/8D en 18 Retos, 9 rivales lógicos y Season Score 681.3. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency.
- SIM · Nico S. 092, DEL, nivel 85.9. trayectoria positiva: 4V/4E/3D en 11 Retos, 8 rivales lógicos y Season Score 679.1. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_rating_reliability.
- SIM · Víctor F. 534, MC, nivel 85.6. trayectoria positiva: 2V/0E/1D en 3 Retos, 3 rivales lógicos y Season Score 679.0. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, low_confidence_dependency.
- SIM · Lina B. 158, DEF, nivel 83.6. trayectoria adversa: 3V/1E/6D en 10 Retos, 6 rivales lógicos y Season Score 677.2. Estado no certificable: ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_network_diversity.

## Comparación con la simulación matemática V3

| Métrica p50 | Synthetic World | V3 10k |
| --- | ---: | ---: |
| Evidencias aceptadas/jugador | 15 fuente / 8 aceptadas | 25 |
| Rivales lógicos | 7 | 15 |
| Confidence | 0.678 | 0.891 |
| Network diversity | 0.554 | 0.87 |
| Reliability | 0.64 | 0.779 |
| Ranking eligible ratio | 0.211 | 0.764 |
| Trophy eligible ratio | 0.002 | 0.464 |

La divergencia principal es la estructura social: 50 equipos, redes provinciales pequeñas, repetición y participantes distribuidos de forma muy desigual frente al grafo amplio de 10.000 jugadores.

## Contrafactuales A-E

| Clon | Escenario | Partidos añadidos | Ranking | Trofeo | Pending | Orgánico |
| --- | --- | --- | --- | --- | --- | --- |
| A | V3 intacta | 0 | 135 | 1 | 54 | 0 |
| B | Certificación provincial 20/8 | 0 | 135 | 1 | 76 | 0 |
| C | V3 + densidad de Retos 25% | 275 | 176 | 1 | 69 | 0 |
| D | Rotación: no aplicada, problema no demostrado | 0 | 135 | 1 | 54 | 0 |
| E | V3 sin holds de integridad | 0 | 135 | 55 | 0 | 54 |

D no muta el mundo: la auditoría no demostró que la rotación fuese un defecto. E mide el efecto de los holds, no propone desactivarlos.

## Hipótesis A-G

- **A SIMULATION_DENSITY: principal.** 133/135 rankeados fallan diversidad y el grafo solo tiene 50 equipos.
- **B SYNTHETIC_AGENT_BEHAVIOR: contribuye.** 5137/14484 evidencias se excluyen y existe una cola extrema de actividad.
- **C PRODUCT_FLOW_LOSS: no respaldada.** El invariante encuentra 0 pérdidas.
- **D SEASON_SCORE_INTEGRATION_BUG: no respaldada en creación de evidencia.** Sí se corrigió drift de configuración del adaptador, sin alterar el mundo V1.
- **E V3_RULE_TOO_STRICT: posible, no decidida.** Diversidad domina en este mundo, pero los clones y V3 10k deben guiar la decisión humana.
- **F INTEGRITY_FALSE_POSITIVES: visible pero atribuible en gran parte al mundo.** 50 legítimos quedan pending; su red sintética es objetivamente cerrada.
- **G EXPECTED_BEHAVIOR: parcial.** Casual y low-activity no certifican, como se espera; que el jugador muy activo tampoco pueda hacerlo casi nunca no es deseable.

## Recomendación

Mantener por ahora las reglas V3. No hay evidencia para relajar 25/10 sin una nueva población más amplia y orgánica. Corregir Synthetic World V2 para no inyectar elegibilidad, usar la configuración V3 exacta y generar más equipos/rivales independientes de forma natural; repetir entonces esta misma auditoría.

## Distribuciones complementarias

### Team IDs frente a rivales lógicos

| Rivales | Team IDs | Logical opponents |
| --- | --- | --- |
| 0 | 112 | 112 |
| 1-2 | 20 | 23 |
| 3-5 | 67 | 141 |
| 6-9 | 166 | 147 |
| 10-14 | 154 | 137 |
| 15+ | 121 | 80 |

### Network diversity

| Tramo | Total | Barcelona | Madrid | Valencia | Sevilla | Girona | Otros |
| --- | --- | --- | --- | --- | --- | --- | --- |
| <0.25 | 112 | 34 | 7 | 12 | 22 | 9 | 28 |
| 0.25-0.49 | 149 | 16 | 43 | 43 | 31 | 2 | 14 |
| 0.50-0.67 | 298 | 109 | 86 | 34 | 18 | 25 | 26 |
| >=0.68 | 81 | 36 | 19 | 2 | 4 | 18 | 2 |

### Rating reliability

| Tramo | Total | Barcelona | Madrid | Valencia | Sevilla | Girona | Otros |
| --- | --- | --- | --- | --- | --- | --- | --- |
| <0.45 | 110 | 33 | 27 | 15 | 12 | 9 | 14 |
| 0.45-0.54 | 108 | 36 | 23 | 18 | 11 | 11 | 9 |
| 0.55-0.74 | 219 | 63 | 55 | 31 | 26 | 16 | 28 |
| >=0.75 | 203 | 63 | 50 | 27 | 26 | 18 | 19 |

### Recencia de actividad

| Tramo | Total | Barcelona | Madrid | Valencia | Sevilla | Girona | Otros |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0-4 semanas | 320 | 103 | 74 | 56 | 34 | 25 | 28 |
| 5-8 semanas | 116 | 34 | 38 | 13 | 13 | 7 | 11 |
| 9-12 semanas | 31 | 11 | 6 | 5 | 4 | 5 | 0 |
| 13+ semanas | 173 | 47 | 37 | 17 | 24 | 17 | 31 |

### Escenarios de actividad

| Actividad | Jugadores | Ranking | % ranking | Trofeo | % trofeo |
| --- | --- | --- | --- | --- | --- |
| low_activity | 150 | 0 | 0 | 0 | 0 |
| hyperactive | 133 | 84 | 63.2 | 0 | 0 |
| casual | 161 | 0 | 0 | 0 | 0 |
| regular | 196 | 51 | 26 | 1 | 0.5 |

### Comparación provincial

| Provincia | Jugadores | Retos p50 | Rivales p50 | Confidence p50 | Diversity p50 | Ranking | Trofeo | Pending |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 08 | 195 | 12 | 8 | 0.7 | 0.6 | 44 | 0 | 21 |
| 15 | 20 | 26.5 | 14.5 | 0.69 | 0.56 | 7 | 0 | 6 |
| 17 | 54 | 8.5 | 6 | 0.7 | 0.62 | 7 | 1 | 2 |
| 28 | 155 | 17 | 9 | 0.68 | 0.57 | 52 | 0 | 19 |
| 30 | 27 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| 41 | 75 | 13 | 5 | 0.68 | 0.42 | 11 | 0 | 6 |
| 46 | 91 | 23 | 5 | 0.63 | 0.43 | 11 | 0 | 0 |
| 50 | 23 | 24 | 5 | 0.69 | 0.49 | 1 | 0 | 0 |

### Actividad e integridad del Top 50

| # | Jugador | Actividad | Integridad | Ranking provincial | Bloqueos |
| --- | --- | --- | --- | --- | --- |
| 1 | SIM · Alex F. 609 | 1 semanas | 13.35 | 1 | insufficient_network_diversity, low_confidence_dependency |
| 2 | SIM · Pablo G. 029 | 2 semanas | 7.32 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 3 | SIM · Paula N. 416 | 1 semanas | 6.88 | 2 | insufficient_challenges, insufficient_network_diversity |
| 4 | SIM · Hugo A. 064 | 2 semanas | 16.48 | 1 | insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 5 | SIM · Sofía F. 054 | 3 semanas | 12.76 | 3 | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 6 | SIM · Lina T. 306 | 1 semanas | 19.48 | fuera | ranking_not_eligible, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 7 | SIM · Irene B. 586 | 3 semanas | 21.57 | 1 | insufficient_network_diversity, low_confidence_dependency |
| 8 | SIM · Lina R. 173 | 1 semanas | 9.57 | 1 | insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 9 | SIM · Marc G. 042 | 5 semanas | 16.15 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 10 | SIM · Sergio N. 274 | 1 semanas | 33.67 | 2 | insufficient_competitive_confidence, insufficient_network_diversity |
| 11 | SIM · Alex N. 170 | 3 semanas | 10.72 | 1 | insufficient_challenges, insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 12 | SIM · Bruno B. 127 | 2 semanas | 7.94 | 1 | insufficient_network_diversity, low_confidence_dependency |
| 13 | SIM · Hugo G. 430 | 2 semanas | 14.71 | 3 | insufficient_network_diversity |
| 14 | SIM · Sofía A. 533 | 2 semanas | 9.74 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 15 | SIM · Hugo V. 445 | 3 semanas | 10.44 | 4 | insufficient_network_diversity, low_confidence_dependency |
| 16 | SIM · Marc N. 163 | 8 semanas | 8.46 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, low_confidence_dependency |
| 17 | SIM · Lina N. 061 | 2 semanas | 12.33 | 4 | insufficient_network_diversity, low_confidence_dependency |
| 18 | SIM · Paula T. 019 | 2 semanas | 7.54 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 19 | SIM · Leo D. 391 | 2 semanas | 13.88 | 5 | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 20 | SIM · Vera C. 159 | 3 semanas | 8.17 | 2 | insufficient_network_diversity, low_confidence_dependency |
| 21 | SIM · Paula M. 280 | 1 semanas | 14.16 | fuera | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 22 | SIM · Hugo M. 069 | 3 semanas | 9 | 6 | insufficient_network_diversity |
| 23 | SIM · Marc R. 205 | 1 semanas | 11.58 | 5 | insufficient_network_diversity |
| 24 | SIM · Marc G. 226 | 2 semanas | 10.92 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 25 | SIM · Rai V. 421 | 3 semanas | 7.76 | 7 | insufficient_network_diversity, low_confidence_dependency |
| 26 | SIM · Marta M. 503 | 3 semanas | 11.43 | 6 | insufficient_network_diversity, low_confidence_dependency |
| 27 | SIM · Irene F. 147 | 5 semanas | 3.46 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 28 | SIM · Vera S. 192 | 3 semanas | 10.09 | 3 | insufficient_network_diversity, low_confidence_dependency |
| 29 | SIM · Irene F. 138 | 2 semanas | 11.68 | 8 | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 30 | SIM · Bruno N. 513 | 1 semanas | 17.01 | fuera | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 31 | SIM · Sofía R. 045 | 3 semanas | 19.82 | fuera | ranking_not_eligible, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 32 | SIM · Rai R. 343 | 2 semanas | 10.94 | 9 | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 33 | SIM · Leo C. 382 | 11 semanas | 12.2 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 34 | SIM · Eva D. 351 | 11 semanas | 4.51 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 35 | SIM · Nico V. 337 | 2 semanas | 9.71 | 10 | insufficient_network_diversity, low_confidence_dependency |
| 36 | SIM · Alex D. 236 | 1 semanas | 7.61 | 11 | insufficient_challenges, insufficient_network_diversity, low_confidence_dependency |
| 37 | SIM · Dani R. 366 | 3 semanas | 10.08 | 4 | insufficient_competitive_confidence, insufficient_network_diversity, insufficient_rating_reliability |
| 38 | SIM · Eva S. 281 | 44 semanas | 5.4 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, insufficient_recent_activity |
| 39 | SIM · Eva R. 271 | 3 semanas | 8.3 | 12 | insufficient_competitive_confidence, insufficient_network_diversity, insufficient_rating_reliability, low_confidence_dependency |
| 40 | SIM · Joel D. 348 | 1 semanas | 15.15 | fuera | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 41 | SIM · Eric N. 026 | 1 semanas | 10.25 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 42 | SIM · Lina S. 488 | 3 semanas | 12.55 | 13 | insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |
| 43 | SIM · Hugo M. 310 | 3 semanas | 11.15 | 14 | insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 44 | SIM · Vera F. 051 | 44 semanas | 5.4 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, insufficient_recent_activity |
| 45 | SIM · Sara S. 208 | 15 semanas | 13.84 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents, insufficient_competitive_confidence, insufficient_network_diversity, low_confidence_dependency |
| 46 | SIM · Pablo V. 617 | 9 semanas | 2.84 | fuera | ranking_not_eligible, insufficient_challenges |
| 47 | SIM · Vera S. 269 | 3 semanas | 10.25 | fuera | ranking_not_eligible, insufficient_competitive_confidence, insufficient_network_diversity, insufficient_rating_reliability, low_confidence_dependency |
| 48 | SIM · Víctor R. 515 | 7 semanas | 3.66 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 49 | SIM · Sara T. 476 | 12 semanas | 2.03 | fuera | ranking_not_eligible, insufficient_challenges, insufficient_logical_opponents |
| 50 | SIM · Pablo F. 632 | 4 semanas | 15.58 | fuera | ranking_not_eligible, insufficient_logical_opponents, insufficient_network_diversity, low_confidence_dependency |

## Incidencias y regresiones

- `SW-0059`: separación explícita entre partido y evidencia jugador-partido.
- `SW-0060`: la cobertura artificial deja de activarse por defecto; el V1 preservado conserva sus nueve controles como historia.
- `SW-0061`: cohorts attacker/legitimate calculadas por propietario de la evidencia, no por partido completo.
- `SW-0062`: configuración exacta V3 restaurada en el adaptador sintético.
- `SW-0063`: percentiles y narrativa del informe etiquetados sin ambigüedad.
- `SW-0064`: identidad única para las etapas duplicadas del funnel, verificada sin errores de consola.
- `SW-0065`: runner de concurrencia ejecutado con mundo QA local explícito, sin mutar V1.
- `SW-0066`: lint focalizado V1.1 sin símbolos muertos ni avisos.
- `SW-0067`: dashboard local arrancado en sesión controlada y verificado por HTTP 200.
