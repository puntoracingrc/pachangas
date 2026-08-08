# Catálogo definitivo V1 de logros y cajas

Generado desde la migración `20260808185802_achievement_catalog_v2.sql`. La versión funcional V1 se almacena como `achievement_catalog_v2` para no cambiar el significado del catálogo ya desplegado.

## Decisiones cerradas

- 101 escalones activos agrupados en 22 familias: 45 individuales y 56 colectivos.
- El mérito individual no genera caja, puntos ni cosméticos.
- Cada logro colectivo genera una caja independiente por participante canónico.
- Solo cuentan hechos `confirmed` o `auto_confirmed`; goles no asignados nunca crean mérito individual.
- En goles por partido solo se concede el escalón máximo aplicable.
- Portería a cero incluye 0-0. Goleada conserva la regla desplegada de diferencia mínima de 4.
- La victoria externa normal mantiene su caja repetible; su impacto está medido en `REWARD_ECONOMY_V1_SIMULATION.md`.
- La secuencia de activación evita cajas retroactivas; el historial antiguo se conserva sin borrar concesiones.
- Rating V2 permanece independiente.

## Familias activas

| Familia | Sujeto | Ámbito | Escalones | Umbrales | Repetible |
| --- | --- | --- | ---: | --- | --- |
| player.matches | player | all | 8 | 1, 5, 10, 25, 50, 100, 250, 500 | no |
| team.external.matches | team | external | 8 | 1, 5, 10, 25, 50, 100, 250, 500 | no |
| team.internal.matches | team | internal | 8 | 1, 5, 10, 25, 50, 100, 250, 500 | no |
| player.wins | player | all | 7 | 1, 5, 10, 25, 50, 100, 250 | no |
| team.external.wins | team | external | 7 | 1, 5, 10, 25, 50, 100, 250 | yes |
| player.match_goals | player | all | 5 | 1, 1, 1, 1, 1 | yes |
| team.external.match_goals | team | external | 5 | 2, 3, 4, 5, 6 | yes |
| team.internal.match_goals | team | internal | 5 | 2, 3, 4, 5, 6 | yes |
| player.goals | player | all | 7 | 1, 10, 25, 50, 100, 250, 500 | no |
| team.external.clean_sheets | team | external | 1 | 1 | yes |
| team.external.big_wins | team | external | 1 | 1 | yes |
| team.external.close_wins | team | external | 1 | 1 | yes |
| team.internal.big_wins | team | internal | 1 | 1 | yes |
| team.internal.close_wins | team | internal | 1 | 1 | yes |
| player.win_streak | player | all | 4 | 3, 5, 10, 15 | no |
| team.external.win_streak | team | external | 4 | 3, 5, 10, 15 | no |
| player.unbeaten | player | all | 4 | 3, 5, 10, 20 | no |
| team.external.unbeaten | team | external | 4 | 3, 5, 10, 20 | no |
| player.opponents_played | player | external | 5 | 3, 5, 10, 25, 50 | no |
| team.external.opponents_played | team | external | 5 | 3, 5, 10, 25, 50 | no |
| player.opponents_won | player | external | 5 | 3, 5, 10, 25, 50 | no |
| team.external.opponents_won | team | external | 5 | 3, 5, 10, 25, 50 | no |

## Clasificación del catálogo anterior

Todas las filas antiguas permanecen para trazabilidad y quedan inactivas. `MIGRATE` significa que su capacidad compatible vive en V2; `DEPRECATE` significa que no continúa como logro activo. No se borran grants históricos.

| Achievement key anterior | Sujeto | Ámbito | Clasificación | Nota |
| --- | --- | --- | --- | --- |
| team.external.goals.025 | team | external | DEPRECATE | Retained for history; inactive without replacement semantics. |
| team.internal.goals.025 | team | internal | DEPRECATE | Retained for history; inactive without replacement semantics. |
| team.internal.goals.100 | team | internal | DEPRECATE | Retained for history; inactive without replacement semantics. |
| team.internal.scoreless.001 | team | internal | DEPRECATE | Retained for history; inactive without replacement semantics. |
| player.external.braces.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.double_hat_tricks.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.goals.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.goals.010 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.hat_tricks.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.matches.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.pokers.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.repokers.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.external.wins.001 | player | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.braces.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.double_hat_tricks.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.goals.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.goals.010 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.hat_tricks.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.matches.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.matches.005 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.matches.025 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.pokers.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.repokers.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| player.internal.wins.001 | player | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.big_wins.001 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.big_wins.005 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.clean_sheets.001 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.clean_sheets.005 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.close_wins.001 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.match_goals.002 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.match_goals.003 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.match_goals.004 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.match_goals.005 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.match_goals.006 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.matches.001 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.matches.005 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.matches.010 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.matches.025 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.opponents.003 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.opponents.010 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.unbeaten.005 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.unbeaten.010 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.win_streak.003 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.win_streak.005 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.wins.001 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.wins.005 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.wins.010 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.external.wins.025 | team | external | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.big_wins.001 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.close_wins.001 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.match_goals.002 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.match_goals.003 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.match_goals.004 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.match_goals.005 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.match_goals.006 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.matches.001 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.matches.005 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.matches.010 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.matches.025 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |
| team.internal.matches.050 | team | internal | MIGRATE | Historical row preserved; active meaning migrated to catalog V2. |

