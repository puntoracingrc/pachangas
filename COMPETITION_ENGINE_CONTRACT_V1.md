# Competition Engine Contract V1

Estado: `CONTRATO NORMATIVO R0 - SIN IMPLEMENTACION PRODUCTIVA`

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
| `Competition` | Identidad, modalidad, organizador, temporada y lifecycle | Sí |
| `CompetitionRuleSet` | Familia lógica de reglas | Sí |
| `CompetitionRuleRevision` | Configuración inmutable y fecha efectiva | Sí |
| `CompetitionCategory` | Edad/género/nivel y reglas aplicables | Sí |
| `CompetitionStage` | Grupo, liga, knockout, serie o participación | Sí |
| `CompetitionEntry` | Solicitud/aceptación de un equipo | Sí |
| `CompetitionRoster` | Plantilla del equipo para categoría/temporada | Sí |
| `CompetitionRosterMember` | Elegibilidad contextual del jugador | Sí |
| `CompetitionRound` | Jornada o ronda programable | Sí |
| `CompetitionMatchContext` | Enlace entre partido canónico, fase, ronda y reglas | Sí |
| `MatchSheet` | Participantes, oficiales y hechos del partido | Sí |
| `OfficialResultDecision` | Resultado que computa y su procedencia | Sí |
| `StandingSnapshot` | Tabla materializada y reconstruible | Sí |
| `DisciplinaryEvent` | Tarjeta u otro hecho deportivo original | Sí |
| `CompetitionSanction` | Consecuencia consumible del reglamento/comité | Sí |
| `AdministrativeDecision` | Excepción motivada que produce efectos | Sí |
| `RefereeProfile` | Faceta arbitral universal, separada de jugador | Sí |
| `RefereeAssignment` | Designación para partido y estado | Sí |
| `Club` | Organización que puede agrupar equipos y staff | Sí |
| `ClubMembership` | Relación persona-club con ámbito | Sí |
| `CompetitionStaffAssignment` | Rol de organización en una competición | Sí |
| `CompetitionEntitlement` | Capacidad comercial/operativa concedida | Sí |
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
  matchSheetPolicy

structure
  stageGraph
  roundGenerationPolicy
  advancementRules

results
  scoringPolicy
  tieBreakCriteria
  knockoutResolutionPolicy
  publicationPolicy

operations
  postponementPolicy
  noShowPolicy
  suspendedMatchPolicy
  withdrawalPolicy

discipline
  cardTypeCatalog
  accumulationRules
  dismissalPolicy
  sanctionCarryPolicy

governance
  authorityPolicy
  claimPolicy
  appealPolicy
  refereeAssignmentPolicy
```

### 6.3 Validación estructural

Antes de publicar, el servidor DEBE comprobar al menos:

- todos los nodos del grafo de fases son alcanzables o están marcados como
  opcionales;
- todo destino de avance existe y no genera ciclos no declarados;
- la puntuación y los desempates son deterministas;
- el último criterio de desempate termina o crea una decisión persistida;
- los mínimos no superan los máximos de roster/acta/campo;
- las ventanas no se solapan de forma ambigua;
- cada tarjeta activa tiene efecto inmediato definido;
- toda sanción tiene alcance y forma de consumo;
- toda excepción tiene una autoridad capaz de resolverla;
- una categoría sin tabla no publica standings ni concede avance por clasificación;
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

### 8.1 Competición

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

### 8.4 Jornada/ronda

```text
draft -> published -> in_progress -> completed -> locked
```

Una ronda `locked` solo cambia mediante decisión administrativa y rebuild.

### 8.5 Contexto de partido

El contexto amplía, no sustituye, los estados canónicos existentes:

```text
scheduled
postponed
ready
in_progress
played
suspended
abandoned
result_pending
official
cancelled
```

La traducción entre estos estados y los estados actuales
`draft/published/lineup_open/lineup_closed/played/finalized/historical` debe definirse
en R1 como una máquina explícita, sin inferencias por fecha.

### 8.6 Asignación arbitral

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
categoryId
stageId
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

También puede conservar `legNumber`, `seriesId`, `groupId`, `bracketSlotId` o
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

## 14. Competition Discipline

### 14.1 Hecho disciplinario

`DisciplinaryEvent` conserva:

```text
competitionId
canonicalMatchId
teamEntryId
playerProfileId?
officialId?
cardType
reasonCode
minute?
reportedByAssignmentId
status: active | corrected | cancelled
revision
supersedesId?
```

Corregir jugador, minuto o tarjeta crea una revisión/evento. No se borra el original.

### 14.2 Sanción

El motor deriva una propuesta de sanción usando la revisión de reglas. Cuando la regla
requiera comité, la propuesta no se vuelve ejecutable hasta una decisión autorizada.

Una sanción distingue:

- causa y eventos fuente;
- alcance por competición/categoría/fase;
- partidos a cumplir o ventana temporal;
- estado provisional, activa, cumplida, anulada o corregida;
- autoridad y posibilidad de recurso;
- consumos concretos por partido.

### 14.3 Consumo

“Siguiente partido” significa el siguiente encuentro elegible que la regla determine,
no el siguiente registro por `created_at`. El servidor consume la sanción al confirmar
participación/cierre del partido aplicable, con operación idempotente.

Aplazamientos, cancelaciones y byes no consumen una sanción salvo regla explícita.

### 14.4 Frontera con Conduct y Rating

Competition Discipline puede bloquear una alineación. No puede:

- editar GRL, facetas, fiabilidad o assessment;
- crear evidencia de Rating;
- crear automáticamente una sanción social;
- revelar al público un reporte privado de Conduct;
- activar rewards por sí sola.

## 15. Excepciones administrativas

Toda excepción de la matriz A01-A12 se representa mediante:

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
```

