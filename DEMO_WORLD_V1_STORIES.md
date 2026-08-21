# Demo World V1 Stories

Las doce historias se generan desde entidades canonicas del snapshot. No son textos independientes: cada una conserva IDs resolubles y una fecha estable dentro de la temporada Demo 2026/27.

## Story 01 - Un 3-0 abrió el mapa de rivales

- Equipo: Cobalto Raval y Brúixola Sants.
- Partido: `demo_match_076`, finalizado 3-0 el 12 de marzo de 2027.
- Jugador: Bruno Quer, `demo_player_006`, marco los tres goles.
- Funcion que ensena: Reto completado, resultado, hat-trick y primera porteria a cero.

## Story 02 - Cobre para la primera victoria

- Equipo: Cobalto Raval.
- Evidencia: `demo_achievement_team_001`, primera victoria confirmada dentro de cinco victorias externas.
- Recompensa: borde Cobre mediante el mapping productivo `team.external.wins.001`.
- Funcion que ensena: logro de equipo, evidencia y recompensa cosmetica.

## Story 03 - Una plantilla que ya tiene memoria

- Equipo: Cobalto Raval.
- Evidencia: 60 partidos finalizados, 10 Retos y una plantilla de 11 jugadores.
- Funcion que ensena: identidad de equipo, estadisticas acumuladas, ranking y escudo evolucionado.

## Story 04 - La contrapropuesta evitó cancelar

- Equipos: Vértice Gràcia y Brúixola Sants.
- Reto: `demo_challenge_001`, estado `countered`, sin partido canonico prematuro.
- Funcion que ensena: contrapropuesta de fecha/modalidad y flujo de Retos pendiente de acuerdo.

## Story 05 - Un mediocentro busca grupo

- Jugador: Nico Valira, `demo_player_331`.
- Perfil: agente libre, mediocentro, fútbol sala/fútbol 7, zona pública Barcelona/Vallès.
- Funcion que ensena: Mercado de jugadores, carta Rating V2 y privacidad sin datos de contacto.

## Story 06 - Confirmo y estuvo en el campo

- Evidencia: `demo_attendance_005` enlaza `demo_player_006` con `demo_match_076` como `played`.
- Funcion que ensena: diferencia entre asistencia real, baja justificada, cancelacion tardia y no-show.

## Story 07 - Girona entra en la red

- Equipo: Riu Girona.
- Evidencia: tres Retos ganados, una porteria a cero y ranking Demo provincial.
- Funcion que ensena: red territorial, rivales conocidos y progresion de escudo fuera de Barcelona.

## Story 08 - Los laureles exigen evidencia

- Equipo: Cobalto Raval.
- Evidencia: `demo_achievement_team_003` registra 60 partidos finalizados.
- Recompensa: Laureles mediante el mapping productivo `team.matches.025`.
- Funcion que ensena: logro acumulativo y pieza visual respaldada por historial.

## Story 09 - Un rechazo no rompe la agenda

- Equipos: Marina Fosca y Volcà Olot.
- Reto: `demo_challenge_004`, estado `rejected`, sin partido canonico.
- Funcion que ensena: historial de propuesta rechazada y continuidad del Mercado de rivales.

## Story 10 - Partidos publicos con contexto

- Equipos: Ferro Sant Andreu y Premià Set.
- Partido: `demo_match_126`, programado para el 30 de marzo de 2027.
- Estado: modalidad futbol 7, zona publica, nueve confirmados, dos reservas y tres plazas.
- Funcion que ensena: Mercado de partidos con contexto antes de una solicitud simulada.

## Story 11 - Tres goles, una caja y una pieza nueva

- Jugador: Bruno Quer, `demo_player_006`.
- Evidencia: `demo_achievement_player_001` nace del hat-trick de `demo_match_076` y sella `demo_reward_box_001`.
- Recompensa: `player.frame.barrio.copper`.
- Funcion que ensena: abrir caja 3D bajo demanda, guardar en inventario, distintivo NEW y equipar localmente.

## Story 12 - El #27 ya tiene contexto

- Jugador: Bruno Quer, `demo_player_006`.
- Ranking: `demo_ranking_entry_27` representa su read model publico en la posicion 27.
- Funcion que ensena: Ranking Provincial Season Score V3, elegibilidad, revision publicada y premios desactivados.

## Cobertura conjunta

El recorrido de las historias permite descubrir equipo, carta, partido, asistencia, alineacion, marcador, goleadores, Retos, Mercado, Ranking Provincial, logros, cajas, inventario, escudos y cosmeticos sin tutorial lineal ni datos productivos.
