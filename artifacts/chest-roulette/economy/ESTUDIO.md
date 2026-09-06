# Precio fijo de la ruleta de premios

Fecha: 6 de septiembre de 2026. Estudio local de diseño; no cambia precios, saldos, probabilidades ni configuración del servidor.

**Actualización posterior del usuario:** semanal acumulable por actividad en los últimos 30 días, una gratuita por test inicial y otra por test avanzado. El escenario actualizado y las reglas están en [REGLAS-GRATUITAS.md](REGLAS-GRATUITAS.md); sustituye la recomendación inicial de limitar las gratuitas a bienvenida. Las tablas base siguientes siguen siendo la comparación sin gratuitas.

## Decisión propuesta

**15 puntos por tirada para todos**, con las mismas probabilidades y tabla de premios para todos. El inventario solo determina si un cosmético se incorpora o se convierte en puntos; nunca altera el precio ni las probabilidades. Es una recomendación para la primera versión, pendiente de contrastar con actividad real, no un precio acordado en el estudio original.

10 puntos permite demasiada reinversión al completar la colección. 20 consume más saldo y reduce bastante la frecuencia de uso para quien empieza. 15 ofrece un punto intermedio. Mantener cualquier ajuste futuro global y transparente; no aplicar precios personalizados por colección.

## Fuentes y método

- Pesos, rangos enteros de puntos y conversiones de duplicados extraídos automáticamente de `supabase/migrations/20260808175354_reward_economy_v1.sql`.
- Cosméticos actualizados mediante `supabase/migrations/20260810040115_player_cosmetics_v1.sql`: 14 cosméticos personales en estos pools.
- Probabilidades de la ruleta actual: común 60%, poco común 25%, raro 10%, épico 4%, legendario 1%. Son una elección del prototipo; el estudio anterior no fijaba una ruleta.
- Apertura: sortear una entrada por su peso, sortear puntos dentro de su intervalo, entregar el cosmético o convertirlo si ya existe. Los premios combinados mantienen sus puntos base y añaden la conversión si son repetidos.
- No se usa la tabla de premios simplificada del prototipo: difiere del catálogo del proyecto.
- Comparación de temporadas basada en las hipótesis de partidos de `tests/reward-economy-v1-1-simulation.test.ts`, con sorteos de premios corregidos y aleatoriedad separada para partidos y premios. Es una aproximación del ritmo de juego, no una ejecución del motor SQL de logros ni telemetría de usuarios.
- La simulación anterior sumaba la media de puntos de cada rareza a todos los cofres y contaba duplicados sin convertirlos. Sus cifras anuales no bastan para fijar este precio.

## Resultado matemático por tirada

| Precio fijo | Consumo neto medio sin repetidos | Consumo neto medio con colección completa |
| --- | ---: | ---: |
| 10 | 3,74 puntos | 0,95 puntos |
| 15 | 8,74 puntos | 5,95 puntos |
| 20 | 13,74 puntos | 10,95 puntos |

La devolución media es 6,25725 puntos sin repetidos y 9,04625 con todos los cosméticos obtenidos. “Sin repetidos” es el extremo matemático de una apertura: una colección que comienza vacía va acumulando cosméticos y deja de estar en ese extremo.

Con 10 puntos, la devolución al completar la colección es un 90,46% del coste. No genera puntos ilimitados en promedio, pero deja muy poco consumo de saldo y mucha variabilidad. Con 15 devuelve el 60,31%; con 20, el 45,23%. Estos porcentajes son exclusivamente de puntos: no asignan un valor monetario ni en puntos a los cosméticos nuevos.

## Cuánto duran 100 puntos

2.000 simulaciones por combinación, abriendo cada premio y reinvirtiendo hasta no poder pagar otra tirada. Sin ingresos por partidos ni tiradas gratuitas. La colección inicialmente vacía crece durante cada sesión.

| Precio fijo | Tiradas medias empezando sin cosméticos | Tiradas medias con colección completa | p95 con colección completa |
| --- | ---: | ---: | ---: |
| 10 | 32,52 | 98,28 | 245 |
| 15 | 10,82 | 15,21 | 25 |
| 20 | 6,51 | 7,98 | 12 |

p95 indica el percentil 95, no el máximo. La mediana con colección completa es 73, 14 y 7 tiradas respectivamente. El promedio de 98,28 a precio 10 está elevado por sesiones largas afortunadas. Guardar cofres para abrir después aplaza el retorno de puntos, pero no corrige este equilibrio si finalmente se abren y se reinvierten.

## Ritmo semanal simulado

