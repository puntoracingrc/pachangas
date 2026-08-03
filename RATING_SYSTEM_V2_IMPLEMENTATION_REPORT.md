# Rating System V2 - Informe de implementación y cierre

## 1. Trazabilidad

| Dato | Valor |
| --- | --- |
| Rama | `codex/rating-system-v2` |
| Commit base exacto | `abcd7d25f00959afb405b68bd56f02c2058e1fe2` |
| Fecha de cierre técnico | 2026-08-03 03:21:48 CEST |
| Estado inicial | Worktree dedicado y limpio antes de implementar V2 |
| Entorno | macOS, Node.js 24.16.0, Next.js 16.2.6 y PostgreSQL 16 desechable en Docker |
| Fuentes consultadas | Código local y documentación oficial de Supabase; ninguna lectura de datos de producción |
| Producción | No consultada, modificada ni desplegada |
| Alcance de publicación | Commit y PR borrador autorizados; sin merge ni despliegue |

El contrato funcional procede de `CURRENT_RATING_SYSTEM_AUDIT.md`, de la especificación de Rating System V2 y del requisito posterior de servidor central autoritativo.

## 2. Veredicto

**Código local completo: sí. Activación productiva: todavía no. Fusión: pendiente de cerrar staging remoto y PR.**

La implementación y sus 24 unidades SQL pasan en una base PostgreSQL 16 creada desde cero y vuelven a pasar al reaplicarlas con la activación diferida siempre en último lugar. También superan pruebas de dos clientes concurrentes. Las 23 migraciones aditivas se han aplicado en la rama Supabase de staging `iozcjirlfytryzrcmrnq`; la unidad 24 de cierre V1 no se ha aplicado. Antes de activar V2 en producción sigue siendo obligatorio cerrar la QA remota autenticada con Realtime, publicar/actualizar el PR borrador y solo después decidir la activación diferida.

El lint global continúa fallando por deuda previa fuera del alcance: 43 problemas, 23 errores y 20 avisos. El lint focalizado de todos los archivos nuevos de V2 pasa.

## 3. Autoridad central

Supabase/PostgreSQL es la única fuente de verdad de V2. El cliente no decide cartas, facetas, elegibilidad, asistencia, alineación, resultado, pago, snapshots, permisos ni recálculos.

```text
Cliente envía intención
  operationId + expectedRevision + objetivo + acción semántica + metadatos
                           |
                           v
RPC autoritativa, transacción y bloqueo FOR UPDATE
                           |
       valida actor, permisos, versión y estado actual
                           |
                           v
tablas normalizadas + payload derivado + evento + recibo idempotente
                           |
                           v
respuesta canónica completa + confirmedRevision + serverSequence
                           |
                           v
cliente sustituye su previsualización por el estado confirmado
```

### 3.1 Contrato de operación

Cada mutación autoritativa de V2:

- exige usuario autenticado, salvo el token invitado limitado;
- exige `operationId` UUID;
- exige `expectedRevision` del grupo/partido;
- admite `clientMetadata` solo como metadato no autoritativo;
- bloquea la fila de grupo antes de comparar la revisión;
- rechaza una revisión antigua con conflicto explícito;
- incrementa `payload_revision` una sola vez;
- conserva un evento con `server_sequence` generado por PostgreSQL;
- conserva un recibo con actor, revisión esperada, revisión resultante, fecha de servidor, secuencia y respuesta;
- devuelve `operationId`, `expectedRevision`, `confirmedRevision`, `confirmedAt`, `serverSequence` y snapshot canónico;
- devuelve exactamente el mismo recibo si se repite el mismo `operationId` por el mismo actor;
- rechaza reutilizar el `operationId` de otro actor.

### 3.2 Realtime y caché

Realtime se utiliza solo como aviso. En un `UPDATE` de `pachanga_groups`, `app/page.tsx` vuelve a consultar la fila oficial, compara `payload_revision` y aplica el payload confirmado. No confía en el payload del evento.

`localStorage`, el payload grande y los read models son copias derivadas. En un grupo remoto no pueden confirmar una acción ni competir con PostgreSQL. El modo demo sigue siendo local deliberadamente porque no representa usuarios ni partidos reales.

El contrato permanente de Pachangas IQ queda fijado como server-authoritative con caché local. El cliente puede guardar snapshots, catálogos, campos, partidos finalizados y read models como caché derivada, pero toda creación, modificación, valoración, resultado o acción social debe confirmarse mediante RPC/API central con `operationId` y revisión esperada. No existe cola offline de operaciones deportivas: un rechazo, timeout, offline o cliente obsoleto obliga a descartar la previsualización y recargar el estado canónico.

Las cartas, medias, historiales y niveles no se recalculan en cada lectura del navegador. Se recalculan en PostgreSQL cuando un evento relevante cambia evidencias, asistencia, alineación o finalización, y luego se devuelven como payload/read model canónico con revisión y secuencia de servidor.

