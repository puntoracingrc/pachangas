# Competition Rules Matrix V1

Estado: `R0 RECONCILIADO - CONTENIDO CERRADO, REVISION HUMANA EN PR PENDIENTE`

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
Futsal, `MAD` Juegos Deportivos Municipales de Madrid y `FV7` Fundació Valldor7.
`FCF` Federación Catalana y `FA` The Football Association son fuentes oficiales
complementarias de contraste.

## 2. Matriz comparada obligatoria

| Área | Observación comparada | Evidencia | Clase dominante | Campo o agregado de contrato |
| --- | --- | --- | --- | --- |
| Inscripción | Todas necesitan participantes elegibles; mínimos, máximos y plazos varían | `DC`, `IC`, `GC`, `RFEF-FS`, `MAD` | `COMMON` + `CONFIGURABLE` | `registrationPolicy`, `rosterPolicy` |
| Identificación | Se usan nombre, nacimiento, foto o documento en combinaciones distintas; verificar no exige conservar DNI completo | `IC`, `GC`, `PSG`, `MAD`, `FV7` | `CONFIGURABLE` | `identityRequirements[]`, `PlayerCompetitionCredential` |
| Plantillas | Equipo habitual, roster de competición y convocatoria de partido son capas distintas | `DC`, `IC`, `GC`, `PSG`, `FV7` | `COMMON` + `CONFIGURABLE` | `CompetitionRoster`, `CompetitionMatchSquad` |
| Altas/bajas | Los plazos, sustituciones y dispensas dependen de fase/categoría | `IC`, `GC`, `PSG`, `RFEF-FS` | `CONFIGURABLE` | `rosterChangeWindows[]`, `dispensationPolicy` |
| Partido | El acta y los participantes efectivos son evidencia canónica | Todas | `COMMON` | `MatchSheet`, `MatchParticipantSnapshot` |
| Puntuación | 3/1/0 es frecuente, pero hay puntos por periodos, deducciones o ausencia de tabla | `DC`, `PSG`, `HC`, `MAD` | `CONFIGURABLE` | `scoringPolicy` |
| Desempates | El orden y el ámbito cambian ampliamente | `DC`, `IC`, `GC`, `DANA`, `PSG`, `RFEF-FS` | `CONFIGURABLE` | `tieBreakCriteria[]` |
| Liga | Una edición puede contener splits, reasignación de divisiones y playoff posterior | `RFEF-FS`, `MAD`, `FV7` | `COMMON` + `CONFIGURABLE` | `CompetitionEdition`, `stageGraph`, `CompetitionStageMembership` |
| Grupos | Tamaño, número de vueltas, clasificación y destinos varían | `DC`, `IC`, `GC`, `DANA`, `HC` | `CONFIGURABLE` | `groupStagePolicy`, `advancementRules[]` |
| Eliminatorias | Directo, prórroga, tanda corta/larga o series según ronda | `DC`, `IC`, `DANA`, `RFEF-FS` | `CONFIGURABLE` | `knockoutResolutionPolicy` |
| Aplazamientos | Hay plazos normales y potestad extraordinaria de organización | `IC`, `DANA`, `MAD`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `postponementPolicy`, `PostponementRequest`, `AdministrativeDecision` |
| Suspensiones de partido | Clima, campo o fuerza mayor pueden llevar a reanudar, repetir, resolver o cancelar | `GC`, `PSG`, `IFAB`, `MAD`, `FV7`, `FCF` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `MatchSuspension`, `VenueConditionDecision` |
| Incomparecencia | Retraso y no-show son incidentes distintos; cortesía, marcador, deducción, multa y exclusión varían | `DC`, `IC`, `GC`, `DANA`, `PSG`, `MAD`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `lateArrivalPolicy`, `noShowPolicy`, decisiones asociadas |
| Tarjetas | Amarilla y roja son habituales; azul puede estar desactivada, durar un tiempo o liberar por gol | `MIC`, `RFEF-FS`, `MAD`, `FV7`, `FA` | `CONFIGURABLE` + `PRESET` | `cardTypeCatalog[]`, `temporaryDismissalPolicy` |
| Acumulación | Puede no existir o usar ciclos por stage, split, competición o edición | `DC`, `IC`, `GC`, `DANA`, `FV7` | `CONFIGURABLE` | `DisciplinaryCycle`, `accumulationRules[]` |
| Rojas | La expulsión no determina siempre la misma suspensión posterior | `DC`, `GC`, `MIC`, `DANA`, `PSG` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `dismissalPolicy`, `CompetitionSanction` |
| Arrastre | Puede continuar entre partidos/fases, resetear o no existir | `DC`, `MIC`, ligas federativas | `CONFIGURABLE` | `sanctionCarryPolicy` |
| Reclamaciones | Plazo exacto, estado, depósito, materia, resolución y niveles cambian | `IC`, `GC`, `DANA`, `PSG`, `MAD`, `FV7` | `CONFIGURABLE` | `claimPolicy`, `SanctionAppeal`, `appealPolicy` |
| Autoridad | Árbitro, delegado de equipo, staff de sede, organizador y comité tienen potestades distintas | `IC`, `GC`, `MIC`, `RFEF-C`, `MAD`, `FV7`, `FCF` | `COMMON` + `CONFIGURABLE` | `CompetitionTeamDelegate`, `VenueStaffAssignment`, `authorityPolicy` |

