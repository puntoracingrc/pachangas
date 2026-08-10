# Season Score — validación de élite del PR #115

Todos los datos son sintéticos. Esta iteración no crea producto, tablas remotas, rankings reales, trofeos ni sanciones.

## Diagnóstico del 0% anterior

El 0% era **métrica y fórmula, en distinta medida**. La métrica anterior comparaba exactamente diez nombres entre 10.000 elegibles a escala nacional: un jugador de referencia #10 predicho #11 contaba como fallo completo, y mezclaba territorios que en producto tendrán rankings separados. Además, el ground truth de mérito era otra fórmula sintética parcialmente parecida al candidato. Al corregir ámbito, añadir NDCG/candidate recall y validar contra rendimiento futuro, la señal deja de ser binaria. La fórmula sigue teniendo margen si las métricas predictivas o de estabilidad quedan por debajo de los intervalos multi-seed.

## Metodología no circular

- NDCG usa relevancia ordinal lineal hasta 2K; evita que un #11 cuente casi como cero sin fingir que es Top10.
- Capacidad usa `latent_skill`; mérito de temporada combina 45% capacidad, 35% rendimiento individual sintético realizado y 20% oposición, distinto del candidato.
- La verdad futura usa solo semanas 35–52. El simulador genera un índice individual oculto con ruido determinista separado del calendario; ni el motor ni la selección de ventana pueden leerlo.
- Ese índice existe solo para validar capacidad predictiva del laboratorio. No es Rating V2, no usa goles y no propone un campo de producto.

## Finalista de esta iteración

`elite-weight-55-30-15`: pesos **55/30/15**, ventana `recent_30`, calidad `full`, elegibilidad de ranking 15/6.

### Ventanas

| Candidato | Ventana | Calidad | Pesos | NDCG10 terr. | Recall20 terr. | NDCG futuro | Recall futuro | Uplift | Churn | Volumen | Objetivo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| elite-window-recent_20 | recent_20 | competitive | 40/45/15 | 0.4969 | 0.6 | 0.479 | 0.6 | 9.7551 | 0.3551 | 0.0695 | 0.587098 |
| elite-window-recent_25 | recent_25 | competitive | 40/45/15 | 0.4947 | 0.6 | 0.4818 | 0.6 | 10.7528 | 0.2653 | 0.1385 | 0.594272 |
| elite-window-recent_30 | recent_30 | competitive | 40/45/15 | 0.5393 | 0.6 | 0.5041 | 0.6 | 11.2165 | 0.2245 | 0.1856 | 0.607668 |
| elite-window-all_saturated | all_saturated | competitive | 40/45/15 | 0.5605 | 0.6 | 0.4749 | 0.6 | 11.1183 | 0.1918 | 0.2227 | 0.605337 |
| elite-window-hybrid_70_30 | hybrid_70_30 | competitive | 40/45/15 | 0.5194 | 0.6 | 0.498 | 0.6 | 10.3665 | 0.2959 | 0.1608 | 0.594208 |

### Calidad competitiva

| Candidato | Ventana | Calidad | Pesos | NDCG10 terr. | Recall20 terr. | NDCG futuro | Recall futuro | Uplift | Churn | Volumen | Objetivo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| elite-quality-full | recent_30 | full | 40/45/15 | 0.5796 | 0.6 | 0.4826 | 0.6 | 10.0582 | 0.2327 | 0.0502 | 0.617886 |
| elite-quality-competitive | recent_30 | competitive | 40/45/15 | 0.5393 | 0.6 | 0.5041 | 0.6 | 11.2165 | 0.2245 | 0.1856 | 0.607668 |
| elite-quality-challenge_calibrated | recent_30 | challenge_calibrated | 40/45/15 | 0.3657 | 0.4 | 0.3509 | 0.5 | 8.361 | 0.2776 | 0.1726 | 0.47969 |

### Mejores pesos del grid

