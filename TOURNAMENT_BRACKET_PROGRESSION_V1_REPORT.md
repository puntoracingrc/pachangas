# Tournament Bracket Progression V1

## Regla de ganador

PostgreSQL resuelve el ganador; el navegador no lo propone como autoridad.

Orden:

1. resultado reglamentario;
2. prórroga si la RuleRevision lo exige;
3. penaltis si el empate continúa y la policy lo permite;
4. `NO_SHOW`, `FORFEIT` o decisión administrativa R4D válida.

Si no existe desempate válido: `KNOCKOUT_WINNER_REQUIRED` y no se publica
avance.

Los goles de tanda se guardan separados (`shootout_home`, `shootout_away`): no
alteran GF, goleadores ni marcador deportivo ordinario.

## AdvanceDecision

Cada avance conserva:

- node fuente;
- decisión oficial opcional;
- razón de avance;
- ganador y perdedor resueltos por servidor;
- slots destino;
- decisión supersedida;
- revisión, secuencia y hora del servidor.

Razones activas: resultado deportivo, prórroga, penaltis, bye, forfeit,
no-show y decisión administrativa.

El avance, resolución de slots, actualización de node, invalidación, read model
y notificación se confirman en una transacción. Un fallo downstream revierte
el origen y no deja un node parcialmente completado.

## Tercer puesto

Cuando `thirdPlaceMatchEnabled` está activo, los perdedores de SF1/SF2 llenan
un node específico. Cuando está desactivado no existe node ni match ficticio.

## Correcciones y lineage

Una OfficialResultDecision supersedida produce:

1. resolución nueva;
2. AdvanceDecision nueva;
3. decisión previa preservada;
4. `BracketDependencyImpact` con nodes, matches, árbitros, horarios,
   disciplina, resultados y completion afectados;
5. descendencia stale/invalidation;
6. replacement solo si el partido descendiente no comenzó.

El match retirado y su contexto histórico mantienen los participantes exactos
de aquella revisión. Ninguna consulta de último snapshot depende solo de un
timestamp.

## R4D, R5 y conducta

- Un no-show confirmado puede producir OfficialResultDecision y avance.
- No crea automáticamente Conduct ni una sanción social.
- R5 aplica carry/reset de contadores según RuleRevision sin borrar eventos.
- Rating V2, Rewards, Conduct y Billing permanecen byte-isolated de R6C.

## Realtime y notificaciones

Invalidaciones tipadas cubren bracket, node, slot, match, result, advance,
referee, discipline, incident y completion. Tras `SUBSCRIBED` o reconexión, el
cliente relee el snapshot canónico; nunca aplica el payload WAL como estado.

Notificaciones idempotentes: rival definido, partido programado, clasificado,
eliminado, avance, finalista, tercer puesto, corrección, invalidación y campeón.

## Pruebas

- 11 carreras concurrentes: un ganador y un stale/conflict.
- 16 negativos, incluido resultado no oficial, empate no resuelto, shootout
  empatado, ganador enviado por cliente y downstream iniciado.
- 14/16 equipos: dos byes explícitos, cero `CanonicalMatch` de bye.
- Corrección Demo: 8 matches activos, 9 históricos y 1 retirado.
- Invariantes globales: 0 ganadores dobles, 0 matches o advances duplicados.

Rendimiento local:

| Operación | p50 | p95 |
| --- | ---: | ---: |
| Advance | 74,55 ms | 79,60 ms |
| Invalidación downstream | 62,78 ms | 71,42 ms |
| Bracket view | 31,29 ms | 43,19 ms |
| Organizer Desk | 50,93 ms | 54,11 ms |