## 3. Matriz ampliada

| Área | Observación comparada | Evidencia | Clase dominante | Campo o agregado de contrato |
| --- | --- | --- | --- | --- |
| Modalidad | 5v5, 7v7, 8v8, F11 y futsal cambian límites y leyes aplicables | `DC`, `HC`, `IFAB`, `RFEF-FS` | `CONFIGURABLE` | `sportFormat` |
| Duración | Minutos, partes y prórroga dependen de categoría/fase | `HC`, `IFAB`, `DANA` | `CONFIGURABLE` | `matchDurationPolicy` |
| Sustituciones | Rotatorias, retorno, ventanas o límites por acta | `DC`, `GC`, `DANA`, `IFAB` | `CONFIGURABLE` | `substitutionPolicy` |
| Edad/género | Categorías y dispensas son explícitas | `DC`, `GC`, `MIC`, `HC` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `eligibilityPolicy`, `EligibilityDispensation` |
| Participación múltiple | Puede prohibirse jugar con dos equipos de una categoría | `PSG` | `CONFIGURABLE` | `crossRosterPolicy` |
| Edición/splits | Una temporada puede cambiar divisiones entre splits y terminar en playoff | `RFEF-FS`, `HC`, `FV7` | `COMMON` + `CONFIGURABLE` | `CompetitionEdition`, `CompetitionStageMembership` |
| Delegado de equipo | La representación en una competición no equivale a owner/admin global | `FV7` | `COMMON` + `CONFIGURABLE` | `CompetitionTeamDelegate` |
| Staff de sede | Delegado de campo, auxiliar, coordinador arbitral y comité tienen permisos acotados | `FV7`, `FCF` | `COMMON` + `CONFIGURABLE` | `VenueStaffAssignment`, `CompetitionStaffAssignment` |
| Provisionales | Un jugador puntual requiere permiso por partido; máximo, coste y excepción varían | `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `CompetitionTemporaryPlayerPermit` |
| Equipación/dorsal | Se puede exigir uniforme, dorsal coincidente, resolución de colores y gracia inicial | `GC`, `MIC`, `FV7` | `CONFIGURABLE` | `CompetitionTeamKit`, `CompetitionPlayerJerseyNumber`, `kitPolicy` |
| Disponibilidad | Una imposibilidad real no es una preferencia de día, hora o sede | `FV7` | `COMMON` + `CONFIGURABLE` | `TeamAvailabilityConstraint`, `TeamSchedulePreference` |
| Publicación infantil | Algunas categorías no publican resultados ni clasificación | `PSG`, `HC` | `CONFIGURABLE` | `publicationPolicy.mode` |
| Fase | Cada partido pertenece a una fase y ronda inequívocas | Todas las competiciones multifase | `COMMON` | `CompetitionMatchContext` |
| Avance | La posición puede derivar a A/B, Gold/Silver/Bronze o eliminación | `DC`, `IC`, `GC`, `DANA`, `HC` | `CONFIGURABLE` | `advancementRules[]` |
| Sorteo | Puede resolver grupos, bombos o un desempate final | `DC`, `DANA`, `PSG` | `CONFIGURABLE` | `drawPolicy`, `PersistedDrawOutcome` |
| Resultado deportivo | Marcador producido en el campo | Todas | `COMMON` | `SportingResult` |
| Resultado oficial | Puede sustituir al deportivo por 0-3, exclusión o decisión | `IC`, `GC`, `MIC`, `DANA`, `MAD` | `COMMON` | `OfficialResultDecision` |
| Estados de partido | Aplazado, suspendido y cancelado no son sinónimos ni un resultado | `IFAB`, `MAD`, `FV7`, `FCF` | `COMMON` + `CONFIGURABLE` | `CompetitionMatchContext`, `MatchSuspension`, `PostponementRequest` |
| Retraso | Puede iniciar cortesía, acortar juego o terminar en resolución; no implica no-show automático | `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `LateArrivalIncident`, `lateArrivalPolicy` |
| Clima/campo | Jugar, aplazar o suspender puede depender de inspección y autoridades distintas | `IFAB`, `FV7`, `FCF` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `VenueConditionDecision`, `MatchSuspension` |
| Retirada/descalificación | Puede afectar partidos pasados y futuros | `IC`, `DANA`, `RFEF-FS`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `WithdrawalDecision`, rebuild controlado |
| Alineación indebida | La consecuencia depende del resultado y reglamento | `MIC`, `GC`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `IneligibleLineupDecision` |
| Responsabilidad | La causa de suspensión puede cambiar la resolución | `IFAB`, `MAD` | `ADMINISTRATIVE_EXCEPTION` | `responsibleParty`, `decisionReasonCode` |
| Fair play | Puede ser desempate o baremo disciplinario | `DC` | `CONFIGURABLE` | `fairPlayPolicy` |
| Deportividad | Puede publicarse como clasificación separada, pero una fórmula opaca no se debe inferir | `DC`, `FV7` | `CONFIGURABLE` | `CompetitionSportsmanshipSnapshot` |
| Edad media | Puede ser criterio de desempate | `IC`, `RFEF-FS` | `CONFIGURABLE` | `AVERAGE_AGE` tie-break strategy |
| Faltas acumuladas | Puede decidir una fase de futsal | `RFEF-FS` | `CONFIGURABLE` | `ACCUMULATED_FOULS` strategy |
| Depósito/multa | Protestas o no-shows pueden tener cuantía | `IC`, `GC`, `DANA`, `PSG` | `CONFIGURABLE` | `feePolicy`, fuera de pagos hasta fase autorizada |
| Economía compuesta | Cuota, licencia, provisional, multa, crédito y descuento son conceptos distintos | `IC`, `MAD`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `CompetitionFeePolicy`, `CompetitionCharge`, `CompetitionCredit` |
| Sanción por rango | El reglamento puede proponer un rango que el comité concreta con motivo | `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | `sanctionRangePolicy`, `AdministrativeDecision` |
| Unidad de sanción | Puede cumplirse por partido, jornada, semana, fase o expulsión | `FV7`, `FCF` | `CONFIGURABLE` | `CompetitionSanction.serviceUnit`, `SanctionServiceEvent` |
| Ámbito disciplinario | Prepartido, descanso, postpartido, recinto y público asociado pueden contar | `FV7` | `CONFIGURABLE` | `disciplinaryContextPolicy` |
| Apelación | Debe conservar plazo, estado, resolución, historial y actor; la cifra cambia | `IC`, `DANA`, `MAD`, `FV7` | `COMMON` + `CONFIGURABLE` | `SanctionAppeal`, `AppealDecision` |
| Publicación disciplinaria | El resumen público no debe exponer expediente o evidencia privada | `FV7` + privacidad Pachangas | `COMMON` + `CONFIGURABLE` | `PublicSanctionReadModel`, expediente privado |
| Cobertura médica | Puede vincularse a una licencia y a un flujo de lesión | `FV7` | `CONFIGURABLE` | `CompetitionMedicalCoveragePolicy`, fuera del núcleo R1 |
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
| `C15` | Jerarquía de edición | Todo partido competitivo se ubica en edición, stage/split, división/grupo y ronda cuando proceda |
| `C16` | Tres capas de jugador | Equipo habitual, roster de competición y convocatoria/acta no se sustituyen entre sí |
| `C17` | Representación contextual | Delegados y staff reciben permisos por competición/sede, nunca por elevación implícita del rol global |
| `C18` | Restricción frente a preferencia | Una indisponibilidad dura puede invalidar calendario; una preferencia solo influye en optimización |
| `C19` | Estado operativo explícito | Aplazar, suspender, cancelar, jugar y oficializar resultado son hechos distintos con lineage |
| `C20` | Exposición disciplinaria separada | El read model público no contiene evidencia privada, identidad sensible ni expediente completo |
| `C21` | Efectos administrativos compuestos | Marcador, puntos, sanción, multa, crédito y reincidencia son efectos independientes de una decisión |

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
| `F31` | Edición y stages | splits, divisiones, grupos, reasignación, playoff y fechas efectivas |
| `F32` | Delegado de equipo | acciones, vigencia, categorías/fases y capacidad de sustitución |
| `F33` | Staff de sede | roles, sedes, turnos, potestades y escalado |
| `F34` | Jugador provisional | máximo, autorización, identidad, cobertura, coste declarativo y excepción |
| `F35` | Equipación y dorsal | kits, colores, dorsal, conflicto, responsable y jornadas de gracia |
| `F36` | Disponibilidad dura | equipo, intervalo, sede/modalidad y motivo permitido |
| `F37` | Preferencias de calendario | día, hora, sede, peso, prioridad y capacidad de incumplimiento |
| `F38` | Retraso | cortesía, inicio de reloj, opciones, autoridad y escalado a no-show |
| `F39` | Campo y climatología | inspección, antelación, autoridades, suspensión y fuerza mayor |
| `F40` | Tarjeta azul | habilitada, expulsión personal, sustitución, tiempo y/o gol liberador |
| `F41` | Ciclo disciplinario | ámbito por stage/split/competición/edición, umbrales, reset y carry |
| `F42` | Servicio de sanción | unidad en partido/jornada/semana/fase, elegibilidad y consumo |
| `F43` | Rango de comité | mínimo/máximo, recomendación, factores y autoridad decisora |
| `F44` | Apelación | legitimación, deadline exacto, estados, efecto suspensivo y resolución |
| `F45` | Visibilidad disciplinaria | campos públicos, anonimización, retención y base de publicación |
| `F46` | Deportividad | hechos, pesos, ámbito, publicación y versión de fórmula |
| `F47` | Economía competitiva | conceptos de cuota/licencia/permiso/multa/crédito/descuento, sin cobro en R1 |
| `F48` | Cobertura médica | elegibilidad, vigencia, centro, incidente y datos mínimos |

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
| `A13` | Permiso provisional excepcional | jugador, límite superado, motivo, vigencia, aprobador y coste declarativo |
| `A14` | Calendario fuera de disponibilidad | restricción afectada, causa, conformidades, alternativa y notificación |
| `A15` | Conflicto de equipaciones | kits declarados, responsable del cambio, solución y periodo de gracia aplicado |
| `A16` | Decisión por clima/estado del campo | inspección, autoridades presentes, evidencia, minuto y resolución |
| `A17` | Resolución por retraso | llegada, cortesía, reloj, opción elegida y efecto deportivo/administrativo |
| `A18` | Sanción dentro de rango | artículo, rango, factores, propuesta, decisión humana y autoridad |
| `A19` | Corrección tras apelación | decisión recurrida, deadline, historial, resolución y efectos reconstruidos |
| `A20` | Exención o crédito económico | concepto, importe declarativo, motivo y autoridad; cobro separado |

Una excepción nunca es un `UPDATE` manual de la tabla final. Es un comando
autoritativo que crea una decisión, recalcula las proyecciones afectadas y emite un
evento de servidor.

## 8. Trazabilidad consolidada por fuentes

`Cerrada` significa que el concepto y su clasificación quedan fijados en R0. No
significa que Pachangas IQ haya elegido una cifra. Cuando una capacidad está cerrada
pero sus valores no, la fila lo dice expresamente.

| Regla | Fuente o fuentes | Clasificación | Aplica a liga / torneo / ambas | Decisión cerrada o pendiente |
| --- | --- | --- | --- | --- |
| Partido canónico y contexto competitivo | Todas + arquitectura Pachangas | `COMMON` | Ambas | Cerrada |
| Jerarquía edición -> stage/split -> división/grupo -> ronda -> partido | `RFEF-FS`, `HC`, `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Reasignación entre splits y playoff posterior | `RFEF-FS`, `FV7` | `CONFIGURABLE` | Liga | Cerrada como capacidad; reglas pendientes |
| Delegado del equipo por competición | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Staff de sede con permisos separados | `FV7`, `FCF` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada; autoridad exacta pendiente |
| Equipo, roster y convocatoria separados | `DC`, `IC`, `GC`, `PSG`, `FV7` | `COMMON` | Ambas | Cerrada |
| Jugador provisional por partido | `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Capacidad cerrada; máximo, autorización y coste pendientes |
| Identidad verificada sin conservar DNI completo por defecto | `IC`, `GC`, `PSG`, `FV7` | `CONFIGURABLE` | Ambas | Principio cerrado; política documental pendiente |
| Fotografía o dorsal obligatorio | `GC`, `MIC`, `FV7` | `CONFIGURABLE` / `PRESET` | Ambas | Pendiente por categoría/preset |
| Conflicto de colores y jornadas de gracia | `FV7` | `CONFIGURABLE` / `PRESET` | Ambas | Capacidad cerrada; valores pendientes |
| Disponibilidad dura separada de preferencia | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada |
| Calendario reproducible y publicado por versión | `MAD`, `FV7` + arquitectura Pachangas | `COMMON` + `CONFIGURABLE` | Liga | Cerrada |
| Aplazado, suspendido y cancelado como estados distintos | `IFAB`, `MAD`, `FV7`, `FCF` | `COMMON` | Ambas | Cerrada |
| Retraso distinto de no-show | `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada; minutos y consecuencias pendientes |
| Cinco/diez minutos de cortesía | `FV7` | `PRESET` / `CONFIGURABLE` | Ambas | No adoptada como default |
| Resultado administrativo 5-0 | `FV7` | `PRESET` / `ADMINISTRATIVE_EXCEPTION` | Ambas | No adoptado como default |
| Clima y estado del campo con revisión de autoridad | `IFAB`, `FV7`, `FCF` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Cerrada como workflow; autoridad exacta pendiente |
| Resultado deportivo separado del oficial | `IC`, `GC`, `MIC`, `DANA`, `MAD`, `FV7` | `COMMON` | Ambas | Cerrada |
| Consecuencias administrativas compuestas | `IC`, `MAD`, `FV7` | `COMMON` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Cerrada la separación; valores pendientes |
| Tarjetas amarilla, roja y azul habilitables | `MIC`, `RFEF-FS`, `MAD`, `FV7`, `FA` | `CONFIGURABLE` / `PRESET` | Ambas | Cerrada la familia; catálogo pendiente |
| Azul: tiempo fijo o tiempo/gol | `FV7`, `FA` | `CONFIGURABLE` / `PRESET` | Ambas | Variantes de producto pendientes |
| Cinco amarillas producen un partido | `FV7` | `CONFIGURABLE` / `PRESET` | Ambas | No adoptada como universal |
| Ciclo reiniciado entre splits | `FV7` | `CONFIGURABLE` / `PRESET` | Liga | No adoptado como universal |
| Arrastre entre fase, competición o edición | `DC`, `MIC`, `FV7` | `CONFIGURABLE` | Ambas | Política pendiente |
| Sanción en partidos, jornadas, semanas, fase o expulsión | `FV7`, `FCF` | `CONFIGURABLE` | Ambas | Capacidad cerrada; catálogo pendiente |
| Comité decide dentro de rangos | `MIC`, `RFEF-C`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Cerrada; autoridad exacta pendiente |
| Disciplina fuera del tiempo de juego | `FV7` | `CONFIGURABLE` | Ambas | Cerrada como ámbito opcional |
| Apelación con deadline, estado, resolución e historial | `IC`, `DANA`, `MAD`, `FV7` | `COMMON` + `CONFIGURABLE` | Ambas | Workflow cerrado; plazo exacto pendiente |
| Plazo de apelación de 72 horas | `FV7` | `PRESET` / `CONFIGURABLE` | Ambas | No adoptado como universal |
| Read model público separado del expediente privado | `FV7` + privacidad Pachangas | `COMMON` + `CONFIGURABLE` | Ambas | Cerrada; campos públicos pendientes |
| Deportividad | `DC`, `FV7` | `CONFIGURABLE` | Ambas | Fórmula pendiente; no activar una inferida |
| Cuota, licencia, permiso, multa, crédito y descuento separados | `IC`, `MAD`, `FV7` | `CONFIGURABLE` + `ADMINISTRATIVE_EXCEPTION` | Ambas | Modelo preparado; activación diferida a R10 |
| Cobertura médica ligada a licencia | `FV7` | `CONFIGURABLE` | Ambas | Capacidad futura opcional |
| Desempates como lista ordenada | `DC`, `IC`, `GC`, `DANA`, `PSG`, `RFEF-FS` | `CONFIGURABLE` / `PRESET` | Ambas | Cerrada la forma; orden pendiente por preset |
| Participación en varios equipos | `PSG`, `FV7` | `CONFIGURABLE` | Ambas | Decisión de producto pendiente |

