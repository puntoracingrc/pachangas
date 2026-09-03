# Rating V2 Initial Assessment Onboarding Report

Fecha de apertura: 2026-09-03 23:13 CEST
Fecha de cierre técnico local: 2026-09-04 00:10 CEST
Fecha de cierre de staging: 2026-09-04 00:36 CEST

## 1. Clasificación final

**REPRODUCED_AUTHORITY_DEFECT**

Estado de entrega actual: **READY FOR MERGE**. La reproducción, la corrección,
los gates locales, la Preview exacta y el E2E autenticado en Supabase staging
están cerrados.

## 2. SHA base real

- Repositorio: `puntoracingrc/pachangas`.
- Base: `origin/main`.
- SHA: `7670a69e2f3b5c96b0d47aef76e6c8388b71983a`.
- El SHA coincide con el checkpoint solicitado y contiene los cierres de
  Official UI V3I Batch 001 y 002.
- El checkout compartido conserva intactos sus cambios previos del laboratorio
  de ficha; todo este trabajo vive en un worktree aislado.

## 3. Issue #165

- Issue: [#165](https://github.com/puntoracingrc/pachangas/issues/165).
- Estado al iniciar: `OPEN`.
- Comentarios al iniciar: 0.
- Referencia cruzada localizada: PR #162.
- El issue no se cerrará hasta completar producción y el informe documental.

## 4. Fuentes revisadas

Se revisaron los informes Rating V2 existentes, las 24 migraciones V2 y su
cierre de rutas V1, las autoridades de perfil y assessment, los informes de
perfil social y onboarding V3E/V3F, las suites DB/concurrencia/staging, el
endpoint real, la UI que lo invoca, el ledger local y el ledger remoto.

Los nombres históricos `RATING_SYSTEM_V2_REPORT.md` y las migraciones
`20260805...` indicados en la orden no existen en este `main`; se localizaron y
usaron sus equivalentes reconciliados. No se editó ninguna migración histórica.

## 5. Call graph anterior

1. `app/page.tsx` abre la evaluación y crea una previsualización local.
2. `completeInitialPlayerAssessment` llama una vez a
   `persistSharedEngineAssessment`.
3. `clientWriteFetch` envía intención autenticada a
   `POST /api/ratings/assessment`, con `operationId` y revisión esperada.
4. El endpoint obtiene la sesión, ignora cualquier actor aportado por el
   navegador y recalcula el resultado desde las respuestas originales con
   `calculateSharedAssessmentResult`.
5. Un cliente server-only invoca
   `persist_pachanga_player_assessment_authoritative_v2`.
6. La autoridad bloquea el grupo, valida replay y revisión, y llama a
   `persist_pachanga_player_assessment_v2`.
7. Para `initial`, la función interna llamaba primero a
   `upsert_pachanga_own_player_profile`.
8. El guard del perfil exigía una evaluación inicial ya persistida y abortaba.

## 6. Objetos PostgreSQL implicados

Funciones principales:

- `persist_pachanga_player_assessment_authoritative_v2`.
- `persist_pachanga_player_assessment_authoritative_v2_impl`.
- `persist_pachanga_player_assessment_v2`.
- `upsert_pachanga_own_player_profile`.
- `pachanga_recalculate_player_rating_v2`.
- `sync_pachanga_player_profile_to_groups`.
- `pachanga_authoritative_response_v2`.
- `pachanga_operation_replay_v2`.

Tablas principales:

- `pachanga_groups`.
- `pachanga_group_members`.
- `pachanga_player_profiles`.
- `pachanga_player_assessments`.
- `pachanga_player_rating_snapshots`.
- `pachanga_operation_receipts`.
- `pachanga_group_events`.

## 7. Reproducción

Se construyó PostgreSQL 17.6 desde el baseline canónico y todas las migraciones
del SHA base. Dos actores sintéticos independientes comenzaron con identidad
Auth y membresía mínima, pero sin perfil, evaluación, ficha, rating, evento,
receipt ni notificación. Ambos llamaron exactamente a la autoridad usada por
la aplicación, sin insertar perfil o evaluación manualmente.

Resultado de ambos recorridos:

- éxito: no;
- SQLSTATE: `P0001`;
- mensaje: `Complete the initial player assessment before creating a new profile`;
- perfil parcial: 0;
- evaluación huérfana: 0;
- snapshot/facetas parciales: 0;
- evento: 0;
- receipt de éxito: 0;
- notificación: 0.

El identificador textual histórico `rating_initial_assessment_required` ya no
era el mensaje emitido, pero el defecto de autoridad era el mismo.

## 8. Causa raíz

La aplicación ya realizaba una sola llamada al servidor. El defecto estaba
dentro de la transacción SQL: el perfil se intentaba crear antes de insertar la
evaluación inicial que autorizaba su creación. El guard funcionaba como estaba
diseñado, pero el orden interno hacía imposible el primer alta legítima.

## 9. Solución

La migración nueva redefine solo las dos funciones internas necesarias. Para
una evaluación `initial` válida:

1. valida íntegramente actor, membresía, motor, versiones, rating, fiabilidad,
   seis facetas heredadas y seis facetas V2;
2. valida replay, fingerprint y revisión bajo los locks existentes;
3. inserta la evaluación con `player_profile_id` temporalmente nulo;
4. ejecuta el upsert protegido del perfil dentro de la misma transacción;
5. bloquea el perfil resultante y enlaza la evaluación;
6. conserva el mismo cálculo, resumen, sincronización, evento y receipt;
7. confirma todo o revierte todo.

No se desactiva el guard. No se concede DML al navegador. No se cambia la UI,
el endpoint, el motor, las fórmulas, las facetas, la escala ni las ventanas.

## 10. Atomicidad

Las pruebas PostgreSQL demuestran rollback total para:

- payload inválido;
- campo obligatorio ausente;
- faceta fuera de rango;
- revisión obsoleta;
- error inducido durante la creación del perfil.

En todos los casos quedan cero perfiles parciales, evaluaciones huérfanas,
eventos engañosos y receipts de éxito.

## 11. Idempotencia

Se reutiliza `pachanga_operation_receipts`; no se crea un ledger paralelo. La
intención recibe un SHA-256 server-side en
`client_metadata.assessmentRequestFingerprint`.

- Mismo `operationId` y misma intención: mismo resultado canónico.
- La variación no autoritativa de `calculatedAt` en el resultado recalculado no
  rompe el replay.
- Mismo `operationId` con intención distinta: `PT409`, sin segunda escritura.
- Timeout o respuesta perdida: el retry recupera el receipt original.

## 12. Concurrencia

Pruebas reales con varias conexiones PostgreSQL cubren:

- dos llamadas idénticas simultáneas;
- mismo identificador con payload incompatible;
- dos operaciones distintas para el mismo actor;
- fanout de seis llamadas;
- dos actores independientes;
- retry tras respuesta perdida.

Resultado: un perfil, una evaluación, un evento y un receipt por actor; cero
deadlocks, duplicados o respuestas contradictorias.

## 13. Grants y RLS

Estado verificado en fresh, upgrade y staging:

- RLS activa en `pachanga_player_profiles` y
  `pachanga_player_assessments`.
- Solo existen políticas de lectura propia para `authenticated`.
- No existen políticas `INSERT`, `UPDATE`, `DELETE` o `ALL` en esas tablas.
- La envoltura pública es ejecutable por `service_role`, no por `anon` ni
  `authenticated`.
- Las dos implementaciones internas están revocadas para `PUBLIC`, `anon`,
  `authenticated` y `service_role`.
- Las funciones redefinidas mantienen `SECURITY DEFINER` y
  `search_path=pg_catalog` con nombres de esquema explícitos.

## 14. Direct writes

Los intentos autenticados de insertar directamente perfil o evaluación fallan.
La llamada autenticada al helper interno también falla. No se añadió ninguna
ruta de bypass ni se expuso una clave `service_role` al cliente.

## 15. Cliente y server action

No fue necesario modificar `app/`. La ruta existente ya cumplía el contrato:
una intención, actor derivado de sesión, cálculo server-side, espera de
respuesta autoritativa y caché `no-store`. La corrección es compatible con el
frontend anterior y con el actual.

## 16. Offline

El intento sintético sin red falla cerrado y no crea filas. No existe una cola
offline para esta operación deportiva. Tras reconectar, el mismo
`operationId` puede recuperar la respuesta confirmada del servidor.

## 17. Realtime

La operación confirmada emite un único
`player_initial_assessment_v2_completed` con secuencia de servidor. El cliente
usa el evento como invalidación y relee el estado canónico; el payload WAL no
se trata como autoridad.

## 18. Migración

Nueva migración forward-only:

`20260903211715_rating_v2_atomic_initial_assessment_onboarding.sql`

No crea tablas, columnas, índices, triggers, RLS ni flags. Sustituye la
definición de dos funciones y reafirma sus revokes. Las 235 migraciones
históricas permanecen sin cambios.

## 19. Ledger

- Producción antes del release: 235, última
  `20260902102800_social_inbox_receipt_notification_index_v1`.
- Fresh/upgrade local tras la migración: 236, última
  `20260903211715_rating_v2_atomic_initial_assessment_onboarding`.
- Staging efímero tras bootstrap reconciliado: 236 versiones únicas, misma
  última versión.

## 20. Fresh y upgrade

Se validaron dos recorridos independientes:

- fresh: baseline canónico más todas las migraciones;
- upgrade: esquema reproducido desde `main` más la migración nueva.

Ambos ejecutan las suites nuevas y las históricas. Sus esquemas normalizados
`public/private` resultan equivalentes con SHA-256:

`b15fb054abba913fad4e5598378b6d5a48d8f8fa6a06f4184b5d8e2546493c59`

Hashes finales de las funciones modificadas:

- authority impl: `c96b377142ca123412eb47a154207c67`;
- assessment impl: `429056ea0ec389b04ae1e096843cf8f0`.

## 21. Staging

Rama Supabase desechable:

- nombre: `rating-v2-issue-165-20260903`;
- ref: `imgvsrjgaobsfnphmepc`;
- PostgreSQL: 17.6;
- salud del proyecto: `ACTIVE_HEALTHY`;
- filas iniciales en grupos, miembros, perfiles, evaluaciones, eventos y
  notificaciones: 0.

La rama nació con el bootstrap de migraciones incompleto. Se aplicó el baseline
canónico, se reconciliaron sus 36 versiones absorbidas y se ejecutaron en orden
las incrementales hasta 236. El test SQL transaccional remoto pasa y vuelve a
`0 perfiles | 0 evaluaciones | 0 grupos`.

Preview funcional validada:

- deployment: `dpl_8Lg3ikVpQsPFpzns5MTXNKLtLYZM`;
- URL inmutable:
  `https://pachangas-erv2koe4x-persianas-almar-web-s-projects.vercel.app`;
- metadata SHA: `29de4fd4028d7d90571c482c1b75c9712a854076`;
- estado: `READY`.

El E2E utilizó cinco usuarios Auth sintéticos, un actor con dos sesiones
simultáneas y las rutas reales Preview/API/Supabase. Verificó alta inicial,
perfil y evaluación enlazados, ficha/read model, retry tras respuesta perdida,
doble submit, conflicto de payload, revisión obsoleta, actor adulterado
ignorado, DML/helper interno denegados, fallo offline, Realtime y refetch
canónico. Resultado: `PASS`, con cero notificaciones.

Antes de destruir staging se leyeron exactamente 5 usuarios, 4 grupos, 3
perfiles, 3 evaluaciones, 3 eventos, 3 receipts y 0 notificaciones sintéticas.
La rama Supabase fue eliminada después de recoger la evidencia y su ref dejó de
estar presente. Las tres variables Vercel Preview limitadas a esta rama también
fueron retiradas.

El primer intento Preview fue rechazado con 401 porque el arnés usaba la
cabecera de protección de Vercel donde la API necesitaba el bearer de Supabase.
Se sustituyó por la cookie temporal oficial. Un intento posterior demostró el
flujo funcional y detectó una aserción exacta de coma flotante
(`5.499999999999999` frente a `5.5`); se corrigió exclusivamente el test con
tolerancia de `1e-9`, sin modificar cálculo ni dato persistido.

## 22. Seguridad y Advisors

No aparece ninguna alerta de Advisors específica de las funciones, perfiles o
evaluaciones modificadas. Staging reproduce la deuda preexistente de Advisors;
el mayor número de índices sin uso se debe a que la rama está vacía. No se
corrige deuda ajena en este hotfix.

Las firmas semánticas de staging y producción coinciden para columnas,
constraints, índices, políticas, RLS y triggers. Al excluir las dos funciones
del hotfix, se observan tres definiciones públicas preexistentes distintas entre
la cadena del repositorio y producción (`append_pachanga_player_rating`,
`finalize_pachanga_match_if_current_impl` y
`save_pachanga_payload_if_current_impl`). Ninguna participa en el alta inicial;
no se altera dentro de este alcance.

## 23. Pruebas focalizadas

- Contrato TypeScript: 6/6 PASS.
- Nueva suite DB/RLS/atomicidad: PASS.
- Nueva suite de concurrencia: PASS.
- Rating V2 DB histórico: PASS.
- Rating V2 concurrencia histórica: PASS.
- Instalación fresh: PASS.
- Upgrade exacto: PASS.
- Staging SQL con rollback: PASS.
- Staging Auth/API/Realtime: PASS.
- Staging dos sesiones/concurrencia/retry: PASS.
- Staging directo/offline/revisión obsoleta: PASS fail-closed.
- Preview `/perfil` y Service Worker exacto: PASS.

La limpieza de la suite histórica de concurrencia se adaptó a las tablas
operativas inmutables añadidas por Wave 8B. El cambio solo borra los fixtures
propios al finalizar y no modifica ninguna aserción de producto.

## 24. Suite global

Baseline:

- total: 862/862;
- Node: 20/20;
- TS/TSX: 842/842;
- rutas estáticas: 78/78.

Resultado final local actual:

- total: 868/868;
- Node: 20/20;
- TS/TSX: 848/848;
- failed/skipped/todo/cancelled: 0/0/0/0;
- rutas estáticas: 78/78;
- typecheck: PASS;
- build independiente: PASS;
- lint global: PASS;
- lint focalizado: PASS;
- `git diff --check`: PASS;
- secret scan: PASS.

QA visual de la Preview exacta:

- `1440x900`: PASS;
- `390x844`: PASS;
- `360x800`: PASS;
- `844x390`: PASS;
- overflow, controles cortados, imágenes rotas y overlays: 0;
- errores y warnings de consola: 0;
- 4xx inesperados: 0 (los tres 400 son los rechazos intencionados del E2E);
- 5xx: 0.

## 25. Datos reales y servicios externos

- Usuarios reales creados: 0.
- Perfiles reales creados: 0.
- Evaluaciones reales creadas: 0.
- Equipos o entidades reales creadas: 0.
- Notificaciones externas: 0.
- Push/email/SMS/WhatsApp: 0.
- Stripe: 0 llamadas y 0 cambios.
- Producción: solo lectura hasta el release autorizado por esta tarea.

## 26. Regresiones

Las suites globales mantienen verdes Rating V2, perfil social, onboarding V3E,
núcleo V3F, cartas, Auth, RLS, Realtime, offline, PWA, Social Core Hotfix 001 y
002, Official UI V3H y Official UI V3I Batch 001/002.

- `SOCIAL-RC-001` a `SOCIAL-RC-012`: cerrados y congelados.
- `OFFICIAL-UI-V3I-001` a `OFFICIAL-UI-V3I-003`: cerrados y congelados.

## 27. Rollback

Antes de producción se conserva la definición anterior y sus hashes. La
estrategia prioritaria es roll-forward. Una migración compensatoria podría
restaurar las dos funciones anteriores, sin tocar datos ni abrir DML, aunque
reintroduciría el bloqueo. No se aplicará salvo incidente real.

## 28. Límites

No se modifica UI, CSS, navegación, Demo World, cartas, logros, recompensas,
escudos, Conduct, competiciones, venues, pagos, Stripe, Service Worker,
manifest, Google Places ni otros issues. No se inicia Wave 9C.

La QA física Android, iPhone y PWA instalada permanece `PENDING` y está fuera
del alcance autorizado.

## 29. Archivos del cambio funcional

- `RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_PLAN.md`.
- `RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_REPORT.md`.
- `supabase/migrations/20260903211715_rating_v2_atomic_initial_assessment_onboarding.sql`.
- `tests/rating-v2-initial-onboarding-authority.test.ts`.
- `tests/rating-v2-initial-onboarding-authority-db.sql`.
- `tests/rating-v2-initial-onboarding-concurrency.mjs`.
- `tests/rating-v2-initial-onboarding-staging-e2e.mjs`.
- `tests/rating-system-v2-concurrency.mjs`.
- `package.json`.

`package-lock.json`: sin cambios. Migraciones históricas: sin cambios.

## 30. Estado productivo

- PR funcional: pendiente de apertura tras el último gate local.
- Migración productiva: no aplicada.
- Deployment funcional: pendiente.
- Smoke y logs productivos: pendientes.
- Issue #165: abierto.

## 31. Estado del issue

El defecto está reproducido y la corrección está verificada localmente y en
staging autenticado. El issue permanece abierto hasta completar merge,
migración, deployment, readback y el PR documental de producción.

## 32. Conclusión

La solución es mínima y server-authoritative. Rompe el ciclo sin relajar el
guard: la evaluación válida nace primero de forma provisional dentro de la
misma transacción, habilita el perfil protegido, se enlaza a ese perfil y solo
entonces se confirma el conjunto completo. Ningún estado parcial es visible si
la transacción falla.
