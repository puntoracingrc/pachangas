# Conducta, Reportes y No-show V1

## Estado de la entrega

- Rama: `codex/conduct-reports-no-show-v1`.
- Base exacta: PR #117, commit `e62fd139bd99b661936b83775d3889fad3f70bbf`.
- Alcance: local, Preview y PR borrador apilado. No se ha aplicado SQL remoto ni se han activado flags reales.
- Autoridad: PostgreSQL/Supabase decide; el navegador solo envía intención, `operationId`, revisión esperada y metadatos no sensibles.
- Aislamiento: conducta y asistencia no escriben Rating V2, GRL, facetas, assessments, Season Score, TOPS, logros, cajas ni recompensas.

## Modelo de asistencia

La fuente canónica posterior al partido está normalizada en:

- `private.pachanga_attendance_closures`: un cierre por grupo y partido.
- `private.pachanga_post_match_attendance`: un hecho por participante canónico.
- `private.pachanga_attendance_reviews`: contradicción privada del jugador.
- `private.pachanga_attendance_events`: auditoría inmutable de certificación, respuesta y resolución.
- `public.pachanga_attendance_group_state`: revisión y secuencia pública mínima para invalidación Realtime.

Estados deportivos posteriores:

| Estado | Significado | Consecuencia automática |
| --- | --- | --- |
| `played` | Participación posterior confirmada | Ninguna |
| `excused_absence` | No participó, pero existía baja justificada | Ninguna |
| `late_cancellation` | Avisó demasiado cerca del partido | Historial privado y eventual recordatorio |
| `unexcused_no_show` | Confirmó y finalmente no apareció sin baja válida | Historial privado y eventual revisión humana |

Una transición previa `voy -> no` continúa siendo una cancelación. Nunca se infiere un no-show sin cierre posterior completo.

### Certificación, ventanas y disputa

- Solo owner/admin del propio grupo puede cerrar su plantilla.
- El partido debe estar jugado/finalizado y dentro de la ventana configurable, cuyo baseline es 48 horas.
- El cierre exige exactamente todos los participantes normalizados, sin omisiones ni duplicados.
- `late_cancellation` y `unexcused_no_show` generan aviso in-app obligatorio.
- El jugador dispone de una ventana configurable, baseline 72 horas, para aceptar o disputar.
- La falta de respuesta puede pasar a `confirmed_uncontested`; no impone sanción.
- La revisión puede mantener, corregir o escalar. Una corrección conserva estado original, actor, fecha, motivo y eventos.

### Política experimental de fiabilidad

| Señal confirmada | Ventana | Acción |
| --- | --- | --- |
| 1 no-show | Historial | Sin acción punitiva |
| 2 no-shows | 90 días | Recordatorio obligatorio |
| 3 no-shows | 180 días | Caso candidato a revisión humana |
| 4 cancelaciones tardías | 90 días | Recordatorio de fiabilidad |

Los umbrales viven en `private.pachanga_conduct_settings`. Una recomendación nunca aplica una restricción por sí sola.

## Modelo de reportes

Los reportes se guardan en tablas privadas y requieren una relación deportiva validada por el servidor:

- partido finalizado;
- reto aceptado enlazado a un partido finalizado;
- partido abierto finalizado;
- participación de invitado finalizada.

El servidor resuelve actor, perfil objetivo, pertenencia, participación y revisión canónica. El cliente no puede imponer identidad, evidencia, prioridad, cluster ni decisión.

Categorías V1:

- `abusive_behavior`: comportamiento abusivo;
- `harassment`: acoso;
- `threats_or_violence`: amenazas o violencia;
- `discriminatory_behavior`: comportamiento discriminatorio;
- `deliberate_cheating`: trampa deliberada;
- `repeated_disruption`: interrupciones reiteradas;
- `other`: otro.

La descripción es opcional, privada y limitada a 500 caracteres. Auto-reporte, objetivo inventado, actor ajeno, contexto no finalizado y revisión obsoleta son rechazados.

### Idempotencia y fuentes

- Un `operationId` repetido devuelve el mismo recibo canónico.
- Existe una única opinión por evaluador, objetivo, contexto y categoría.
- Un cluster agrupa `caso + equipo fuente + tipo de contexto + contexto`.
- `report_count` cuenta reportes activos.
- `independent_source_count` cuenta equipos fuente distintos.
- `correlated_source_count = max(report_count - independent_source_count, 0)`.
- Amenazas/violencia elevan prioridad a `urgent_review`, nunca culpabilidad ni bloqueo automático.
- Reportes recíprocos dentro de 14 días marcan `mutual_retaliation` para revisión contextual.

## Moderación, warnings y restricciones

Los casos mantienen estados auditables desde `submitted` hasta `closed`, incluyendo agrupación, revisión, confirmación, descarte, warning, restricción, apelación y corrección.

Un warning formal conserva caso, categoría, emisor interno, fecha, vigencia, revisión y secuencia. Una restricción requiere:

1. caso confirmado;
2. flag `social_restrictions_enabled` activo;
3. acción explícita de moderación interna;
4. duración 7, 30, 90 días o indefinida.

Gates implementados en PostgreSQL:

- `public_market`: desactiva publicación e invitaciones del perfil de mercado.
- `send_challenges`: bloquea la creación de retos por el actor restringido.
- `receive_public_challenges`: bloquea que ese admin acepte o contraproponga; todavía puede rechazar y otro admin no hereda su restricción personal.
- `public_match_access`: bloquea solicitudes a partidos públicos.
- `public_guest_access`: bloquea altas aceptadas de acceso invitado.

La expiración recupera automáticamente la capacidad social y conserva historial. Warning y restricción admiten apelación; una corrección revoca la medida sin borrar evidencia.

## Privacidad y RLS

Todas las identidades, descripciones y evidencias viven en `private`. `anon` y `authenticated` no reciben acceso directo. Las lecturas pasan por RPCs con `security definer` y `search_path` cerrado.

| Actor | Ve agregado propio | Ve reporte que envió | Ve identidad del informante | Cierra asistencia | Modera/anula |
| --- | ---: | ---: | ---: | ---: | ---: |
| Anónimo | No | No | No | No | No |
| Jugador | Sí | Sí, referencia opaca | No | No | Solo disputa/apela lo propio |
| Owner/admin de grupo | Solo asistencia de su grupo | Sí, si lo envió | No | Sí, plantilla propia | Corrige asistencia propia; no casos globales |
| Moderador de seguridad | Sí | Sí | Sí | No por rol global solamente | Sí |
| Service role | Operación interna | Operación interna | Operación interna | Expiraciones programadas | Expiraciones programadas |

El rol de seguridad se obtiene exclusivamente de `app_metadata.pachangas_security_role`. Los nombres o IDs de informantes no aparecen en Realtime, read models sociales, avisos del objetivo ni payload del grupo. La telemetría elimina claves con apariencia de PII y no almacena texto de denuncias.

## Realtime y notificaciones

Realtime publica solo dos invalidadores mínimos:

- `pachanga_conduct_subject_state`, visible únicamente por su usuario;
- `pachanga_attendance_group_state`, visible por admins del grupo.

Tras el evento, el cliente recupera el read model canónico por RPC. No se transmite evidencia privada por Realtime.

Se reutiliza `pachanga_user_notifications` para:

- cierre negativo de asistencia;
- disputa y resolución/corrección;
- recordatorios de no-show y cancelación tardía;
- nuevo caso para moderación;
- revisión urgente;
- warning y corrección;
- restricción y corrección;
- apelación y resolución;
- expiración.

Los avisos administrativos son `mandatory_in_app`. Esta fase no envía push ni correo reales.

Las siete RPC de mutación de Conduct V1 están registradas en el bridge PWA. Un cliente incompatible bloquea únicamente esas escrituras y no presenta un rechazo como éxito; las seis RPC de lectura permanecen disponibles.

## UI

- `/perfil/conducta`: asistencia, respuesta, warnings, restricciones, apelaciones y reportes propios.
- `/reportar`: formulario contextual privado; no funciona sin objetivo, contexto y revisión.
- `/admin/conduct`: cierre completo de asistencia y revisiones del grupo; cola/evidencia solo para moderación interna.
- Partido histórico: el menú del jugador muestra `Reportar conducta` solo para otro perfil registrado y un grupo real.
- Manual: documenta el flujo de asistencia, privacidad, reportes y límites sociales.

Los retos se reportan desde su partido finalizado enlazado, donde existen participantes individuales verificables. El reto por sí solo no ofrece un selector libre de personas.

## Feature flags

| Flag | Default de migración | Uso |
| --- | ---: | --- |
| `attendance_closure_enabled` | `false` | Cierre postpartido |
| `conduct_reports_enabled` | `false` | Reportes contextuales |
| `social_restrictions_enabled` | `false` | Aplicación y enforcement social |

Son independientes y permiten desplegar asistencia, reportes, moderación y restricciones por fases. Ningún flag se ha activado remotamente.

## Synthetic World

### Replay del mundo fuente

Mundo `3df9494d-3b8c-4447-96e8-d5244892af78`, revisión 313, secuencia 69458. El replay es derivado y no persiste cambios.

| Métrica | Resultado |
| --- | ---: |
| Posibles no-shows reanalizados | 37 |
| Reincidentes fuente | 8 |
| `played` | 3 |
| `excused_absence` | 3 |
| `late_cancellation` | 2 |
| `unexcused_no_show` final | 29 |
| Disputas | 13 |
| Correcciones | 8 |
| Cancelaciones normales reanalizadas | 424 |
| Falsos no-show sobre cancelaciones normales | 0 |
| Candidatos a recordatorio 90 días | 6 |
| Candidatos a revisión 180 días | 2 |

Conducta fuente:

| Métrica | Resultado |
| --- | ---: |
| Escenarios/casos | 79 |
| Reportes brutos | 91 |
| Reportes por caso | 1,15 |
| Fuentes independientes | 81 |
| Señales correlacionadas | 10 |
| Campañas del mismo equipo | 2 |
| Retaliation contextual | 3 |
| Descartes recomendados | 1 |
| Restricciones recomendadas | 2 |
| Restricciones aplicadas automáticamente | 0 |

### Temporada soak nueva

- Semilla: `20260819`.
- Equipos: 50.
- Jugadores registrados: 640.
- Partidos: 1422, con 1343 confirmados.
- Casos: 88; reportes brutos: 139; fuentes independientes: 90; correlacionados: 49.
- No-shows candidatos: 290; cancelaciones normales: 577; falsos positivos: 0.
- Invariantes diarias: 0 fallos. Invariantes semanales: 0 fallos.
- Restricciones automáticas: 0.

### Carga humana orientativa

La extrapolación no es una observación real:

| Base | Casos humanos estimados por temporada |
| --- | ---: |
| Mundo fuente, 640 jugadores | 79 |
| Soak, 640 jugadores | 88 |
| 1.000 jugadores | 138 |
| 5.000 jugadores | 688 |
| 10.000 jugadores | 1.375 |

La agrupación reduce tickets brutos, pero V1 conserva revisión humana en todos los casos. No se sustituye carga humana por auto-sanción.

## Coverage matrix

| Flujo | Contrato | SQL/RLS | Concurrencia | Synthetic |
| --- | ---: | ---: | ---: | ---: |
| Cierre completo de asistencia | Sí | Sí | Sí | Sí |
| Cancelación tardía separada | Sí | Sí | Sí | Sí |
| No-show confirmado | Sí | Sí | Sí | Sí |
| Disputa y corrección | Sí | Sí | Sí | Sí |
| Reporte contextual | Sí | Sí | Sí | Sí |
| Retry y duplicado | Sí | Sí | Sí | Sí |
| Fuentes correlacionadas/independientes | Sí | Sí | Sí | Sí |
| Campaña falsa y retaliation | Sí | Sí | N/A | Sí |
| Triage y warning | Sí | Sí | Sí | Sí |
| Restricción explícita y gates | Sí | Sí | Sí | Sí |
| Apelación, corrección y expiry | Sí | Sí | Sí | Sí |
| Anonimato por actor | Sí | Sí | N/A | N/A |
| Aislamiento deportivo | Sí | Sí | N/A | Sí |

## Incidencias de esta fase

Se registraron SW0081-SW0104 antes de cada corrección: 2 `ENVIRONMENT_ISSUE`, 11 `TESTABILITY_GAP` y 11 `PRODUCT_BUG`. Todas figuran `fixed: true` y `regressionVerified: true`.

Entre los fallos corregidos están: concurrencia del recibo idempotente, cierre parcial de plantilla, ambigüedades SQL de casos/apelaciones/restricciones, anonimato de fixtures, hooks React, reaplicación de migración, finalización real del soak, hash canónico estable, enforcement completo de gates sociales, dependencias locales del worktree y clasificación de escrituras en el bridge PWA.

## Decisiones pendientes

- `NEEDS_PRODUCT_DECISION`: si una restricción social impide recibir un trofeo TOPS. No se ha decidido ni implementado.
- Revisión legal/privacy de los periodos de retención operativa (730 días) y archivo (1825 días) antes de producción.
- Recalibrar con uso real los umbrales experimentales de recordatorios, revisiones y cancelación tardía.
- Definir capacidad y turnos de moderación antes de activar reportes en un entorno real.

## Estado técnico final

El artefacto canónico de simulación está en `simulation/synthetic-world/generated/conduct-reports-no-show-v1-summary.json`. El hash canónico excluye la proyección diagnóstica de incidencias, mientras una comparación completa antes/después sigue detectando cualquier mutación del replay.

No se ha modificado Supabase remoto, producción ni Rating V2. La migración es aditiva, reejecutable localmente y deja las tres capacidades desactivadas por defecto.

### Validación de cierre

- Diff completo frente a `e62fd139bd99b661936b83775d3889fad3f70bbf`: 30 rutas.
- `npm test`: PASS, build de producción y 186 tests.
- `npm run typecheck`: PASS.
- Lint focalizado de Conduct V1, puente PWA, manual y Synthetic World: PASS.
- Lint global: deuda preexistente, 43 incidencias (23 errores y 20 avisos) fuera del alcance de esta fase.
- SQL/RLS local: PASS contra el Supabase local de Synthetic World.
- Concurrencia e idempotencia: PASS.
- `npm run synthetic:conduct-v1`: PASS; mundo fuente preservado en revisión 313 y secuencia 69458.
- QA visual local: escritorio en Synthetic World, móvil vertical en `/perfil/conducta` y móvil apaisado en `/admin/conduct`; sin desbordamiento horizontal ni errores de consola.
- `git diff --check`: PASS.