## 4. Superficie de cambios

Antes de preparar la publicación se confirmaron exactamente **38 rutas persistentes de implementación V2 modificadas o creadas**. El runbook operativo solicitado para el PR añadió una ruta documental y el endurecimiento previo a staging añade una guardia de emergencia diferida, por lo que el PR contiene **40 rutas únicas**:

- 5 archivos existentes modificados: `app/globals.css`, `app/mercado/page.tsx`, `app/page.tsx`, `package.json`, `tests/rendered-html.test.mjs`.
- 5 archivos de aplicación nuevos: `app/api/ratings/assessment/route.ts`, `app/global-rating-panel.tsx`, `app/rating-assessment-contract.ts`, `app/rating-system-v2.ts`, `app/valorar-equipo/page.tsx`.
- 23 migraciones SQL aditivas nuevas y 1 migración de cierre V1 diferida.
- 3 pruebas nuevas: `tests/rating-system-v2.test.ts`, `tests/rating-system-v2-db.sql`, `tests/rating-system-v2-concurrency.mjs`.
- Este informe.
- El runbook `docs/rating-system-v2-deployment-runbook.md`.
- La guardia de continuidad `supabase/deferred-migrations/20260802203605_rating_v2_emergency_safe_hold.sql`, excluida del despliegue normal.

## 5. Migraciones

| Migración | Responsabilidad principal |
| --- | --- |
| `20260802105905_rating_system_v2_schema.sql` | Modelo normalizado, evidencias, snapshots, invitados, equipos externos, restricciones, índices y RLS inicial. |
| `20260802105906_rating_system_v2_functions.sql` | Fórmulas V2, elegibilidad, recálculo, snapshots, global, invitados y preservación histórica. |
| `20260802105907_rating_system_v2_backfill.sql` | Backfill conservador e idempotente del legado sin inventar autores ni observaciones. |
| `20260802105908_rating_system_v2_assessments.sql` | Persistencia de assessments calculados por el motor TypeScript compartido. |
| `20260802131048_rating_system_v2_hardening.sql` | Anonimato, mínimo social de tres evaluadores, interruptor por grupo y calibración externa. |
| `20260802143000_rating_v2_authority_foundation.sql` | Revisiones, metadatos, secuencia del servidor, recibos y snapshots canónicos. |
| `20260802143100_rating_v2_privacy_reads.sql` | Lecturas privadas, resumen agregado y moderación mediante identificador opaco. |
| `20260802143200_rating_v2_authoritative_mutations.sql` | Valoración individual y configuración de valoraciones con revisión e idempotencia. |
| `20260802143300_rating_v2_authoritative_void.sql` | Anulación propia y moderación opaca, ambas autoritativas y auditadas. |
| `20260802143400_rating_v2_profile_authority.sql` | Alta y patch del perfil universal resueltos en servidor. |
| `20260802143500_rating_v2_match_authority.sql` | Payload, asistencia, alineación, pago, goleadores y finalización autoritativos. |
| `20260802143600_rating_v2_payload_validation.sql` | Rechazo de facetas, votos y resultados definitivos falsificados dentro del payload cliente. |
| `20260802143700_rating_v2_global_calibration.sql` | Calibración global determinista con ventana de 12 meses y snapshots. |
| `20260802143750_rating_v2_registered_opponents.sql` | Vinculación de rivales registrados sin duplicar identidades de equipo. |
| `20260802143800_rating_v2_global_authority.sql` | Contexto y valoraciones globales autoritativas. |
| `20260802143900_rating_v2_guest_tokens.sql` | Token invitado con hash, alcance, caducidad, revisión e idempotencia. |
| `20260802144000_rating_v2_assessment_authority.sql` | Assessment de una sola ejecución, actor resuelto y respuesta canónica. |
| `20260802144100_rating_v2_secondary_match_authority.sql` | Mercado público, solicitudes y operaciones secundarias de partido con revisión. |
| `20260802144150_rating_v2_market_profile_authority.sql` | Perfil de mercado sincronizado desde el perfil universal oficial. |
| `20260802144300_rating_v2_guest_authority.sql` | Crear, enlazar y revertir invitados con historial y revisión. |
| `20260802144400_rating_v2_snapshot_assignment_fix.sql` | Corrección de asignación de columnas al crear snapshots de partido. |
| `20260802144500_rating_v2_restoration_semantics.sql` | Restaura la evidencia original sin crear voto ni peso nuevo y separa `opinion_created_at` de `restored_at`. |
| `20260802144600_rating_v2_canonical_ordering.sql` | Lectura canónica de snapshots y órdenes deterministas mediante secuencia, revisión o fecha más ID estable. |
| `deferred-migrations/20260802144700_rating_v2_legacy_write_closure.sql` | Activación diferida: revoca RPC antiguas y `UPDATE` directo solo cuando el frontend V2 ya está verificado. |