| Candidato | Pesos | NDCG10 terr. | Recall20 terr. | NDCG futuro | Recall futuro | Uplift | Churn | Volumen | Objetivo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| elite-weight-55-30-15 | 55/30/15 | 0.6294 | 0.8 | 0.6245 | 0.7 | 11.9081 | 0.1673 | 0.0413 | 0.720613 |
| elite-weight-55-35-10 | 55/35/10 | 0.6274 | 0.7 | 0.6117 | 0.7 | 11.5855 | 0.1816 | 0.0282 | 0.69879 |
| elite-weight-50-30-20 | 50/30/20 | 0.6207 | 0.7 | 0.5899 | 0.7 | 11.9206 | 0.1755 | 0.0594 | 0.692968 |
| elite-weight-50-35-15 | 50/35/15 | 0.6168 | 0.7 | 0.5964 | 0.7 | 11.4798 | 0.1918 | 0.0448 | 0.691049 |
| elite-weight-45-30-25 | 45/30/25 | 0.6168 | 0.7 | 0.5899 | 0.7 | 11.9578 | 0.1755 | 0.0797 | 0.690441 |
| elite-weight-45-35-20 | 45/35/20 | 0.6018 | 0.7 | 0.5753 | 0.7 | 11.6696 | 0.1939 | 0.0633 | 0.683621 |
| elite-weight-50-40-10 | 50/40/10 | 0.593 | 0.7 | 0.5577 | 0.7 | 11.4128 | 0.2041 | 0.0309 | 0.679937 |
| elite-weight-45-40-15 | 45/40/15 | 0.593 | 0.7 | 0.5281 | 0.7 | 10.8852 | 0.2041 | 0.0478 | 0.670429 |

## Provincias y comunidades

| Densidad | Territorios | Precision@10 p50 | NDCG@10 p50 | Candidate recall@20 p50 | Rank error p50 |
| --- | --- | --- | --- | --- | --- |
| dense | 10 | 0.4 | 0.4962 | 0.6 | 19 |
| medium | 30 | 0.5 | 0.6207 | 0.7 | 12 |
| small | 11 | 0.6 | 0.8008 | 0.9 | 5.4 |

De 52 territorios base, 52 tienen al menos 30 elegibles y 51 tienen al menos 50. Agregado provincial >=50:

| Métrica | Media | p10 | p50 | p90 |
| --- | --- | --- | --- | --- |
| Precision@10 | 0.4824 | 0.2 | 0.5 | 0.7 |
| Recall@10 | 0.4824 | 0.2 | 0.5 | 0.7 |
| Overlap@10 | 4.8235 | 2 | 5 | 7 |
| NDCG@10 | 0.6176 | 0.431 | 0.6294 | 0.8008 |
| NDCG@20 | 0.7729 | 0.6137 | 0.7956 | 0.8837 |
| Mean rank error | 12.951 | 4.6 | 11.3 | 24.3 |
| Median rank error | 6.7255 | 2 | 6 | 14 |
| Near miss | 0.3628 | 0.125 | 0.3333 | 0.6 |
| Candidate recall@20 | 0.7373 | 0.5 | 0.8 | 0.9 |

Peor provincia por NDCG@10: **La Rioja (0.2966)**. Mejor: **Cuenca (0.9331)**.

En comunidades se evaluaron 17; 10 entran en el agregado tras retirar 7 duplicados conceptuales uniprovinciales. Los CSV conservan ambos para auditoría.

| Métrica autonómica | Media | p10 | p50 | p90 |
| --- | --- | --- | --- | --- |
| Precision@10 | 0.27 | 0 | 0.3 | 0.4 |
| Recall@10 | 0.27 | 0 | 0.3 | 0.4 |
| Overlap@10 | 2.7 | 0 | 3 | 4 |
| NDCG@10 | 0.3054 | 0.0047 | 0.2516 | 0.4588 |
| NDCG@20 | 0.4919 | 0.2436 | 0.5537 | 0.6268 |
| Mean rank error | 49.57 | 8.4 | 34.9 | 103.6 |
| Median rank error | 19.8 | 4 | 11 | 36 |
| Near miss | 0.1798 | 0 | 0.1429 | 0.3333 |
| Candidate recall@20 | 0.45 | 0.2 | 0.4 | 0.6 |

