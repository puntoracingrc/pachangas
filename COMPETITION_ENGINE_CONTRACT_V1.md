# Competition Engine Contract V1

Estado: `R0 RECONCILIADO - CONTENIDO CERRADO, REVISION HUMANA EN PR PENDIENTE`

## 1. Alcance y lenguaje normativo

Este contrato fija cómo deberán integrarse competiciones, clubes y árbitros en
Pachangas IQ. Gobierna R1-R10 del roadbook y evita que League Engine o Tournament
Engine nazcan como productos paralelos.

Los términos `DEBE`, `NO DEBE`, `PUEDE` y `REQUIERE` son normativos. Los nombres de
tablas y tipos de esta fase son conceptuales; R1 podrá ajustarlos a las convenciones
del repositorio siempre que preserve todos los invariantes.

Este documento no:

- crea tablas, RPC, rutas o componentes;
- selecciona valores comerciales de presets;
- activa planes, cobros, premios o rankings;
- modifica Supabase, datos remotos o producción;
- modifica Rating V2, Conduct, Rewards, Player Cosmetics o Team Cosmetics.

## 2. Invariantes no negociables

### 2.1 Un partido, varios contextos

Debe existir un único partido canónico y un contexto opcional de competición:

```text
CanonicalMatch
  + optional CompetitionMatchContext
```

Queda prohibido crear motores de partido independientes como:

```text
NormalMatch
LeagueMatch
TournamentMatch
RefereedMatch
```

Liga y torneo generan y gobiernan contexto, calendario, elegibilidad, clasificación y
disciplina. No duplican asistencia, alineación, resultado, goleadores, fotografía,
valoraciones ni ficha del jugador.

### 2.2 PostgreSQL es la única autoridad

Toda creación o modificación deportiva DEBE atravesar una RPC/API central que:

1. identifica al actor autenticado;
2. valida rol, entitlement, estado y revisión esperada;
3. bloquea el agregado correspondiente;
4. aplica la operación una sola vez;
5. incrementa una revisión monotónica;
6. persiste evento, recibo y fecha del servidor;
7. actualiza read models canónicos;
8. devuelve el snapshot confirmado completo afectado.

El cliente solo envía intención. Nunca decide el resultado definitivo mediante JSON,
`localStorage`, IndexedDB, una hora del dispositivo o un cálculo optimista.

### 2.3 El partido conserva sus reglas

Todo partido de competición DEBE referenciar la revisión exacta y congelada de reglas
aplicable al crearse o al quedar programado. Una edición posterior del borrador o del
preset no puede alterar su interpretación histórica.

### 2.4 No se borra historia significativa

Resultados, actas, tarjetas, sanciones, plantillas, inscripciones, clasificaciones,
aplazamientos, asignaciones arbitrales y decisiones administrativas no se eliminan
para corregirlos. Se anulan, sustituyen o corrigen con lineage explícito.

### 2.5 Separación de dominios

```text
Competition Discipline != Conduct
Competition Standing   != Rating V2
Competition Award      != Rating V2
Billing state          != Competition entitlement
```

- Una amarilla, roja, azul, sanción, posición o campeonato NO modifica GRL, facetas,
  confianza o fórmula de Rating V2.
- Una tarjeta no abre automáticamente un caso de Conduct.
- Una incidencia grave PUEDE ofrecer una acción separada para reportar Conducta.
- Una clasificación no concede rewards salvo un contrato explícito posterior.
- Los cinco mappings vigentes de Team Cosmetic Rewards permanecen intactos.

## 3. Encaje con el producto existente

### 3.1 Autoridades que se reutilizan

| Dominio existente | Autoridad actual | Regla de integración |
| --- | --- | --- |
| Equipo | `pachanga_groups` | Una inscripción referencia el equipo; no crea una copia de su identidad |
| Membresía | membresías owner/admin/player | Sirve para actuar por el equipo, pero no concede autoridad organizadora |
| Jugador | `pachanga_player_profiles` | La persona conserva una ficha universal entre equipos y competiciones |
| Partido de grupo | read model, participantes, goleadores y RPC V2 | Se enlaza mediante contexto; no se copia |
| Reto/partido rival | retos, `pachanga_external_matches` y resultados versionados | Se adapta a identidad canónica antes de entrar en calendarios |
| Operación | `operationId`, revisión, receipts y `server_sequence` | Es el patrón obligatorio de comandos nuevos |
| Realtime | evento como invalidación | El cliente recarga el read model oficial afectado |
| Rating | Rating V2 | Solo consume evidencia deportiva que ya cumpla su contrato |
| Conduct | Conduct V1 | Sigue teniendo hechos, permisos y moderación propios |
| Rewards | economía y catálogos actuales | No reciben mappings implícitos desde competición |

### 3.2 Brecha de identidad canónica

El código actual tiene más de una procedencia de partido: el partido del payload/read
model de grupo y el partido externo asociado a Retos. Antes de que R4 genere una sola
jornada, R1 DEBE implantar una de estas soluciones equivalentes:

- una identidad canónica única referenciada por ambos modelos; o
- un registro de binding único que asigne cada procedencia a un `canonicalMatchId`.

El binding DEBE garantizar:

```text
una procedencia activa -> un canonicalMatchId
un partido de competición -> un canonicalMatchId
un canonicalMatchId -> como máximo un encuentro deportivo real
```

No se permite sincronizar dos copias por last-write-wins.

## 4. Agregados conceptuales