Las 23 migraciones aditivas se aplican primero. La unidad 24 se valida después como activación separada y no forma parte de un `supabase db push` ordinario. Esta separación evita romper V1 antes de desplegar V2; el procedimiento completo está en `docs/rating-system-v2-deployment-runbook.md`.

`deferred-migrations/20260802203605_rating_v2_emergency_safe_hold.sql` tampoco forma parte de las 24 unidades de despliegue. Es una guardia de incidente: mantiene V1 y `UPDATE` directo revocados y garantiza únicamente la RPC V2 de asistencia para un frontend temporal de mantenimiento. Debe convertirse en una migración nueva y ensayarse en staging antes de cualquier uso.

### 5.1 Artefactos preexistentes

Se compararon expresamente `supabase/.temp/cli-latest` y `tsconfig.tsbuildinfo` con el commit base `abcd7d25f00959afb405b68bd56f02c2058e1fe2`. Ninguna de las dos rutas existe en ese commit y ninguna existe en el worktree final; por tanto, el estado fiel al base es su ausencia. No aparecen en `git diff`, `git status` ni entre las 40 rutas del PR.

### 5.2 Orden canónico auditado

Se revisaron las consultas de aplicación y todas las funciones PostgreSQL finales que seleccionan el último snapshot, evento, recibo, assessment o evidencia. Los índices temporales no se contaron como lecturas. El contrato final es:

| Familia | Orden autoritativo | Evidencia |
| --- | --- | --- |
| Estado de grupo | `payload_revision` / `confirmedRevision` | RPC y recarga Realtime rechazan una revisión inferior. |
| Evento de grupo | `server_sequence DESC` | Identidad monotónica y única; nunca usa la hora del dispositivo. |
| Recibo de operación | Clave única `(group_id, operation_id)`; conserva `result_revision` y `server_sequence` | Replay idempotente devuelve exactamente la respuesta almacenada. |
| Evidencia individual emitida | `opinion_created_at DESC, created_at DESC, id DESC` | El desbloqueo y la sustitución no dependen de empates temporales. |
| Evidencia activa | Índice único por pareja | No puede haber dos candidatas activas. |
| Snapshot de carta | `created_at DESC, id DESC` | RPC `get_latest_pachanga_player_rating_snapshot_v2`. |
| Assessment | Tipo avanzado primero, después `completed_at DESC, id DESC` | Selección estable aunque dos fechas coincidan. |
| Copia de grupo en cliente | `created_at DESC, id DESC` | La lista de recuperación no cambia de orden ante timestamps iguales. |

La auditoría del catálogo PostgreSQL no localizó ninguna función ejecutable que terminase una selección con `created_at DESC` o `completed_at DESC` sin desempate. La prueba SQL crea tres snapshots con el mismo `created_at` en una sola sentencia, compara el RPC con una lectura cliente bajo RLS y obtiene el mismo ID estable. La prueba concurrente repite la lectura desde dos conexiones y ambas reciben el mismo snapshot canónico.

## 6. Modelo normalizado

| Objeto | Autoridad |
| --- | --- |
| `pachanga_player_profiles` V2 | Capas base, calibrada y actual; fiabilidad, dominio y versión del motor. |
| `pachanga_individual_rating_evidence` | Opiniones direccionales inmutables, fecha de emisión original, restauración separada y una única opinión activa por pareja. |
| `pachanga_rating_evidence_state_events` | Historial de activación, sustitución, anulación y restauración. |
| `pachanga_player_rating_snapshots` | Reconstrucción histórica de cada capa de carta. |
| `pachanga_match_rating_snapshots` | Nivel de grupo, nivel de alineación y estado al finalizar. |
| `pachanga_match_rating_participants` | Participación real, reserva, lado y carta usada en ese partido. |
| `pachanga_guest_identities` | Identidad persistente del invitado y enlace reversible a usuario futuro. |
| `pachanga_global_rating_responses` | Respuestas individuales globales conservadas para auditoría. |
| `pachanga_global_rating_evidence` | Observación oficial agregada por partido y objetivo. |
| `pachanga_team_external_rating_snapshots` | Calibración histórica de grupos y equipos externos. |
| `pachanga_operation_receipts` | Idempotencia y respuesta canónica de cada intención. |
| `pachanga_group_events` | Historial ordenado por secuencia del servidor. |

## 7. Rutas antiguas y frontera de confianza

Después de activar las migraciones, los clientes `anon` y `authenticated` no pueden ejecutar las rutas antiguas de escritura que permitían votos absolutos, patches de perfil o mutaciones de partido sin revisión.

Quedan revocadas, entre otras:

- `append_pachanga_player_rating`;
- `complete_pachanga_player_initial_assessment`;
- `complete_pachanga_player_advanced_assessment`;
- `save_pachanga_payload_if_current`;
- `patch_pachanga_match_player_status`;
- `patch_pachanga_match_lineup_state`;
- `patch_pachanga_match_player_paid`;
- `patch_pachanga_match_scorers`;
- `finalize_pachanga_match_if_current`;
- `sync_pachanga_market_profile`;
- `sync_pachanga_open_match`;
- `request_pachanga_open_match`;
- `review_pachanga_open_match_request`;
- escritura directa `UPDATE` sobre `pachanga_groups`.

Las funciones internas de compatibilidad siguen existiendo para que las envolturas V2 puedan delegar dentro de la misma transacción, pero no son alcanzables por clientes. Ninguna función V2 `SECURITY DEFINER` conserva ejecución para `PUBLIC`; todas fijan `search_path` explícito.

El cliente de valoración individual solo envía grupo, objetivo, seis comparaciones semánticas, `operationId`, revisión esperada y metadatos. PostgreSQL resuelve evaluador, pertenencia, carta de referencia, confianza, opinión activa y partidos compartidos. Los resultados calculados enviados dentro del payload se rechazan.

El endpoint de assessments autentica al usuario, recupera del servidor el assessment inicial cuando corresponde, recalcula desde las respuestas originales con `football-rating-v1` y solo entonces utiliza `service_role` para invocar la función de persistencia. La clave de servicio no se expone al navegador.

## 8. Anonimato y matriz de acceso

`evaluator_profile_id` se conserva únicamente para autorización y recálculo. La tabla cruda solo es visible al evaluador de sus propios votos y al rol interno `service_role`. El resumen social no devuelve evaluadores. La moderación ordinaria usa `moderationId`, sin usuario, perfil, nombre ni relación reversible. Los eventos y recibos de una valoración ocultan el actor para miembros y administradores.

| Actor | Puede ver resultado agregado | Puede ver su voto | Puede ver identidad del evaluador | Puede anular |
| --- | ---: | ---: | ---: | ---: |
| Jugador evaluado | Sí, desde 3 evaluadores | Solo votos que él haya emitido | No | Solo votos propios emitidos |
| Miembro ordinario | Sí, desde 3 evaluadores | Sí | No | Su propio voto |
| Administrador del grupo | Sí, desde 3 evaluadores | Sí | No; solo `moderationId` opaco | Sí, mediante `moderationId` y con auditoría |
| Evaluador | Sí, desde 3 evaluadores | Sí, comparaciones y fecha propias | Solo sabe que el voto es suyo | Sí, su propio voto |
| Rol interno de seguridad | Sí | Sí, para investigación | Sí | Sí, mediante operación interna auditada |

La matriz se prueba en SQL con usuarios objetivo, evaluador, otro miembro, administrador y `service_role`. También se comprueba que la detección de reciprocidad no sea legible por miembros ni administradores ordinarios.

## 9. Fórmulas consolidadas

