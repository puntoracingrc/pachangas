# Pachangas IQ Synthetic World V1 - Informe final

## Trazabilidad

- Rama: `codex/synthetic-world-v1`.
- Base exacta: `4c75d52e15449528fe206e4d542715ec96d42422` (`Validate Season Score trophy integrity V3`, PR #115).
- Entorno: macOS, Node 24.16, Next 16.2.6, Supabase CLI/Docker exclusivamente local.
- Persistencia: PostgreSQL local, esquema aislado `simulation`.
- Servicios externos: ninguno. Producción, Supabase remoto, Vercel, email y push no se modificaron.
- Mundo de referencia: `3df9494d-3b8c-4447-96e8-d5244892af78`, temporada 2026-09-01 a 2027-06-30, revisión final 313.

## Resultado

Se construyó un mundo sintético persistente con reloj virtual, semillas reproducibles, agentes con decisiones contextuales, eventos ordenados por secuencia de servidor, revisiones monotónicas, recibos idempotentes, snapshots, matriz de cobertura, detector de invariantes, incidencias permanentes y dashboard local. La simulación distingue siempre entre ruta real de producto, adaptador sintético, laboratorio y capacidad ausente.

El servidor local es autoridad. El navegador no calcula ni persiste resultados canónicos y no existe cola offline deportiva. Cada escritura del dashboard envía `operationId` inmutable y revisión esperada; el servidor rechaza una revisión obsoleta y devuelve el snapshot confirmado.

## Mundo persistente

| Métrica | Resultado |
| --- | ---: |
| Equipos | 50 |
| Jugadores registrados | 640 |
| Invitados | 30 |
| Partidos totales | 1.441 |
| Partidos confirmados/autoconfirmados | 1.423 |
| Partidos pendientes al cierre | 0 |
| Retos | 1.591 |
| Eventos autoritativos | 69.458 |
| Notificaciones | 28.267 |
| Logros y cajas | 3.730 / 3.730 |
| Opiniones sociales sintéticas | 3.961 |
| Filas de ranking actuales | 135 |
| Partidos de Reto marcados no excluidos | 950 |
| Historial de ranking persistido | 574 filas |
| Incidencias persistidas | 64 |

La base local ocupa 223 MB. Las relaciones principales ocupan aproximadamente 23 MB (`worlds`), 46 MB (`events`), 43 MB (`entities`) y 87 MB (`snapshots`). El mundo conserva 2 checkpoints, 9 snapshots mensuales y 1 de fin de temporada. También existe un segundo mundo pequeño para QA del reloj y concurrencia del dashboard.

## Población y conducta

Los 670 agentes cubren ocho perfiles de asistencia: 372 normales, 60 que rechazan correctamente, 60 bajas tempranas, 56 bajas tardías, 30 propensos a lesión, 38 no-show ocasional, 18 reincidentes y 36 que dejan de responder. Los perfiles de conducta incluyen 567 correctos, 49 antideportivos ocasionales, 24 conflictivos, 12 reincidentes, 12 coordinadores de denuncia falsa y 6 retaliatorios.

Distribución territorial: Barcelona 209, Madrid 161, Valencia 94, Sevilla 78, Girona 56, Murcia 28, Zaragoza 23 y A Coruña 21. Hay 626 agentes activos, 10 temporalmente indisponibles, 4 dormidos y 30 futuros/invitados.

La temporada produjo 30 bajas tempranas, 394 tardías, 18.742 asistencias jugadas y 37 posibles no-shows. Ocho agentes repitieron. Como el producto no posee un hecho canónico posterior de presencia, los 37 permanecen como `NEEDS_PRODUCT_DECISION`; no se convierten en sanciones.

Se generaron 79 situaciones que habrían necesitado reportes generales y 30 revisiones reales de retirada de invitado. Los escenarios incluyen jugador correcto, conflicto, conducta ocasional, reincidencia, ráfaga de un equipo, fuentes de equipos distintos, denuncia falsa coordinada, reportes mutuos y una denuncia aislada contra historial limpio. Ningún escenario general inventa una tabla o RPC de producto.

## Auditoría ampliada de conducta

| Capacidad | Clasificación |
| --- | --- |
| Reportes/denuncias generales | not_implemented |
| Conducta general | partially_implemented |
| Distinción real de no-show | not_implemented |
| Avisos por apuntarse y cancelar | implemented |
| Avisos por lesión y recuperación | implemented |
| Deduplicación y preferencias | implemented |
| Avisos administrativos obligatorios | implemented |
| Motor de warning/sanction | partially_implemented |
| Revisión de retirada de invitado | implemented |

Las notificaciones observadas incluyen 18.031 altas de asistencia, 318 cancelaciones, 107 indisponibilidades y 123 recuperaciones. Los tests SQL confirman deduplicación, preferencias y que los avisos obligatorios siguen visibles in-app. Una baja normal no equivale a no-show. El detalle completo y la propuesta separada están en [`CONDUCT_REPORTS_NO_SHOW_PROPOSAL.md`](./CONDUCT_REPORTS_NO_SHOW_PROPOSAL.md).

## Ranking e integridad

Season Score V3 usa sin cambios la fórmula 55/30/15, ventana reciente de 30 evidencias, estrategia de exclusión y retención, grafo de rivales y reglas provinciales del laboratorio de PR #115. La simulación no recalibra Rating V2 ni altera facetas.

El mundo final contiene 1 jugador `eligible`, 54 `pending_integrity_review` y 80 `not_eligible`. Una cohorte de control añadió nueve empates canónicos para cubrir el umbral provincial que faltaba al agente `agent-325`: pasó de 18 a 27 retos válidos y conservó Rating V2/facetas idénticos. Los agentes atacantes y sus dependencias de baja confianza permanecen retenidos.

El historial provincial tiene diez fechas, siete provincias representadas, 82 jugadores distintos en Top 10, 70 entradas posteriores al primer snapshot territorial, 16 líderes distintos y 12 cambios de número uno. Las capacidades autonómica y nacional están cubiertas por el laboratorio Season Score, pero el dashboard persistente V1 materializa historial provincial.

## Flujos y cobertura

La simulación ejecuta adaptadores de dominio trazados a RPC/trigger de producto para equipos, retos, mercado, asistencia, alineación, finalización, resultados externos, valoraciones, logros, cajas y notificaciones. El inventario encontró 232 RPC definidas, 67 llamadas por la web, 82 tablas, 84 claves de logro y 55 tipos de notificación.

Ausencias expresas: abandonar grupo, caducar retos, reportes generales, sanciones sociales y no-show canónico. La autocaducidad de resultados es parcial. Las dependencias de tiempo no inyectables se ejecutan mediante adaptador sintético y nunca se presentan como llamada real al PostgreSQL de producto.

Los 50 equipos incluyen 29 de fútbol 7, 14 de sala y 7 de fútbol 11; 29 son públicamente retables, 12 funcionan por invitación, 7 son privados y 2 están temporalmente indisponibles. Hay 15 equipos de actividad alta, 17 regular, 12 casual y 6 baja. Se cubren estilos equilibrado, estable, veterano, rotación alta, amigos cerrados y joven.

Los retos terminaron en 1.106 aceptados, 378 rechazados, 35 cancelados y 72 expirados. Estos últimos cuentan como demanda fallida porque no existe caducidad canónica. Los partidos incluyen 335 internos y 1.106 Retos: 1.296 confirmados, 127 autoconfirmados y 18 cancelados; 295 utilizaron invitados. Las discrepancias se resolvieron antes del cierre y no quedan partidos disputados.

La matriz final contiene 30 flujos PASS, 5 sin cobertura y 3 FAIL por capacidad ausente. Sin cobertura: invitación admin de equipo, abandonar grupo, abrir partido al mercado, modificación de alineación e integración persistente de `exclusion_and_hold`. FAIL cuantificado: 72 caducidades de reto, 37 no-shows no distinguibles y 79 reportes de conducta imposibles.

Se ejercitaron 44 agentes atacantes: colusión, equipos falsos, participantes fantasma, farming de rivales, manipulación de rating, sybils, cambio oportunista de equipo y territorio. Se excluyeron 150 evidencias de Reto; ningún atacante obtuvo certificación elegible y cuatro quedaron expresamente retenidos. No se alteró evidencia fuente ni Rating V2.

## Persistencia, RLS y concurrencia

- El esquema `simulation` está aislado de `anon` y `authenticated`.
- Snapshots y eventos se seleccionan por `server_sequence`/revisión, nunca solo por `created_at`.
- Los recibos hacen idempotentes create, avance, reconciliación y controles del dashboard.
- Dos clientes con la misma revisión no pueden confirmar escrituras divergentes: uno avanza y el otro recibe conflicto 409.
- La API es local, sin caché HTTP, y la vista de producción devuelve 404.
- Los exports y la base se conservan para inspección; no forman parte del producto.

## Incidencias

El catálogo permanente usa exclusivamente `PRODUCT_BUG`, `SIMULATION_BUG`, `TESTABILITY_GAP`, `ENVIRONMENT_ISSUE` y `NEEDS_PRODUCT_DECISION`. Todo hallazgo se registra antes de arreglarse; solo pasa a `regression_verified` tras una prueba que reproduce el caso.

Se conservaron como abiertos los límites reales del entorno, las capacidades no implementadas y los avisos de dependencias. Un falso positivo visual móvil está marcado explícitamente como tal, con las mediciones DOM que lo descartaron. Las correcciones incluyen idempotencia del dashboard, cobertura de conducta, normalización de perfiles legados, goleadores invitados, sincronización del catálogo y elegibilidad real del ranking.

Estado final: 50 incidencias `regression_verified`, 4 `needs_product_decision`, 9 abiertas y 1 falso positivo. Por severidad hay 0 critical, 16 high, 18 medium, 18 low y 12 info. Tres de las abiertas documentan suites SQL históricas de logros/recompensas: esperan las filas colectivas V2 activas, mientras el catálogo V3 las desactiva expresamente y activa 60 definiciones colectivas V3. La suite SQL V3 vigente pasa; no se reactivó V2 para satisfacer contratos obsoletos.

## Rendimiento

La batería manual de 30 semillas ejecutó 1.050 días virtuales, 4.721 partidos y 283.421 eventos en 22,224 s: 21,17 ms por día virtual y 352,6 MB de RSS máxima. Las cinco semillas smoke mantienen invariantes diarias y semanales.

## Dashboard y reproducción

Ruta local: `/admin/simulation-world`. Controles: seleccionar mundo, avanzar horas/días/semanas, pausar, clonar, exportar y cambiar de pestaña. Vistas: resumen, timeline, jugadores, equipos, partidos, ranking, conducta, cobertura e incidencias. La carga pesada se difiere hasta después del shell.

Para reproducir una incidencia se utiliza su semilla, fecha virtual, operación, entidades relacionadas y pasos guardados. Para conservar un estado se toma snapshot; para explorar otra evolución se clona con una semilla nueva. No se rebobina destruyendo historial.

## Verificación

- `test:synthetic-world`: PASS, 20/20, incluida temporada completa y regresión de elegibilidad.
- Soak de 30 semillas: PASS, 1.050 días y 283.421 eventos.
- `npm test`: PASS, build + 6 pruebas HTML + 149 pruebas TypeScript.
- SQL/RLS: PASS para Synthetic World, notificaciones, invitados, Rating V2, grupos/retos y catálogo V3.
- Concurrencia: PASS para dashboard, invitados, Rating V2, grupos/retos, logros y catálogo V3.
- Suites SQL históricas V1/V2: 3 FAIL documentados como `SW-0051` a `SW-0053`; sus expectativas fueron sustituidas por V3 y no forman parte de `npm test`.
- Typecheck, build, lint focalizado y `git diff --check`: PASS.
- Lint global: 43 hallazgos preexistentes fuera de Synthetic World, 23 errores y 20 avisos; registrado como `SW-0050`.
- QA visual: PASS en 1280x834 y 390x844; móvil tiene `bodyWidth = clientWidth = 390`, sin overflow horizontal.

Capturas verificadas: [`final-desktop.png`](./simulation/synthetic-world/screenshots/final-desktop.png), [`final-mobile-conduct.png`](./simulation/synthetic-world/screenshots/final-mobile-conduct.png) y [`final-incidents.png`](./simulation/synthetic-world/screenshots/final-incidents.png). La captura visible corresponde a revisión 311; las revisiones 312 y 313 solo añaden incidencias diagnósticas al catálogo.

## Límites honestos

- No se ejecutó producción ni staging.
- No se enviaron correo, push, Stripe, Google Places ni tráfico externo.
- No hay sistema general de reportes, no-show o sanciones; solo se cuantifica su demanda.
- La simulación no convierte ausencia de definición en bug del producto.
- Rating V2, sus fórmulas, facetas, assessments, votos, perfiles y evidencias no se modifican.

## Apéndice V1.1: embudo de ranking

La auditoría posterior preservó el mundo `3df9494d-3b8c-4447-96e8-d5244892af78` en revisión 313, secuencia 69.458 y hash de estado `92ab28b6092f4e20bfed43297dc4669a`, idéntico al checkpoint previo. Todos los experimentos A-E viven en mundos clonados.

La aclaración principal es de unidad: 950 son partidos de Reto marcados no excluidos por el generador. El motor recibió 14.484 filas jugador-partido, aceptó 9.347 mediante B y excluyó 5.137. El invariante `eligible_source_match_without_ranking_evidence` encontró cero pérdidas.

De 640 registrados, 135 entran en ranking provincial, uno cumple la certificación/trofeo persistida y 54 quedan `pending_integrity_review`. Al retirar los nueve partidos de control históricos, la elegibilidad orgánica de trofeo es cero. El cuello dominante es diversidad de red: 133 de los 135 rankeados fallan ese gate; quitarlo aisladamente elevaría el contrafactual estricto de 1 a 17, sin que ello constituya una recomendación de producto.

Las incidencias `SW-0059` a `SW-0066` quedaron registradas antes de corregirse y cerradas con regresión. Cubren la ambigüedad de unidades, la contaminación por controles automáticos, la clasificación de cohorts de confidence, el drift de configuración V3, el etiquetado de percentiles, la identidad duplicada de filas React, la precondición del runner de concurrencia y dos símbolos muertos detectados por lint focalizado. La configuración del adaptador vuelve a coincidir exactamente con V3; Rating V2 permanece intacto.

La pestaña local `Ranking funnel` fue verificada en 1440x900 y 390x844, con documento sin overflow horizontal y sin errores o avisos de consola en una sesión limpia. El diagnóstico completo, Top 50, Top 20 Barcelona, distribuciones, matriz attacker/legitimate, comparación V3 10k y clones A-E está en [`RANKING_FUNNEL_V1_1_REPORT.md`](./RANKING_FUNNEL_V1_1_REPORT.md).

## Entrega

La rama debe publicarse como PR borrador apilado sobre el commit exacto de PR #115. No debe fusionarse ni desplegarse. El worktree y la base local deben conservarse mientras el PR permanezca sin fusionar.
