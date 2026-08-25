# Demo World V2 Stories

## Continuidad de V1

V2 conserva las doce historias sociales de V1 y sus referencias `demo_*`.
Sobre ellas anade un recorrido de Liga derivado del Simulation World. Las
historias de Liga no son copy independiente: cada una resuelve una jornada,
un CanonicalMatch, una decision oficial o una relacion publica del snapshot.

## Story 13 - Una Liga completa, no una tarjeta decorativa

- Competition: `demo_league_competition`.
- Edicion: Temporada 2026/27.
- Participantes: seis equipos Demo ya existentes.
- Evidencia: cinco jornadas, quince CanonicalMatches y quince resultados
  oficiales.
- Descubrimiento: Liga, equipos, calendario, partido y clasificacion desde la
  misma shell de `/demo`.

## Story 14 - El aplazamiento conserva la fecha original

- Partido: `demo_league_match_003`, Cobalto Raval contra Marina Fosca.
- Flujo real: solicitud local, aceptacion rival, aprobacion del organizador y
  nueva fecha.
- Lineage: `postponement -> fixture_change -> official_result`.
- Resultado: 0-2, computado una sola vez en la clasificacion.

## Story 15 - Cambiar de campo no crea otro partido

- Partido: `demo_league_match_007`, Circuit Poblenou contra Marina Fosca.
- Cambio: Pista Demo Liga -> Camp Municipal Besos.
- Lineage: `fixture_change -> official_result`.
- Resultado: el CanonicalMatch, la jornada y la revision deportiva permanecen
  unidos.

## Story 16 - Un no-show produce una decision oficial

- Partido: `demo_league_match_011`, Onze del Clot contra Marina Fosca.
- Flujo real: reporte tras el grace period y confirmacion del organizador.
- Outcome: `NO_SHOW`.
- Resultado reglamentario: 3-0.
- Privacidad: el snapshot no publica evidencia, notas internas ni identidad del
  reporter.

## Story 17 - Suspender no destruye lo ya jugado

- Partido: `demo_league_match_015`, Ferro Sant Andreu contra Cobalto Raval.
- Incidencia: suspension en el minuto 38 con 1-1 parcial.
- Flujo real: confirmacion, programacion de reanudacion y reanudacion sobre el
  mismo CanonicalMatch.
- Lineage: `suspension -> resumption -> official_result`.
- Resultado final: 2-2.

## Story 18 - Un retraso normal no se convierte en no-show

- Partido: `demo_league_match_005`.
- Flujo real: el rival reporta el retraso y el equipo confirma su llegada
  dentro del grace period.
- Resultado: `arrived_within_policy`, sin no-show, sancion ni marcador
  administrativo.

## Story 19 - La tabla se puede reconstruir

- Fuente: quince OfficialResultDecision.
- Read model: StandingSnapshot de seis filas.
- Lider: Onze del Clot, 10 puntos, diferencia +3.
- Verificacion: un oracle independiente reconstruye las ocho columnas
  deportivas y coincide exactamente con PostgreSQL.

## Story 20 - Un Club conecta equipos y arbitros

- Club: `demo_club_001`, Club Esportiu Raval IQ.
- Equipos: Cobalto Raval y Circuit Poblenou.
- Arbitros relacionados: Alex Serra, Nora Vidal y Dani Pons.
- Descubrimiento: perfil publico, equipos asociados y perfiles de Mercado sin
  exponer datos de contacto.

## Story 21 - Arbitros disponibles, assignments todavia no

- Perfiles: ocho arbitros ficticios publicos.
- Estados: disponibles o disponibilidad limitada.
- Modalidades: futbol 7, futbol 11 y futbol sala.
- Regla visible: `refereeAssignmentsEnabled = false`; ningun perfil adquiere
  autoridad ni aparece asignado a un partido.

## Story 22 - El organizador ve el mismo producto

- Perspectiva: `league-organizer`.
- Estado: local y efimero, sin Auth.
- Descubrimiento: League Scheduling, Match Operations, incidencias y standings
  mediante los mismos renderers productivos que usan las superficies privadas.

## Cobertura conjunta

V2 permite recorrer equipo, jugador, partido, asistencia, alineacion,
resultado, goleadores, Mercado, Retos, Ranking, logros, rewards, Clubs,
arbitros, Liga, calendario, jornadas, clasificacion e incidencias R4D. Todo el
mundo publico es ficticio y read-only; la autoridad real se utiliza solo para
generar y verificar el snapshot.
