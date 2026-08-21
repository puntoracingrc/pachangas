# Competition Rules Matrix V1

Estado: `CONTRATO DE CLASIFICACION R0`

## 1. Propósito

Esta matriz convierte la investigación oficial de
`COMPETITION_RULES_RESEARCH_V1.md` en decisiones de modelado. No define todavía un
reglamento comercial de Pachangas IQ ni crea presets productivos.

La clasificación es exhaustiva para el alcance R0:

| Clase | Significado | Regla de implementación |
| --- | --- | --- |
| `COMMON` | Concepto que todo motor competitivo necesita | Debe existir en el modelo canónico; su valor puede ser configurable |
| `CONFIGURABLE` | Política que cambia por competición, categoría, fase o ronda | Vive en una revisión de reglas validada y congelable |
| `PRESET` | Conjunto cómodo de valores iniciales | Se copia; nunca se referencia en vivo ni se impone como universal |
| `ADMINISTRATIVE_EXCEPTION` | Situación que requiere autoridad y juicio contextual | Se resuelve con una decisión inmutable, motivada y auditada |

Abreviaturas de fuentes: `DC` Donosti Cup, `IC` IberCup, `GC` Gothia Cup, `MIC`
MICFootball, `DANA` Dana Cup, `PSG` Piteå Summer Games, `HC` Helsinki Cup, `IFAB`
Laws of the Game, `RFEF-C` Reglamento de Competiciones, `RFEF-FS` Liga Prime
Futsal y `MAD` Juegos Deportivos Municipales de Madrid.

## 2. Matriz comparada obligatoria

| Área | Observación comparada | Evidencia | Clase dominante | Campo o agregado de contrato |
| --- | --- | --- | --- | --- |
| Inscripción | Todas necesitan participantes elegibles; mínimos, máximos y plazos varían | `DC`, `IC`, `GC`, `RFEF-FS`, `MAD` | `COMMON` + `CONFIGURABLE` | `registrationPolicy`, `rosterPolicy` |
| Identificación | Se usan nombre, nacimiento, foto o documento en combinaciones distintas | `IC`, `GC`, `PSG`, `MAD` | `CONFIGURABLE` | `identityRequirements[]` |
| Plantillas | Puede ser abierta, congelada al check-in o limitada por convocatoria | `DC`, `IC`, `GC`, `PSG` | `CONFIGURABLE` | `rosterLockPolicy`, `matchSheetPolicy` |
| Altas/bajas | Los plazos, sustituciones y dispensas dependen de fase/categoría | `IC`, `GC`, `PSG`, `RFEF-FS` | `CONFIGURABLE` | `rosterChangeWindows[]`, `dispensationPolicy` |
| Partido | El acta y los participantes efectivos son evidencia canónica | Todas | `COMMON` | `MatchSheet`, `MatchParticipantSnapshot` |
| Puntuación | 3/1/0 es frecuente, pero hay puntos por periodos, deducciones o ausencia de tabla | `DC`, `PSG`, `HC`, `MAD` | `CONFIGURABLE` | `scoringPolicy` |
| Desempates | El orden y el ámbito cambian ampliamente | `DC`, `IC`, `GC`, `DANA`, `PSG`, `RFEF-FS` | `CONFIGURABLE` | `tieBreakCriteria[]` |
| Liga | Una o dos vueltas no bastan: puede haber Apertura/Clausura y playoffs | `RFEF-FS`, `MAD` | `CONFIGURABLE` | `stageGraph`, `roundGenerationPolicy` |
| Grupos | Tamaño, número de vueltas, clasificación y destinos varían | `DC`, `IC`, `GC`, `DANA`, `HC` | `CONFIGURABLE` | `groupStagePolicy`, `advancementRules[]` |
| Eliminatorias | Directo, prórroga, tanda corta/larga o series según ronda | `DC`, `IC`, `DANA`, `RFEF-FS` | `CONFIGURABLE` | `knockoutResolutionPolicy` |
| Aplazamientos | Hay plazos normales y potestad extraordinaria de organización | `IC`, `DANA`, `MAD` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `postponementPolicy`, `AdministrativeDecision` |
| Suspensiones de partido | Puede reanudarse, repetirse, resolverse o darse por perdido | `GC`, `PSG`, `IFAB`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `SuspendedMatchDecision` |
| Incomparecencia | Cortesía, 0-3, deducción, multa y exclusión varían | `DC`, `IC`, `GC`, `DANA`, `PSG`, `MAD` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `noShowPolicy`, `NoShowDecision` |
| Tarjetas | Amarilla y roja son habituales; azul puede estar activa o desactivada | `MIC`, `RFEF-FS`, `MAD` | `CONFIGURABLE` | `cardTypeCatalog[]` |
| Acumulación | Algunos torneos no acumulan amarillas; las ligas pueden usar umbrales | `DC`, `IC`, `GC`, `DANA` | `CONFIGURABLE` | `accumulationRules[]` |
| Rojas | La expulsión no determina siempre la misma suspensión posterior | `DC`, `GC`, `MIC`, `DANA`, `PSG` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `dismissalPolicy`, `CompetitionSanction` |
| Arrastre | Puede continuar entre partidos/fases, resetear o no existir | `DC`, `MIC`, ligas federativas | `CONFIGURABLE` | `sanctionCarryPolicy` |
| Reclamaciones | Plazo, depósito, materia recurrible y niveles cambian | `IC`, `GC`, `DANA`, `PSG`, `MAD` | `CONFIGURABLE` | `claimPolicy`, `appealPolicy` |
| Autoridad | Árbitro, organizador y comité tienen potestades distintas | `IC`, `GC`, `MIC`, `RFEF-C`, `MAD` | `COMMON` + `CONFIGURABLE` | `CompetitionStaffAssignment`, `authorityPolicy` |

