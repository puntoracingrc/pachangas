# TOPS V1 - Territory Award Readiness y piloto provincial

## Decisión

Season Score queda congelado en **55% Calidad, 30% Competición y 15% Oposición**, con ventana `recent_30`. La elegibilidad de ranking permanece en 15 evidencias, 6 rivales lógicos, fiabilidad >= 0,45 y actividad <= 12 semanas. El baseline individual de premio permanece en 25 Retos, 10 rivales, confianza >= 0,72, fiabilidad >= 0,55 y actividad reciente.

`territory_award_readiness` no modifica puntos ni aplica multiplicadores territoriales. Responde una pregunta distinta de la certificación individual: si el ecosistema provincial ofrece evidencia suficiente para habilitar premios.

## Estados

- `ranking_inactive`: no alcanza el mínimo para mostrar una tabla significativa.
- `ranking_active`: la clasificación puede mostrarse, pero todavía no existe una población Top 10 completa.
- `trophy_not_ready`: hay Top 10 visible, pero el territorio no puede certificar premios.
- `trophy_ready`: la madurez territorial permite pasar después a la decisión individual de integridad.

## Señales y razones

El snapshot conserva equipos y jugadores activos, población rankeada, candidatos 25/10 sin usar la decisión antifraude individual, Retos válidos, aristas técnicas, aristas lógicas independientes, cobertura de equipos conectados, medianas de Retos/rivales/confianza e historia observada. Los códigos públicos son: `insufficient_active_teams`, `insufficient_ranking_population`, `insufficient_award_candidates`, `insufficient_independent_competition`, `insufficient_valid_challenges`, `insufficient_history` y `ready`.

No se expone en la UI pública ningún motivo antifraude. La telemetría agregada no contiene nombres, correos, IDs de usuario ni coordenadas.

## Hysteresis e historial

Cada snapshot tiene `calculatedAt`, revisión monotónica, estado observado, estado confirmado, razones y señales. `trophy_ready` exige tres ventanas consecutivas; las demás promociones, dos. Una degradación exige tres ventanas bajas. Los premios históricos ya concedidos no se eliminan. En el cierre se congela el ranking, se fija readiness, se reconcilia integridad y solo después se certifican reconocimientos.

## Flags y scopes

- `provincial_rankings_enabled=true`.
- `provincial_awards_enabled=false` en el piloto.
- Comunidad autónoma: LAB ONLY.
- España: LAB ONLY.
- Rankings ON / awards OFF es un estado soportado y probado.

## Crecimiento territorial sano

| Equipos | Ranking | Candidatos 25/10 | Retos | Aristas independientes | Observado | Confirmado |
| --- | --- | --- | --- | --- | --- | --- |
| 10 | 10 | 0 | 300 | 45 | trophy_not_ready | trophy_not_ready |
| 20 | 20 | 20 | 600 | 141 | trophy_ready | trophy_not_ready |
| 30 | 30 | 30 | 900 | 214 | trophy_ready | trophy_not_ready |
| 50 | 50 | 50 | 1500 | 363 | trophy_ready | trophy_ready |
| 75 | 75 | 75 | 2250 | 547 | trophy_ready | trophy_ready |
| 100 | 100 | 100 | 3000 | 724 | trophy_ready | trophy_ready |
| 150 | 150 | 150 | 4500 | 1111 | trophy_ready | trophy_ready |

Con 10 equipos el ranking puede existir, pero el territorio queda `trophy_not_ready`: solo hay nueve rivales posibles y no se rebaja 25/10. La red sana alcanza `trophy_ready` después de tres ventanas maduras; no queda bloqueada por el `externalNetworkRatio` absoluto.

## Red manipulada

El escenario manipulado puede alcanzar madurez territorial cuando tiene volumen y conexiones observables. Eso no certifica a sus jugadores: cada candidato sigue pasando después por V3 e integridad individual. `TERRITORY READY?` y `PLAYER TRUSTWORTHY?` permanecen separados.

## Synthetic World original

- Mundo: `3df9494d-3b8c-4447-96e8-d5244892af78`.
- Revisión: 313.
- Secuencia: 69458.
- SHA-256 antes/después: `5b1d72085eb81cab92fb89bdd547e6020771868044172ac0b548d3903c2f66b1` / `5b1d72085eb81cab92fb89bdd547e6020771868044172ac0b548d3903c2f66b1`.

| Código | Provincia | Equipos | Ranking | Candidatos | Readiness |
| --- | --- | --- | --- | --- | --- |
| 08 | Barcelona | 14 | 44 | 8 | trophy_not_ready |
| 15 | A Coruña | 3 | 7 | 2 | ranking_inactive |
| 17 | Girona | 4 | 7 | 1 | ranking_inactive |
| 28 | Madrid | 15 | 52 | 5 | trophy_not_ready |
| 41 | Sevilla | 4 | 11 | 1 | ranking_inactive |
| 46 | Valencia/València | 7 | 11 | 0 | trophy_not_ready |
| 50 | Zaragoza | 3 | 1 | 0 | ranking_inactive |

El mundo original no se guarda ni se modifica; TOPS V1 solo genera read models y telemetría agregada.

## Cierre y política #11

Fases: `season_active` -> `season_frozen` -> `territory_readiness_final` -> `integrity_reconciliation` -> `award_certification` -> `season_closed`. Si el territorio no está preparado, la clasificación se archiva sin trofeo. Si está preparado y awards está activo, un jugador limpio puede recibir premio y uno pendiente conserva su trofeo pendiente. El #11 nunca asciende automáticamente por un #8 pendiente.

## Producto

La UI piloto provincial muestra posición viva, Season Score, movimiento, Retos válidos y rivales. Un no elegible solo ve cuántos Retos y rivales le faltan. `live_position` no equivale a `season_award`. M3 permanece `experimental_reference`; V3, Rating V2, GRL, facetas y assessments no cambian.
