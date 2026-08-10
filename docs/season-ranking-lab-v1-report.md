# Season Ranking Lab V1 — informe reproducible

Generado con semilla `20260809`. Todos los datos son sintéticos. Este informe no activa rankings, trofeos, sanciones ni escrituras remotas.

## Resumen ejecutivo

Se compararon 5 candidatos principales, 13 combinaciones de pesos, 5 umbrales de elegibilidad, 3 perfiles de repetición y 4 modelos de volumen sobre 10.000 jugadores, 1000 equipos y 3 temporadas. La recomendación experimental es **40/45/15 · Últimos 20** (`candidate_e_recent20`), seleccionada por una función explícita que combina fidelidad deportiva, precisión de Top, resistencia al volumen y reducción de contaminación. No es todavía una fórmula de producto.

## Fórmulas candidatas

| Candidato | Elegibles | Spearman mérito | Corr. latent | Top10 | Top50 | Top100 | Ventaja volumen |
| --- | --- | --- | --- | --- | --- | --- | --- |
| candidate_a_full_rating | 9852 | 0.8506 | 0.8321 | 0 | 0.2 | 0.31 | 0.0853 |
| candidate_b_competitive_recent25 | 9812 | 0.8133 | 0.767 | 0 | 0.16 | 0.27 | 0.2978 |
| candidate_c_integrity_saturated | 9838 | 0.8231 | 0.7733 | 0 | 0.1 | 0.26 | 0.3103 |
| candidate_d_best20_control | 9726 | 0.7714 | 0.7548 | 0 | 0.02 | 0.11 | 0.6072 |
| candidate_e_recent20 | 9257 | 0.7947 | 0.7248 | 0 | 0.16 | 0.25 | 0.0695 |

La precisión Top 10 exacta del finalista es 0% en esta población. Es una advertencia explícita: aunque el orden global y el Top 100 son razonables, el laboratorio todavía no justifica publicar trofeos ni tratar esta fórmula como cerrada.

Fórmula común, antes del factor experimental de integridad:

`Season Score = 10 × (calidad × peso_calidad + competición × peso_competición + oposición × peso_oposición) / 100`.

- **Calidad**: Rating V2 de solo lectura × fiabilidad × desbloqueo de evidencia competitiva.
- **Competición**: media bayesiana saturada de `50 + 85 × (resultado_real - resultado_esperado)`, limitada a 0–100.
- **Oposición**: 58% nivel medio rival + 42% diversidad saturada.
- **Integridad**: solo en el candidato protegido, factor 1–0,58 derivado de riesgo por encima de 20; no sanciona ni modifica Rating.
- **Redondeo**: dos decimales en la salida visible; cálculos internos sin redondeos intermedios salvo entradas sintéticas.
- **Diferencia de goles**: con idéntico W/D/L, el modelo actual da 708.6/708.6; la alternativa ensayada daría 712.1/724.1 y crea 12 puntos de incentivo a ampliar goleadas. Se descarta para V1.

## Casos humanos A–G

| Jugador | Pos. | Rating | Retos | Rivales | Calidad | Competición | Oposición | Score | Elegible |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | MC | 90 | 20 | 12 | 320.62 | 260.41 | 127.55 | 708.59 | Sí |
| B | MC | 78 | 70 | 10 | 275.79 | 268.57 | 117.22 | 661.58 | Sí |
| C | MC | 93 | 5 | 3 | 255.33 | 298.55 | 99.61 | 653.48 | No |
| D | MC | 85 | 23 | 15 | 302.81 | 302 | 135.19 | 740 | Sí |
| E | MC | 84 | 50 | 10 | 298.15 | 302.88 | 118.96 | 720 | Sí |
| F | DEF | 88 | 25 | 12 | 313.5 | 284.16 | 128.42 | 726.08 | Sí |
| G | DEL | 86 | 25 | 12 | 306.37 | 284.16 | 128.42 | 718.95 | Sí |

Los goles registrados de F y G no entran en ninguna función. F (726.08) puede superar a G (718.95) por calidad/rendimiento, no por posición. C permanece provisional con 5 Retos.

## Integridad y red team

