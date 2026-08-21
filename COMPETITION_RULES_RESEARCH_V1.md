# Competition Rules Research V1

Estado: `R0 RECONCILIADO - CONTENIDO CERRADO, REVISION HUMANA EN PR PENDIENTE`

## 1. Trazabilidad

| Dato | Valor |
| --- | --- |
| Proyecto | Pachangas IQ |
| Rama | `codex/competition-rules-research-v1` |
| Commit base | `d5ac022ea5aeabb4f9e6105756acf18a4d6c954c` |
| Fecha | 2026-08-21, `Europe/Madrid` |
| Alcance | Bloque R0 del roadbook de competiciones, clubes y árbitros |
| Código consultado | Repositorio local en un worktree aislado |
| Fuentes externas | Reglamentos y páginas oficiales públicas enlazadas en este documento |
| Servicios y datos | No se consultó ni modificó Supabase remoto; no se modificó producción |
| Cambios de producto | Ninguno: esta fase solo crea investigación, matriz y contrato |

Este documento es una investigación de producto e ingeniería, no una interpretación
jurídica de los reglamentos. Los textos oficiales mandan en cada competición. Las
reglas se registran como fotografía de las versiones públicas consultadas y no deben
convertirse en valores universales sin una revisión posterior de la fuente vigente.

## 2. Pregunta de investigación

El objetivo no era encontrar un reglamento que Pachangas IQ pudiera copiar. Era
responder cuatro preguntas antes de construir el motor:

1. ¿Qué conceptos aparecen en prácticamente todas las competiciones?
2. ¿Qué valores cambian entre organizaciones, categorías o fases?
3. ¿Qué combinaciones conviene ofrecer como presets editables?
4. ¿Qué situaciones solo puede resolver una autoridad mediante una decisión
   administrativa auditada?

La conclusión principal es clara: el dominio común es estable, pero los valores y
procedimientos no lo son. Puntuación, desempates, composición de fases, penaltis,
plantillas, sustituciones, tarjetas, incomparecencias, protestas y correcciones deben
ser datos versionados, nunca constantes repartidas por el frontend o SQL.

## 3. Método

- Se seleccionaron doce referencias oficiales principales de torneos internacionales, fútbol
  base, fútbol amateur municipal, fútbol sala federativo y las Laws of the Game.
- Se añadieron como contraste complementario el Reglamento General de la Federación
  Catalana y las reglas de fútbol reducido de The FA.
- Se compararon reglas de inscripción, identidad, plantilla, acta, puntuación,
  desempates, fases, disciplina, incomparecencias, partidos suspendidos,
  reclamaciones y autoridad.
- Se auditó el modelo real de Pachangas IQ para separar capacidades reutilizables de
  huecos nuevos.
- Cada hallazgo se trasladó a `COMPETITION_RULES_MATRIX_V1.md` como `COMMON`,
  `CONFIGURABLE`, `PRESET` o `ADMINISTRATIVE_EXCEPTION`.
- El resultado normativo para las siguientes fases se fija en
  `COMPETITION_ENGINE_CONTRACT_V1.md`.

## 4. Catálogo de referencias oficiales

Todas las fuentes se consultaron el 21 de agosto de 2026.