Peor comunidad no duplicada por NDCG@10: **Andalucía (0.0047)**. Mejor: **Extremadura (0.6529)**.

## España

| Truth | Top | Overlap | Precision | NDCG | Recall en 2K |
| --- | --- | --- | --- | --- | --- |
| capacity | 10 | 0 | 0 | 0.023 | 0 |
| capacity | 25 | 2 | 0.08 | 0.0787 | 0.12 |
| capacity | 50 | 6 | 0.12 | 0.1374 | 0.2 |
| capacity | 100 | 17 | 0.17 | 0.2092 | 0.28 |
| season_merit | 10 | 0 | 0 | 0 | 0 |
| season_merit | 25 | 0 | 0 | 0.0362 | 0.12 |
| season_merit | 50 | 6 | 0.12 | 0.1375 | 0.18 |
| season_merit | 100 | 18 | 0.18 | 0.2286 | 0.37 |
| future | 10 | 0 | 0 | 0 | 0 |
| future | 25 | 0 | 0 | 0 | 0 |
| future | 50 | 0 | 0 | 0.0193 | 0.06 |
| future | 100 | 8 | 0.08 | 0.1503 | 0.2 |

Métricas nacionales del candidato anterior corregidas:

| Truth | Top | Overlap | Precision | NDCG | Recall en 2K |
| --- | --- | --- | --- | --- | --- |
| capacity | 10 | 0 | 0 | 0 | 0 |
| capacity | 25 | 1 | 0.04 | 0.0247 | 0.04 |
| capacity | 50 | 1 | 0.02 | 0.0209 | 0.06 |
| capacity | 100 | 7 | 0.07 | 0.0793 | 0.17 |
| season_merit | 10 | 1 | 0.1 | 0.0752 | 0.1 |
| season_merit | 25 | 1 | 0.04 | 0.0473 | 0.08 |
| season_merit | 50 | 2 | 0.04 | 0.0907 | 0.1 |
| season_merit | 100 | 12 | 0.12 | 0.1645 | 0.28 |
| future | 10 | 0 | 0 | 0 | 0 |
| future | 25 | 0 | 0 | 0 | 0 |
| future | 50 | 0 | 0 | 0.0187 | 0 |
| future | 100 | 5 | 0.05 | 0.1081 | 0.17 |

## Out-of-sample y multi-seed

El ranking se calcula con semanas 1–34 y se valida exclusivamente con Retos de semanas 35–52. Top 100 obtiene rendimiento futuro medio 68.3329 frente a 56.4249 de población: uplift **11.9081**, correlación 0.7503.

| Top | Elegibles | Rendimiento futuro | Uplift rendimiento | Oposición futura | Uplift oposición | Índice competitivo | Uplift índice |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 10 | 6857 | 68.0463 | 16.7284 | 71.2074 | -0.5381 | 68.8366 | 12.4118 |
| 25 | 6857 | 66.6468 | 15.3288 | 72.0995 | 0.3539 | 68.01 | 11.5851 |
| 50 | 6857 | 66.8695 | 15.5516 | 71.9506 | 0.205 | 68.1398 | 11.7149 |
| 100 | 6857 | 67.0692 | 15.7513 | 72.1241 | 0.3786 | 68.3329 | 11.9081 |

El índice competitivo futuro es una referencia sintética fuera de muestra; no modifica ni pretende sustituir Rating V2.

| Métrica (20 seeds) | Media | Std | p5 | p50 | p95 |
| --- | --- | --- | --- | --- | --- |
| futureNdcg10 | 0.6116 | 0.0236 | 0.5588 | 0.6157 | 0.6416 |
| futureRecall20 | 0.7 | 0.0316 | 0.6 | 0.7 | 0.7 |
| ndcg10 | 0.7071 | 0.0278 | 0.6509 | 0.7032 | 0.7571 |
| predictiveUplift | 12.2718 | 0.4495 | 11.2526 | 12.2933 | 12.816 |
| rankError | 9.52 | 0.8698 | 8.3 | 9.4 | 11 |
| recall20 | 0.785 | 0.0357 | 0.7 | 0.8 | 0.8 |