## 3. Matriz ampliada

| Área | Observación comparada | Evidencia | Clase dominante | Campo o agregado de contrato |
| --- | --- | --- | --- | --- |
| Modalidad | 5v5, 7v7, 8v8, F11 y futsal cambian límites y leyes aplicables | `DC`, `HC`, `IFAB`, `RFEF-FS` | `CONFIGURABLE` | `sportFormat` |
| Duración | Minutos, partes y prórroga dependen de categoría/fase | `HC`, `IFAB`, `DANA` | `CONFIGURABLE` | `matchDurationPolicy` |
| Sustituciones | Rotatorias, retorno, ventanas o límites por acta | `DC`, `GC`, `DANA`, `IFAB` | `CONFIGURABLE` | `substitutionPolicy` |
| Edad/género | Categorías y dispensas son explícitas | `DC`, `GC`, `MIC`, `HC` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `eligibilityPolicy`, `EligibilityDispensation` |
| Participación múltiple | Puede prohibirse jugar con dos equipos de una categoría | `PSG` | `CONFIGURABLE` | `crossRosterPolicy` |
| Publicación infantil | Algunas categorías no publican resultados ni clasificación | `PSG`, `HC` | `CONFIGURABLE` | `publicationPolicy.mode` |
| Fase | Cada partido pertenece a una fase y ronda inequívocas | Todas las competiciones multifase | `COMMON` | `CompetitionMatchContext` |
| Avance | La posición puede derivar a A/B, Gold/Silver/Bronze o eliminación | `DC`, `IC`, `GC`, `DANA`, `HC` | `CONFIGURABLE` | `advancementRules[]` |
| Sorteo | Puede resolver grupos, bombos o un desempate final | `DC`, `DANA`, `PSG` | `CONFIGURABLE` | `drawPolicy`, `PersistedDrawOutcome` |
| Resultado deportivo | Marcador producido en el campo | Todas | `COMMON` | `SportingResult` |
| Resultado oficial | Puede sustituir al deportivo por 0-3, exclusión o decisión | `IC`, `GC`, `MIC`, `DANA`, `MAD` | `COMMON` | `OfficialResultDecision` |
| Retirada/descalificación | Puede afectar partidos pasados y futuros | `IC`, `DANA`, `RFEF-FS`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `WithdrawalDecision`, rebuild controlado |
| Alineación indebida | La consecuencia depende del resultado y reglamento | `MIC`, `GC`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `IneligibleLineupDecision` |
| Responsabilidad | La causa de suspensión puede cambiar la resolución | `IFAB`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `responsibleParty`, `decisionReasonCode` |
| Fair play | Puede ser desempate o baremo disciplinario | `DC` | `CONFIGURABLE` | `fairPlayPolicy` |
| Edad media | Puede ser criterio de desempate | `IC`, `RFEF-FS` | `CONFIGURABLE` | `AVERAGE_AGE` tie-break strategy |
| Faltas acumuladas | Puede decidir una fase de futsal | `RFEF-FS` | `CONFIGURABLE` | `ACCUMULATED_FOULS` strategy |
| Depósito/multa | Protestas o no-shows pueden tener cuantía | `IC`, `GC`, `DANA`, `PSG` | `CONFIGURABLE` | `feePolicy`, fuera de pagos hasta fase autorizada |
| Designación arbitral | Número, elegibilidad y coste dependen de modalidad | `RFEF-FS`, `MAD` | `CONFIGURABLE` | `refereeAssignmentPolicy` |
| Cambio de sede/horario | El organizador puede actuar en casos previstos | `IC`, `DANA`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `ScheduleChangeDecision` |
| Corrección | Un hecho original no se borra; se corrige con lineage | Patrón de autoridades y contrato Pachangas | `COMMON` | `revision`, `supersedesId`, `status` |

