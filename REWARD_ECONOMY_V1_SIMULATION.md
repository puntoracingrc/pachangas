# Simulación de economía de recompensas V1

## Alcance

La simulación usa el catálogo conservador V1 y una semilla fija. Modela cajas por goles colectivos, victoria, portería a cero, goleada, victoria ajustada y los principales hitos acumulativos. No modela compras, dinero real, transferencias, rachas ni todos los hitos de rivales, por lo que sirve para detectar inflación evidente, no para predecir el comportamiento real.

Los perfiles son:

- Casual: 1 partido por semana.
- Activo: 2 partidos por semana.
- Muy activo: 4 partidos por semana.

## Resultados

| Perfil | Periodo | Partidos | Cajas | Puntos | Comunes | Poco comunes | Raras | Épicas | Legendarias | Cosméticos únicos | Duplicados |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Casual | 3 meses | 13 | 30 | 210 | 17 | 9 | 4 | 0 | 0 | 4 | 3 |
| Casual | 6 meses | 26 | 56 | 487 | 24 | 18 | 6 | 8 | 0 | 7 | 9 |
| Casual | 12 meses | 52 | 94 | 1.053 | 44 | 24 | 8 | 17 | 1 | 10 | 30 |
| Activo | 3 meses | 26 | 56 | 460 | 34 | 10 | 6 | 6 | 0 | 7 | 12 |
| Activo | 6 meses | 52 | 103 | 953 | 49 | 29 | 9 | 15 | 1 | 11 | 26 |
| Activo | 12 meses | 104 | 203 | 1.869 | 109 | 53 | 16 | 23 | 2 | 12 | 54 |
| Muy activo | 3 meses | 52 | 111 | 1.251 | 56 | 30 | 11 | 6 | 8 | 9 | 28 |
| Muy activo | 6 meses | 104 | 223 | 2.585 | 106 | 56 | 12 | 43 | 6 | 11 | 57 |
| Muy activo | 12 meses | 208 | 347 | 3.181 | 196 | 87 | 38 | 23 | 3 | 12 | 95 |

No aparece un crecimiento explosivo: incluso el perfil muy activo queda en 347 cajas y 3.181 puntos al año. La adquisición del pequeño catálogo V1 se completa con actividad alta, tras lo cual aumenta la conversión de duplicados; será la señal principal que habrá que recalibrar con datos reales antes de fijar precios o ampliar pools.

## Umbrales V1

- Menos de 700 cajas por año para el perfil de 4 partidos semanales.
- Menos de 10.000 `player_points` anuales para ese mismo perfil.
- Como máximo los 12 cosméticos V1 distintos.
- Los duplicados siempre se convierten a puntos y nunca crean copias acumulables.

Estos umbrales son alarmas técnicas, no precios futuros. La tienda y el coste de los cosméticos quedan fuera de V1.
