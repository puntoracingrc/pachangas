# Season Score V3 — elegibilidad de trofeo y anti-manipulación

Todos los datos son sintéticos. Este PR sigue siendo un laboratorio: no crea rankings, trofeos, sanciones, tablas ni RPC de producto.

## Decisión ejecutiva

- **Top10 provincial: YES** para un rollout experimental controlado con estrategia B+C, sujeto a validar con datos reales anonimizados antes de conceder premios.
- **Top10 autonómico: NO**. La señal o cobertura multi-seed no alcanza todavía el nivel provincial.
- **Top10 España: NO**. Top100 es más defendible que Top10, pero no debe forzarse el lanzamiento nacional.
- Rollout recomendado: **provincia → comunidad → España**.

## Fórmula y dos elegibilidades

La única puntuación sigue siendo Season Score: **55% Calidad, 30% Competición, 15% Oposición**, ventana **recent_30**. No existe una segunda puntuación de trofeo. Internamente se ordena con precisión completa; el score visible puede redondearse.

- Ranking durante temporada: 15 Retos, 6 rivales lógicos, fiabilidad >= 0,45, actividad <= 12 semanas.
- Trofeo provincial baseline: 25 Retos, 10 rivales lógicos, confianza >= 0,72, diversidad de red >= 0,68, fiabilidad >= 0,55 y actividad <= 12 semanas.
- Estados: **eligible**, **provisional**, **pending_integrity_review**, **not_eligible**.

## Estrategias A/B/C

| Estrategia | Contaminación Top10 | Contaminación certificada | Pendientes | Alto riesgo |
| --- | --- | --- | --- | --- |
| control | 0.2 | 0 | 0 | 0 |
| score_penalty | 0.2 | 0 | 0 | 0 |
| evidence_exclusion | 0 | 0 | 0 | 0 |
| certification_hold | 0.2 | 0 | 0 | 0 |
| penalty_and_hold | 0.2 | 0 | 0 | 0 |
| exclusion_and_hold | 0 | 0 | 0 | 0 |

La recomendación es **B+C: excluir evidencia no suficientemente independiente o fiable y retener la certificación excepcional**. A sola no reduce el ataque residual de oposición inflada. Con 5% de manipuladores, B+C deja contaminación Top10 en **0** y contaminación de trofeos en **0**.

## Evidencia explicable

**match_competitive_confidence** usa reto aceptado, campo/hora coherentes, participantes, resultado bilateral, antigüedad e historial de equipos e independencia del rival. No usa GPS, fingerprinting ni Rating V2.

**opponent_independence_score** usa owner/admin, solapamiento de plantilla, cuentas compartidas, edad, historial de enfrentamientos y clúster deportivo. Equipos técnicos con >=75% de plantilla compartida, o >=55% más admin común y reciente creación, se colapsan en un **logical_opponent_id**.

| Política | Elegibles | NDCG10 p50 | Recall20 p50 | Ventaja volumen |
| --- | --- | --- | --- | --- |
| graduated | 7643 | 0.695 | 0.8 | 0.0202 |
| hard_050 | 7643 | 0.695 | 0.8 | 0.0202 |
| hard_075 | 7643 | 0.695 | 0.8 | 0.0202 |

El modelo graduado mantiene la lectura más estable: >=0,75 peso completo; 0,50–0,75 peso reducido; <0,50 excluido. Independencia <0,50 también excluye la evidencia del ranking.

## Club legítimo, granja y colusión

| Caso | Team IDs | Rivales lógicos | Diversidad | Riesgo | Certificación |
| --- | --- | --- | --- | --- | --- |
| legitimate-club-player | 4 | 4 | 0.4522 | 8.67 | not_eligible |
| fake-farm-beneficiary | 10 | 1 | 0.0061 | 49.59 | not_eligible |

El club real conserva cuatro rivales lógicos y riesgo bajo; no recibe trofeo solo porque 4 < 10, no por sanción. Las diez identidades falsas con 90% de plantilla y el mismo admin colapsan a un rival lógico. La colusión entre equipos reales conserva score visible, pero su circuito cerrado reduce diversidad a **0.5765** y no certifica el trofeo.

## Participación fantasma

| Modo | Acciones extra/partido | Ataque aceptado | Completado legítimo |
| --- | --- | --- | --- |
| Confirmación propia | 0 | 1 | 0.99 |
| Confirmación admin | 1 | 0.48 | 0.96 |
| Confirmación cruzada rival | 2 | 0.08 | 0.91 |
| Muestreo Top10/anomalías | 0.18 | 0.12 | 0.97 |

La opción D, muestreo solo para Top10 o anomalías, ofrece el mejor compromiso. Son supuestos de laboratorio, no tasas observadas.

## Ataque al corte #15 → #9