## Tabla funcional final

| achievement_key | nombre | scope | family | condition | threshold | unique/repeatable | collective/individual | reward_box | base_rarity | display_priority | match_type | active | notes |
| --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | ---: | --- | --- | --- |
| player.all.matches.001 | Primeros minutos | all | player.matches | player_appearances >= 1 | 1 | unique | individual | none | common | 11 | all | yes | MIGRATE |
| team.external.matches.001 | Primer partido | external | team.external.matches | team_matches >= 1 | 1 | unique | collective | common / pool v1 | common | 11 | external | yes | MIGRATE |
| team.internal.matches.001 | Primer partido | internal | team.internal.matches | team_matches >= 1 | 1 | unique | collective | common / pool v1 | common | 11 | internal | yes | MIGRATE |
| player.all.matches.100 | Centenario | all | player.matches | player_appearances >= 100 | 100 | unique | individual | none | rare | 110 | all | yes | MIGRATE |
| team.external.matches.100 | Cien partidos | external | team.external.matches | team_matches >= 100 | 100 | unique | collective | rare / pool v1 | rare | 110 | external | yes | MIGRATE |
| team.internal.matches.100 | Cien partidos | internal | team.internal.matches | team_matches >= 100 | 100 | unique | collective | rare / pool v1 | rare | 110 | internal | yes | MIGRATE |
| player.all.wins.100 | Cien victorias | all | player.wins | player_wins >= 100 | 100 | unique | individual | none | epic | 120 | all | yes | MIGRATE |
| team.external.wins.100 | Cien victorias | external | team.external.wins | team_wins >= 100 | 100 | unique | collective | epic / pool v1 | epic | 120 | external | yes | MIGRATE |
| player.all.goals.100 | Centenario goleador | all | player.goals | player_goals >= 100 | 100 | unique | individual | none | epic | 140 | all | yes | MIGRATE |
| player.all.matches.005 | Uno de los nuestros | all | player.matches | player_appearances >= 5 | 5 | unique | individual | none | common | 15 | all | yes | MIGRATE |
| team.external.matches.005 | Cinco partidos | external | team.external.matches | team_matches >= 5 | 5 | unique | collective | common / pool v1 | common | 15 | external | yes | MIGRATE |
| team.internal.matches.005 | Cinco partidos | internal | team.internal.matches | team_matches >= 5 | 5 | unique | collective | common / pool v1 | common | 15 | internal | yes | MIGRATE |
| player.all.matches.010 | En dinámica | all | player.matches | player_appearances >= 10 | 10 | unique | individual | none | common | 20 | all | yes | MIGRATE |
| team.external.matches.010 | Diez partidos | external | team.external.matches | team_matches >= 10 | 10 | unique | collective | uncommon / pool v1 | uncommon | 20 | external | yes | MIGRATE |
| team.internal.matches.010 | Diez partidos | internal | team.internal.matches | team_matches >= 10 | 10 | unique | collective | uncommon / pool v1 | uncommon | 20 | internal | yes | MIGRATE |
| player.all.wins.001 | Primera alegría | all | player.wins | player_wins >= 1 | 1 | unique | individual | none | common | 21 | all | yes | MIGRATE |
| team.external.wins.001 | Victoria | external | team.external.wins | partido confirmado ganado | 1 | repeatable | collective | common / pool v1 | common | 21 | external | yes | first: Primera victoria; MIGRATE |
| player.all.wins.005 | Cinco victorias | all | player.wins | player_wins >= 5 | 5 | unique | individual | none | common | 25 | all | yes | MIGRATE |
| team.external.wins.005 | Cinco victorias | external | team.external.wins | team_wins >= 5 | 5 | unique | collective | uncommon / pool v1 | uncommon | 25 | external | yes | MIGRATE |
| player.all.matches.250 | Leyenda del vestuario | all | player.matches | player_appearances >= 250 | 250 | unique | individual | none | epic | 260 | all | yes | MIGRATE |
| team.external.matches.250 | Doscientos cincuenta partidos | external | team.external.matches | team_matches >= 250 | 250 | unique | collective | epic / pool v1 | epic | 260 | external | yes | MIGRATE |
| team.internal.matches.250 | Doscientos cincuenta partidos | internal | team.internal.matches | team_matches >= 250 | 250 | unique | collective | epic / pool v1 | epic | 260 | internal | yes | MIGRATE |
| player.all.wins.250 | Historia ganadora | all | player.wins | player_wins >= 250 | 250 | unique | individual | none | legendary | 270 | all | yes | MIGRATE |
| team.external.wins.250 | Doscientas cincuenta victorias | external | team.external.wins | team_wins >= 250 | 250 | unique | collective | legendary / pool v1 | legendary | 270 | external | yes | MIGRATE |
| player.all.double_hat_tricks.001 | Doble hat-trick | all | player.match_goals | goles personales >= 6 | 1 | repeatable | individual | none | legendary | 28 | all | yes | first: Primer doble hat-trick; MIGRATE |
| player.all.repokers.001 | Repóker | all | player.match_goals | goles personales exactos = 5 | 1 | repeatable | individual | none | epic | 29 | all | yes | first: Primer repóker; MIGRATE |
| player.all.goals.250 | Goleador histórico | all | player.goals | player_goals >= 250 | 250 | unique | individual | none | epic | 290 | all | yes | MIGRATE |
| player.all.pokers.001 | Póker | all | player.match_goals | goles personales exactos = 4 | 1 | repeatable | individual | none | rare | 30 | all | yes | first: Primer póker; MIGRATE |
| player.all.wins.010 | Diez alegrías | all | player.wins | player_wins >= 10 | 10 | unique | individual | none | uncommon | 30 | all | yes | MIGRATE |
| team.external.wins.010 | Diez victorias | external | team.external.wins | team_wins >= 10 | 10 | unique | collective | uncommon / pool v1 | uncommon | 30 | external | yes | MIGRATE |
| player.all.hat_tricks.001 | Hat-trick | all | player.match_goals | goles personales exactos = 3 | 1 | repeatable | individual | none | rare | 31 | all | yes | first: Primer hat-trick; MIGRATE |
| team.external.match_goals.006 | Seis o más | external | team.external.match_goals | goles del equipo >= 6 | 6 | repeatable | collective | epic / pool v1 | epic | 31 | external | yes | MIGRATE |
| team.internal.match_goals.006 | Seis o más | internal | team.internal.match_goals | goles del equipo >= 6 | 6 | repeatable | collective | epic / pool v1 | epic | 31 | internal | yes | MIGRATE |
| player.all.braces.001 | Doblete | all | player.match_goals | goles personales exactos = 2 | 1 | repeatable | individual | none | uncommon | 32 | all | yes | first: Primer doblete; MIGRATE |
| team.external.match_goals.005 | Manita | external | team.external.match_goals | goles del equipo exactos = 5 | 5 | repeatable | collective | rare / pool v1 | rare | 32 | external | yes | MIGRATE |
| team.internal.match_goals.005 | Manita | internal | team.internal.match_goals | goles del equipo exactos = 5 | 5 | repeatable | collective | rare / pool v1 | rare | 32 | internal | yes | MIGRATE |
| team.external.match_goals.004 | Cuatro goles | external | team.external.match_goals | goles del equipo exactos = 4 | 4 | repeatable | collective | uncommon / pool v1 | uncommon | 33 | external | yes | MIGRATE |
| team.internal.match_goals.004 | Cuatro goles | internal | team.internal.match_goals | goles del equipo exactos = 4 | 4 | repeatable | collective | uncommon / pool v1 | uncommon | 33 | internal | yes | MIGRATE |
| team.external.match_goals.003 | Tres goles | external | team.external.match_goals | goles del equipo exactos = 3 | 3 | repeatable | collective | uncommon / pool v1 | uncommon | 34 | external | yes | MIGRATE |
| team.internal.match_goals.003 | Tres goles | internal | team.internal.match_goals | goles del equipo exactos = 3 | 3 | repeatable | collective | uncommon / pool v1 | uncommon | 34 | internal | yes | MIGRATE |
| player.all.matches.025 | Habitual | all | player.matches | player_appearances >= 25 | 25 | unique | individual | none | uncommon | 35 | all | yes | MIGRATE |
| team.external.match_goals.002 | Dos goles | external | team.external.match_goals | goles del equipo exactos = 2 | 2 | repeatable | collective | common / pool v1 | common | 35 | external | yes | MIGRATE |
| team.external.matches.025 | Veinticinco partidos | external | team.external.matches | team_matches >= 25 | 25 | unique | collective | uncommon / pool v1 | uncommon | 35 | external | yes | MIGRATE |
| team.internal.match_goals.002 | Dos goles | internal | team.internal.match_goals | goles del equipo exactos = 2 | 2 | repeatable | collective | common / pool v1 | common | 35 | internal | yes | MIGRATE |
| team.internal.matches.025 | Veinticinco partidos | internal | team.internal.matches | team_matches >= 25 | 25 | unique | collective | uncommon / pool v1 | uncommon | 35 | internal | yes | MIGRATE |
| player.all.goals.001 | Primer gol | all | player.goals | player_goals >= 1 | 1 | unique | individual | none | common | 41 | all | yes | MIGRATE |
| team.external.clean_sheets.001 | Portería a cero | external | team.external.clean_sheets | goles del rival = 0 | 1 | repeatable | collective | common / pool v1 | common | 41 | external | yes | first: Primera portería a cero; MIGRATE |
| team.external.big_wins.001 | Goleada | external | team.external.big_wins | victoria por diferencia >= 4 | 1 | repeatable | collective | uncommon / pool v1 | uncommon | 42 | external | yes | first: Primera goleada; MIGRATE |
| team.external.close_wins.001 | Por la mínima | external | team.external.close_wins | victoria por diferencia = 1 | 1 | repeatable | collective | common / pool v1 | common | 43 | external | yes | first: Primera victoria por la mínima; MIGRATE |
| team.internal.big_wins.001 | Partido desatado | internal | team.internal.big_wins | victoria por diferencia >= 4 | 1 | repeatable | collective | uncommon / pool v1 | uncommon | 44 | internal | yes | first: Primer partido desatado; MIGRATE |
| player.all.wins.025 | Ganador habitual | all | player.wins | player_wins >= 25 | 25 | unique | individual | none | uncommon | 45 | all | yes | MIGRATE |
| team.external.wins.025 | Veinticinco victorias | external | team.external.wins | team_wins >= 25 | 25 | unique | collective | rare / pool v1 | rare | 45 | external | yes | MIGRATE |
| team.internal.close_wins.001 | Hasta el final | internal | team.internal.close_wins | victoria por diferencia = 1 | 1 | repeatable | collective | common / pool v1 | common | 45 | internal | yes | first: Primer final ajustado; MIGRATE |
| player.all.goals.010 | Diez goles | all | player.goals | player_goals >= 10 | 10 | unique | individual | none | common | 50 | all | yes | MIGRATE |
| player.all.matches.500 | Historia viva | all | player.matches | player_appearances >= 500 | 500 | unique | individual | none | legendary | 510 | all | yes | MIGRATE |
| team.external.matches.500 | Quinientos partidos | external | team.external.matches | team_matches >= 500 | 500 | unique | collective | legendary / pool v1 | legendary | 510 | external | yes | MIGRATE |
| team.internal.matches.500 | Quinientos partidos | internal | team.internal.matches | team_matches >= 500 | 500 | unique | collective | legendary / pool v1 | legendary | 510 | internal | yes | MIGRATE |
| player.all.goals.500 | Historia del gol | all | player.goals | player_goals >= 500 | 500 | unique | individual | none | legendary | 540 | all | yes | MIGRATE |
| player.all.matches.050 | Veterano | all | player.matches | player_appearances >= 50 | 50 | unique | individual | none | uncommon | 60 | all | yes | MIGRATE |
| team.external.matches.050 | Cincuenta partidos | external | team.external.matches | team_matches >= 50 | 50 | unique | collective | rare / pool v1 | rare | 60 | external | yes | MIGRATE |
| team.internal.matches.050 | Cincuenta partidos | internal | team.internal.matches | team_matches >= 50 | 50 | unique | collective | rare / pool v1 | rare | 60 | internal | yes | MIGRATE |
| player.win_streak.003 | Tres seguidas | all | player.win_streak | player_max_win_streak >= 3 | 3 | unique | individual | none | common | 61 | all | yes | MIGRATE |
| team.external.win_streak.003 | Tres victorias seguidas | external | team.external.win_streak | team_max_win_streak >= 3 | 3 | unique | collective | uncommon / pool v1 | uncommon | 61 | external | yes | MIGRATE |
| player.win_streak.005 | Cinco seguidas | all | player.win_streak | player_max_win_streak >= 5 | 5 | unique | individual | none | uncommon | 62 | all | yes | MIGRATE |
| team.external.win_streak.005 | Cinco victorias seguidas | external | team.external.win_streak | team_max_win_streak >= 5 | 5 | unique | collective | rare / pool v1 | rare | 62 | external | yes | MIGRATE |
| player.win_streak.010 | Diez seguidas | all | player.win_streak | player_max_win_streak >= 10 | 10 | unique | individual | none | epic | 63 | all | yes | MIGRATE |
| team.external.win_streak.010 | Diez victorias seguidas | external | team.external.win_streak | team_max_win_streak >= 10 | 10 | unique | collective | epic / pool v1 | epic | 63 | external | yes | MIGRATE |
| player.win_streak.015 | Quince seguidas | all | player.win_streak | player_max_win_streak >= 15 | 15 | unique | individual | none | legendary | 64 | all | yes | MIGRATE |
| team.external.win_streak.015 | Quince victorias seguidas | external | team.external.win_streak | team_max_win_streak >= 15 | 15 | unique | collective | legendary / pool v1 | legendary | 64 | external | yes | MIGRATE |
| player.all.goals.025 | Veinticinco goles | all | player.goals | player_goals >= 25 | 25 | unique | individual | none | uncommon | 65 | all | yes | MIGRATE |
| player.unbeaten.003 | Tres sin perder | all | player.unbeaten | player_max_unbeaten_streak >= 3 | 3 | unique | individual | none | common | 65 | all | yes | MIGRATE |
| team.external.unbeaten.003 | Tres sin perder | external | team.external.unbeaten | team_max_unbeaten_streak >= 3 | 3 | unique | collective | common / pool v1 | common | 65 | external | yes | MIGRATE |
| player.unbeaten.005 | Cinco sin perder | all | player.unbeaten | player_max_unbeaten_streak >= 5 | 5 | unique | individual | none | uncommon | 66 | all | yes | MIGRATE |
| team.external.unbeaten.005 | Cinco sin perder | external | team.external.unbeaten | team_max_unbeaten_streak >= 5 | 5 | unique | collective | uncommon / pool v1 | uncommon | 66 | external | yes | MIGRATE |
| player.unbeaten.010 | Diez sin perder | all | player.unbeaten | player_max_unbeaten_streak >= 10 | 10 | unique | individual | none | rare | 67 | all | yes | MIGRATE |
| team.external.unbeaten.010 | Diez sin perder | external | team.external.unbeaten | team_max_unbeaten_streak >= 10 | 10 | unique | collective | rare / pool v1 | rare | 67 | external | yes | MIGRATE |
| player.unbeaten.020 | Veinte sin perder | all | player.unbeaten | player_max_unbeaten_streak >= 20 | 20 | unique | individual | none | legendary | 68 | all | yes | MIGRATE |
| team.external.unbeaten.020 | Veinte sin perder | external | team.external.unbeaten | team_max_unbeaten_streak >= 20 | 20 | unique | collective | legendary / pool v1 | legendary | 68 | external | yes | MIGRATE |
| player.all.wins.050 | Medio centenar de victorias | all | player.wins | player_wins >= 50 | 50 | unique | individual | none | rare | 70 | all | yes | MIGRATE |
| team.external.wins.050 | Cincuenta victorias | external | team.external.wins | team_wins >= 50 | 50 | unique | collective | rare / pool v1 | rare | 70 | external | yes | MIGRATE |
| player.opponents_played.003 | Tres rivales | external | player.opponents_played | player_distinct_opponents >= 3 | 3 | unique | individual | none | common | 71 | external | yes | MIGRATE |
| team.external.opponents_played.003 | Tres rivales | external | team.external.opponents_played | team_distinct_opponents >= 3 | 3 | unique | collective | common / pool v1 | common | 71 | external | yes | MIGRATE |
| player.opponents_played.005 | Cinco rivales | external | player.opponents_played | player_distinct_opponents >= 5 | 5 | unique | individual | none | common | 72 | external | yes | MIGRATE |
| team.external.opponents_played.005 | Cinco rivales | external | team.external.opponents_played | team_distinct_opponents >= 5 | 5 | unique | collective | common / pool v1 | common | 72 | external | yes | MIGRATE |
| player.opponents_played.010 | Diez rivales | external | player.opponents_played | player_distinct_opponents >= 10 | 10 | unique | individual | none | uncommon | 73 | external | yes | MIGRATE |
| team.external.opponents_played.010 | Diez rivales | external | team.external.opponents_played | team_distinct_opponents >= 10 | 10 | unique | collective | uncommon / pool v1 | uncommon | 73 | external | yes | MIGRATE |
| player.opponents_played.025 | Veinticinco rivales | external | player.opponents_played | player_distinct_opponents >= 25 | 25 | unique | individual | none | rare | 74 | external | yes | MIGRATE |
| team.external.opponents_played.025 | Veinticinco rivales | external | team.external.opponents_played | team_distinct_opponents >= 25 | 25 | unique | collective | rare / pool v1 | rare | 74 | external | yes | MIGRATE |
| player.opponents_played.050 | Cincuenta rivales | external | player.opponents_played | player_distinct_opponents >= 50 | 50 | unique | individual | none | epic | 75 | external | yes | MIGRATE |
| team.external.opponents_played.050 | Cincuenta rivales | external | team.external.opponents_played | team_distinct_opponents >= 50 | 50 | unique | collective | epic / pool v1 | epic | 75 | external | yes | MIGRATE |
| player.opponents_won.003 | Tres rivales vencidos | external | player.opponents_won | player_distinct_opponent_wins >= 3 | 3 | unique | individual | none | uncommon | 76 | external | yes | MIGRATE |
| team.external.opponents_won.003 | Tres rivales vencidos | external | team.external.opponents_won | team_distinct_opponent_wins >= 3 | 3 | unique | collective | uncommon / pool v1 | uncommon | 76 | external | yes | MIGRATE |
| player.opponents_won.005 | Cinco rivales vencidos | external | player.opponents_won | player_distinct_opponent_wins >= 5 | 5 | unique | individual | none | uncommon | 77 | external | yes | MIGRATE |
| team.external.opponents_won.005 | Cinco rivales vencidos | external | team.external.opponents_won | team_distinct_opponent_wins >= 5 | 5 | unique | collective | uncommon / pool v1 | uncommon | 77 | external | yes | MIGRATE |
| player.opponents_won.010 | Diez rivales vencidos | external | player.opponents_won | player_distinct_opponent_wins >= 10 | 10 | unique | individual | none | rare | 78 | external | yes | MIGRATE |
| team.external.opponents_won.010 | Diez rivales vencidos | external | team.external.opponents_won | team_distinct_opponent_wins >= 10 | 10 | unique | collective | rare / pool v1 | rare | 78 | external | yes | MIGRATE |
| player.opponents_won.025 | Veinticinco rivales vencidos | external | player.opponents_won | player_distinct_opponent_wins >= 25 | 25 | unique | individual | none | epic | 79 | external | yes | MIGRATE |
| team.external.opponents_won.025 | Veinticinco rivales vencidos | external | team.external.opponents_won | team_distinct_opponent_wins >= 25 | 25 | unique | collective | epic / pool v1 | epic | 79 | external | yes | MIGRATE |
| player.opponents_won.050 | Cincuenta rivales vencidos | external | player.opponents_won | player_distinct_opponent_wins >= 50 | 50 | unique | individual | none | legendary | 80 | external | yes | MIGRATE |
| team.external.opponents_won.050 | Cincuenta rivales vencidos | external | team.external.opponents_won | team_distinct_opponent_wins >= 50 | 50 | unique | collective | legendary / pool v1 | legendary | 80 | external | yes | MIGRATE |
| player.all.goals.050 | Medio centenar | all | player.goals | player_goals >= 50 | 50 | unique | individual | none | rare | 90 | all | yes | MIGRATE |

## Preparado para futuro, no activo

- Goles 750/1000 y triple hat-trick.
- Reconocimiento individual de portero y MVP rival cuando exista evidencia canónica.
- Rankings territoriales, temporadas, pase premium, tienda y tarjetas sociales compartibles.
- Umbrales por modalidad para goleada.

No hay filas activas ni recompensas para estas capacidades.