| Agregado / entidad | Responsabilidad | Revisión propia |
| --- | --- | ---: |
| `Competition` | Identidad estable, modalidad, organizador y familia competitiva | Sí |
| `CompetitionEdition` | Temporada/edición concreta y lifecycle operativo | Sí |
| `CompetitionRuleSet` | Familia lógica de reglas | Sí |
| `CompetitionRuleRevision` | Configuración inmutable y fecha efectiva | Sí |
| `CompetitionCategory` | Edad/género/nivel y reglas aplicables | Sí |
| `CompetitionStage` | Stage o split: liga, grupos, knockout, serie o participación | Sí |
| `CompetitionDivision` | Nivel deportivo contextual dentro de una edición/stage | Sí |
| `CompetitionGroup` | Agrupación competitiva dentro de stage/división | Sí |
| `CompetitionStageMembership` | Pertenencia histórica de una entrada a stage/división/grupo | Sí |
| `CompetitionEntry` | Solicitud/aceptación de un equipo | Sí |
| `CompetitionTeamDelegate` | Representación del equipo limitada a esa inscripción/competición | Sí |
| `CompetitionRoster` | Plantilla del equipo para categoría/temporada | Sí |
| `CompetitionRosterMember` | Elegibilidad contextual del jugador | Sí |
| `CompetitionMatchSquad` | Convocatoria/acta propuesta para un partido concreto | Sí |
| `CompetitionTemporaryPlayerPermit` | Autorización excepcional y temporal por partido | Sí |
| `PlayerCompetitionCredential` | Estado de verificación e identidad mínima, sin documento completo por defecto | Sí |
| `CompetitionTeamKit` | Equipaciones y colores declarados por edición | Sí |
| `CompetitionPlayerJerseyNumber` | Dorsal contextual y vigencia | Sí |
| `TeamAvailabilityConstraint` | Restricción dura que el calendario no puede infringir sin decisión | Sí |
| `TeamSchedulePreference` | Preferencia ponderada de día, hora o sede | Sí |
| `CompetitionRound` | Jornada o ronda programable | Sí |
| `CompetitionMatchContext` | Enlace entre partido canónico, fase, ronda y reglas | Sí |
| `MatchSheet` | Participantes, oficiales y hechos del partido | Sí |
| `RefereeMatchReport` | Informe arbitral versionado y firmado sobre el encuentro | Sí |
| `PostponementRequest` | Solicitud, respuestas, deadline y resolución de aplazamiento | Sí |
| `LateArrivalIncident` | Llegada tardía y transición posible hacia no-show | Sí |
| `MatchSuspension` | Hecho de suspensión/abandono, minuto, marcador y evidencia | Sí |
| `VenueConditionDecision` | Inspección de clima/campo y autoridad que decide | Sí |
| `OfficialResultDecision` | Resultado que computa y su procedencia | Sí |
| `StandingSnapshot` | Tabla materializada y reconstruible | Sí |
| `BracketSnapshot` | Cuadro y avance materializados y reconstruibles | Sí |
| `CompetitionSportsmanshipSnapshot` | Clasificación opcional con fórmula/versiones explícitas | Sí |
| `DisciplinaryEvent` | Tarjeta u otro hecho deportivo original | Sí |
| `DisciplinaryCycle` | Ámbito y vigencia de acumulación por stage/split/edición | Sí |
| `DisciplinaryCounter` | Acumulación materializada y reconstruible | Sí |
| `CompetitionSanction` | Consecuencia consumible del reglamento/comité | Sí |
| `SanctionServiceEvent` | Consumo, reversión o cumplimiento de una sanción | No mutable |
| `SanctionAppeal` | Expediente de recurso, deadline, estado e historial | Sí |
| `AdministrativeDecision` | Excepción motivada que produce efectos | Sí |
| `RefereeProfile` | Faceta arbitral universal, separada de jugador | Sí |
| `RefereeAssignment` | Designación para partido y estado | Sí |
| `Club` | Organización que puede agrupar equipos y staff | Sí |
| `ClubMembership` | Relación persona-club con ámbito | Sí |
| `CompetitionStaffAssignment` | Rol de organización en una competición | Sí |
| `VenueStaffAssignment` | Delegado de campo, auxiliar o coordinador en sede/turno | Sí |
| `CompetitionEntitlement` | Capacidad comercial/operativa concedida | Sí |
| `CompetitionFeePolicy` | Conceptos económicos declarativos y versionados | Sí |
| `CompetitionCharge` | Cargo futuro originado por una regla/decisión, sin ejecutar cobro en R1 | Sí |
| `CompetitionCredit` | Crédito o descuento futuro con causa y vigencia | Sí |
| `CompetitionMedicalCoveragePolicy` | Cobertura opcional asociada a licencia/edición | Sí |
| `MatchInjuryIncident` | Incidente mínimo para un futuro flujo de cobertura | Sí |
| `CompetitionOperationReceipt` | Replay idempotente de un comando | No mutable |
| `CompetitionEvent` | Evento ordenado para auditoría e invalidación | No mutable |

Toda entidad mutable compartida DEBE tener como mínimo:

```text
id
revision
createdAt
updatedAt
createdBy cuando proceda
status
```

Todo evento o decisión DEBE añadir:

```text
serverSequence
operationId
actorId
confirmedAt
reasonCode
```

### 4.1 Jerarquía obligatoria

La estructura navegable y auditable es:

```text
Competition
  -> CompetitionEdition
    -> CompetitionStage (incluye split)
      -> CompetitionDivision y/o CompetitionGroup
        -> CompetitionRound (jornada/ronda)
          -> CompetitionMatchContext -> CanonicalMatch
```

Una entrada puede cambiar de división o grupo entre stages mediante una nueva
`CompetitionStageMembership` con vigencia. Nunca se reescribe su pertenencia anterior.
Un playoff posterior es otro stage del mismo grafo, no una copia del campeonato ni
un segundo partido deportivo.

## 5. Identidades y snapshots

### 5.1 Persona y jugador

La ficha universal sigue siendo la autoridad de identidad deportiva actual. Un roster
no copia la ficha viva como una segunda identidad. Conserva:

- referencia al perfil universal;
- equipo y competición;
- dorsal/rol contextual;
- estado de elegibilidad;
- dispensas vigentes;
- snapshot mínimo necesario en el momento de inscripción o partido.

Un snapshot histórico puede conservar nombre deportivo, posición y datos visibles
entonces. No puede convertirse en una ruta de escritura hacia la ficha universal.

Las tres capas operativas son obligatoriamente distintas:

```text
equipo habitual (`pachanga_groups`)
  -> `CompetitionRoster` de la edición
    -> `CompetitionMatchSquad` / participantes efectivos del partido
```

Un `CompetitionTemporaryPlayerPermit` puede habilitar a una persona para un único
partido sin convertirla silenciosamente en miembro permanente o roster estable. El
servidor valida máximo, autorización excepcional, credential, cobertura y revisión de
reglas. Precio o cargo, si existe, es un efecto económico declarativo separado.

`PlayerCompetitionCredential` debe poder expresar `unverified`, `verified`,
`expired`, `rejected` o `revoked`, método y autoridad. Por defecto conserva el estado
y una referencia opaca a evidencia protegida, no las dos caras del DNI ni una copia
descargable por organizadores ordinarios.

### 5.2 Equipo y club

`pachanga_groups` continúa siendo el equipo. `Club` es una organización superior que
PUEDE agrupar varios equipos. Un club no absorbe membresías ni crea jugadores nuevos.

La misma persona puede ser:

```text
jugador de Equipo A
admin de Equipo B
staff de Club C
árbitro independiente
organizador de Competición D
```

Cada permiso se resuelve por asignación y ámbito, nunca por el rol más alto que tenga
la persona en otro agregado.

`CompetitionTeamDelegate` representa al equipo únicamente en su entrada y edición.
Puede recibir acciones como gestionar roster, declarar equipación, responder a un
horario o presentar recurso, pero no hereda automáticamente `owner/admin` global ni
puede actuar por otro equipo. Su vigencia, sustitución y categorías/fases se auditan.

La equipación también es contextual: `CompetitionTeamKit` conserva colores y tipo de
kit por edición, mientras `CompetitionPlayerJerseyNumber` conserva dorsal y vigencia.
Un conflicto de colores o un periodo de gracia se resuelve con la política congelada
o una decisión, nunca cambiando la identidad global del equipo o jugador.

### 5.3 Árbitro

La faceta de árbitro es universal y distinta de una carta de jugador. No tiene GRL ni
facetas de Rating V2. Una asignación conserva el perfil arbitral y, cuando proceda,
un snapshot de nombre, acreditación verificada y categoría visible en ese partido.

## 6. Reglamento versionado

### 6.1 Lifecycle

```text
draft -> validated -> published -> frozen -> superseded
                     \-> withdrawn (antes de uso)
```