## 4. Registro `COMMON`

`COMMON` obliga a modelar el concepto. No congela sus valores.

| ID | Concepto común | Invariante |
| --- | --- | --- |
| `C01` | Identidad canónica de partido | Un mismo encuentro no puede existir como copias independientes por producto |
| `C02` | Contexto de competición | Un partido competitivo conoce competición, categoría, fase, ronda y revisión de reglas |
| `C03` | Revisión inmutable | Un partido conserva la versión exacta de reglas con la que se disputó |
| `C04` | Equipo e inscripción | Cada participante tiene una entrada y un roster elegible trazables |
| `C05` | Acta | Participantes, oficiales, hechos y cierre quedan versionados |
| `C06` | Doble resultado | Se distingue marcador deportivo de resultado oficial efectivo |
| `C07` | Autoridad | Cada comando se valida contra un rol de competición con alcance explícito |
| `C08` | Elegibilidad | El servidor impide alinear a quien no cumple roster o sanción |
| `C09` | Grafo de fases | La competición describe cómo se crean partidos y cómo se avanza |
| `C10` | Determinismo | Tabla, avance y sanciones se reconstruyen desde datos canónicos y reglas congeladas |
| `C11` | Lineage | Correcciones y decisiones conservan el hecho anterior; no se borran |
| `C12` | Auditoría | Toda mutación tiene actor, operación, revisión, secuencia y fecha del servidor |
| `C13` | Publicación | Visibilidad de resultados y tablas es política de servidor |
| `C14` | Separación de dominios | Disciplina deportiva no modifica Rating V2 ni abre Conduct automáticamente |

## 5. Registro `CONFIGURABLE`