| Resultado calculado | Fórmula exacta | Entradas | Límites | Redondeo | Fuente de verdad | Archivo/función |
| --- | --- | --- | --- | --- | --- | --- |
| Delta semántico | `{-10,-5,0,+5,+10}` para `MUCHO_PEOR..MUCHO_MEJOR` | Comparación | Conjunto fijo | Ninguno | Contrato V2 | `comparisonDelta`; `pachanga_rating_v2_comparison_delta` |
| Observación relativa | `clamp(facetaEvaluador + delta, 0, 100)` | Snapshot del evaluador y comparación | `0..100` | Ninguno | Evidencia PostgreSQL | `record_pachanga_individual_rating_authoritative_v2` |
| Peso del prior base | `P = 2 + 3 * (R / 100)` | Fiabilidad base `R` | `P=2..5` | Ninguno | Recálculo PostgreSQL | `baseEvidenceWeight`; `pachanga_recalculate_player_rating_v2` |
| Peso de evaluador | `Wi = 0.5 + 0.5 * (Ci / 100)` | Confianza `Ci` resuelta por servidor | `Wi=0.5..1` | Ninguno | Recálculo PostgreSQL | `evaluatorEvidenceWeight`; `pachanga_recalculate_player_rating_v2` |
| Observación ajustada | `clamp(Oi, max(0,B-15), min(100,B+15))` | Observación `Oi`, base `B` | Distancia máxima 15 | Ninguno | Recálculo PostgreSQL | `calibrateFacets`; `pachanga_recalculate_player_rating_v2` |
| Faceta calibrada | `clamp((P*B + sum(Wi*OiAjustada)) / (P + sum Wi), 0, 100)` | Base y una evidencia activa por evaluador | `0..100` | Ninguno persistido | PostgreSQL | Mismas funciones |
| Faceta actual | `clamp(facetaCalibrada + modificadorActual, 0, 100)` | Faceta calibrada y modificador | `0..100` | Ninguno persistido | Perfil V2 | `applyCurrentModifiers`; recálculo SQL |
| GRL de capa | `clamp(sum(faceta * pesoPosición), 0, 100)` | Seis facetas y posición | `0..100`, solo dominio de campo | Solo presentación | Motor versionado | `calculateOverall`; `pachanga_rating_v2_overall` |
| Nivel estable de grupo | `sum(GRLcalibrado seleccionados) / N` | Hasta 11 activos con más apariciones confirmadas en 12 meses | Máximo 11 | Ninguno persistido | PostgreSQL/snapshot | `stableGroupLevel`; `pachanga_group_level_v2` |
| Nivel de alineación | `sum(GRLactual participantes) / N` | Confirmados, juegan y no reserva | Participantes elegibles | Ninguno persistido | Snapshot de partido | `lineupLevel`; `snapshot_pachanga_match_ratings_v2` |
| Observación global oficial | `sum(observaciones admin) / N` | Respuestas válidas del partido/objetivo | `0..100` | Ninguno persistido | PostgreSQL | `aggregateOfficialObservation`; `pachanga_refresh_global_official_v2` |
| Nivel externo calibrado | `clamp((5*B + sum(Wi*clamp(Oi,B-10,B+10))) / (5 + sum Wi),0,100)` | Base `B`; 12 meses; `Wi=1` registrado/admin, `0.5` invitado | `0..100`, influencia individual ±10 | Ninguno persistido | PostgreSQL | `externallyCalibratedTeamLevel`; `pachanga_recalculate_group_external_level_v2` |
| Nivel provisional invitado | `clamp(sum(Oi)/N,0,100)`; sin observaciones usa el valor provisional existente | Observaciones válidas del invitado | `0..100` | Ninguno persistido | PostgreSQL | `guestProvisionalLevel`; `pachanga_recalculate_guest_level_v2` |
| Assessment inicial/avanzado | Resultado exacto de `calculateInitialRatings` o `calculateAdvancedRatings` | Respuestas originales validadas | Contrato `football-rating-v1` | El motor decide | API Node compartida, no navegador ni fórmula SQL antigua | `calculateSharedAssessmentResult` |
| Desbloqueo de nueva valoración | `partidosCompartidos(opinionCreatedAtUltimaOpinionEmitida, ahora)` | Última evidencia realmente emitida por la pareja, incluida si después fue anulada | Primera valoración: 0; siguientes: mínimo 3 | Ninguno | PostgreSQL | `get_pachanga_rating_eligibility` |
| Restauración de opinión | Reactivar el `evidence_id` original; `opinion_created_at` no cambia; `restored_at=server_now()` | Última opinión anterior sustituida | No crea evidencia, voto, peso ni fecha de emisión | Ninguno | PostgreSQL | `void_pachanga_individual_rating_v2` |
| Snapshot canónico más reciente | Máximo por `created_at DESC, id DESC` | Snapshots persistidos del jugador | UUID estable deshace empates temporales | Ninguno | PostgreSQL | `get_latest_pachanga_player_rating_snapshot_v2` |

Los cálculos persistidos usan `numeric`. El redondeo visual no se vuelve a guardar.

## 10. Precedencia

| Dato final | Fuente inicial | Fuentes que pueden modificarlo | Orden | Sobrescribe/media/delta | ¿Reconstruible? |
| --- | --- | --- | --- | --- | --- |
| Facetas base | Assessment inicial | Assessment avanzado, una sola vez | Inicial, después avanzado | Avanzado reemplaza capa base | Sí |
| Facetas calibradas | Facetas base | Última evidencia activa de cada evaluador | Prior base y media ponderada conmutativa | Media ponderada | Sí |
| Facetas actuales | Facetas calibradas | Modificadores temporales persistidos | Después de calibrar | Delta | Sí |
| GRL base/calibrado/actual | Facetas de su capa | Pesos de posición versionados | Tras cada capa | Suma ponderada | Sí |
| Opinión individual activa | Ninguna | Nueva opinión elegible tras 3 partidos compartidos; anulación puede reactivar la anterior | Emisión por secuencia del servidor; restauración solo registra `restored_at` | Sustituye la activa; restaurar reutiliza evidencia, fecha y peso originales | Sí |
| Próximo desbloqueo del evaluador | Primera valoración inmediata | Partidos compartidos posteriores a la última opinión realmente emitida | `opinion_created_at` más reciente; `restored_at` nunca reinicia el corte | Contador, no media | Sí |
| Resumen social | Opiniones activas | Nuevos evaluadores independientes | Tras recálculo | Oculto hasta 3; luego agregado | Sí |
| Nivel de grupo | GRL calibrado de activos habituales | Participación confirmada futura | En cada snapshot | Media de hasta 11 | Sí |
| Nivel de alineación | Participantes reales | Asistencia, reserva y alineación confirmadas | Al finalizar | Media | Sí |
| Nivel externo | Nivel estable/base | Evidencia global de 12 meses | En cada evidencia válida | Prior 5 más media ponderada | Sí |
| Estado de partido | Snapshot canónico del grupo | RPC autoritativa aceptada | `server_sequence` y `payload_revision` | Reemplazo transaccional | Sí |
| Read model/payload local | Snapshot del servidor | Respuesta RPC o recarga tras Realtime | Solo después de confirmación | El servidor sobrescribe la copia | Sí |
| Snapshot de carta leído | Historial de snapshots | Nuevos recálculos y finalizaciones | `created_at DESC, id DESC` | Selecciona uno; no mezcla filas | Sí |