## 9. Estrategias de desempate soportables

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

## 10. Valores que queda prohibido hardcodear

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
5 amarillas = 1 partido
reset de tarjetas entre splits
5 o 10 minutos de cortesía
5-0 por retraso o incomparecencia
2 o 4 provisionales por partido
5 EUR o 7 EUR por provisional
azul = 2 o 5 minutos
azul termina al recibir un gol
72 horas para apelar
sanción medida siempre en partidos
visitante cambia siempre de equipación
tres jornadas de gracia para uniformes
```

Un valor puede coincidir con esos ejemplos, pero debe proceder de la revisión de
reglas del partido o de una decisión administrativa explícita.

## 11. Cobertura del Gate R0

| Requisito del roadbook | Cobertura | Estado |
| --- | --- | --- |
| 8-12 referencias oficiales | 12 referencias principales + 2 contrastes | Cumplido |
| Torneos conocidos | Donosti, IberCup, Gothia, MIC | Cumplido |
| Otros torneos | Dana, Piteå, Helsinki | Cumplido |
| Liga F7/F11 amateur/local | Juegos Municipales Madrid y Fundació Valldor7 | Cumplido |
| Fútbol sala | RFEF Liga Prime | Cumplido |
| Marco federativo | IFAB, RFEF y contraste FCF | Cumplido |
| 19 áreas mínimas | Matriz obligatoria completa | Cumplido |
| Identificar `COMMON` | Registro C01-C21 | Cumplido |
| Identificar `CONFIGURABLE` | Registro F01-F48 | Cumplido |
| Identificar `PRESET` | Registro P01-P06 | Cumplido |
| Identificar `ADMINISTRATIVE_EXCEPTION` | Registro A01-A20 | Cumplido |
| Trazabilidad por fuente, ámbito y decisión | Tabla consolidada de esta matriz | Cumplido |

**Resultado: el contenido de la matriz satisface el Gate R0; la integración queda
pendiente del PR documental y de revisión humana.** Los valores de los presets siguen
deliberadamente sin activar. R1 no está autorizado por este documento.