Se probaron 1/3/5/10 cuentas por 1/3/5/10 partidos. Coste mínimo observado: **no alcanzado dentro de 10 cuentas y 10 partidos**. La evidencia débil permanece en historial, pero B+C no la confirma como evidencia de ranking.

## Elegibilidad territorial

| Regla | Ámbito | Certificados | Territorios | NDCG10 | Recall20 | Top100 ES |
| --- | --- | --- | --- | --- | --- | --- |
| province-20/8 | province | 6262 | 51 | 0.7502 | 0.9 |  |
| province-25/10 | province | 4635 | 51 | 0.7814 | 0.9 |  |
| province-30/10 | province | 2843 | 44 | 0.8243 | 0.9 |  |
| autonomous_community-25/10 | autonomous_community | 4304 | 17 | 0.6893 | 0.7 |  |
| autonomous_community-30/12 | autonomous_community | 2610 | 16 | 0.7448 | 0.8 |  |
| autonomous_community-35/15 | autonomous_community | 1339 | 14 | 0.7609 | 0.9 |  |
| national-30/12 | national | 2290 | 0 | 0 | 0 | 0.6616 |
| national-40/15 | national | 562 | 0 | 0 | 0 | 0.8805 |
| national-50/20 | national | 74 | 0 | 0 | 0 | 0.9953 |

## Multi-seed (30 × 10.000 jugadores)

| Métrica | Media | p5 | p50 | p95 |
| --- | --- | --- | --- | --- |
| communityNdcg10 | 0.7398 | 0.6865 | 0.7307 | 0.7966 |
| communityRecall20 | 0.8033 | 0.7 | 0.8 | 0.9 |
| contamination5pct | 0 | 0 | 0 | 0 |
| nationalTop100Ndcg | 0.872 | 0.7917 | 0.8751 | 0.9015 |
| nationalTop10Ndcg | 0.418 | 0.1211 | 0.3841 | 0.6513 |
| predictiveUplift | 12.2514 | 11.5464 | 12.2814 | 12.7681 |
| provinceNdcg10 | 0.7896 | 0.7602 | 0.7892 | 0.8162 |
| provinceRecall20 | 0.89 | 0.8 | 0.9 | 0.9 |

Objetivos provinciales: NDCG10 p50 >=0,75; recall20 p50 >=0,85; uplift p5 >10; contaminación p95 <=0,05; falso positivo high-risk <=0,02; |ventaja volumen| <=0,10.

## España

| Truth | Top | Overlap | Precision | NDCG | Recall 2K |
| --- | --- | --- | --- | --- | --- |
| capacity | 10 | 2 | 0.2 | 0.2757 | 0.5 |
| capacity | 25 | 12 | 0.48 | 0.6465 | 0.92 |
| capacity | 50 | 37 | 0.74 | 0.8602 | 0.88 |
| capacity | 100 | 72 | 0.72 | 0.8786 | 0.95 |
| season_merit | 10 | 1 | 0.1 | 0.2327 | 0.5 |
| season_merit | 25 | 10 | 0.4 | 0.6412 | 0.92 |
| season_merit | 50 | 39 | 0.78 | 0.8716 | 0.92 |
| season_merit | 100 | 74 | 0.74 | 0.8805 | 0.97 |

Se evaluó Top100 además de Top50/25/10. El mismo Season Score se usa en todos los ámbitos; solo cambia la certificación.

## Robustez, corte y desempate

- Dependencia total de algún partido en la muestra leave-one-out: 0.2083.
- Dependencia de evidencia de baja confianza: 0.
- Churn Top10 semanas 40→48: media 0.1625, p50 0.1, p90 0.3.
- Empates exactos con precisión canónica: 0.
- Cutoffs provinciales a <=1 punto: 17/52; es telemetría, no bloqueo.
- Desempate público solo tras empate canónico exacto: confianza competitiva, rivales lógicos, fiabilidad Rating, Retos válidos en ventana, fecha más temprana al alcanzar el score.

## Certificación y carga humana

Un #8 pendiente conserva su puesto; #11 no asciende y el trofeo queda pendiente: {"promoteRank11":false,"trophyStatus":"pending"}. Flujo: **season frozen → integrity reconciliation → awards certified → season closed**.

Candidaturas pendientes normales: 0; perfiles deduplicados: 0. La revisión humana se limita a candidato Top10 + anomalía. Ventanas 24h/48h/7d: 24h=viable, 48h=viable, 168h=viable.

## Entrega solicitada (1–40)