- `draft`: editable por actor autorizado.
- `validated`: pasa validaciones estructurales, todavía no gobierna partidos.
- `published`: seleccionable para una competición que no ha comenzado.
- `frozen`: ya gobierna al menos una fase/partido y es inmutable.
- `superseded`: existe una revisión posterior, pero sigue siendo válida para historia.
- `withdrawn`: retirada antes de gobernar hechos deportivos.

No existe transición de `frozen` a editable.

### 6.2 Contenido mínimo

Una `CompetitionRuleRevision` DEBE contener o referenciar:

```text
identity
  ruleSetId
  version
  effectiveFrom
  sourcePresetId?
  sourcePresetVersion?

format
  sportFormat
  categoryPolicy
  matchDurationPolicy
  substitutionPolicy

registration
  registrationPolicy
  identityRequirements
  rosterPolicy
  temporaryPlayerPolicy
  matchSheetPolicy
  kitPolicy

structure
  editionPolicy
  stageGraph
  divisionAndGroupPolicy
  stageReassignmentPolicy
  roundGenerationPolicy
  advancementRules

results
  scoringPolicy
  tieBreakCriteria
  knockoutResolutionPolicy
  publicationPolicy

operations
  postponementPolicy
  lateArrivalPolicy
  noShowPolicy
  suspendedMatchPolicy
  venueConditionPolicy
  hardAvailabilityPolicy
  schedulePreferencePolicy
  withdrawalPolicy

discipline
  cardTypeCatalog
  temporaryDismissalPolicy
  disciplinaryContextPolicy
  disciplinaryCycles
  accumulationRules
  dismissalPolicy
  sanctionRangePolicy
  sanctionServicePolicy
  sanctionCarryPolicy

governance
  authorityPolicy
  teamDelegatePolicy
  venueStaffPolicy
  claimPolicy
  appealPolicy
  refereeAssignmentPolicy

publication
  publicSanctionPolicy
  playerDataVisibilityPolicy
  sportsmanshipPolicy

futureCapabilities
  feePolicy
  medicalCoveragePolicy
```

### 6.3 Validación estructural

Antes de publicar, el servidor DEBE comprobar al menos:

- todos los nodos del grafo de fases son alcanzables o están marcados como
  opcionales;
- todo destino de avance existe y no genera ciclos no declarados;
- la puntuación y los desempates son deterministas;
- el último criterio de desempate termina o crea una decisión persistida;
- los mínimos no superan los máximos de roster/acta/campo;
- todo stage pertenece a una edición y toda membership tiene vigencia no ambigua;
- una reasignación de división conserva el stage anterior y no mueve resultados ya
  disputados;
- las ventanas no se solapan de forma ambigua;
- una restricción dura y una preferencia no comparten semántica ni prioridad;
- cada tarjeta activa tiene efecto inmediato definido;
- una tarjeta azul activa define condiciones de liberación (`duration`,
  `opponent_goal`, ambas o ninguna) y sustitución;
- cada ciclo disciplinario declara ámbito, reset y política de arrastre;
- toda sanción tiene alcance y forma de consumo;
- todo rango de sanción que requiera juicio termina en comité, no en máximo/mínimo
  escogido por el cliente;
- toda excepción tiene una autoridad capaz de resolverla;
- toda apelación tiene deadline calculable con hora del servidor, estados y autoridad;
- una categoría sin tabla no publica standings ni concede avance por clasificación;
- el read model público disciplinario no referencia evidencia privada;
- una fórmula de deportividad ausente u opaca no puede publicarse como calculada;
- no existen referencias a un preset mutable en tiempo de ejecución.

### 6.4 Cambio excepcional tras iniciar

Un cambio posterior al inicio crea una revisión nueva con:

```text
supersedesRevisionId
effectiveFrom
effectiveScope
reasonCode
reasonText
approvedBy
approvedAt
```

`effectiveScope` distingue partidos futuros, fase futura o aplicación retroactiva
autorizada. La retroactividad exige una `AdministrativeDecision`, simulación previa
del impacto y rebuild auditado de read models. Nunca se obtiene editando la revisión
original.

## 7. Presets

Los presets P01-P06 de la matriz son plantillas de autoría. El flujo DEBE ser:

```text
seleccionar preset
-> copiar valores y procedencia
-> editar
-> validar
-> mostrar resumen completo
-> confirmar
-> publicar revisión propia
```

El frontend no puede ocultar parámetros “avanzados” que cambien resultados,
elegibilidad o sanciones. Puede agruparlos y explicar sus efectos.

## 8. Estados canónicos

### 8.1 Competición y edición

```text
draft
-> registration_open
-> registration_closed
-> scheduled
-> active
-> completed
-> archived
```

Salidas extraordinarias:

```text
draft/registration_open -> cancelled
scheduled/active        -> suspended -> active | cancelled
```

`archived` es de solo lectura. `completed` solo se alcanza cuando partidos,
decisiones pendientes y clasificación final son coherentes.

`Competition` puede conservar identidad estable mientras cada `CompetitionEdition`
recorre este lifecycle. Una edición cerrada no se reutiliza para la temporada
siguiente ni se reabre para simular un split nuevo.

### 8.2 Inscripción de equipo

```text
draft -> submitted -> accepted -> active -> completed
                  \-> rejected
accepted/active -> withdrawn | disqualified
```

Aceptar una entrada no concede al equipo permisos de organizador.

### 8.3 Plantilla

```text
draft -> submitted -> approved -> locked
                   \-> changes_requested
locked -> amended (solo decisión autorizada)
```

Cada enmienda conserva la plantilla anterior y su fecha efectiva.

La convocatoria y el permiso provisional tienen lifecycles propios:

```text
CompetitionMatchSquad: draft -> submitted -> validated -> locked
                                      \-> rejected
CompetitionTemporaryPlayerPermit: requested -> approved -> consumed
                                           \-> rejected | cancelled | expired
```

Consumir un permiso no incorpora al jugador al roster. Repetir la operación devuelve
el mismo receipt y no crea un segundo permiso, cargo o participante.

### 8.4 Jornada/ronda

```text
draft -> published -> in_progress -> completed -> locked
```

Una ronda `locked` solo cambia mediante decisión administrativa y rebuild.

### 8.5 Contexto de partido

El contexto amplía, no sustituye, los estados canónicos existentes:

```text
scheduled -> postponed -> scheduled
scheduled -> ready -> in_progress -> played
ready/in_progress -> suspended -> scheduled | in_progress | abandoned | cancelled
played/abandoned -> result_pending -> official
scheduled/postponed -> cancelled
```

La traducción entre estos estados y los estados actuales
`draft/published/lineup_open/lineup_closed/played/finalized/historical` debe definirse
en R1 como una máquina explícita, sin inferencias por fecha.

`postponed` conserva la obligación de disputar el encuentro y espera nueva fecha;
`suspended` conserva minuto, marcador y causa para reanudar o resolver; `cancelled`
termina el encuentro sin fingir un resultado deportivo. `abandoned` significa que se
inició y no terminó. Ninguno equivale por sí mismo a una derrota administrativa.

### 8.6 Estado del resultado

El lifecycle del encuentro y el del resultado son ortogonales:

```text
none -> sporting_submitted -> sporting_confirmed
     -> disputed -> administrative_review
     -> official
official -> superseded | annulled (solo decisión autorizada)
```