## 11. Estado funcional

| Comportamiento | Estado | Evidencia |
| --- | --- | --- |
| Primera valoración inmediata entre miembros activos | CONFIRMADO | Elegibilidad SQL y pruebas 0 partidos. |
| Sustitución tras 3 partidos compartidos adicionales | CONFIRMADO | Snapshots direccionales y pruebas 0/1/2/3. |
| Una única opinión activa por pareja | CONFIRMADO | Índice parcial, bloqueo y carrera de dos clientes. |
| Comparaciones relativas; sin votos absolutos | CONFIRMADO | UI semántica, validación SQL y revocación V1. |
| Servidor resuelve evaluador, referencia y confianza | CONFIRMADO | RPC autoritativa y test de payload falsificado. |
| Anonimato social y moderación opaca | CONFIRMADO | RLS, RPC de lectura y matriz SQL. |
| Media social oculta hasta 3 evaluadores | CONFIRMADO | Resumen SQL/UI y casos 0/1/2/3. |
| Interruptor de valoraciones por grupo | CONFIRMADO | RPC autoritativa, auditoría y UI admin. |
| Assessment obligatorio y avanzado opcional, una vez | CONFIRMADO | API compartida y restricción SQL idempotente. |
| Perfil universal como autoridad de la carta | CONFIRMADO | Perfil normalizado y patches autoritativos. |
| Asistencia sin duplicados | CONFIRMADO | RPC transaccional y carrera concurrente. |
| Alineación sin duplicados y con revisión | CONFIRMADO | RPC transaccional y carrera concurrente. |
| Finalización única, snapshot y rotación única | CONFIRMADO | RPC, recibo y carrera concurrente. |
| Anulación propia/moderada auditada | CONFIRMADO | Evidencia de estado y carrera concurrente. |
| Restauración de la opinión anterior sin voto ni peso nuevo | CONFIRMADO | Prueba SQL A-B: conserva evidencia, confianza y `opinion_created_at`; separa `restored_at`; el desbloqueo parte de la segunda emisión anulada. |
| Selección canónica con timestamps idénticos | CONFIRMADO | Tres snapshots en una sentencia; RPC, lectura RLS y dos clientes convergen al mismo ID. |
| Revisión obsoleta al reconectar | CONFIRMADO | Rechazo explícito y recarga convergente. |
| Realtime vuelve a leer estado oficial | CONFIRMADO | Suscripción activa de `app/page.tsx`. |
| Invitados, token y enlace reversible | CONFIRMADO | Backend, UI de token e integración SQL. |
| Valoración global de rival/invitado/equipo registrado | CONFIRMADO | UI, RPC, calibración y SQL. |
| Snapshot histórico de carta y equilibrio | CONFIRMADO | Tablas y finalización autoritativa. |
| Cuestionario y GRL específico de portero | AUSENTE POR DECISIÓN DE PRODUCTO | Se conserva dominio separado; no se inventó fórmula. |
| Flujo completo de hábitos/limitaciones vivas | PARCIAL | Existe capa de modificadores, falta el formulario persistido completo. |
| Detección legítima de cuentas múltiples | AUSENTE | No se añadió fingerprinting ni una heurística invasiva. |

No quedan dos motores activos capaces de escribir la carta calibrada: las rutas V1 de cliente están revocadas y las funciones internas solo son alcanzables desde envolturas V2. Antes de desplegar estas migraciones, producción continúa usando el esquema legado; después, las rutas antiguas dejan de ser ejecutables por clientes.

## 12. Pruebas de concurrencia y convergencia

`tests/rating-system-v2-concurrency.mjs` abre dos conexiones PostgreSQL independientes con la misma revisión y comprueba:

| Carrera | Resultado esperado y observado |
| --- | --- |
| Primera valoración simultánea | Un ganador, un conflicto de revisión, una evidencia activa. |
| Sustitución simultánea | Un ganador, una activa y dos evidencias históricas. |
| Asistencia simultánea | Un ganador y un solo participante normalizado. |
| Alineación simultánea | Un ganador, cada jugador una vez y snapshot canónico común. |
| Finalización simultánea | Una finalización, un snapshot y una sola rotación/contador. |
| Anulación simultánea | Una anulación efectiva y restauración determinista de la evidencia anterior, sin fila ni peso sintéticos. |
| Reconexión con revisión antigua | Rechazo explícito, ningún cambio y recarga del snapshot vigente. |
| Snapshots con el mismo `created_at` | Dos clientes reciben el mismo UUID canónico mediante `created_at DESC, id DESC`. |

Después de cada carrera, dos actores vuelven a leer PostgreSQL y obtienen exactamente el mismo JSON canónico. El recorrido final confirma que `confirmedRevision`, eventos, secuencias únicas y `operationId` únicos tienen el mismo conteo. El total es 7 u 8 según qué intención de asistencia gane y si hace falta normalizarla; la prueba rechaza cualquier otro resultado. Las repeticiones idempotentes no incrementan la revisión ni duplican eventos.

## 13. Validación ejecutada

| Comprobación | Resultado |
| --- | --- |
| `npm test` | PASS: build, 5 pruebas de rutas y 37 pruebas TypeScript, 42 en total. |
| `tests/rating-system-v2.test.ts` | PASS: 21 pruebas unitarias, de propiedades y contrato. |
| `npm run test:rating-v2:db` | PASS: seguridad, RLS, privacidad, fórmulas, legado, idempotencia, restauración A-B y empate de snapshots dentro de transacción. |
| `npm run test:rating-v2:concurrency` | PASS: 8 carreras/convergencias y diario ordenado. |
| Contrato documental previo a staging | PASS: 5/5 pruebas sobre versionado de cliente, actualización PWA, silencio V1, timeouts, volumen, restauración y ausencia de reapertura directa. |
| Guardia de emergencia en PostgreSQL 16 local | PASS tras esquema completo + 23 migraciones + unidad 24 + guardia: `UPDATE` directo es falso; las 10 RPC V1 son falsas para `anon` y `authenticated`; solo la asistencia autoritativa V2 permanece ejecutable para `authenticated`. |
| SQL/RLS después de la guardia | PASS: batería completa en la base desechable, incluida privacidad, idempotencia, restauración y snapshots. |
| Concurrencia después de la guardia | PASS: 8 casos, incluida selección canónica con el mismo timestamp, y revisión final convergente. |
| Restauración A-B | PASS: vuelve la primera evidencia con fecha/peso originales, sin voto nuevo; `restoredAt` separado y desbloqueo calculado desde la segunda opinión emitida. |
| Snapshots con timestamp idéntico | PASS: RPC, lectura RLS y dos conexiones seleccionan el mismo ID; otro miembro no puede leerlo. |
| Auditoría del catálogo SQL | PASS: ninguna función final depende solo de fecha descendente para elegir el último registro. |
| Base PostgreSQL 16 desde cero | PASS con 23 migraciones aditivas y la activación diferida aplicada como unidad 24. |
| Reaplicación completa de migraciones | PASS sobre la misma base con datos V2, manteniendo la activación como último paso. |
| `npx tsc --noEmit --incremental false` | PASS. |
| Build Next.js | PASS; 19 rutas, incluida `/api/ratings/assessment` y `/valorar-equipo`. |
| Lint focalizado V2 | PASS. |
| Lint global | FAIL esperado: 43 problemas preexistentes, 23 errores y 20 avisos. |
| `git diff --check` | PASS final. |
| `git status --porcelain=v1 -uall` | Checkpoint previo al runbook: 38 rutas. PR endurecido: 40 rutas únicas, incluidas documentación operativa y guardia de emergencia. |
| Limpieza local | PASS: bootstrap temporal eliminado, contenedor PostgreSQL desechable retirado y sin `supabase/.temp/cli-latest` ni `tsconfig.tsbuildinfo`. |

La base SQL fue exclusivamente local y desechable. Se utilizaron stubs locales de `auth` y la publicación de Realtime necesaria para simular el esquema de Supabase. No se usó ninguna credencial ni dato remoto.

### 13.1 Revalidación del 3 de agosto de 2026

