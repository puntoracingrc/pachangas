# League Match Operations V1 Report

## Contrato

R4C opera exclusivamente sobre `CanonicalMatch + CompetitionMatchContext`.
No crea una tabla de partidos de Liga paralela ni escribe fixtures dentro del
payload del grupo.

La RPC `command_pachanga_league_match_operations_v1` resuelve en PostgreSQL:

- actor autenticado y capability;
- Competition, Entry, roster y RuleRevision;
- partido, contexto y jornada;
- revision esperada;
- fecha y secuencia del servidor;
- receipt idempotente e invalidaciones.

## Adaptador canonico

`get_pachanga_league_canonical_match_v1` entrega un
`LeagueCanonicalMatchView` con contexto, ronda, equipos, regla congelada,
rosters elegibles, Attendance, squads, resultado, decision oficial, permisos y
siguientes acciones. Rechaza:

- contexto inexistente o fixture no publicado;
- competicion distinta de `LEAGUE`;
- actor sin relacion deportiva valida;
- funciones futuras de torneo, arbitro o disciplina.

## Attendance

La unica autoridad sigue siendo `pachanga_match_participants`. R4C anade la
identidad `canonical_match_id`, Entry y roster member en esa tabla y conserva:

- `voy`, `no voy`, pendiente;
- revision monotona;
- cierre por lado;
- historial e invalidacion Realtime.

Marcar asistencia no concede elegibilidad. El cierre de squad vuelve a validar
roster, revision, Entry y RuleRevision.

## CompetitionMatchSquad

Entidades:

- `pachanga_competition_match_squads`;
- `pachanga_competition_match_squad_revisions`;
- `pachanga_competition_match_squad_members`.

Lifecycle:

```text
draft -> submitted -> validated -> locked
                   -> rejected -> draft
```

Cada cambio crea una revision con checksum. `locked` es inmutable. Se validan
en servidor minimo/maximo, titulares, suplentes, dorsal, duplicados, vigencia,
Entry, roster, elegibilidad, RuleRevision y ausencia en ambos equipos.

Autoridad permitida: team owner, PRIMARY_DELEGATE o ROSTER_MANAGER efectivo.
Jugador ordinario, rival, Club no asignado, arbitro y support no pueden editar.

## MatchSheet y lifecycle

La MatchSheet minima enlaza partido, squads, cierres de Attendance, Sporting
Result y Official Result. No contiene tarjetas, incidentes, clima, firma
arbitral ni suspension.

```text
scheduled -> ready -> in_progress -> played -> result_pending -> official
```

Ningun estado se infiere por la hora. Los estados futuros devuelven
`FEATURE_NOT_AVAILABLE`.

## Seguridad

- RLS activada en todas las tablas publicas R4C.
- `INSERT/UPDATE/DELETE` revocados a `anon` y `authenticated`.
- Evidencia y receipts internos en `private` o solo `service_role`.
- Funciones `SECURITY DEFINER` con `search_path = pg_catalog`.
- Actor siempre desde `auth.uid()`; no existe `actorId` de cliente.
- Payload y metadata se normalizan y limitan.
- Lecturas publicas no contienen Attendance, roster, disputa ni evidencia.

## Realtime y PWA

Las invalidaciones tipadas cubren match, squad, result, round y standings. El
cliente invalida la entidad concreta y vuelve a solicitar el snapshot canonico;
tambien relee al entrar en `SUBSCRIBED` o reconectar. Nunca usa WAL como estado.

Offline solo conserva read models cacheados o borradores visuales. Attendance,
squad, resultado, decision y rebuild nunca se muestran como confirmados sin
receipt servidor.

## Validacion

- SQL/RLS/adversarial: PASS.
- Direct table writes: rechazadas.
- Idempotencia de todas las acciones: mismo receipt y cero efectos duplicados.
- Concurrencia de create/submit/lock/edit: `1 winner / 1 conflict`.
- Staging: 15 contexts archivados con historia y cero entidades activas.