| Ataque | Sin protección | Con integridad | Riesgo | Ventaja vs honesto |
| --- | --- | --- | --- | --- |
| collusion | 829.01 | 719.82 | 8.57 | 108.95 |
| fake_matches | 851.73 | 748.96 | 21.53 | 131.67 |
| fake_participation | 788.69 | 749.62 | 13.47 | 68.63 |
| ghost_teams | 889.75 | 430.71 | 38.5 | 169.69 |
| impossible_volume | 810.79 | 793.09 | 18 | 90.73 |
| opponent_boost | 859 | 703.37 | 11.38 | 138.94 |
| rating_boost | 743.24 | 614.7 | 8.14 | 23.18 |
| repeated_opponent | 789.57 | 516.13 | 33.72 | 69.51 |
| sacrifice_accounts | 929.03 | 354.08 | 51.41 | 208.97 |
| simultaneous_matches | 768.68 | 665.25 | 25.66 | 48.62 |
| smurf | 626.68 | 644.32 | 5 | -93.38 |
| sybil | 909.99 | 344.55 | 54.15 | 189.93 |
| team_hopping | 764.98 | 717.69 | 6.57 | 44.92 |
| territory_gaming | 761.81 | 714.5 | 11.5 | 41.75 |

Con 5% de manipuladores, la ocupación sintética del Top 10 pasa de 100% a 0%. La tasa de falso positivo `suspicious/high_risk` en los cinco casos legítimos adversariales es 0%. `watch` es una señal para revisión, nunca una acusación.

## Territorio

- 50 provincias + Ceuta + Melilla = 52 territorios base.
- 17 comunidades autónomas; Ceuta y Melilla no reciben una comunidad inventada y compiten en su territorio base y España.
- Comunidades uniprovinciales marcadas `territorialDuplicate=true`: Illes Balears, La Rioja, Madrid, Murcia, Navarra, Asturias, Cantabria.
- Empate 8/8 conserva provincia previa: `08`. Al superar 9/8 cambia a `17` sin reiniciar score.
- El mismo score alimenta rango provincial, autonómico y nacional; no existen tres scores.
- Con umbral 30 se activan 52 territorios y con 50 se activan 51, de 52. El experimento controlado 15/30/50/100/500 está en `territory_density_threshold_experiment.csv`. Recomendación experimental: 30 para mostrar tabla provisional y 50 para reconocer un Top 10 prestigioso.
- Dos ecosistemas con mismo Rating y W/D/L producen 628.33 ante rival medio 70 y 752.22 ante rival medio 90: la oposición corrige parte del sesgo territorial, pero requiere datos reales antes de un Top España.

## Volumen, nuevos y actividad

| Retos | Score | Peso útil |
| --- | --- | --- |
| 10 | 644.92 | 10 |
| 20 | 682.18 | 20 |
| 40 | 695.89 | 19.5 |
| 80 | 700.21 | 20 |
| 120 | 676.45 | 19 |

El modelo recomendado satura: el salto controlado entre 40 y 120 Retos es -19.44 puntos, no una suma infinita. `best_20` queda como control porque permite cherry-picking. El newcomer es elegible por primera vez en 15 Retos. La inactividad conserva score (736.58 → 736.58) pero al final queda fuera de elegibilidad visible; se recomienda soft-gate de actividad, no decay destructivo.

Churn medio semanal: Top10 0.3, Top50 0.22, Top100 0.21. Son 45 snapshots semanales vivos; el cierre de temporada genera filas inmutables separadas por `seasonId`.

## Recomendación V1 experimental

1. Pesos: **40/45/15**.
2. Elegibilidad: **15 Retos / 6 rivales lógicos**, fiabilidad mínima 0.45.
3. Rival decay: **100/100/50/25/0%**.
4. Volumen: **recent_20**, media saturada; no suma ni mejores partidos perpetuos.
5. Rating: desbloqueo `competitive`; Rating V2 permanece intacto.
6. Actividad: soft-gate de 12 semanas para visibilidad/premio, sin borrar Season Score.
7. Top 10 territorial: mostrar provisional desde 30 elegibles y no recomendar trofeo hasta 50.

## Riesgos abiertos

- La participación canónica prueba inscripción, no presencia física; hace falta UX ligera de confirmación cruzada antes de usarla para premios.
- Places fija el venue acordado, no demuestra presencia; congelar y auditar cambios, permitir reporte rival.
- Colusión entre equipos reales e independencia de clubes requieren grafo histórico y revisión humana.
- Comparabilidad entre ecosistemas territoriales necesita datos reales anonimizados antes de lanzamiento.
- Smurfs y rivales artificialmente inflados no pueden resolverse solo con Season Score.

## Validación local

- `npm test`: **PASS**, build de producción y 125 tests.
- `npm run test:season-ranking-lab`: **PASS**, 14 tests de justicia, territorio, reproducibilidad y ataques.
- `npm run typecheck`: **PASS**.
- lint focalizado sobre `simulation/season-ranking-lab` y los dos tests: **PASS**.
- `npm run lint` global: **FAIL preexistente**, 23 errores y 20 avisos en `app/`; ningún hallazgo pertenece al laboratorio y no se modificó esa deuda.
- `git diff --check`: **PASS**.
- Alcance persistente: 41 rutas, sin SQL, migraciones, UI, Rating V2 ni catálogo de logros.