| Código | Competición / autoridad | Temporada o versión | Aporta especialmente | Fuente oficial |
| --- | --- | --- | --- | --- |
| `DC` | Donosti Cup | Reglamento publicado vigente | Grupos, Champions/Europa, fair play, plantillas, no-show | [Reglamento Donosti Cup](https://www.donosticup.com/es/reglamento-0) |
| `IC` | IberCup Cascais | 2027 | Tres cuadros, acreditación, protestas, sanciones y cambios organizativos | [IberCup Regulation](https://cascais.ibercup.com/en/informations/regulation) |
| `GC` | Gothia Cup | 2026 | Cuadros A/B, dispensas por edad, abandono e interrupción | [Gothia Cup Regulations](https://gothiacup.se/app/regulation) |
| `MIC` | MICFootball | 2027 | Base RFEF/FCF, comité, elegibilidad y tarjeta azul desactivada | [Reglamento MICFootball](https://micfootball.com/reglamento/) |
| `DANA` | Dana Cup | 2026 | Prórroga según ronda, sanción, protestas y cambios de horario | [Dana Cup Tournament Rules](https://www.danacup.dk/en/tournament/tournament-rules/) |
| `PSG` | Piteå Summer Games | 2026 | Congelación de listas, categorías sin clasificación y walkover | [Tournament Regulations](https://pitea.cupmanager.net/en/tournament-regulations-2026) |
| `HC` | Helsinki Cup | 2026 | Formatos y publicación distintos por edad y nivel | [Tournament Guide 2026](https://helsinkicup.fi/wp-content/uploads/2026/05/HelsinkiCup_Turnausesite_2026_ENG_v2.pdf) |
| `IFAB` | IFAB | Laws 2026/27 | Leyes base y modificaciones permitidas a organizadores | [Latest law changes](https://www.theifab.com/law-changes/latest/) y [General modifications](https://www.theifab.com/laws/latest/general-modifications/) |
| `RFEF-C` | RFEF | Reglamento de Competiciones 2025 | Marco organizativo, órganos y potestad reglamentaria | [Reglamentos RFEF](https://rfef.es/es/federacion/normativas-y-circulares/reglamentos) |
| `RFEF-FS` | RFEF Liga Prime Futsal | 2026/27 | Liga por aperturas, playoffs, elegibilidad y desempates de fase | [Normas Primera División FS](https://rfef.es/sites/default/files/2026-06/1._FS_-_Primera_Division.pdf) |
| `MAD` | Juegos Deportivos Municipales de Madrid | 2026/27 | Liga amateur, aplazamientos, no-show, alineación indebida y recursos | [Normativa 47 JDM](https://sede.madrid.es/csvfiles/UnidadesDescentralizadas/UDCBOAM/Contenidos/Boletin/2026/Julio/Ficheros%20PDF/BOAM_10181_30072026134637088.pdf) |
| `FV7` | Fundació Valldor7 | 2025/26 y reglamentos publicados | Splits, divisiones, delegados, operación semanal, provisionales, disciplina y economía | [Competiciones](https://virtual.fundaciovalldor7.com/competicions), [documentos](https://virtual.fundaciovalldor7.com/santa-perpetua-es-24-25/documentos), [reglamento interno](https://fundaciovalldor7.com/?download_id=4604&sdm_process_download=1) y [condiciones](https://virtual.fundaciovalldor7.com/cornella-hospitalet-f7-es-25-26_ca/competicio/inscripcio) |

Fuentes oficiales complementarias, usadas para contrastar autoridad y variantes pero
no contadas dentro de la muestra principal de doce:

| Código | Autoridad | Aporta | Fuente oficial |
| --- | --- | --- | --- |
| `FCF` | Federación Catalana de Fútbol | Suspensión, fuerza mayor y decisión del órgano competente | [Reglament General](https://files.fcf.cat/documentos/reglamentgeneral14.pdf) |
| `FA` | The Football Association | Tarjeta azul como exclusión temporal en small-sided football | [Law 12: Fouls and Misconduct](https://www.thefa.com/football-rules-governance/lawsandrules/laws/football-5-5/law-12---fouls-and-misconduct) |

## 5. Evidencia por referencia

### 5.1 Donosti Cup (`DC`)

- Aplica reglas FIFA/RFEF con modificaciones del torneo.
- Usa liguillas de cuatro o cinco equipos a una vuelta.
- Fútbol 11 emplea tres puntos por victoria, uno por empate y cero por derrota;
  otras modalidades pueden puntuar por periodos y no deben heredar esa fórmula.
- El orden de desempate combina enfrentamiento directo, diferencia general,
  fair play, goles y, en último término, sorteo informático, con diferencias por
  modalidad.
- La posición de grupo decide el destino entre cuadros Champions, Europa o
  eliminación.
- Una eliminatoria empatada puede ir directamente a una tanda corta de penaltis.
- No existe un máximo único de plantilla de torneo, pero sí un máximo de jugadores
  en el acta de cada partido y reglas propias de sustitución.
- Las dispensas de edad y género son explícitas y requieren autorización.
- Las amarillas no se acumulan; una roja sí puede generar uno o más partidos de
  suspensión según el comité.
- El fair play tiene una escala propia de puntos disciplinarios.
- Una incomparecencia tras el periodo de cortesía puede producir un 0-3, salvo que
  la organización reconozca fuerza mayor.
- Si un equipo queda por debajo del mínimo de jugadores, el comité decide el efecto
  deportivo. No es una simple operación aritmética del marcador.

### 5.2 IberCup Cascais (`IC`)

- Los grupos pueden contener entre cuatro y seis equipos.
- El desempate usa una secuencia distinta: diferencia de goles, goles marcados,
  enfrentamiento directo, victorias y edad media más joven.
- La categoría y la posición pueden conducir a cuadros Gold, Silver o Bronze.
- Una retirada o descalificación puede reescribir administrativamente todos los
  resultados de la fase de grupos como 0-3.
- Las eliminatorias no usan prórroga y pasan a cinco penaltis más muerte súbita.
- El acta se valida antes del partido y la inclusión en ella tiene significado de
  participación según el reglamento.
- La inscripción requiere identidad, fecha de nacimiento, foto y documentación,
  con plazos y controles de acreditación.
- La falta de acreditación puede tener una sanción de puntos y bloquear la siguiente
  participación.
- Las amarillas no se acumulan. La consecuencia de una roja depende también del
  informe arbitral y del formato de juego.
- Las protestas tienen plazo y depósito económico; no reabren decisiones de hecho
  del árbitro.
- El no-show puede implicar 0-3 y multa, pero un retraso verificado puede permitir
  espera, aplazamiento o reprogramación.
- La organización conserva potestad para modificar campos, horarios y calendario.

### 5.3 Gothia Cup (`GC`)

- Mantiene el patrón de grupos de cuatro o cinco equipos y 3/1/0, pero su último
  desempate puede resolverse por tanda de penaltis.
- Los primeros clasificados acceden al playoff A y los restantes al B.
- La lista general y la convocatoria de partido tienen límites diferentes.
- La identificación, la foto y los controles de edad son parte de la elegibilidad.
- Las dispensas cambian según modalidad y categoría.
- Una roja suspende al menos el siguiente partido y el jurado puede ampliar la
  sanción; las amarillas no se acumulan.
- Utilizar un jugador suspendido puede convertir el resultado en un 0-3
  administrativo.
- La reiteración de incomparecencias puede terminar en exclusión.
- Ante un partido interrumpido, el jurado puede ordenar repetición, reanudación,
  tanda, fijación de resultado o derrota administrativa.
- Las protestas tienen plazo y depósito; el jurado resuelve de forma definitiva.

### 5.4 MICFootball (`MIC`)

- Parte de RFEF y Federación Catalana, pero mantiene modificaciones propias.
- Exige registro y acreditación para participar.
- Las excepciones por edad dependen de la categoría.
- Un comité con representación organizativa, arbitral y federativa resuelve por
  escrito las incidencias y sus decisiones son finales dentro del torneo.
- La alineación de un jugador inelegible o suspendido puede imponer un 0-3.
- La doble amarilla expulsa durante el partido.
- La tarjeta azul está expresamente desactivada en esta edición; por tanto, un tipo
  de tarjeta no puede asumirse activo solo porque el motor lo soporte.
- La expulsión y la suspensión posterior no son idénticas: algunas expulsiones
  pueden revisarse sin arrastre al siguiente encuentro.

### 5.5 Dana Cup (`DANA`)

- Usa grupos de cuatro o cinco, puntuación 3/1/0 y cuadros A/B.
- El desempate combina diferencia, goles, enfrentamiento directo y sorteo.
- Las primeras eliminatorias van a penaltis; semifinales y finales pueden incorporar
  una prórroga corta antes de la tanda.
- Los límites de convocatoria y sustitución dependen de la modalidad.
- Existe mínimo de jugadores y tolerancia de retraso, con potestad del jurado para
  reconocer fuerza mayor.
- La roja conlleva una suspensión mínima y puede ampliarse; las amarillas no se
  acumulan.
- La incomparecencia produce un resultado administrativo y, en fase inicial, una
  omisión puede obligar a recalcular resultados anteriores.
- Una protesta exige plazo corto y depósito; los hechos arbitrales son finales.
- El organizador puede cambiar grupos, campos y horarios.

### 5.6 Piteå Summer Games (`PSG`)

- Combina grupos y eliminatorias, con 3/1/0 y un orden de desempate propio.
- Algunas categorías de iniciación no publican puntos, clasificación ni playoff.
  El motor necesita un modo de participación sin tabla, no una tabla ocultada en el
  cliente.
- La lista puede quedar congelada en el check-in y se complementa con una alineación
  por partido.
- Se restringe que un jugador participe en varios equipos de la misma categoría.
- La tanda tiene una cantidad definida de lanzamientos seguida de muerte súbita.
- La incomparecencia y, especialmente, su reiteración pueden causar exclusión.
- Un abandono deliberado puede recibir un tratamiento distinto de un retraso o una
  ausencia por fuerza mayor.
- El jurado dispone de varias resoluciones posibles para partidos interrumpidos.
- Las rojas generan suspensión revisable y las advertencias no se acumulan.

### 5.7 Helsinki Cup (`HC`)

- La estructura cambia por edad y nivel: hay categorías sin clasificación, otras con
  liguilla y una sola colocación, y otras con finales A/B/C.
- El organizador puede reasignar nivel o combinar series para equilibrar el cuadro.
- Formato de campo, número de jugadores y duración varían entre 5v5, 7v7, 8v8 y
  11v11.
- La resolución de empates no es única para todas las fases.
- Esta fuente impide modelar “torneo” como un único árbol fijo y confirma que el
  grafo de fases debe pertenecer a la versión de reglas de cada categoría.

### 5.8 IFAB (`IFAB`)

- Las Laws of the Game son la base del partido, pero autorizan modificaciones en
  fútbol juvenil, veterano, discapacidad y grassroots sobre tamaño de campo,
  duración, número de jugadores, sustituciones de retorno y otras materias.
- La autoridad de la competición puede determinar el tratamiento de un partido
  abandonado, además de la responsabilidad deportiva que describen las Laws.
- IFAB aporta el vocabulario común del juego; no sustituye el reglamento de
  competición para puntos, inscripción, fases, protestas o sanciones acumuladas.

### 5.9 Reglamento de Competiciones RFEF (`RFEF-C`)

- El reglamento organiza en libros el marco de competición, participantes, órganos y
  procedimientos.
- Distingue organización de la competición, función arbitral y órganos con potestad
  disciplinaria o resolutiva.
- Para Pachangas IQ, la conclusión útil es estructural: actor, autoridad y ámbito
  deben quedar explícitos; no basta con un booleano `isAdmin` del equipo.

### 5.10 RFEF Liga Prime Futsal (`RFEF-FS`)

- Una competición de liga puede contener varias fases con identidad propia: Apertura
  y Clausura a una vuelta, seguidas de playoffs al mejor de varios partidos.
- La puntuación regular es 3/1/0, pero los desempates cambian entre clasificación
  agregada, fase individual y eliminatoria.
- Algunos desempates pueden llegar a un partido adicional, faltas acumuladas o edad
  media, mostrando que no todos los criterios son una columna numérica simple.
- La exclusión o doble incomparecencia puede alterar partidos futuros y la tabla.
- La inscripción depende de requisitos deportivos, jurídicos, económicos, de campo
  y licencias.
- El acta solo admite personal autorizado y la designación arbitral tiene su propio
  ámbito administrativo y económico.

### 5.11 Juegos Deportivos Municipales de Madrid (`MAD`)

- Articula inscripciones, fases, disciplina y recursos para múltiples deportes y
  categorías de competición local.
- La documentación identificativa admitida varía por edad y situación.
- En determinados formatos, la primera incomparecencia supone derrota y deducción de
  puntos; una segunda puede excluir. En formatos a una sola vuelta, la primera puede
  ser suficiente para excluir.
- Un partido suspendido puede resolverse de forma distinta según quién sea
  responsable.
- Los aplazamientos exigen una solicitud formal y un plazo previo.
- Las reclamaciones y recursos tienen canales y vencimientos definidos.
- Una alineación indebida puede producir pérdida administrativa, deducción de puntos
  y sanciones, pero el resultado previo puede influir en la corrección concreta.
- Las tarifas y la cantidad de árbitros cambian por modalidad.

### 5.12 Fundació Valldor7 (`FV7`)

Valldor7 es la referencia más próxima al funcionamiento semanal que Pachangas IQ
quiere soportar. Combina ligas largas, torneos, varias sedes, F7 y fútbol sala con un
portal público de resultados, equipos, sanciones y estadísticas.

- Una edición puede contener dos splits, divisiones/grupos distintos y un playoff
  posterior. La jerarquía necesaria es `CompetitionEdition -> Stage/Split ->
  Division/Group -> Matchday/Round -> CanonicalMatch`.
- El delegado de un equipo dentro de una competición es una responsabilidad propia.
  No tiene por qué ser owner global del equipo ni recibir todos sus permisos.
- Se distinguen equipo habitual, plantilla inscrita y convocatoria de partido.
  Además existe un permiso de jugador provisional por encuentro.
- Los reglamentos publicados muestran que límites y precios de provisionales han
  cambiado entre versiones. Esto confirma que máximo, coste, identidad y cobertura
  pertenecen a la revisión de la edición, no al código.
- La web pública expone split, división, grupo, jornada, instalación, campo,
  participantes, no participantes, cuerpo técnico, uniformes y eventos del partido.
- Disponibilidad obligatoria y preferencia de día, hora o sede son datos distintos.
- Delegado de campo, auxiliares, coordinador arbitral y comité necesitan permisos
  acotados que no equivalen a editar resultado o sanción.
- Un retraso puede iniciar el cronómetro y dejar al rival u organización elegir entre
  jugar menos tiempo o una resolución administrativa. No todo retraso es no-show.
- Una incomparecencia puede producir a la vez resultado oficial, ajuste de puntos,
  multa, crédito y contador de reincidencia. El marcador no puede representar por sí
  solo todos esos efectos.
- La política meteorológica y la suspensión sobre el terreno pueden exigir decisión
  conjunta de delegado de campo y árbitro.
- La tarjeta azul publicada permite sustitución al cumplirse una duración o al
  recibirse un gol. No se modela correctamente con un único número de minutos.
- La acumulación puede reiniciarse entre splits sin borrar una sanción ya generada.
- Una sanción puede medirse en partidos o en semanas, y su ámbito puede depender de
  si una persona participa en varios equipos.
- Los artículos sancionadores usan rangos que requieren decisión motivada de comité,
  no siempre una consecuencia automática fija.
- La disciplina puede abarcar prepartido, descanso, postpartido, instalaciones y
  espectadores asociados a un equipo.
- El portal separa una lista pública de sancionados y partidos restantes del detalle
  privado de evidencia, artículo, decisión y apelación.
- Valldor7 publica deportividad, pero no se localizó su fórmula. Pachangas IQ puede
  preparar un snapshot opcional, pero no copiar ni deducir una puntuación opaca.
- Cuota de equipo, fichas, provisionales, multas, créditos y descuentos demuestran
  que la economía futura necesita conceptos separados y versionados.
- La cobertura médica ligada a la ficha es una capacidad opcional futura, no parte
  del núcleo de League Engine V1.

Dos límites de evidencia quedan expresos. No se localizó el contenido vigente y
completo de su reglamento específico de aplazamientos, por lo que no se adopta ningún
plazo atribuido a Valldor7. Tampoco se conoce la fórmula pública de deportividad.

### 5.13 Contrastes complementarios (`FCF`, `FA`)

- La FCF confirma que el árbitro puede suspender por estado del campo,
  incomparecencia, inferioridad, incidentes, retirada o fuerza mayor, mientras el
  órgano competente revisa y resuelve las consecuencias.
- The FA usa tarjeta azul como exclusión temporal de dos minutos en su reglamento de
  fútbol reducido. Frente a la variante por duración o gol de Valldor7 y la ausencia
  de azul en MIC, demuestra que “tarjeta azul” es una familia configurable, no una
  semántica universal.

## 6. Comparación transversal

| Área | Patrón común | Variación demostrada | Consecuencia de diseño |
| --- | --- | --- | --- |
| Identidad | Se valida quién puede jugar | Documento, foto, edad y momento de control varían | Política de identificación por categoría y datos privados separados |
| Plantilla | Existe una lista elegible y una convocatoria | Abierta, congelada, ilimitada o limitada; altas con plazos | Plantilla versionada y convocatorias por partido |
| Fases | Los partidos pertenecen a una estructura | Liga, grupos, cuadros A/B/C, series, participación sin tabla | Grafo de fases, no enum fijo de “liga/torneo” |
| Puntos | Una fase competitiva asigna puntos | 3/1/0, puntos por periodos, deducciones, sin puntos | Estrategia de puntuación versionada |
| Desempate | El orden debe ser determinista | H2H, diferencia, goles, victorias, fair play, edad, sorteo, partido | Lista ordenada de criterios con parámetros |
| Eliminatoria | Debe existir una resolución | Directo a 3 o 5 penaltis, prórroga solo en ciertas rondas, serie | Regla por fase/ronda |
| Incomparecencia | Requiere una consecuencia oficial | Cortesías distintas, 0-3, multa, puntos, exclusión, fuerza mayor | Incidente + decisión administrativa, nunca solo marcador automático |
| Tarjetas | Se registran hechos arbitrales | Amarilla sin acumulación, umbrales, doble amarilla, azul activa/inactiva | Catálogo y política disciplinaria por revisión |
| Roja | Expulsión y sanción son conceptos distintos | Siguiente partido automático, revisión, extensión o sin arrastre | Evento, decisión y consumo de sanción separados |
| Partido interrumpido | No siempre tiene resultado deportivo final | Reanudar, repetir, tanda, fijar resultado, derrota | Resultado deportivo separado del resultado oficial |
| Protesta | Hay plazo y autoridad | Depósito, canal, hechos no recurribles, uno o dos niveles | Flujo configurable y resolución inmutable |
| Organizador | Puede resolver excepciones | Calendario, sedes, dispensas, fuerza mayor, exclusiones | Roles de competición y decisiones auditadas |
| Edición y splits | Una temporada puede contener fases sucesivas | Dos splits, divisiones reasignadas y playoff | Jerarquía versionada por edición y memberships históricos |
| Delegados y staff | Hay responsables operativos con ámbito | Delegado de equipo, campo, auxiliar, coordinador, comité | Asignaciones y permisos separados del admin global |
| Provisionales | Un jugador puntual requiere elegibilidad | Máximo, coste, documento, cobertura y excepción varían | Permiso por partido, revisionado y auditable |
| Equipaciones | Uniforme y dorsal pueden ser requisito | Periodo de gracia y resolución de colores cambian | Kits contextuales y conflicto previo al partido |
| Calendario semanal | Restricción y preferencia no son lo mismo | Días, horas, sedes y pesos | Restricciones duras separadas de objetivos de optimización |
| Retraso | Es un incidente previo al no-show | Cortesía, reloj, partido acortado o walkover | Workflow propio y autoridad configurable |
| Tarjeta azul | El tipo no determina un único efecto | Desactivada, tiempo fijo, tiempo o gol, sustitución | Política de evento y liberación por condiciones |
| Sanción | La consecuencia tiene unidad y ámbito | Partidos, jornadas, semanas, fase o expulsión | Ledger y consumos, no un solo contador global |
| Visibilidad disciplinaria | Parte del estado puede ser público | Lista resumida frente a expediente privado | Read models público y privado separados |
| Economía | Una resolución puede tener efectos no deportivos | Cuota, ficha, multa, crédito y descuento | Efectos declarativos preparados para R10, no cobro en R1 |

### 6.1 Trazabilidad de decisiones reconciliadas

La tabla completa y estable está en `COMPETITION_RULES_MATRIX_V1.md`. Esta síntesis
demuestra que ninguna cifra observada se convierte en regla universal.

| Regla o decisión | Fuente(s) | Clasificación | Ámbito | Estado |
| --- | --- | --- | --- | --- |
| Partido canónico con contexto competitivo | Todas + arquitectura Pachangas | `COMMON` | Liga y torneo | Cerrada |
| Edición con stages/splits y divisiones | `RFEF-FS`, `HC`, `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Delegado por inscripción | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Plantilla, roster y convocatoria separados | `GC`, `IC`, `PSG`, `FV7` | `COMMON` | Ambas | Cerrada |
| Jugador provisional | `FV7` | `CONFIGURABLE` | Ambas | Cerrada como capacidad; valores pendientes |
| Verificación sin guardar DNI por defecto | `IC`, `GC`, `FV7` | `CONFIGURABLE` | Ambas | Cerrada como principio; política legal pendiente |
| Disponibilidad distinta de preferencia | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Tarjeta azul | `MIC`, `FV7`, `FA` | `CONFIGURABLE` / `PRESET` | Ambas | Variantes de producto pendientes |
| Cinco amarillas y reset entre splits | `FV7` | `CONFIGURABLE` / `PRESET` | Ambas | No es default; pendiente de catálogo |
| Resultado y consecuencias administrativas | `IC`, `MAD`, `FV7` | `COMMON` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Cerrada la separación; valores pendientes |
| Sanción en partidos o semanas | `FV7`, `FCF` | `CONFIGURABLE` | Ambas | Cerrada como capacidad |
| Deportividad | `DC`, `FV7` | `CONFIGURABLE` | Ambas | Fórmula pendiente; no activar |
| Cuotas, multas y créditos | `IC`, `MAD`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Diferido a R10 |
| Cobertura médica | `FV7` | `CONFIGURABLE` | Ambas | Capacidad futura opcional |

## 7. Auditoría de la base actual de Pachangas IQ

La investigación se cruzó con el código real para evitar crear entidades duplicadas.

| Capacidad actual | Evidencia local | Reutilización | Hueco para R1+ |
| --- | --- | --- | --- |
| Equipo | `pachanga_groups` y membresías owner/admin/player | Un equipo de competición referencia un grupo existente | Un club podrá agrupar varios equipos sin sustituirlos |
| Jugador universal | `pachanga_player_profiles` | La identidad deportiva sigue siendo única entre equipos | Inscripción y roster necesitan snapshots contextuales |
| Partido de grupo | `pachanga_match_read_model`, participantes y goleadores | Mantener el partido y sus estados canónicos | Añadir enlace de contexto de competición |
| Reto / rival | `pachanga_team_challenges` y `pachanga_external_matches` | Reutilizar sus patrones de resultado, evidencia y revisión | Resolver una identidad canónica común de partido antes de generar calendarios |
| Resultado versionado | `pachanga_external_result_versions` | Patrón válido para resultado deportivo, propuesta y corrección | Generalizar sin duplicar el historial existente |
| Autoridad de escritura | RPC V2, `operationId`, `expectedRevision`, locks | Es el contrato obligatorio de toda mutación nueva | Recibos y eventos específicos de competición |
| Orden de eventos | `server_sequence` y revisiones | Realtime como invalidación y recarga canónica | Secuencias por agregado de competición |
| Caché PWA | Bridge de versión y caché de lectura | Snapshots locales derivados, sin éxito offline | Políticas de TTL e invalidación por entidad |
| Conducta | Conduct V1, asistencia y moderación humana | Se mantiene separado | Solo enlace explícito para incidentes graves |
| Rating | Rating V2 y snapshots autoritativos | Puede consumir un partido elegible según su contrato | Ninguna tarjeta o clasificación toca GRL/facetas |
| Rewards | Catálogos y cinco mappings de equipo | Permanecen intactos | Cualquier premio futuro exige contrato separado |
| Billing | Estado de suscripción en grupo | Puede informar al entitlement | Falta una autoridad genérica de capacidad organizadora |
| Plataforma | Roles y Control Center | Reutilizar para seguridad interna | Roles de organizador/comité deben tener alcance de competición |
| Club | No localizado como dominio canónico | Ninguna | Entidad nueva en R2 |
| Árbitro | No localizado como perfil/asignación canónica | Ninguna | Entidades nuevas en R3 |
| Competición | No localizado un motor productivo de liga/torneo | Ninguna | Foundation nueva en R1 |

### 7.1 Decisión de integración

Pachangas IQ no debe crear tablas independientes de partido para cada producto.
R1 deberá definir una identidad o binding canónico que permita enlazar, sin copiar:

- el partido de un grupo;
- el partido procedente de un Reto;
- un futuro partido generado por liga;
- un futuro partido generado por torneo.

El contexto de competición añade fase, jornada, reglas, designación y efecto en tabla.
No pasa a ser dueño de asistencia, alineación, resultado deportivo o ficha del jugador
cuando esas autoridades ya existen.

## 8. Hallazgos de producto

### 8.1 Elementos comunes

Son comunes la identidad del partido, participantes elegibles, acta, reglas vigentes,
autoridad, resultado oficial, fase, trazabilidad y una forma determinista de resolver
la clasificación o el avance cuando se publican.

“Común” significa que el concepto es obligatorio, no que su valor sea idéntico.

### 8.2 Elementos configurables

Son configurables, entre otros:

- modalidades, número mínimo y máximo de jugadores;
- composición y publicación de fases;
- puntos, deducciones y desempates;
- prórroga, penaltis y series;
- inscripción, documentación, altas, bajas y congelación de plantilla;
- tarjetas habilitadas, acumulación, suspensión y arrastre;
- tolerancia y consecuencias de incomparecencia;
- aplazamientos, protestas, depósitos y niveles de recurso;
- autoridad requerida para cada decisión.

### 8.3 Presets

Un preset es una plantilla editable y con procedencia, no una verdad oficial. Los
primeros presets candidatos son F7 amateur, F11 amateur, fútbol sala y torneo corto.
Cada competición debe copiar el preset a su propia revisión; una actualización del
preset nunca modifica reglamentos ya publicados.

### 8.4 Excepciones administrativas

Fuerza mayor, dispensas, alineación indebida, retirada, partido interrumpido,
reprogramación extraordinaria, protesta y exclusión requieren una decisión que
conserve actor, motivo, evidencia, regla aplicada y efecto. No deben implementarse
como edición directa de marcador, tabla o JSON.

## 9. Decisiones todavía necesarias

Estas decisiones no bloquean R0, pero deben resolverse antes del bloque indicado:

| Decisión | Antes de | Motivo |
| --- | --- | --- |
| Política de documentos y menores | R1/R4 | Minimización, acceso y retención de datos sensibles |
| Identidad canónica unificada de partido | R1 | Evitar que partido local y externo formen motores paralelos |
| Alcance de organizador, comité y supervisor | R1 | No reutilizar sin más el rol admin de equipo |
| Catálogo inicial de presets y propietario | R1/R5 | Valores editables, versionados y con procedencia |
| Equipos invitados sin grupo Pachangas | R1/R4 | Identidad, alta posterior y acceso limitado |
| Club con varios equipos y nombres de temporada | R2 | Separar marca del club e identidad deportiva del equipo |
| Privacidad y verificación del árbitro | R3 | Perfil público frente a documentación privada |
| Disponibilidad de recurso/apelación por plan | R4/R5 | No sacrificar justicia por implementación comercial |
| Premios y efectos de campeón | R10 | Rewards permanece fuera del contrato de competición inicial |
| Preset seleccionado por defecto | R1 | Es una decisión de producto, no una conclusión reglamentaria |
| Participación con dos equipos | R1/R4 | Debe definirse por ámbito y edición |
| Fotografía obligatoria | R1/R4 | Varía por categoría, control y base jurídica |
| Almacenamiento de documentos de identidad | R1/R4 | Requiere análisis jurídico y de seguridad específico |
| Arrastre entre competiciones o temporadas | R5 | No se infiere de un único organizador |
| Potestad exacta de árbitro, organizador y comité | R1/R3/R5 | Debe aprobarse por acción y ámbito |
| Variantes de tarjeta azul ofrecidas | R5 | Valldor7, The FA y MIC muestran semánticas incompatibles |
| Tasas de reclamación | R5/R10 | El expediente no depende de activar un cobro |
| Consecuencias económicas automáticas | R10 | Requieren contrato, billing y autoridad separados |
| Datos públicos de jugadores y sanciones | R1/R5 | Deben minimizarse y configurarse con base jurídica |

## 10. Resultado del Gate R0

**Gate de contenido R0: APROBADO. Gate de integración: PENDIENTE DE PR Y REVISION
HUMANA.**

La investigación permite identificar de manera explícita:

- `COMMON`: conceptos obligatorios del dominio y sus invariantes.
- `CONFIGURABLE`: parámetros que varían por competición, categoría, fase o ronda.
- `PRESET`: combinaciones reutilizables que siempre se copian a una revisión editable.
- `ADMINISTRATIVE_EXCEPTION`: decisiones humanas extraordinarias, motivadas y
  auditadas.

La aprobación documental no implementa ni activa League Engine o Tournament Engine.
R1 permanece sin autorización hasta que el PR exclusivamente documental sea revisado
y fusionado en `main`. Después deberá comenzar por reglamentos versionados,
ediciones/stages/splits, divisiones, organizadores, permisos y entitlements; no por el
calendario ni por una pantalla “Crear torneo”. PostgreSQL seguirá siendo la única
fuente de verdad y el partido canónico el núcleo compartido.