Así, un partido suspendido puede conservar un `SportingResult` parcial sin tener
`OfficialResultDecision`, y un partido jugado puede esperar una resolución oficial.

### 8.7 Asignación arbitral

```text
proposed -> accepted -> confirmed -> completed
         \-> declined
accepted/confirmed -> cancelled | replaced
```

## 9. Contrato de comandos

### 9.1 Envelope de intención

Toda escritura DEBE recibir:

```ts
type CompetitionCommand = {
  operationId: string;       // UUID único
  aggregateId: string;
  expectedRevision: number;
  action: string;
  payload: unknown;          // solo datos permitidos para esa acción
  clientMetadata?: {
    clientVersion?: string;
    serviceWorkerVersion?: string;
    installedMode?: "browser" | "standalone" | "fullscreen";
    sessionId?: string;
  };
};
```

El servidor resuelve actor, roles, entitlement, reglas vigentes, estado, tiempo,
secuencia y efectos calculados. No confía en un `actorId`, una tabla, una sanción, un
nivel, un snapshot o una autoridad enviados por el navegador.

### 9.2 Respuesta confirmada

```ts
type ConfirmedCompetitionResponse<T> = {
  operationId: string;
  confirmedRevision: number;
  confirmedAt: string;
  serverSequence: number;
  snapshot: T;
  invalidations: Array<{
    entityType: string;
    entityId: string;
    revision: number;
  }>;
};
```

La respuesta contiene el read model canónico completo afectado. El cliente sustituye
cualquier previsualización por ese snapshot.

### 9.3 Idempotencia y concurrencia

- Un `(actor, operationId)` repetido devuelve el mismo recibo y no reaplica efectos.
- Reutilizar el mismo `operationId` con otro actor o payload se rechaza.
- La revisión obsoleta produce conflicto explícito, nunca last-write-wins.
- La transacción bloquea el agregado raíz y los agregados secundarios en un orden
  documentado para evitar deadlocks.
- Un comando que afecta competición y partido debe confirmar ambos o ninguno.
- La secuencia procede del servidor y ordena eventos con timestamps idénticos.

## 10. Partido canónico y contexto competitivo

`CompetitionMatchContext` DEBE contener al menos:

```text
competitionId
editionId
categoryId
stageId
divisionId?
groupId?
roundId?
canonicalMatchId
homeEntryId
awayEntryId
ruleRevisionId
scheduledAt
venueId?
status
revision
```

También puede conservar `legNumber`, `seriesId`, `bracketSlotId` o
`displayOrder`, pero esos campos no crean una identidad deportiva nueva.

### 10.1 Propiedad de datos

| Dato | Autoridad |
| --- | --- |
| Fecha/sede programada por competición | Contexto de competición |
| Asistencia | Partido canónico |
| Alineación | Partido canónico, validada contra elegibilidad de competición |
| Goleadores | Partido canónico |
| Marcador deportivo | Partido canónico/acta |
| Marcador oficial | `OfficialResultDecision` |
| Puntos y clasificación | Read model de competición |
| Tarjetas | Acta/`DisciplinaryEvent` |
| Sanciones acumuladas | Competition Discipline |
| Rating | Rating V2, bajo su contrato independiente |

### 10.2 Validación de alineación

Al cerrar o modificar una alineación de competición, el servidor DEBE comprobar en la
misma operación:

- membresía/roster elegible en la fecha efectiva;
- documentación o dispensa requerida;
- ausencia de sanción aplicable no consumida;
- límites de convocatoria y modalidad;
- permiso provisional válido si la persona no pertenece al roster ordinario;
- dorsal y equipación exigibles en esa revisión;
- incompatibilidad con otro equipo/partido si la regla lo prohíbe;
- revisión actual de roster, contexto y partido.

Una interfaz no puede saltarse el bloqueo usando la RPC genérica del partido.

## 11. Resultados y decisiones oficiales

### 11.1 Dos capas obligatorias

```text
SportingResult
  scoreHome
  scoreAway
  shootout?
  evidence
  confirmedBy

OfficialResultDecision
  sourceSportingResultId?
  effectiveScoreHome
  effectiveScoreAway
  outcome
  pointsAdjustments[]
  responsibleEntryId?
  reasonCode
  authority
  supersedesId?
```

La clasificación siempre consume el resultado oficial activo. Si no hay excepción,
el resultado oficial referencia y refleja el deportivo. Un 0-3 administrativo no
reescribe las fotografías, goleadores o marcador que realmente se registraron.

### 11.2 Propuestas y disputas

El flujo puede reutilizar los patrones de resultados externos actuales:

```text
submitted -> accepted -> official
          -> change_proposed -> accepted | disputed
          -> disputed -> administrative_review -> official | annulled
```

Cada versión permanece accesible a la autoridad correspondiente. La respuesta pública
solo expone el resultado efectivo y la explicación permitida.

### 11.3 Rebuild

Una decisión que afecta resultados ya computados emite un evento de rebuild con:

- rango de competición/fase afectado;
- revisión de entrada;
- motor y versión;
- snapshots sustituidos;
- nueva revisión y secuencia;
- checksum o resumen determinista.

El rebuild no se ejecuta en el navegador ni durante cada lectura.

### 11.4 Retraso, no-show, aplazamiento y suspensión

Los flujos no se colapsan en un botón de marcador:

```text
PostponementRequest
  requested -> awaiting_response -> approved | denied | expired | withdrawn

LateArrivalIncident
  reported -> arrived_within_policy | arrived_late | escalated_to_no_show

MatchSuspension
  reported -> confirmed -> resume | replay | administrative_resolution | cancelled
```

Un cambio de asistencia `voy -> no voy` no crea por sí solo un no-show. El no-show
competitivo requiere partido, hora del servidor, obligación válida, evidencia y la
autoridad definida. Retraso, incomparecencia, clima, estado del campo y fuerza mayor
usan `reasonCode` distintos.

Una decisión sobre el terreno puede requerir árbitro y delegado de campo; una
resolución posterior puede corresponder al organizador o comité. Esa separación es
configurable en `authorityPolicy`. Los minutos de cortesía y cualquier resultado
administrativo proceden de la revisión o decisión, nunca de constantes universales.

## 12. Calendario y grafo de fases

### 12.1 Grafo

Una competición se expresa como nodos y transiciones:

```text
StageNode
  type: league | group | knockout | series | placement | participation
  ruleRevisionId
  inputs[]
  outputs[]
```

Las transiciones declaran condición, número de plazas, prioridad y destino. Esto
permite representar liga pura, grupos A/B/C, Apertura/Clausura, playoff, consolación o
categorías sin clasificación sin código de motor duplicado.

### 12.2 Generación de jornadas

El servidor genera un borrador reproducible a partir de:

- entradas aceptadas;
- formato y vueltas;
- ventanas y restricciones;
- sedes/disponibilidad si existen;
- semilla persistida si hay sorteo;
- versión del generador.

`TeamAvailabilityConstraint` es una restricción dura: un borrador que la infringe es
inválido salvo `AdministrativeDecision` explícita. `TeamSchedulePreference` es un
objetivo ponderado: el generador intenta satisfacerlo, registra cumplimiento y puede
publicar una opción que no lo cumpla. Día, hora y sede preferidos nunca se traducen
automáticamente en indisponibilidad.