1. Baseline: 55/30/15, recent30, Rating V2 completo como entrada de solo lectura.
2. Certificación: cuatro estados, sin sanción automática.
3. Match confidence: escala 0–1 explicable.
4. Opponent independence: escala 0–1 explicable.
5. Rivales lógicos: grafo y colapso solo experimental.
6. False positives club: riesgo bajo, sin fusión por owner solo.
7. Fake teams: 10 team IDs → 1 rival lógico.
8. Collusion: circuito cerrado detectado por diversidad de red.
9. Fake participation: comparadas A/B/C/D.
10. Fake matches: incluidos en mezcla de ataques.
11. Ataque #15→#9: matriz 4×4.
12. Coste mínimo: >20 unidades sintéticas.
13. Contaminación 0/1/2/5/10%: **strategy_contamination.csv**.
14. Falsos positivos high-risk: 0.
15. Ranking eligibility: 15/6.
16. Trofeo provincia: 20/8, 25/10 y 30/10 comparados.
17. Trofeo comunidad: 25/10, 30/12 y 35/15 comparados.
18. Trofeo España: 30/12, 40/15 y 50/20 comparados.
19. Provincia NDCG p50 multi-seed: 0.7892.
20. Provincia recall20 p50: 0.9.
21. Predictive uplift p5: 11.5464.
22. Comunidad NDCG/recall p50: 0.7307/0.8.
23. España Top100/50/25/10: **summary.json** y tabla anterior.
24. Volume advantage: 0.0202.
25. Leave-one-out total: 0.2083.
26. Leave-one-out baja confianza: 0.
27. Churn: 0.1625.
28. Exact ties: 0.
29. Tie breaker: cinco criterios públicos y deterministas.
30. Revisión manual deduplicada: 0.
31. Top10 province readiness: YES.
32. Top10 autonomous readiness: NO.
33. Top10 Spain readiness: NO.
34. Razones: métricas objetivas, cobertura, ataques y estabilidad descritos arriba.
35. Configuración: B+C, 25/10 provincia, 30/12 comunidad, 40/15 España; España no se activa aún si readiness=NO.
36. Riesgos: simulación sintética, colusión sofisticada y confirmación física no observada.
37. Tests: unitarios V3, suite Season Score, typecheck, build y lint documentados al cierre del PR.
38. Commits: se añadirá el SHA de cierre al actualizar el PR.
39. Producción intacta: sí.
40. Rating V2 intacto: sí; no se modifica fórmula, facetas, assessments, votos, perfiles ni evidencias.


## Trazabilidad adicional V3

### Team ID frente a rival lógico

| Caso | Team IDs | Pasa 10 team IDs | Rivales lógicos | Pasa 10 lógicos |
| --- | --- | --- | --- | --- |
| legitimate-club-player | 4 | false | 4 | false |
| fake-farm-beneficiary | 10 | true | 1 | false |

### Colusión A-E y anillo de diez equipos

| Escenario | Estrategia | Diversidad | Score | Certificación |
| --- | --- | --- | --- | --- |
| ABCDE | control | 0.5765 | 854.36 | not_eligible |
| ABCDE | score_penalty | 0.5765 | 854.36 | not_eligible |
| ABCDE | evidence_exclusion | 0.5765 | 854.36 | not_eligible |
| ABCDE | certification_hold | 0.5765 | 854.36 | not_eligible |
| ABCDE | penalty_and_hold | 0.5765 | 854.36 | not_eligible |
| ABCDE | exclusion_and_hold | 0.5765 | 854.36 | not_eligible |
| ten-team-ring | control | 0.5765 | 881.71 | eligible |
| ten-team-ring | score_penalty | 0.5765 | 881.71 | eligible |
| ten-team-ring | evidence_exclusion | 0.5765 | 881.71 | eligible |
| ten-team-ring | certification_hold | 0.5765 | 881.71 | pending_integrity_review |
| ten-team-ring | penalty_and_hold | 0.5765 | 881.71 | pending_integrity_review |
| ten-team-ring | exclusion_and_hold | 0.5765 | 881.71 | pending_integrity_review |

Una red cerrada no cambia Season Score: en estrategias con hold pasa a revisión de integridad; no se inventa un score alternativo.

### Política cuando un Top10 queda pendiente

| Política | Promueve #11 | Estado del trofeo |
| --- | --- | --- |
| no_promotion | false | withheld |
| provisional_promotion | true | provisional |
| trophy_pending | false | pending |

La recomendación es **trophy_pending**: se conserva el ranking, no se promueve automáticamente al #11 y la concesión espera la reconciliación.

## Validación técnica de cierre

- Simulación V3: 30 seeds × 10.000 jugadores, PASS.
- Build de producción y suite completa: 149 tests, PASS.
- Typecheck: PASS.
- ESLint focalizado del laboratorio V3: PASS sin avisos.
- ESLint global: 23 errores y 20 avisos preexistentes, todos fuera de las rutas V3; no se modifican en este PR.
- `git diff --check`: PASS.
- Supabase, Vercel y producción: no consultados ni modificados en esta iteración.
- Rating V2: intacto; las nuevas reglas leen su salida y nunca recalculan ni escriben facetas, votos, assessments o snapshots.