## Privacidad

Recomendadas: grafo deportivo, partidos, participantes, equipos, owners/admins, solapamiento de plantilla, venue acordado y tiempos (datos de producto existentes o sensibilidad baja/moderada). No recomendadas por defecto: fingerprint oculto, GPS permanente, sanción por IP compartida o geolocalización continua (sensibilidad alta y falsos positivos).

## Entrega solicitada (1–63)

1. SHA inicial: `53fa08604f28a9f5e9f758120fcd9566bc3a7107`.
2. Rama/worktree: `codex/season-ranking-lab-v1` / `/Users/macbookpro14/.codex/worktrees/pachangas-season-ranking-lab-v1`.
3. Arquitectura: motor puro + configuración JSON + simulador + métricas + red team + datasets/SVG.
4. Temporadas: planned/active/frozen/closed y tres temporadas sintéticas.
5. Territorio: códigos provinciales canónicos y comunidad asociada.
6. Mapping provincia→comunidad: `src/territories.ts`.
7. Ceuta/Melilla: base+nacional, sin comunidad ficticia.
8. Uniprovinciales: duplicado marcado, no doble trofeo.
9. Provincia principal: máximo de Retos válidos.
10. Empate: conserva anterior; sin anterior, primera en alcanzar máximo.
11. Elegibilidad: 6/3, 8/4, 10/5, 12/5 y 15/6 comparadas.
12. Rival decay: tres curvas comparadas.
13. Volumen: all_saturated, recent_20, recent_25 y best_20.
14. Fórmulas: cinco candidatos principales.
15. Pesos: 13 combinaciones válidas del grid.
16. A–G: `human_profiles.csv`.
17. Defensa/goleador: goles no usados; F vs G documentado.
18. Hiperactivo: B y perfiles 10–120.
19. Newcomer: 2/5/8/10/15/25 Retos.
20. Rival fuerte: D.
21. Farmeador: E y suite repeated_opponent.
22. Simulación: 10.000 jugadores.
23. Provincial: columnas `provinceRank` y dataset completo.
24. Autonómico: `autonomousCommunityRank`.
25. España: `nationalRank`.
26. Estabilidad semanal: seis cortes.
27. Rank churn: Top10/50/100 en `weekly_churn.csv`.
28. Actividad: score conservado, elegibilidad reciente separada.
29. Sybil: incluido.
30. Equipos fantasma: incluido.
31. Collusion/win trading: incluido.
32. Rating interno inflado: incluido.
33. Opponent-strength boosting: incluido.
34. Team hopping: incluido.
35. Rival farming: incluido.
36. Fake participation: incluido.
37. Venue/province manipulation: incluido.
38. Fake matches: incluido.
39. Impossible volume/travel: incluido.
40. Smurf: incluido.
41. Sacrifice accounts: incluido.
42. Integrity risk 0–100: diagnóstico, no sanción.
43. Contaminación sin protección: `anti_abuse_results.csv`.
44. Contaminación protegida: mismo dataset.
45. False positive rate: 0% suspicious/high.
46. Casos legítimos: cinco perfiles adversariales.
47. Señales recomendadas: grafo deportivo y evidencia ya disponible.
48. Señales descartadas: GPS/fingerprint/IP como autoridad.
49. Finalistas: métricas en `ranking_formula_comparison.csv`.
50. Recomendada: `candidate_e_recent20`, experimental.
51. Elegibilidad recomendada: 15/6 + reliability.
52. Rival decay recomendado: 1/1/0.5/0.25/0.
53. Ventana/saturación: recent_20.
54. Rating reliability: factor y desbloqueo competitivo.
55. Actividad reciente: soft-gate, sin decay de score.
56. Umbral Top 10: 30 provisional / 50 reconocimiento.
57. Riesgos abiertos: participación, Places, colusión y comparabilidad.
58. No implementar: trofeos, auto-ban, GPS, rankings reales ni tablas remotas.
59. Tests: build + 125 tests PASS; 14 focalizados PASS; typecheck y lint focalizado PASS; lint global conserva deuda preexistente.
60. Archivos: 41 rutas de código, tests, config, datasets, SVG e informe.
61. Commit/PR: se registra en la entrega Git posterior a este informe reproducible.
62. Producción: no tocada.
63. Rating V2: no modificado.

## Datasets y gráficos

Los CSV de salida y los nueve SVG están en `simulation/season-ranking-lab/results/`. Se regeneran con `npm run lab:season-ranking`; no contienen PII.