## Incertidumbre y robustez del corte

- Provincias bootstrap: 51; #10 y #11 comparten banda de incertidumbre en 100%.
- Confianza media del score #10: 0.62.
- Top 10 con dependencia de algún partido individual: 28.82% de media territorial.
- Sensibilidad de eliminaciones individuales: 7.34%.

Season Score mantiene el orden provisional. Para trofeo, la evidencia adicional filtra sin introducir una fórmula secreta:

| Regla | Elegibles | Territorios | NDCG10 | Recall20 | Rank error |
| --- | --- | --- | --- | --- | --- |
| 20/8 | 7665 | 51 | 0.6864 | 0.8 | 9.7 |
| 25/10 | 5147 | 49 | 0.7701 | 0.9 | 7 |
| 30/10 | 2698 | 33 | 0.8525 | 0.9 | 5.2 |

Mejor equilibrio experimental: **30/10**. Sigue sujeto a los intervalos y no concede trofeos reales.

## Justicia deportiva

| Caso | Rating | Equipo | Win rate | Calidad | Competición | Score |
| --- | --- | --- | --- | --- | --- | --- |
| mediocre-strong-team | 75 | 92 | 0.72 | 396.33 | 189.05 | 713.81 |
| excellent-weak-team | 91 | 72 | 0.48 | 480.88 | 197.59 | 804.29 |
| good-normal-team | 88 | 80 | 0.6 | 465.03 | 212.27 | 805.72 |

| Posición | Elegibles | Top10 plazas | Precision@10 | Share elegible | Share Top | Ratio representación | Corr. mérito |
| --- | --- | --- | --- | --- | --- | --- | --- |
| POR | 928 | 64 | 0.5625 | 0.1002 | 0.1231 | 1.2277 | 0.8606 |
| DEF | 3713 | 210 | 0.4381 | 0.4011 | 0.4038 | 1.0068 | 0.8583 |
| MED | 2779 | 159 | 0.5283 | 0.3002 | 0.3058 | 1.0185 | 0.8542 |
| DEL | 1837 | 87 | 0.4828 | 0.1984 | 0.1673 | 0.8431 | 0.8537 |

Jugar en 1/2/5/10 equipos propios no concede bonus directo: consultar `own_team_diversity.csv`. El equipo forma parte del contexto del resultado, no de la calidad individual.

## Densidad y estacionalidad

| Mínimo elegibles | Territorios | NDCG10 | Recall20 | Rank error |
| --- | --- | --- | --- | --- |
| 30 | 52 | 0.6294 | 0.8 | 10.9 |
| 40 | 51 | 0.6294 | 0.8 | 11.3 |
| 50 | 51 | 0.6294 | 0.8 | 11.3 |
| 75 | 46 | 0.6139 | 0.7 | 12.3 |
| 100 | 38 | 0.5884 | 0.7 | 13 |

| Actividad | Territorios >=50 | NDCG10 | Recall20 | Churn |
| --- | --- | --- | --- | --- |
| normal | 45 | 0.7207 | 0.8 | 0.1614 |
| high_activity | 44 | 0.7044 | 0.8 | 0.1386 |
| summer_dip | 47 | 0.7343 | 0.8 | 0.1152 |
| progressive_growth | 45 | 0.6634 | 0.8 | 0.2455 |
| province_growth | 45 | 0.6929 | 0.8 | 0.2186 |

## Red team y corte #10

Se repitieron los 14 ataques. Con 5% de manipuladores, contaminación Top 10 finalista: 60%; falsos positivos `suspicious/high_risk`: 0%.

| Modo | Provincia | De # | A # | Partidos falsos | Cuentas |
| --- | --- | --- | --- | --- | --- |
| unprotected | 08 | 15 | 9 | 1 | 1 |
| protected | 08 | 15 | 9 |  |  |