| ID | Política configurable | Parámetros mínimos |
| --- | --- | --- |
| `F01` | Modalidad | código, jugadores de campo, mínimos, leyes base |
| `F02` | Categoría | edad, género, nivel, temporada, dispensas permitidas |
| `F03` | Inscripción | apertura, cierre, mínimos, máximos, aprobación |
| `F04` | Identificación | atributos requeridos, verificador, momento, retención |
| `F05` | Plantilla | tamaño, bloqueo, altas/bajas, múltiples equipos, invitados |
| `F06` | Acta | máximo, deadline, estados que cuentan como participación |
| `F07` | Puntuación | victoria, empate, derrota, bonus, penalizaciones |
| `F08` | Desempates | lista ordenada, ámbito, dirección y parámetros |
| `F09` | Liga | vueltas, simetría, descanso, orden local/visitante |
| `F10` | Grupos | tamaño, vueltas, siembra y asignación |
| `F11` | Avance | origen, condición, destino, plazas y prioridad |
| `F12` | Eliminatoria | partido único/serie, prórroga, tanda, replay |
| `F13` | Tanda | lanzamientos iniciales, elegibilidad y muerte súbita |
| `F14` | Duración | periodos, minutos, descanso y tiempo extra |
| `F15` | Sustituciones | cantidad, retorno, ventanas y restricciones |
| `F16` | Aplazamiento | solicitante, antelación, aceptación y límites |
| `F17` | No-show | cortesía, marcador, puntos, multa, reincidencia |
| `F18` | Partido suspendido | resoluciones permitidas y autoridad |
| `F19` | Tarjetas | tipos activos, efectos inmediatos y publicación |
| `F20` | Acumulación | umbrales, sanción, caducidad, reset y arrastre |
| `F21` | Doble amarilla | expulsión, conversión y suspensión posterior |
| `F22` | Roja | mínimo, cautelar, comité y extensión |
| `F23` | Protesta | legitimación, plazo, depósito, materias y autoridad |
| `F24` | Recurso | niveles, plazo, efectos suspensivos y decisión final |
| `F25` | Fair play | eventos, pesos, ámbito y uso como desempate |
| `F26` | Publicación | resultados, tablas, identidad y categorías sin ranking |
| `F27` | Árbitros | número, cualificación, asignación, sustitución |
| `F28` | Calendario | ventanas, sedes, descansos y restricciones |
| `F29` | Retirada | tratamiento de resultados pasados/futuros y tabla |
| `F30` | Resultado administrativo | marcador, puntos, culpable, alcance y rebuild |

## 6. Registro `PRESET`

Los nombres siguientes son categorías de producto provisionales. R1/R5 deberán
documentar la procedencia y revisar cada valor antes de activarlo.

| ID | Preset candidato | Objetivo | Estado R0 |
| --- | --- | --- | --- |
| `P01` | F7 amateur | Liga local con roster, jornadas, acta y disciplina editable | Esqueleto, sin valores oficiales fijados |
| `P02` | F11 amateur | Liga a una/dos vueltas con requisitos de convocatoria | Esqueleto, sin valores oficiales fijados |
| `P03` | Fútbol sala | Liga multifase y disciplina específica | Esqueleto, sin valores oficiales fijados |
| `P04` | Torneo corto | Grupos y eliminatorias en pocos días | Esqueleto, sin valores oficiales fijados |
| `P05` | Eliminatoria directa | Cuadro con partido único o serie | Esqueleto, sin valores oficiales fijados |
| `P06` | Participación formativa | Partidos sin clasificación ni publicación de resultados | Esqueleto, sin valores oficiales fijados |

Reglas obligatorias de preset:

1. El preset tiene versión y fuentes de procedencia.
2. Crear una competición copia sus valores a una revisión propia.
3. Editar el preset no modifica competiciones existentes.
4. El organizador ve y confirma todos los valores antes de publicar.
5. Ningún texto comercial puede llamar “regla oficial” a un preset genérico.

## 7. Registro `ADMINISTRATIVE_EXCEPTION`