| Comprobación | Resultado |
| --- | --- |
| `npm test` | PASS: build Next.js, TypeScript de Next, 5 pruebas HTML/rutas y 37 pruebas TS. |
| Supabase staging `iozcjirlfytryzrcmrnq` en solo lectura | PASS: PostgreSQL 17.6, 500 grupos sintéticos `V2V%`, 10.000 perfiles, 250.000 evidencias y 4 snapshots. |
| Timeouts de RPC V2 en staging | PASS: las RPC V2 autoritativas inspeccionadas exponen `lock_timeout=750ms`; también `record_pachanga_guest_team_rating_token_v2` y `void_my_pachanga_individual_rating_v2`. |
| Snapshot de partido en staging | PASS: `snapshot_pachanga_match_ratings_v2` usa los valores calculados del `result`, no referencias ambiguas del nombre de función. |
| Contrato server-authoritative/cache | PASS local: runbook e informe exigen RPC/API central, `operationId`, revisión esperada, sin cola offline deportiva y read models canónicos. |
| Lint de tests tocados | PASS: `tests/rendered-html.test.mjs` y `tests/rating-system-v2-concurrency.mjs`. |
| Lint global | FAIL esperado: 43 problemas preexistentes, 23 errores y 20 avisos en `app/legal-data.tsx`, `app/mercado/page.tsx`, `app/page.tsx` y `app/theme-toggle.tsx`. |
| Lint focalizado de `app/page.tsx` | FAIL esperado por deuda previa del archivo grande; no se corrige aquí para no mezclar UI/pizarra/efectos con Rating V2. |
| `git diff --check` | PASS. |
| Concurrencia SQL local | No reejecutada en esta vuelta: `RATING_V2_DATABASE_URL` no está cargada en el entorno actual. |
| QA HTTP del preview protegido | Bloqueada por Vercel SSO en lectura automática; el preview de PR #93 existe y está READY, pero el fetch de `/api/client-policy` redirige a SSO incluso con URL temporal. |

## 14. Riesgos y siguiente paso

1. Mantener las 23 migraciones aditivas aplicadas en Supabase staging `iozcjirlfytryzrcmrnq`; la unidad 24 de cierre V1 se activa después y por separado.
2. Ejecutar QA autenticada con dos usuarios y Realtime para confirmar el recorrido navegador, API, PostgreSQL y vuelta al navegador cuando estén disponibles la URL/key de staging o una sesión de navegador autorizada.
3. Seguir `docs/rating-system-v2-deployment-runbook.md`: frontend V2 antes de la revocación final V1, con observación de CPU, locks, errores de revisión y latencia de Realtime.
4. Definir con criterio futbolístico el cuestionario y la fórmula específica de porteros antes de habilitarlos en V2.
5. Completar el flujo persistido de hábitos y limitaciones si se desea que los modificadores actuales sean editables por el jugador.

El despliegue no forma parte de esta tarea. No se ha modificado producción ni se ha realizado merge o despliegue. La rama se publica únicamente mediante un PR borrador.

## 15. Addendum de autorización previa a staging

El runbook incorpora tres nuevas puertas obligatorias, sin sustituir ninguna fase anterior:

1. **Compatibilidad PWA:** `clientVersion` es SemVer del bundle más SHA; `minimumSupportedClientVersion` es una política `no-store` del servidor. Un release puente V1 debe instrumentar las escrituras y actualizar el Service Worker de forma controlada antes de elevar el mínimo a V2.
2. **Silencio V1:** para despliegues con usuarios reales, la unidad 24 exige cero escrituras V1 y cero clientes sin versión durante 24 horas en staging y 7 días naturales en producción. En el lanzamiento preusuarios autorizado el owner dispensa esa espera porque no hay usuarios reales ni PWAs activas; se sustituye por una prueba controlada de PWA antigua, CORS, autenticación, offline, reconexión y Realtime.
3. **Rollback seguro:** la guardia diferida no reabre V1 ni `UPDATE` directo. Mantiene únicamente asistencia por la RPC V2 autoritativa para un frontend mínimo de mantenimiento, priorizando mantenimiento o roll-forward.
4. **Volumen y recuperación:** staging debe registrar duración, filas, locks, CPU e índices por migración, ejecutar el backfill con volumen representativo y restaurar realmente un backup en un destino aislado.

Estas puertas están **documentadas y cubiertas por una prueba contractual local**. El bridge PWA ya completó su staging controlado en el PR #93 y permanece separado de Rating V2. La carga representativa de V2 se ejecutó sobre la rama Supabase de staging y detectó dos mejoras incorporadas al SQL: backfill por sincronización diferida/set-based y rechazo rápido ante locks. Queda pendiente cerrar la concurrencia remota final y la QA de navegador de V2 antes de considerar fusionable la rama.

La guardia sí fue aplicada localmente sobre PostgreSQL 16 después de todo el recorrido de migraciones. La matriz observada fue inequívoca: las diez escrituras V1 quedaron denegadas para `anon` y `authenticated`, `authenticated` no tuvo `UPDATE` sobre `pachanga_groups` y conservó únicamente `EXECUTE` sobre la RPC V2 de asistencia. Esto valida el SQL y su mínimo de permisos, pero no sustituye el ensayo de staging con una PWA V1 real, telemetría, carga ni restauración.