Si el modo protegido devuelve vacío, el atacante no alcanza #9 ni con 30 partidos/cuentas sintéticos. No se redujo ninguna protección para mejorar precisión.

## Criterios objetivos propuestos

Son guardas de no-regresión derivadas de los intervalos de 20 seeds, no cifras escogidas antes de simular:

- territorial median NDCG@10 >= **0.65**;
- candidate recall@20 >= **0.7**;
- mean rank error Top10 <= **11**;
- predictive uplift Top100 >= **11** en p5;
- contaminación con 5% de manipuladores <= **20%** (límite p95 de una selección Top10 aleatoria con prevalencia 5%);
- falsos positivos suspicious/high <= **1%**;
- además, ninguna regresión en posición, dependencia de un partido o privacidad.

## Decisión

**Recomiendo otra iteración de laboratorio; todavía no debe implementarse como producto.**

Frenos medidos: contaminación Top10 60% frente al límite 20%; dependencia de un encuentro 28.82% frente al 25% propuesto; y banda #10/#11 compartida en 100% de provincias. Además, la presencia real no queda demostrada por inscripción, el venue acordado no prueba ubicación, colusión real necesita grafo histórico y los ground truths sintéticos no sustituyen datos deportivos reales anonimizados.

## Validación técnica

- 11 tests de élite y 25 tests focalizados Season Score: PASS.
- `npm test`: build de producción y 136 tests: PASS.
- `npm run typecheck`: PASS.
- ESLint focalizado del laboratorio: PASS.
- ESLint global: 23 errores y 20 avisos preexistentes, todos fuera del diff del laboratorio; no se modificaron por esta entrega.
- `git diff --check`: PASS.

## Entrega solicitada (1–37)

1. El 0 anterior era Top10 nacional exacto sobre 10.000 y ground truth sintético; mezclaba ámbito y cercanía.
2. Problema de métrica y parcialmente de fórmula; esta iteración los separa.
3. Nacional anterior corregido: `previous_national_metrics_corrected.csv`.
4. Provincias: `province_season_merit.csv`.
5. Comunidades: `autonomous_communities.csv` con duplicados marcados.
6. NDCG@10: territorial, autonómico y nacional.
7. Candidate recall@20: incluido.
8. Rank error medio/mediano: incluido.
9. Predictive validation: corte 70/30 sin fuga.
10. Multi-seed: 20 seeds de 10.000 jugadores.
11. Incertidumbre: bootstrap reproducible de 100 iteraciones.
12. #10/#11: bandas y gap en `top10_uncertainty.csv`.
13. Ranking: 15/6.
14. Trofeo: 30/10 experimental + confianza/actividad.
15. Ventanas: recent20/25/30, all y hybrid70/30.
16. Híbridos: comparados, no adoptados automáticamente.
17. Pesos: grid 35–55 / 30–50 / 10–25.
18. Calidad: full, competitive y challenge_calibrated.
19. Jugador mediocre/equipo fuerte: probado.
20. Excelente/equipo débil: probado.
21. POR/DEF/MED/DEL: segmentados.
22. Densidad: 30/40/50/75/100.
23. Estabilidad: territorial y cinco perfiles, incluido crecimiento provincial.
24. Leave-one-out: todos los Top10 provinciales >=50.
25. Red team: 14 ataques repetidos.
26. Ataque #15→#9: incluido.
27. Contaminación: 1/2/5/10%.
28. Falsos positivos: cinco casos legítimos.
29. Finalistas: `candidate_elite_comparison.csv`.
30. Recomendación: `elite-weight-55-30-15`, solo laboratorio.
31. Criterios: guardas multi-seed anteriores.
32. Fallos abiertos: presencia, venue, colusión, corte y datos reales.
33. Decisión: otra iteración de laboratorio.
34. Tests: 25 focalizados; build y 136 tests completos en verde. Lint focalizado verde; deuda global preexistente documentada.
35. Commit/PR: actualización del PR #115.
36. Producción/Supabase remoto: intactos.
37. Rating V2, logros y recompensas: intactos.