Publicar el calendario es una operación distinta de generarlo. Una regeneración
posterior crea una versión y muestra el diff; no sobrescribe partidos ya jugados.

### 12.3 Sorteos

Todo sorteo DEBE persistir candidatos, restricciones, algoritmo, versión, semilla o
acta externa y resultado. Volver a consultar nunca repite la aleatoriedad.

## 13. Clasificación

### 13.1 Read model canónico

La tabla se calcula en PostgreSQL cuando cambia uno de estos hechos:

- un resultado pasa a oficial;
- una decisión sustituye un resultado;
- se aplica/anula una deducción;
- una entrada se retira o descalifica;
- cambia una regla con efecto autorizado;
- se cierra o reabre una fase mediante decisión.

No se recalcula en cada render ni se persiste desde el navegador.

### 13.2 Contenido del snapshot

```text
competitionId
stageId
ruleRevisionId
sourceRevision
engineVersion
rows[]
tieBreakExplanations[]
generatedAt
serverSequence
```

Cada fila conserva partidos computados, victorias, empates, derrotas, goles, puntos
base, ajustes, puntos efectivos y claves de desempate. Debe poder explicarse por qué
un equipo está por encima de otro sin revelar datos privados.

### 13.3 Empates

Los criterios se aplican en el orden congelado. Un criterio que requiere mini-tabla
recalcula solo el conjunto empatado. Un criterio no disponible debe declarar si se
omite, falla o requiere decisión; no puede caer silenciosamente a un `id` arbitrario.

El orden técnico estable por ID solo sirve para serialización. Nunca decide una plaza
deportiva salvo que la regla publicada lo declare como sorteo ya persistido.

### 13.4 Deportividad opcional

La deportividad es un read model distinto de standings. Solo puede materializarse si
la revisión publica eventos, pesos, fórmula, ámbito y versión. Si una competición
externa muestra una puntuación sin explicar el cálculo, Pachangas IQ no la copia ni
la deduce. `CompetitionSportsmanshipSnapshot` queda desactivado hasta existir una
fórmula aprobada y reproducible.

## 14. Competition Discipline

### 14.1 Hecho disciplinario

`DisciplinaryEvent` conserva:

```text
competitionId
editionId
stageId
canonicalMatchId
teamEntryId
playerProfileId?
officialId?
cardType
reasonCode
minute?
disciplinaryContext: pre_match | in_match | interval | post_match | venue
reportedByAssignmentId
status: active | corrected | cancelled
revision
supersedesId?
```

Corregir jugador, minuto o tarjeta crea una revisión/evento. No se borra el original.

Cada tipo de tarjeta activo define efectos sin asumir semántica por color. Para una
azul, `temporaryDismissalPolicy` puede declarar:

```text
playerRemovedForRemainder
replacementAllowed
releaseConditions:
  - elapsedDuration?
  - opponentGoal?
releaseMode: first_condition | all_conditions | fixed_only | no_replacement
```

Por ello son compatibles azul desactivada, tiempo fijo o liberación por tiempo/gol.
Ninguna variante queda seleccionada como universal en R0.

### 14.2 Sanción

El motor deriva una propuesta de sanción usando la revisión de reglas. Cuando la regla
requiera comité, la propuesta no se vuelve ejecutable hasta una decisión autorizada.

Una sanción distingue:

- causa y eventos fuente;
- alcance por competición/edición/categoría/stage/split/equipo;
- unidad en partidos, jornadas, semanas, fase o expulsión de la competición;
- estado provisional, activa, cumplida, anulada o corregida;
- autoridad y posibilidad de recurso;
- consumos concretos por partido.

Una regla puede producir una sanción fija o un rango recomendado. Si produce rango,
el servidor crea una propuesta y el comité elige dentro de sus límites con artículo,
factores, motivo y auditoría. No se elige automáticamente el mínimo, el máximo o una
cifra enviada por el cliente.

### 14.3 Ciclos y arrastre

`DisciplinaryCycle` define el ámbito de acumulación y puede coincidir con stage,
split, competición o edición. Un reset abre un ciclo nuevo: no borra eventos ni anula
una sanción ya generada. `sanctionCarryPolicy` determina explícitamente si una
consecuencia cruza stage, equipo, competición o temporada.

La fecha de un evento y la pertenencia efectiva del jugador determinan el contador;
no se usa la ficha actual para reinterpretar una temporada histórica.

### 14.4 Consumo

“Siguiente partido” significa el siguiente encuentro elegible que la regla determine,
no el siguiente registro por `created_at`. El servidor consume la sanción al confirmar
participación/cierre del partido aplicable, con operación idempotente.

Aplazamientos, cancelaciones y byes no consumen una sanción salvo regla explícita.

Cada consumo crea un `SanctionServiceEvent` inmutable con unidad, ámbito, partido o
periodo aplicado, revisión y secuencia. Una corrección revierte mediante otro evento;
no incrementa peso ni reinicia contadores como si fuese una sanción nueva.

### 14.5 Apelaciones y visibilidad

`SanctionAppeal` conserva solicitante autorizado, decisión recurrida, deadline exacto
calculado por el servidor, estado, evidencias, historial, resolución, autoridad y
efecto suspensivo. Su lifecycle mínimo es:

```text
draft -> submitted -> admissible -> under_review -> upheld | modified | overturned
                   \-> inadmissible | withdrawn
```

Una apelación fuera de plazo se rechaza explícitamente y permanece auditable. Ningún
plazo concreto, incluido 72 horas, es universal.

El expediente privado conserva evento, evidencia, identidad de actores, artículo,
propuesta, decisión y apelación. `PublicSanctionReadModel` solo publica los campos
permitidos por `publicSanctionPolicy`, por ejemplo estado, ámbito y unidades restantes,
sin evidencias, documentos ni notas privadas. Realtime no expone el expediente.

### 14.6 Frontera con Conduct y Rating

Competition Discipline puede bloquear una alineación. No puede:

- editar GRL, facetas, fiabilidad o assessment;
- crear evidencia de Rating;
- crear automáticamente una sanción social;
- revelar al público un reporte privado de Conduct;
- activar rewards por sí sola.

## 15. Excepciones administrativas

Toda excepción de la matriz A01-A20 se representa mediante:

```text
AdministrativeDecision
  id
  competitionId
  decisionType
  targetType
  targetId
  authorityAssignmentId
  ruleRevisionId
  reasonCode
  reasonText
  evidenceRefs[]
  previousDecisionId?
  effects[]
  status
  revision
  operationId
  serverSequence
  decidedAt
```

`effects[]` contiene órdenes declarativas validadas, no SQL libre. Ejemplos:

```text
SET_OFFICIAL_RESULT
RESCHEDULE_MATCH
RESUME_FROM_MINUTE
ORDER_REPLAY
DEDUCT_POINTS
GRANT_ELIGIBILITY_DISPENSATION
DISQUALIFY_ENTRY
REBUILD_STAGE
CREATE_SANCTION
REVERSE_SANCTION_SERVICE
CREATE_COMPETITION_CHARGE
CREATE_COMPETITION_CREDIT
```

Una decisión no puede producir efectos fuera de las potestades del actor ni del
catálogo permitido para esa competición.