32.400 temporadas de un año: 400 por combinación de precio (10/15/20), actividad (1/2/4 partidos semanales), victorias (50/70/85%) y colección inicial (vacía/mitad/completa). Todas las cifras son medias de giros semanales, incluyendo reinversión.

| Partidos/semana | Victorias | Precio 10: vacía / completa | Precio 15: vacía / completa | Precio 20: vacía / completa |
| --- | --- | --- | --- | --- |
| 1 | 50% | 10,47 / 13,68 | 1,9 / 2,17 | 1,07 / 1,17 |
| 1 | 70% | 14,13 / 17,48 | 2,51 / 2,81 | 1,4 / 1,51 |
| 1 | 85% | 17,18 / 20,58 | 3,0 / 3,3 | 1,66 / 1,78 |
| 2 | 50% | 23,11 / 26,68 | 3,92 / 4,29 | 2,16 / 2,31 |
| 2 | 70% | 30,86 / 34,2 | 5,13 / 5,52 | 2,83 / 2,99 |
| 2 | 85% | 36,92 / 40,51 | 6,1 / 6,5 | 3,36 / 3,53 |
| 4 | 50% | 48,16 / 51,71 | 7,85 / 8,3 | 4,31 / 4,51 |
| 4 | 70% | 63,16 / 66,39 | 10,26 / 10,73 | 5,61 / 5,83 |
| 4 | 85% | 75,57 / 78,85 | 12,24 / 12,7 | 6,69 / 6,91 |

Con 15 puntos y un partido semanal al 50% de victorias, el jugador que empieza obtiene 1,90 tiradas semanales de media, mediana 2 y p95 6; el veterano con colección completa, 2,17 de media, mediana 2 y p95 7. Hay semanas sin tiradas (27,8% y 26,8%): no se garantiza una tirada en cada semana ni después de cada partido.

La economía devuelve más puntos al veterano mediante duplicados, pero a precio 15 esa diferencia es moderada. A precio 10 la reinversión amplifica mucho esa ventaja. La hipótesis de 85% de victorias representa equipos muy dominantes; no es la media de toda la comunidad.

## Gratis, rareza y colección

- Una tirada de bienvenida única tiene un impacto acotado por jugador. Una tirada semanal introduce un flujo permanente que hay que incluir por separado; no estaba definido en el plan original.
- Con colección completa, una tirada gratuita semanal aporta en promedio 9,05 puntos. A largo plazo eso permite aproximadamente 9,48 tiradas pagadas adicionales si el precio es 10; 1,52 si es 15; 0,83 si es 20. Son promedios marginales de reinversión, sin contar la propia gratuita ni garantizar que el saldo alcance inmediatamente otra tirada.
- Recomendación inicial: si se incluye bienvenida, que sea una sola, registrada por el servidor. No introducir una gratuita periódica sin incorporar su coste al modelo.
- Un cofre legendario tiene un 1% de probabilidad; que contenga cosmético es el 50% de ese 1%: un cosmético legendario sale en el 0,5% de los giros, antes de considerar duplicados. Media de 200 giros, sin garantía ni límite máximo. La probabilidad de al menos uno en 100 giros es aproximadamente 39,4%.
- Ampliar el catálogo cambia el retorno de puntos al reducir duplicados. Se debe recalcular el estudio cuando cambien pools, compensaciones, frecuencia de premios o tiradas gratuitas.

## Alcance y validación

Los pesos suman 100 por pool y cada entrada cosmética resuelve una clave del catálogo. Se verifica conservación de saldo en cada temporada. Dos muestras independientes de 200.000 aperturas contrastan las medias analíticas con tolerancia de 0,08 puntos.

Los escenarios anuales comienzan con saldo cero, sin tiradas gratuitas, sin compras cosméticas alternativas y reinvierten todo el saldo semanalmente. Esto representa uso intensivo voluntario, no el comportamiento esperado de todos los jugadores. Se comparan colección vacía, mitad aleatoria y completa; la completa aproxima un equipo veterano sin bonificaciones iniciales de familias, aunque mantiene hitos de trayectoria del modelo antiguo. Un jugador puede pertenecer a más de un equipo o reservar puntos: no está modelado.

La autoridad de producción sigue pendiente de conectar. Este estudio utiliza las migraciones del proyecto, no una auditoría del catálogo activo de producción. No se han modificado datos reales ni se ha publicado nada. El worktree se conserva porque contiene la implementación de ruleta aún pendiente de integración y publicación.

Reproducir desde el repositorio:

```sh
python3 artifacts/chest-roulette/economy/study.py
python3 artifacts/chest-roulette/economy/budget.py
```

Resultados completos en `results.json` y `budget-100.json`; código y semillas junto a este documento.
