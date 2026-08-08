# Simulación económica de recompensas V1.1

## Método

Simulación determinista de 400 temporadas por escenario, con:

- 1, 2 o 4 Retos por semana.
- 3, 6 o 12 meses.
- 50%, 70% u 85% de victorias.
- Goles Poisson ajustados por fortaleza y marcador reconciliado con victoria, empate o derrota.
- Cajas por victoria, goles, portería a cero, goleada, partido ajustado, Dominio absoluto y trayectoria.
- Primera ocurrencia con subida de rareza.
- Mismo catálogo de puntos y probabilidad cosmética que la economía V1.

La simulación informa, no modifica las reglas.

## Comparación

| Modelo | Media mínima | Media máxima |
| --- | ---: | ---: |
| V1 anterior | 1,76 cajas/partido | 2,75 cajas/partido |
| V1.1 | 1,80 cajas/partido | 2,92 cajas/partido |

El incremento máximo de 0,17 cajas por partido se concentra en equipos con muchos goles y victorias, debido a los componentes múltiples y Dominio absoluto. No se observa una explosión rutinaria: el p95 permanece entre 3 y 5 cajas.

## Escenarios V1.1

| Semana | Meses | Victorias | Media | p50 | p90 | p95 | Máx. | Puntos/año | Cosméticos | Duplicados |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 3 | 50% | 1,93 | 2 | 3 | 4 | 6 | 819 | 5,78 | 2,31 |
| 1 | 3 | 70% | 2,58 | 3 | 4 | 4 | 7 | 1.083 | 6,99 | 3,93 |
| 1 | 3 | 85% | 2,92 | 3 | 4 | 5 | 7 | 1.239 | 7,59 | 4,82 |
| 1 | 6 | 50% | 1,88 | 2 | 3 | 4 | 6 | 754 | 8,32 | 7,91 |
| 1 | 6 | 70% | 2,42 | 3 | 4 | 4 | 7 | 965 | 9,27 | 11,16 |
| 1 | 6 | 85% | 2,83 | 3 | 4 | 5 | 7 | 1.135 | 9,97 | 14,22 |
| 1 | 12 | 50% | 1,84 | 2 | 3 | 4 | 6 | 701 | 10,07 | 20,40 |
| 1 | 12 | 70% | 2,34 | 3 | 3 | 4 | 7 | 891 | 10,89 | 28,13 |
| 1 | 12 | 85% | 2,72 | 3 | 4 | 5 | 7 | 1.039 | 11,26 | 33,68 |
| 2 | 3 | 50% | 1,95 | 2 | 4 | 4 | 7 | 1.571 | 8,47 | 8,17 |
| 2 | 3 | 70% | 2,45 | 3 | 4 | 4 | 8 | 1.959 | 9,33 | 11,39 |
| 2 | 3 | 85% | 2,83 | 3 | 4 | 5 | 8 | 2.279 | 9,87 | 14,06 |
| 2 | 6 | 50% | 1,86 | 2 | 3 | 4 | 7 | 1.422 | 10,15 | 21,03 |
| 2 | 6 | 70% | 2,38 | 3 | 4 | 4 | 7 | 1.815 | 10,78 | 29,14 |
| 2 | 6 | 85% | 2,75 | 3 | 4 | 5 | 7 | 2.110 | 11,37 | 34,60 |
| 2 | 12 | 50% | 1,82 | 2 | 3 | 3 | 7 | 1.342 | 11,61 | 48,84 |
| 2 | 12 | 70% | 2,32 | 3 | 3 | 4 | 7 | 1.713 | 12,24 | 65,04 |
| 2 | 12 | 85% | 2,71 | 3 | 4 | 5 | 8 | 2.018 | 12,77 | 77,46 |
| 4 | 3 | 50% | 1,88 | 2 | 3 | 4 | 7 | 2.865 | 10,11 | 21,11 |
| 4 | 3 | 70% | 2,38 | 3 | 4 | 4 | 7 | 3.638 | 11,05 | 29,16 |
| 4 | 3 | 85% | 2,75 | 3 | 4 | 5 | 7 | 4.221 | 11,36 | 35,22 |
| 4 | 6 | 50% | 1,84 | 2 | 3 | 4 | 6 | 2.718 | 11,60 | 49,27 |
| 4 | 6 | 70% | 2,34 | 3 | 3 | 4 | 7 | 3.463 | 12,34 | 65,29 |
| 4 | 6 | 85% | 2,71 | 3 | 4 | 5 | 7 | 4.035 | 12,63 | 77,50 |
| 4 | 12 | 50% | 1,80 | 2 | 3 | 3 | 7 | 2.567 | 12,53 | 106,27 |
| 4 | 12 | 70% | 2,30 | 3 | 3 | 4 | 7 | 3.310 | 13,07 | 140,44 |
| 4 | 12 | 85% | 2,69 | 3 | 3 | 5 | 7 | 3.907 | 13,39 | 165,40 |

## Lectura de riesgo

- Las cajas por partido permanecen en un rango controlado, incluso sin límite artificial.
- El riesgo económico real está en los duplicados a largo plazo, no en el número puntual de cajas.
- Con cuatro partidos semanales, el catálogo cosmético pequeño satura y crecen las conversiones a puntos.
- Antes de introducir compras o ventajas, conviene ampliar cosméticos o crear sumideros exclusivamente estéticos. No debe tocarse Rating V2.
