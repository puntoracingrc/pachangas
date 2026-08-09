# Conducta V1.1: triage, colas y reducción segura de moderación

## Alcance y salvaguardas

- Base exacta: PR #118, commit `9aa2fa220aed8ae70a0912375b03f8324e6e8591`.
- Rama: `codex/conduct-triage-v1-1`.
- Diff funcional final: 18 rutas respecto de la base, incluidas la migración, las pruebas, la auditoría sintética y este informe.
- Entorno: worktree local, PostgreSQL sintético local y Synthetic World clonado.
- Producción, staging y Supabase remoto: no modificados.
- Flags activados: ninguno.
- Mundo fuente: preservado en revisión `313`, secuencia `69458`, hash canónico `f2b71555b074b32658a11609d148efc5dbda7dc8ef5456d1d2d0b3dcbc776c31`.
- Rating V2, Season Score, TOPS, logros y recompensas: sin cambios de estado ni fórmulas.

## Contrato funcional

Un reporte recibido no equivale a revisión humana y una revisión humana no equivale a sanción. El servidor conserva cada evidencia, calcula una recomendación explicable y mantiene separada la cola operativa. No existe ni se devuelve una puntuación universal de conducta.

| Cola | Uso | Revisión humana inmediata |
| --- | --- | ---: |
| `record_only` | Señal aislada no grave, sin corroboración activa | No |
| `watch` | Señal compatible reciente o patrón todavía insuficiente | No |
| `review` | Categoría sensible o fuentes/contextos independientes suficientes | Sí |
| `priority_review` | Reincidencia o varias fuentes y contextos independientes | Sí, prioritaria |
| `urgent_review` | Amenazas o violencia | Sí, urgente |

`urgent_review` no declara culpabilidad y nunca aplica automáticamente warnings, restricciones o bloqueos.

## Política por categoría

| Categoría | Ventana activa | Aislado | Grave |
| --- | ---: | --- | ---: |
| `other` | 90 días | `record_only` | No |
| `abusive_behavior` | 180 días | `record_only` | No |
| `deliberate_cheating` | 180 días | `record_only` | No |
| `repeated_disruption` | 180 días | `record_only` | No |
| `harassment` | 365 días | `review` | Sí |
| `discriminatory_behavior` | 365 días | `review` | Sí |
| `threats_or_violence` | 365 días | `urgent_review` | Sí |
| `attendance_reliability` | 180 días | flujo separado | No |

La evidencia expirada sigue en auditoría, pero deja de aumentar el riesgo operativo. La retención de 730/1825 días permanece configurable y no se activa como política de producción en esta fase.

## Reglas y reason codes

- Tres o más equipos/fuentes y dos o más contextos: `priority_review`.
- Dos equipos/fuentes y dos o más contextos: `review`.
- Dos señales compatibles recientes en contextos distintos: `priority_review`.
- Señales recientes sin diversidad suficiente: `watch`.
- Muchos clics del mismo equipo/contexto permanecen correlacionados y no multiplican prioridad.
- La reciprocidad añade contexto, pero no eleva por sí sola una campaña cruzada.
- Asistencia/no-show utiliza `ATTENDANCE_RELIABILITY_SEPARATE`; no aumenta una denuncia de violencia o acoso.

Reason codes implementados: `ACTIVE_WINDOW_EXPIRED`, `ATTENDANCE_RELIABILITY_SEPARATE`, `CATEGORY_DISCRIMINATORY_BEHAVIOR`, `CATEGORY_HARASSMENT`, `CATEGORY_THREATS_OR_VIOLENCE`, `CORRELATED_SOURCE_CLUSTER`, `DISTINCT_CONTEXTS_N`, `INDEPENDENT_SOURCES_N`, `ISOLATED_NON_SERIOUS_SIGNAL`, `MUTUAL_RETALIATION`, `RECENT_COMPATIBLE_SIGNALS_1` y `RECENT_COMPATIBLE_SIGNALS_2_PLUS`.

## Auditoría sintética

| Métrica | 79 casos fuente | 88 casos soak |
| --- | ---: | ---: |
| Antes: revisión humana V1 | 79 | 88 |
| Después: revisión humana V1.1 | 4 | 7 |
| `record_only` | 68 | 59 |
| `watch` | 7 | 22 |
| `review` | 3 | 3 |
| `priority_review` | 1 | 4 |
| `urgent_review` | 0 | 0 |
| Recall de casos graves | 100% | 100% |
| Precisión grave | 75% | 85,71% |
| Casos graves omitidos | 0 | 0 |
| Tasa de falsa escalada | 1,32% | 1,22% |
| Campañas falsas elevadas | 0 | 0 |
| Reportes limpios aislados elevados | 0 | 0 |

Los mundos auditados no contienen un escenario sintético de amenaza explícita. La regla urgente se verifica en tests unitarios y SQL/RLS con una amenaza aislada: llega a humano, conserva estado no resuelto y no crea sanción.

## Capacidad y escala

Con llegadas distribuidas durante la temporada, tanto 5 como 10 revisiones por día dejan backlog `0`, espera media `0` y urgentes esperando `0` en ambos mundos. Es una prueba de capacidad, no una promesa de SLA público.