| ID | Excepción | Datos que debe conservar la decisión |
| --- | --- | --- |
| `A01` | Fuerza mayor por retraso/no-show | evidencia, periodo de cortesía, autoridad y resolución |
| `A02` | Dispensa de edad/elegibilidad | persona, alcance, vigencia, motivo y aprobador |
| `A03` | Cambio extraordinario de fecha/campo | versión anterior, nueva programación, afectados y notificación |
| `A04` | Partido suspendido/abandonado | minuto, marcador, hechos, responsable y resolución |
| `A05` | Alineación indebida | jugador, regla, resultado previo y consecuencia oficial |
| `A06` | Corrección disciplinaria | evento original, corrección, sanción recalculada y motivo |
| `A07` | Protesta/recurso | solicitante, evidencia, decisión, instancia y plazos |
| `A08` | Retirada/descalificación | fecha efectiva, partidos afectados y política aplicada |
| `A09` | Reasignación de grupo/nivel | origen, destino, motivo y efecto en calendario |
| `A10` | Sorteo administrativo | candidatos, algoritmo/semilla o acta y resultado persistido |
| `A11` | Cancelación/terminación de competición | autoridad, alcance, standings finales y reembolsos separados |
| `A12` | Sustitución extraordinaria de árbitro | asignación original, sustituto, momento y autoridad |

Una excepción nunca es un `UPDATE` manual de la tabla final. Es un comando
autoritativo que crea una decisión, recalcula las proyecciones afectadas y emite un
evento de servidor.

## 8. Estrategias de desempate soportables

El contrato debe admitir una lista ordenada de estrategias, al menos:

```text
HEAD_TO_HEAD_POINTS
HEAD_TO_HEAD_GOAL_DIFFERENCE
HEAD_TO_HEAD_GOALS_FOR
OVERALL_GOAL_DIFFERENCE
OVERALL_GOALS_FOR
WINS
FAIR_PLAY_POINTS
AVERAGE_AGE
ACCUMULATED_FOULS
PLAYOFF_MATCH
PENALTY_SHOOTOUT
PERSISTED_DRAW
```

Cada estrategia declara su ámbito (`all_tied`, `pair_only`, `mini_table`), dirección,
parámetros y comportamiento si sigue habiendo empate. `PERSISTED_DRAW` guarda un
resultado o semilla una sola vez; jamás vuelve a sortear en cada lectura.

## 9. Valores que queda prohibido hardcodear

No podrán aparecer como verdad universal en componentes, RPC o triggers:

```text
3/1/0
dos primeros pasan
grupos de cuatro
dos vueltas
15 minutos de cortesía
0-3 por defecto
3 o 5 penaltis
prórroga sí/no
3 o 5 amarillas = un partido
roja = un partido
amarillas se limpian al cambiar de fase
máximo 18 o 20 convocados
un único nivel de protesta
```

Un valor puede coincidir con esos ejemplos, pero debe proceder de la revisión de
reglas del partido o de una decisión administrativa explícita.

## 10. Cobertura del Gate R0

| Requisito del roadbook | Cobertura | Estado |
| --- | --- | --- |
| 8-12 referencias oficiales | 11 referencias | Cumplido |
| Torneos conocidos | Donosti, IberCup, Gothia, MIC | Cumplido |
| Otros torneos | Dana, Piteå, Helsinki | Cumplido |
| Liga F7/F11 amateur/local | Juegos Municipales Madrid | Cumplido |
| Fútbol sala | RFEF Liga Prime | Cumplido |
| Marco federativo | IFAB y RFEF | Cumplido |
| 19 áreas mínimas | Matriz obligatoria completa | Cumplido |
| Identificar `COMMON` | Registro C01-C14 | Cumplido |
| Identificar `CONFIGURABLE` | Registro F01-F30 | Cumplido |
| Identificar `PRESET` | Registro P01-P06 | Cumplido |
| Identificar `ADMINISTRATIVE_EXCEPTION` | Registro A01-A12 | Cumplido |

**Resultado: la matriz satisface el Gate R0.** Los valores de los presets siguen
deliberadamente sin activar hasta que R1 cree el modelo versionado y R5 cierre las
políticas disciplinarias.