Una decisión no puede producir efectos fuera de las potestades del actor ni del
catálogo permitido para esa competición.

## 16. Roles y autoridad

### 16.1 Roles de equipo no equivalen a organización

`owner/admin` de un equipo permite representar a ese equipo donde la política lo
autorice. No permite crear reglas, asignarse árbitro, resolver una protesta o cambiar
el resultado de otro equipo.

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
```

Cada asignación declara competición, categorías/fases opcionales, acciones permitidas,
vigencia, concedente y revisión. Los roles pueden combinarse, pero RLS valida cada
capacidad concreta.

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

## 18. RLS, privacidad y exposición

### 18.1 Principio de mínimo privilegio

- Participantes ven competición, calendario, resultados y datos públicos.
- Un representante de equipo gestiona solo su inscripción, roster y respuestas.
- Un árbitro ve solo asignaciones y datos necesarios para oficiar.
- Un organizador ve únicamente competiciones dentro de su asignación.
- Un comité ve expedientes dentro de su competencia, no perfiles privados completos.
- Documentos, fecha de nacimiento completa y verificaciones viven en esquema/tabla
  privada y se exponen por RPC mínima.

### 18.2 Menores

Antes de almacenar documentos de menores, R1/R4 requiere una decisión formal de
minimización, finalidad, retención, acceso, borrado legal y base de legitimación. El
motor debe poder guardar un estado `verified` y evidencia opaca sin exponer el
documento a organizadores ordinarios.

### 18.3 Realtime

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
2. Crear competición, categorías, reglas/revisiones, roles y entitlements.
3. Crear receipts, eventos, RLS y read models mínimos.
4. Implementar lifecycle sin generar todavía liga o torneo.
5. Añadir presets solo como borradores versionados y no activos por defecto.

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

1. Entradas y rosters.
2. Generador de jornadas reproducible.
3. Resultado oficial y standings versionados.
4. Aplazamientos, retiradas y rebuild administrativo.

### R5 - Competition Discipline

1. Catálogo de tarjetas y acta.
2. Acumulación/sanciones configurables.
3. Correcciones, recursos y bloqueo de alineación.
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

### 24.3 Casos mínimos R4

- calendario par/impar, descansos y local/visitante;
- empate múltiple con mini-tabla;
- varios snapshots en la misma transacción eligen el mismo canónico;
- resultado propuesto, disputado, corregido y anulado;
- no-show normal, fuerza mayor, reincidencia y retirada;
- rebuild por decisión sin modificar marcador deportivo;
- dos resultados concurrentes producen un ganador y un conflicto explícito;
- todos los clientes convergen tras recarga.

### 24.4 Casos mínimos R5

- doble amarilla con y sin suspensión posterior;
- amarillas sin acumulación y con varios umbrales;
- roja automática, revisada, ampliada y anulada;
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

- existe investigación trazable de once referencias oficiales;
- las 19 áreas mínimas y áreas adicionales están clasificadas;
- `COMMON`, `CONFIGURABLE`, `PRESET` y `ADMINISTRATIVE_EXCEPTION` tienen registros
  explícitos;
- el partido canónico queda protegido frente a duplicación;
- reglas, resultados, standings, disciplina y excepciones tienen lineage;
- toda escritura futura exige `operationId` y revisión esperada;
- Realtime y caché se mantienen como lectura derivada;
- Rating V2, Conduct, Rewards y Billing conservan fronteras explícitas;
- quedan documentadas las decisiones de producto pendientes.

## 27. Decisiones que R1 debe elevar antes de implementar

1. Elegir el mecanismo exacto de identidad/binding canónico de partido.
2. Aprobar taxonomía y alcance de roles de competición.
3. Definir política de privacidad, documentos y menores.
4. Decidir cómo representar equipos invitados todavía no registrados.
5. Aprobar el primer conjunto de presets y su procedencia.
6. Definir qué entitlements existen y cómo se conceden sin acoplarlos a Stripe.
7. Decidir los límites de corrección retroactiva y quién puede aprobar un rebuild.
8. Definir visibilidad pública de disciplina, decisiones y actas.

Estas decisiones deben resolverse dentro de R1/R3/R4 según corresponda. No justifican
crear antes una pantalla de “Crear torneo” ni hardcodear una política provisional.

## 28. Veredicto

**Gate R0 aprobado. League Engine y Tournament Engine siguen sin implementar.**

El siguiente bloque autorizado por el roadbook es R1, empezando por Competition &
Organizer Foundation y Competition Entitlements. R1 deberá demostrar en tests que
extiende las autoridades actuales y no crea una segunda fuente de verdad.