| Proyección no lineal | Fuente | Soak |
| --- | ---: | ---: |
| 1.000 jugadores | 6 | 11 |
| 5.000 jugadores | 28 | 48 |
| 10.000 jugadores | 53 | 93 |
| 50.000 jugadores | 241 | 421 |

La proyección usa exponente `0,94` sobre la carga observada para no afirmar linealidad perfecta. Son cifras orientativas hasta disponer de datos reales.

## No-show

No se cambia ninguna política del producto. Se comparan únicamente alternativas:

| Umbral | Fuente: 29 confirmados | Soak: 228 confirmados |
| --- | ---: | ---: |
| 2 en 60 días | 4 | 33 |
| 2 en 90 días | 6 | 35 |
| 3 en 120 días | 2 | 20 |
| 3 en 180 días | 2 | 24 |
| 4 en 180 días | 2 | 17 |

Los 37 candidatos fuente equivalen a `0,0578` por jugador registrado y quedan como distribución plausible aún no validada. Los 290 candidatos del soak equivalen a `0,4531` por jugador: se etiquetan expresamente como distribución de estrés y no sirven para recalibrar el producto. La decisión permanece abierta como `SW-0108`.

## Autoridad, privacidad y concurrencia

- PostgreSQL es la única autoridad de colas, reason codes, ventanas, revisiones y lineage.
- Merge y split exigen actor autenticado con rol interno de seguridad, `operationId` y revisiones esperadas.
- RLS y revocaciones impiden que `authenticated` lea política, reportes, identidades o relaciones privadas directamente.
- El navegador solo recibe referencias opacas en la cola; la evidencia identificable se limita al rol interno de seguridad.
- Dos splits idénticos concurrentes producen un solo efecto y la misma respuesta canónica.
- Dos merges distintos con la misma revisión producen un éxito y un rechazo por revisión obsoleta.
- El resultado converge a un caso activo, una rama cerrada, dos relaciones auditables y tres reportes canónicos sin doble conteo.
- Amenazas/violencia no pueden fusionarse mediante la operación general.
- No existe acción de sanción masiva.

## Shadow mode y flags

Valores por defecto de la migración:

```text
conduct_triage_enabled = false
conduct_triage_shadow_mode = true
triage_policy_version = conduct-triage-v1.1-experimental
```

En sombra se calcula la recomendación V1.1, pero `operational_queue` conserva el flujo humano V1 y sus avisos. Solo con triage activo y sombra desactivada dejan de notificarse inmediatamente `record_only` y `watch`. Los flags existentes de asistencia, reportes y restricciones siguen independientes.

## UI admin

`/admin/conduct` incorpora Urgente, Prioritario, Revisión, En observación, Solo registro y Todos, con cantidades, motivos legibles, indicación de modo sombra, evidencia seleccionable y operaciones individuales de unir/separar. Las sanciones continúan caso a caso.

El dashboard local de Synthetic World muestra colas, recall, precisión, falsa escalada, capacidad, proyecciones y comparativa de no-show.

## Incidencias

- `SW-0105`, `SW-0106`, `SW-0107`, `SW-0109`, `SW-0110`, `SW-0111`, `SW-0112`, `SW-0113` y `SW-0114`: corregidas con regresión verificada.
- `SW-0108`: `NEEDS_PRODUCT_DECISION`, abierta por falta de distribución real de no-show.
- Trofeo TOPS durante una restricción social: `NEEDS_PRODUCT_DECISION`; no implementado. El ranking deportivo permanece intacto.

## Verificación

- Motor V1.1: 7/7 tests focalizados superados; Conducta V1 conserva 5/5.
- Replay fuente y soak sobre clones superado, con hashes canónicos preservados.
- SQL/RLS V1 y V1.1 superados en PostgreSQL local.
- Idempotencia y concurrencia superadas con dos sesiones PostgreSQL: un merge aceptado, otro rechazado por revisión obsoleta y replay idempotente del split.
- PWA write bridge superado: 10/10 tests, incluyendo las nuevas RPC de lectura y escritura.
- API del dashboard superada sobre un mundo local descartable: una escritura confirmada, replay idempotente y rechazo `STALE_WORLD_REVISION`; el mundo se eliminó después.
- Suite completa: build y 193 tests superados.
- Typecheck y lint focalizado de todos los archivos V1.1: superados.
- Lint global: mantiene exclusivamente deuda preexistente fuera del alcance, 43 incidencias (23 errores y 20 avisos) en `app/legal-data.tsx`, `app/mercado/page.tsx`, `app/page.tsx` y `app/theme-toggle.tsx`.
- QA visual local superada en escritorio 1440x900, móvil vertical 390x844 y móvil apaisado 844x390. Las colas Urgente, Solo registro y Todos muestran sus casos y cantidades correctos, sin desbordamiento horizontal ni errores de consola.
- Los datos sintéticos de QA y el usuario temporal fueron retirados al terminar; el servidor local se detuvo.
- `git diff --check` y el recuento exacto de rutas se vuelven a ejecutar inmediatamente antes del commit.