Marcador, puntos, sanción, reincidencia, multa y crédito son efectos independientes.
Una resolución puede producir varios, pero ninguno se infiere de otro. Los dos
efectos económicos solo crean registros declarativos preparados para R10: R1-R6 no
capturan pagos, no modifican saldos ni llaman a Stripe.

Cuota de equipo, licencia/ficha, permiso temporal, multa, crédito y descuento usan
conceptos distintos, revisión propia y enlace a la regla o decisión de origen. La
exención también es una decisión auditada; nunca un borrado del cargo.

## 16. Roles y autoridad

### 16.1 Roles de equipo no equivalen a organización

`owner/admin` de un equipo permite representar a ese equipo donde la política lo
autorice. No permite crear reglas, asignarse árbitro, resolver una protesta o cambiar
el resultado de otro equipo.

El actor que representa al equipo en una edición es `CompetitionTeamDelegate`. La
asignación puede originarse en un owner/admin, una invitación aceptada o una decisión
del organizador, pero siempre tiene permisos contextuales, vigencia y revocación
propios. Aceptarla no eleva al actor dentro de `pachanga_groups`.

### 16.2 Roles de competición

El modelo debe soportar, como mínimo:

```text
competition_owner
competition_admin
registration_manager
scheduler
referee_assigner
disciplinary_committee
appeal_committee
result_official
read_only_auditor
venue_delegate
venue_assistant
referee_coordinator
```

Cada asignación declara competición, categorías/fases opcionales, acciones permitidas,
vigencia, concedente y revisión. Los roles pueden combinarse, pero RLS valida cada
capacidad concreta.

`venue_delegate`, `venue_assistant` y `referee_coordinator` se materializan mediante
`VenueStaffAssignment` limitado por sede, fecha/turno y acciones. Revisar credenciales,
registrar estado del campo o coordinar una sustitución arbitral no concede potestad
para fijar una sanción. `disciplinary_committee` y `appeal_committee` permanecen
separados incluso cuando una misma persona ocupe ambos roles.

### 16.3 Árbitro

Un árbitro asignado puede enviar únicamente los hechos habilitados para ese partido y
momento: acta, resultado, tarjetas, suspensión o incidencias. No obtiene acceso al
teléfono, datos privados, Rating interno o configuración del equipo.

### 16.4 Control interno

El rol de seguridad/plataforma se mantiene separado de organizadores ordinarios. El
Control Center puede inspeccionar auditoría y aplicar guardias internas según su
contrato, sin convertirse en un atajo cliente a tablas privadas.

## 17. Entitlements

R1 debe crear una autoridad de capacidades, por ejemplo:

```text
CREATE_COMPETITION
PUBLISH_COMPETITION
MANAGE_MULTIPLE_COMPETITIONS
ENABLE_REFEREE_MARKETPLACE
ENABLE_ADVANCED_DISCIPLINE
```

La RPC consulta `CompetitionEntitlement`; no lee directamente `billing_status` para
decidir. Billing o una concesión manual auditada pueden alimentar el entitlement,
pero no son la misma entidad.

Requisitos:

- revisión y vigencia;
- origen (`subscription`, `trial`, `manual`, `platform`);
- límites cuantitativos explícitos;
- revocación que no borra historia ni rompe lectura;
- periodo de gracia y estado de solo lectura cuando corresponda;
- ninguna limitación comercial puede anular derechos de reclamación ya abiertos.

### 17.1 Capacidades futuras preparadas, no activadas

El contrato reserva identidades para economía competitiva y cobertura médica porque
las reglas reales pueden vincularlas a licencias, provisionales o incidencias. Esto no
autoriza su implementación en R1:

- `CompetitionFeePolicy`, `CompetitionCharge` y `CompetitionCredit` solo describen
  conceptos y causa hasta R10;
- `CompetitionMedicalCoveragePolicy` y `MatchInjuryIncident` son opcionales y exigen
  análisis jurídico, sanitario, de minimización y retención;
- ni el estado deportivo ni una decisión administrativa ejecutan pagos o diagnostican
  lesiones;
- Billing, Stripe y proveedores médicos siguen siendo autoridades separadas.

## 18. RLS, privacidad y exposición

### 18.1 Principio de mínimo privilegio

- Participantes ven competición, calendario, resultados y datos públicos.
- Un representante de equipo gestiona solo su inscripción, roster y respuestas.
- Un árbitro ve solo asignaciones y datos necesarios para oficiar.
- Un organizador ve únicamente competiciones dentro de su asignación.
- Un comité ve expedientes dentro de su competencia, no perfiles privados completos.
- Documentos, fecha de nacimiento completa y verificaciones viven en esquema/tabla
  privada y se exponen por RPC mínima.

### 18.2 Identidad y documentos

El organizador ordinario consulta el resultado mínimo de verificación necesario para
esa edición, no el documento bruto. Pachangas IQ debe soportar `BASIC`, `PHOTO`,
`VERIFIED_IDENTITY` y, solo tras decisión jurídica y de seguridad, `DOCUMENT_REQUIRED`.

El modo recomendado por defecto guarda `verificationStatus`, `verifiedAt`,
`verifiedBy`, `verificationMethod` y una evidencia opaca protegida. No conserva DNI
completo ni lo incluye en snapshots, Realtime, logs, exportaciones generales o caché
local. La fotografía obligatoria y la conservación documental continúan como
decisiones de producto pendientes.

### 18.3 Menores

Antes de almacenar documentos de menores, R1/R4 requiere una decisión formal de
minimización, finalidad, retención, acceso, borrado legal y base de legitimación. El
motor debe poder guardar un estado `verified` y evidencia opaca sin exponer el
documento a organizadores ordinarios.

### 18.4 Realtime

Realtime publica invalidadores mínimos:

```text
entityType
entityId
revision
serverSequence
eventType público/permitido
```

No incluye documentos, notas privadas, identidad de denunciantes, decisiones en
borrador ni payloads internos de comité.

## 19. Caché local y PWA

La caché es read-through y derivada:

| Entidad | Política orientativa | Invalidación |
| --- | --- | --- |
| Catálogo público/presets | Larga con versión | Nueva versión publicada |
| Competición archivada | Larga/inmutable | Corrección administrativa excepcional |
| Reglamento congelado | Inmutable por ID | Nunca se muta; aparece otra revisión |
| Calendario activo | Corta | Evento de competición/ronda |
| Partido activo | Snapshot actual + Realtime | Evento/revisión del partido |
| Clasificación | Por revisión | Resultado/decisión/rebuild |
| Perfil público de árbitro | Media | Revisión del perfil |
| Documentos privados | No persistir en caché general | N/A |

Una operación offline puede mostrarse como borrador local no enviado, pero no como
tarjeta, resultado, sanción, inscripción, aplazamiento o clasificación confirmados.
No existe cola offline automática de operaciones deportivas.

Un cliente antiguo o incompatible conserva lecturas, bloquea escrituras con
`CLIENT_UPDATE_REQUIRED`, descarta optimistic state y realiza la actualización
controlada del Service Worker según el bridge existente.

## 20. Auditoría y orden canónico

Toda consulta que seleccione “el último” evento, snapshot, decisión o recibo DEBE
ordenar por:

```text
serverSequence
revision
confirmedRevision
o timestamp + identificador estable
```

Queda prohibido depender únicamente de `ORDER BY created_at DESC`.

El historial debe permitir reconstruir:

- qué regla gobernaba cada partido;
- quién hizo y confirmó cada cambio;
- qué resultado deportivo se registró;
- qué decisión produjo el resultado oficial;
- qué tabla se publicó tras cada revisión;
- qué tarjeta originó cada sanción y en qué partido se consumió;
- qué notificaciones e invalidaciones se emitieron.

Los logs no sustituyen eventos y receipts duraderos.

## 21. Notificaciones

Las notificaciones se producen después del commit mediante outbox/eventos duraderos.
No participan en la transacción deportiva salvo para crear el intent.

Categorías iniciales futuras:

```text
competition_registration
schedule_change
match_assignment
result_action_required
disciplinary_action_required
claim_resolution
competition_announcement
```

Los avisos que requieren acción reglamentaria pueden ser `mandatory_in_app`. El
usuario puede configurar push/email si el canal está activo, pero no ocultar el aviso
obligatorio dentro de la aplicación.

## 22. Operación de motores

### 22.1 Escritura por evento

Standings, cuadros, sanciones, elegibilidad y read models se calculan al producirse el
evento pertinente. No se recalculan de forma no versionada en cada lectura.

### 22.2 Versiones de motor

Cada snapshot calculado conserva:

```text
engineName
engineVersion
ruleRevisionId
sourceRevision
generatedAt
serverSequence
```

Cambiar el algoritmo requiere versión nueva, fixtures de regresión y rebuild explícito
si debe afectar datos anteriores.

### 22.3 Fallo parcial

Si una proyección secundaria falla después del commit canónico, queda un trabajo
duradero reintentable y la lectura indica la última revisión materializada. No se
simula éxito con una tabla calculada por el cliente.

## 23. Secuencia de implementación

### R1 - Competition & Organizer Foundation

1. Resolver identidad/binding canónico de partido.
2. Crear `Competition`, `CompetitionEdition`, categorías y reglas/revisiones.
3. Modelar stages/splits, divisiones, grupos y memberships históricas sin generar
   todavía calendario ni cuadro.
4. Crear organizadores, `CompetitionTeamDelegate`, staff de sede, permisos y
   entitlements con ámbito.
5. Crear receipts, eventos, RLS y read models mínimos.
6. Implementar lifecycles y estados operativos sin generar todavía liga o torneo.
7. Añadir presets solo como borradores versionados y no activos por defecto.

### R2 - Club Foundation

1. Crear club y membresías con ámbito.
2. Enlazar equipos existentes sin copiarlos.
3. Separar identidad pública de administración y documentos.

### R3 - Referee Platform

1. Perfil arbitral universal.
2. Verificación privada y modalidades.
3. Asignación y lifecycle.
4. Mercado sin acceso a datos sensibles.

### R4 - League Engine

1. Entradas, rosters, convocatorias, provisionales y equipaciones.
2. Restricciones duras, preferencias y generador de jornadas reproducible.
3. Resultado oficial y standings versionados.
4. Retrasos, aplazamientos, clima/campo, retiradas y rebuild administrativo.

### R5 - Competition Discipline

1. Catálogo de tarjetas, azul configurable y acta.
2. Ciclos, contadores, unidades y ámbitos de sanción configurables.
3. Rangos de comité, correcciones, apelaciones y bloqueo de alineación.
4. Prueba explícita de cero cambios en Rating V2 y Conduct.

### R6 - Tournament Engine

1. Grafo de grupos y cuadros.
2. Sorteos persistidos y bombos.
3. Avance determinista.
4. Prórroga, penaltis, series y colocación.

R7-R10 solo se apoyarán en estas autoridades; no podrán recrear lógica deportiva en
UI, billing, marketplace o rewards.

## 24. Gates de pruebas

### 24.1 Gates comunes de cada release

```text
SQL y RLS
idempotencia
concurrencia
bootstrap desde cero
upgrade desde main productivo
typecheck
build
tests focalizados y completos
git diff --check
QA visual 1440x900, 1920x1080, 390x844, 360x800, 844x390
PWA standalone y cliente obsoleto
Control Center y privacidad
```

### 24.2 Casos mínimos R1

- dos organizadores intentan publicar la misma revisión;
- dos dispositivos editan la competición con la misma revisión;
- replay de `operationId` devuelve el mismo receipt;
- admin de equipo no obtiene rol de competición;
- entitlement caducado bloquea escritura, no lectura;
- Realtime invalida solo la entidad afectada;
- reglamento congelado no admite `UPDATE` ni RPC equivalente;
- un partido de Reto y uno de grupo no pueden duplicar identidad canónica.
- una edición con dos splits conserva memberships distintas al reasignar división;
- delegado de equipo no hereda owner/admin y staff de sede no obtiene potestad de comité;
- no puede publicarse un preset o autoridad que siga pendiente de decisión de producto.

### 24.3 Casos mínimos R4

- calendario par/impar, descansos y local/visitante;
- empate múltiple con mini-tabla;
- varios snapshots en la misma transacción eligen el mismo canónico;
- resultado propuesto, disputado, corregido y anulado;
- no-show normal, fuerza mayor, reincidencia y retirada;
- retraso no se convierte en no-show antes de cumplir la regla y la evidencia;
- indisponibilidad dura bloquea; una preferencia incumplida solo queda explicada;
- permiso provisional repetido no duplica jugador, participante ni cargo;
- conflicto de colores y periodo de gracia proceden de la revisión vigente;
- rebuild por decisión sin modificar marcador deportivo;
- dos resultados concurrentes producen un ganador y un conflicto explícito;
- todos los clientes convergen tras recarga.

### 24.4 Casos mínimos R5

- doble amarilla con y sin suspensión posterior;
- amarillas sin acumulación y con varios umbrales;
- ciclos que se mantienen o reinician entre splits sin borrar sanciones emitidas;
- azul desactivada, fija y liberada por tiempo o gol;
- roja automática, revisada, ampliada y anulada;
- sanción por partido y por semana con consumos inequívocos;
- comité decide dentro de rango y deja motivo/auditoría;
- apelación dentro/fuera de plazo, modificada y anulada, con historial;
- read model público no expone expediente, documentos ni evidencia;
- sanción no consumida por aplazamiento/cancelación;
- alineación rechazada por sanción;
- corrección conserva el evento original;
- tarjeta/sanción produce exactamente cero cambios en Rating V2;
- roja no crea caso de Conduct salvo una acción separada.

### 24.5 Casos mínimos R6

- grupos A/B/C y destinos distintos;
- categoría sin clasificación;
- eliminatoria directa a penaltis;
- prórroga solo en semifinal/final;
- serie al mejor de tres;
- sorteo reproducible y persistido;
- retirada que altera el cuadro mediante decisión auditada;
- ningún avance depende del orden de render o de la hora del dispositivo.

## 25. Observabilidad y seguridad operacional

Cada comando debe registrar métricas sin PII de operación, resultado, latencia,
conflicto, versión de cliente y motor. Las alertas deben distinguir:

- conflicto esperado de revisión;
- violación de permiso;
- regla inválida;
- proyección atrasada;
- fallo de notificación;
- inconsistencia que requiere detener mutaciones.

Para migraciones futuras se registrarán duración, filas, locks, CPU y tamaño de
índices; se usarán `lock_timeout` y `statement_timeout` adecuados, backup restaurable,
staging y umbrales objetivos de parada. Ninguna migración reescribe en sitio reglas o
evidencias históricas.

## 26. Criterios de aceptación del contrato

R0 se considera cerrado porque:

- existe investigación trazable de doce referencias oficiales principales y dos
  contrastes complementarios;
- las 19 áreas mínimas y áreas adicionales están clasificadas;
- `COMMON`, `CONFIGURABLE`, `PRESET` y `ADMINISTRATIVE_EXCEPTION` tienen registros
  explícitos;
- el partido canónico queda protegido frente a duplicación;
- reglas, resultados, standings, disciplina y excepciones tienen lineage;
- toda escritura futura exige `operationId` y revisión esperada;
- Realtime y caché se mantienen como lectura derivada;
- Rating V2, Conduct, Rewards y Billing conservan fronteras explícitas;
- la edición admite stages/splits, divisiones, reasignación y playoff sin duplicar
  partidos;
- delegado de equipo, staff de sede, árbitro, organizador y comité tienen ámbitos
  distintos;
- roster, convocatoria y permiso temporal tienen identidades y estados propios;
- retraso, no-show, aplazamiento, suspensión, cancelación, resultado deportivo y
  resultado oficial no se confunden;
- ciclos, rangos, consumos, apelaciones y publicación disciplinaria están modelados;
- quedan documentadas las decisiones de producto pendientes.

## 27. Trazabilidad normativa del contrato

La matriz conserva el inventario exhaustivo. Esta tabla enlaza las decisiones que
modifican directamente este contrato. `Cerrada como capacidad` no selecciona cifras.

| Regla | Fuente o fuentes | Clasificación | Aplica a liga / torneo / ambas | Decisión cerrada o pendiente |
| --- | --- | --- | --- | --- |
| Partido canónico con contexto | Todas + arquitectura Pachangas | `COMMON` | Ambas | Cerrada |
| Edición -> stage/split -> división/grupo -> ronda -> partido | `RFEF-FS`, `HC`, `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Reasignación de división y playoff | `RFEF-FS`, `FV7` | `CONFIGURABLE` | Liga | Capacidad cerrada; política pendiente |
| Delegado contextual del equipo | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Staff de sede con permisos separados | `FV7`, `FCF` | `COMMON` + `CONFIGURABLE` | Ambas | Autoridad exacta pendiente |
| Equipo -> roster -> convocatoria | `DC`, `IC`, `GC`, `PSG`, `FV7` | `COMMON` | Ambas | Cerrada |
| Permiso temporal por partido | `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Capacidad cerrada; valores pendientes |
| Identidad sin DNI completo por defecto | `IC`, `GC`, `PSG`, `FV7` | `CONFIGURABLE` | Ambas | Principio cerrado; política documental pendiente |
| Equipación, dorsal, conflicto y gracia | `GC`, `MIC`, `FV7` | `CONFIGURABLE` / `PRESET` | Ambas | Valores pendientes |
| Disponibilidad dura distinta de preferencia | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Retraso distinto de no-show | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada; valores pendientes |
| Clima/campo y fuerza mayor | `IFAB`, `FV7`, `FCF` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Workflow cerrado; autoridad pendiente |
| Resultado deportivo distinto del oficial | `IC`, `GC`, `MIC`, `DANA`, `MAD`, `FV7` | `COMMON` | Ambas | Cerrada |
| Efectos administrativos separados | `IC`, `MAD`, `FV7` | `COMMON` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Cerrada; valores pendientes |
| Tarjeta azul por tiempo o gol | `MIC`, `FV7`, `FA` | `CONFIGURABLE` / `PRESET` | Ambas | Variantes pendientes |
| Cinco amarillas y reset entre splits | `FV7` | `CONFIGURABLE` / `PRESET` | Ambas | No adoptado como universal |
| Sanciones por distintas unidades/ámbitos | `FV7`, `FCF` | `CONFIGURABLE` | Ambas | Capacidad cerrada; catálogo pendiente |
| Comité elige dentro de rango | `MIC`, `RFEF-C`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Autoridad exacta pendiente |
| Apelación con deadline e historial | `IC`, `DANA`, `MAD`, `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Workflow cerrado; plazo pendiente |
| Read model público y expediente privado | `FV7` + privacidad Pachangas | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada; campos públicos pendientes |
| Deportividad reproducible | `DC`, `FV7` | `CONFIGURABLE` | Ambas | Fórmula pendiente; desactivada |
| Economía competitiva separada | `IC`, `MAD`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Preparada; diferida a R10 |
| Cobertura médica | `FV7` | `CONFIGURABLE` | Ambas | Capacidad futura opcional |

## 28. Decisiones que deben elevarse antes de implementar

1. Elegir el mecanismo exacto de identidad/binding canónico de partido.
2. Aprobar taxonomía y alcance de roles de competición.
3. Definir política de privacidad, documentos y menores.
4. Decidir cómo representar equipos invitados todavía no registrados.
5. Aprobar el primer conjunto de presets y su procedencia.
6. Definir qué entitlements existen y cómo se conceden sin acoplarlos a Stripe.
7. Decidir los límites de corrección retroactiva y quién puede aprobar un rebuild.
8. Definir visibilidad pública de disciplina, decisiones y actas.
9. Elegir, si existe, el preset seleccionado por defecto.
10. Decidir si un jugador puede participar con varios equipos y en qué ámbito.
11. Decidir cuándo la fotografía es obligatoria.
12. Autorizar o descartar el almacenamiento de documentos de identidad completos.
13. Decidir si una sanción puede pasar a otra fase, competición o temporada.
14. Precisar por acción la autoridad de árbitro, organizador, staff de sede y comité.
15. Elegir qué variantes de tarjeta azul se ofrecerán, sin activar una por defecto.
16. Decidir si existen tasas de reclamación y mantener el recurso aunque no haya cobro.
17. Decidir qué consecuencias económicas pueden automatizarse en R10.
18. Definir qué datos de jugadores, actas y sanciones pueden ser públicos.
19. Decidir si se habilita deportividad y aprobar una fórmula reproducible.
20. Decidir si existe cobertura médica y su contrato jurídico/operativo.

Estas decisiones deben resolverse en la fase indicada por su dominio. No justifican
crear antes una pantalla de “Crear torneo” ni hardcodear una política provisional.

## 29. Veredicto

**Gate de contenido R0 aprobado. Gate de integración pendiente de PR y revisión
humana. League Engine y Tournament Engine siguen sin implementar.**

R1 no queda autorizado por este commit. Después de revisar y fusionar el PR
exclusivamente documental, el siguiente bloque será Competition & Organizer
Foundation: reglamentos versionados, ediciones, stages/splits, divisiones,
organizadores, permisos y entitlements. R1 deberá demostrar en tests que extiende las
autoridades actuales y no crea una segunda fuente de verdad; no comenzará por el
calendario ni por una pantalla “Crear torneo”.
