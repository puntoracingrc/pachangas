# Tournament Draw Engine V1 Report

## Estado

`LOCAL CERTIFIED / REMOTE GATES PENDING`

## Contrato del motor

| Capacidad | Implementacion |
| --- | --- |
| Algoritmo | `tournament-draw-v1.0.0` |
| PURE_RANDOM | hash determinista por seed, intento y entry |
| SEEDED_POTS | una entrada del mismo pot por grupo cuando aplica |
| CONSTRAINT_OPTIMIZED | hard/soft con mejor solucion valida |
| MANUAL_ASSISTED | place, move, swap y remove versionados |
| HYBRID | locks inmutables por revision + fill determinista |
| KNOCKOUT | seeds iniciales y byes, sin crear bracket vivo |
| Limite | 128 intentos; 4-64 participantes de producto |

## Determinismo

El motor persiste seed mode, seed, version de algoritmo, checksums de inputs y
resultado, lineage, quality snapshot y explicaciones. La misma seed con los
mismos inputs produce el mismo resultado; una seed distinta produce otra
revision valida.

El checksum semantico excluye reloj y UUID aleatorio no deportivo. Fechas e IDs
de autoridad siguen persistidos en columnas y receipts.

## Validacion y calidad

La validacion comprueba duplicados, ausencias, posiciones, tamanos de grupo,
pot distribution, same-club, nivel, constraints, locks y byes. Un caso sin
solucion devuelve `DRAW_UNSATISFIABLE` con codigo, constraints, locks y
sugerencias. No publica una revision `PENDING`, `INVALID`, `STALE` o con hard
violations.

## Rendimiento local

| Caso | p95 |
| --- | ---: |
| 8 teams pure/random | `185.467 ms` |
| 16 teams pots | `432.028 ms` |
| 32 teams constraints | `774.703 ms` |
| 64 teams | `1810.463 ms` |
| Hybrid complete | `538.747 ms` |
| Manual swap | `7.689 ms` |
| Validate | `8.233 ms` |
| Publish | `7.372 ms` |
| Organizer desk | `1.747 ms` |
| Audit | `0.406 ms` |

Se midieron 260 muestras. La prueba de escala usa rollback completo y deja
cero Tournament matches.

## Casos cubiertos

- 4, 8, 12, 16, 24, 32 y 64 participantes;
- grupos pares e impares;
- 14 participantes en 16 slots con dos byes;
- misma seed, seed distinta y lineage;
- same-club hard avoid y caso imposible;
- inputs stale tras retirada;
- publicacion simultanea `1 winner / 1 stale`;
- resultados y placements falsificados rechazados;
- edicion de sorteo publicado rechazada.

## Limite de producto

Publicar solo materializa grupos o seeds iniciales. R6A contiene un trigger que
rechaza cualquier `CanonicalMatch` asociado al producto Tournament. Match
generation, progresion, resultados, standings, pagos y premios siguen OFF.
