# Pachangas IQ: catálogo V1.1 de logros colectivos

## Alcance

V1.1 conserva las 45 definiciones individuales de `achievement_catalog_v2` y sustituye únicamente las 56 definiciones colectivas V2 por 60 definiciones colectivas `achievement_catalog_v3`.

Estado activo resultante:

- 45 logros individuales V2, reconocimiento sin cajas.
- 60 logros colectivos V3, con cajas por participante canónico.
- 105 escalones activos en total.
- Rating V2 no recibe ninguna escritura ni usa rareza como entrada.

## Migración del catálogo

| Clasificación | Tratamiento |
| --- | --- |
| KEEP | Los logros individuales V2 permanecen activos e intactos. Dominio absoluto nace en V3. |
| MIGRATE | Victorias, goles colectivos, porterías a cero, goleadas, partidos ajustados, rachas y rivales pasan a definiciones colectivas V3. |
| DEPRECATE | `team.internal.matches.*` y `team.external.matches.*` quedan inactivos. Sus grants y cajas históricas se conservan. |

La activación usa `activation_server_sequence`. El backfill crea únicamente el read model global `team.matches`; no evalúa logros ni concede cajas por partidos antiguos.

## Trayectoria global

`team.matches` suma Pachangas internas y Retos canónicos.

| Partidos | Rareza |
| ---: | --- |
| 1 | common |
| 5 | uncommon |
| 10 | uncommon |
| 25 | rare |
| 50 | rare |
| 100 | epic |
| 250 | epic |
| 500 | legendary |

Los read models `internal` y `external` se conservan. En la interfaz, `external` se presenta como **Retos**.

## Retos

- Cada Reto ganado concede el logro repetible Victoria y una caja por participante.
- La primera victoria se presenta como **Primera conquista** mediante la subida de rareza ya existente.
- Goleada requiere victoria y diferencia de al menos cuatro goles.
- Portería a cero requiere cero goles rivales e incluye el 0-0.
- **Dominio absoluto** requiere victoria en Reto, diferencia de al menos cuatro y cero goles rivales. Es adicional y su rareza base es `rare`.

Un 4-0 puede conceder a la vez Victoria, Póker, Goleada, Portería a cero y Dominio absoluto, además de hitos acumulativos legítimos.

## Recompensas por goles colectivos

Una ocurrencia de logro colectivo contiene una lista ordenada `reward_components`. Cada componente crea una caja independiente por participante.

| Goles | Presentación | Componentes por participante |
| ---: | --- | --- |
| 1 | Sin logro de goles | Ninguno |
| 2 | Doblete | Doblete x1 |
| 3 | Hat-trick | Hat-trick x1 |
| 4 | Póker | Póker x1 |
| 5 | Manita | Manita x1 |
| 6 | Doble hat-trick | Hat-trick x2 |
| 7 | 7 goles | Manita x1 + Doblete x1 |
| 8 | Doble póker | Póker x2 |
| 9 | Triple hat-trick | Hat-trick x3 |
| 10 | Doble manita | Manita x2 |
| 11 | 11 goles | Manita x1 + Hat-trick x2 |
| 12 | 12 goles | Manita x2 + Doblete x1 |
| 13 | 13 goles | Manita x2 + Hat-trick x1 |
| 14 | 14 goles | Manita x2 + Póker x1 |
| 15 | 15 goles | Manita x3 |
| 16 | 16 goles | Manita x2 + Hat-trick x2 |
| 17 | 17 goles | Manita x3 + Doblete x1 |
| 18 | 18 goles | Manita x2 + Póker x2 |
| 19 | 19 goles | Manita x2 + Hat-trick x3 |
| 20 | 20 goles | Manita x4 |

Para cifras superiores se consumen bloques de diez. Si quedaría resto uno, se transforma un bloque once en `5 + 3 + 3`. La suma de `component.goals` siempre coincide exactamente con el marcador.

Rareza base de componentes:

- Doblete: `common`.
- Hat-trick: `uncommon`.
- Póker: `uncommon`.
- Manita: `rare`.

La primera ocurrencia del escalón conserva la subida de una rareza. No existe `max_boxes_per_match`.

## Idempotencia

La identidad de una caja colectiva es:

```text
achievement_grant_id + user_id + component_index
```

El índice empieza en cero y mantiene el orden. Repetir la evaluación o ejecutar dos evaluadores concurrentes devuelve cero nuevas concesiones después del ganador y no duplica cajas.

## Rachas y rivales

Las rachas de equipo usan exclusivamente la cronología de Retos:

- Victorias consecutivas: 3, 5, 10 y 15.
- Retos invicto: 3, 5, 10 y 20.

Una Pachanga interna no prolonga, rompe ni modifica esas rachas.

Rivales distintos en Retos:

- Enfrentados: 3, 5, 10, 25, 50 y 100.
- Vencidos: 3, 5, 10, 25 y 50.

Cada `opponent_group_id` cuenta una sola vez por familia.

## Legendary

En V3 colectivo, `legendary` queda reservado a:

- 500 partidos globales.
- 250 victorias en Retos.
- 15 victorias consecutivas en Retos.
- 20 Retos consecutivos sin perder.
- 50 rivales distintos vencidos.

Los componentes por goles y Dominio absoluto no son `legendary`.
