# V3F Social Team Core Incidents

Registro permanente de defectos encontrados durante la implementación y QA.

| ID | Clase | Estado | Escenario original | Corrección | Regresión |
| --- | --- | --- | --- | --- | --- |
| V3F-001 | TESTABILITY_GAP | fixed | El test global obligaba a que Inicio invocase `join_pachanga_team`, aunque V3F debía cerrar esa autoridad legacy. | La expectativa exige lookup/command V2 y prohíbe la invocación antigua. | regression_verified, `npm test` |
| V3F-002 | TESTABILITY_GAP | fixed | El test global exigía fabricar un enlace permanente desde `currentTeam.inviteToken`. | Se exige ausencia del enlace legacy y se verifica la invitación raw-once en `/equipo/invitaciones`. | regression_verified, `npm test` |
| V3F-003 | TESTABILITY_GAP | fixed | Dos contratos V3A/Wave 8D buscaban `Ver plantilla` en el menú global después de convertir `/equipo` en portada contextual. | Los tests exigen `Ver equipo`; plantilla permanece en su subruta. | regression_verified, `npm test` |
| V3F-004 | TESTABILITY_GAP | fixed | El bridge PWA interpretaba tres RPC V3F de lectura como escrituras por no conocerlas. | Se añadieron los lookups/read models al allowlist de lectura; los commands siguen en el gate de escritura. | regression_verified, 45/45 focales y 800/800 globales |
| V3F-005 | PRODUCT_BUG | fixed | El botón de invitación administrativa podía quedar habilitado offline y no producir feedback. | El control se deshabilita/explica y todo command muestra el mensaje offline canónico. | regression_verified, prueba V3F offline |
| V3F-006 | PRODUCT_BUG | fixed | El efecto inicial de Equipo y un Effect Event producían contratos de hooks inestables durante el lint focalizado. | Carga inicial diferida y dependencias ajustadas sin suprimir reglas. | regression_verified, lint 0/0 y typecheck PASS |
| V3F-007 | ENVIRONMENT_ISSUE | fixed_for_v3f_qa | La rama Supabase vacía falló al reproducir migraciones históricas porque `20260728191804` presupone `public.pachanga_admin_invites`, tabla procedente del bootstrap consolidado y no de una migración versionada anterior. | Se creó una base efímera solo de esquema desde el proyecto canónico, sin filas ni PII, y se reconcilió su ledger con las 228 versiones productivas. No se reescribió historia. La reproducibilidad desde cero permanece como deuda separada preexistente. | regression_verified, ledger efímero 228/228 antes de V3F y runner PostgreSQL con rollback |
| V3F-008 | ENVIRONMENT_ISSUE | fixed_for_v3f_qa | La restauración inicial del esquema abortó porque la rama vacía no tenía la extensión `btree_gist` requerida por constraints históricas. | Se instaló la extensión exclusivamente en la rama efímera y se repitió la restauración en una transacción nueva; el primer intento no dejó cambios parciales. | regression_verified, restauración completa y ledger conciliado |
| V3F-009 | SIMULATION_BUG | fixed | El clon `schema-only` no contenía filas estáticas del catálogo cosmético y la creación atómica no podía resolver el escudo base permitido. | Se sembraron únicamente ocho fixtures de catálogo no personales, sin copiar usuarios, actividad ni datos deportivos. | regression_verified, creación atómica y runner SQL remoto con rollback |
| V3F-010 | ENVIRONMENT_ISSUE | fixed | La API de aplicación de migraciones asignó versiones de la hora actual a tres scripts y rechazó dos payloads por tamaño, aunque el SQL se aplicó correctamente. | Se revirtió solo el ledger generado, se registraron las cinco versiones exactas `20260901214523`–`20260901214527` y los dos scripts grandes se ejecutaron en transacciones PostgreSQL explícitas. | regression_verified, ledger efímero exacto 233/233, sin versiones extra |
| V3F-011 | PRODUCT_BUG | fixed | Advisors detectó ocho claves foráneas V3F sin índice de cobertura. | La migración final añade los ocho índices dirigidos a actor, creador, aceptante y declinante. | regression_verified, 0 `unindexed_foreign_keys` V3F y prueba SQL de presencia de los ocho índices |
| V3F-012 | TESTABILITY_GAP | fixed | La matriz SQL no demostraba explícitamente que una sesión anónima autenticable siguiera sin perfil social ni que un usuario ordinario no pudiera cambiar flags de plataforma. | RPC, políticas y regresiones exigen usuario registrado; el command de plataforma conserva su capability interna. | regression_verified, anónimo sin lecturas V3F y usuario ordinario sin `flags.write` |
| V3F-013 | TESTABILITY_GAP | fixed | El primer E2E remoto quedó esperando una invalidación aunque el canal ya informaba `SUBSCRIBED`; el arnés no esperaba la confirmación específica del binding `postgres_changes`. | El arnés espera ahora el ACK `postgres_changes` antes de disparar el command. Los flags se devolvieron a OFF automáticamente y no se tocó producción. | regression_verified, invalidación, refetch y reconexión remotos superados |
| V3F-014 | TESTABILITY_GAP | fixed | El segundo E2E remoto superó todo el flujo funcional pero exigió que `/sw.js` contuviera literalmente “V3F”, aunque el worker identifica el release por SHA y precachea las rutas V3F. | La prueba valida ahora el SHA exacto del worker, `Cache-Control: no-store` y las tres rutas sociales precacheadas. | regression_verified, Preview exacta y seis rutas PASS |
| V3F-015 | TESTABILITY_GAP | fixed | El E2E remoto imprimió `OFFICIAL_UI_V3F_STAGING_PASS`, pero los sockets Realtime mantuvieron vivo el proceso hasta su cierre manual. | El cierre desconecta explícitamente cada cliente Realtime después de retirar canales y sesiones. | regression_verified, repetición completa finalizada con exit code 0 |
| V3F-016 | ENVIRONMENT_ISSUE | fixed_for_release | La integración GitHub no pudo sacar el PR funcional de draft porque GraphQL devolvió `fullDatabaseId` indefinido. | Se utilizó `gh pr ready` sobre el mismo PR y se verificó su estado antes del merge. | regression_verified, PR #253 fusionado |
| V3F-017 | ENVIRONMENT_ISSUE | fixed_for_release | El entorno local no dispone de `curl` para el smoke HTTP productivo previsto. | Se ejecutaron las mismas lecturas con `fetch` de Node, sin escrituras ni cambio de contrato. | regression_verified, rutas, manifest y Service Worker con HTTP 200 |
| V3F-018 | TESTABILITY_GAP | fixed | El conector SQL rechazó como `INVALID_ARGUMENT` el bloque monolítico de canaries productivos con rollback. | La matriz se dividió en siete transacciones independientes, cada una con rollback y readback de residuo. | regression_verified, siete canaries PASS y residuo sintético global cero |
| V3F-019 | ENVIRONMENT_ISSUE | fixed_for_release | La URL local del pooler vinculado no incluía contraseña y no permitía abrir una sesión `psql`; no llegó a ejecutarse SQL. | Los readbacks y canaries se ejecutaron mediante el conector Supabase autorizado, conservando transacciones y rollback. | regression_verified, ledger, ACL, flags, hashes y residuo leídos desde PostgreSQL |
| V3F-020 | SIMULATION_BUG | fixed | El arnés del canary de invitaciones envió `teamRevision` donde el command exige `confirmedRevision`. | Se corrigió exclusivamente el envelope del arnés para usar la revisión canónica devuelta por el servidor. | regression_verified, creación, replay raw-once, aceptación e idempotencia PASS |
| V3F-021 | PRODUCT_BUG | fixed | En la entrada pública a `844x390`, la traslación fija del logo combinada con su límite compacto recortaba el escudo por el borde izquierdo. | El modo landscape compacto aplica una traslación proporcional al ancho del logo, sin cambiar la composición desktop o portrait. | regression_verified, test V3F, QA local `844x390`, 0 overflow y 0 imágenes rotas |
| V3F-022 | SIMULATION_BUG | fixed | El primer intento de activación final consultó `roles.created_at`, columna inexistente; la transacción abortó antes de aplicar cambios. | El arnés usa la columna canónica `granted_at` y repitió la activación mediante la RPC de plataforma. | regression_verified, settings revision 7 y siete flags V3F activos |
| V3F-023 | SIMULATION_BUG | fixed | Un readback diagnóstico consultó `aggregate_type` en vez de la columna canónica `aggregate_kind`; no ejecutó mutaciones. | La consulta se corrigió contra el esquema real y se repitió el readback. | regression_verified, receipts y eventos de settings reconciliados |

## Advisors de la rama efímera

- `unindexed_foreign_keys`: `0` para V3F después de V3F-011.
- `unused_index`: 17 avisos `INFO`, esperables en una rama vacía y conservados
  porque protegen claves y consultas productivas.
- `authenticated_security_definer_function_executable`: un aviso genérico para
  el command de configuración. Es una superficie intencional que valida
  `flags.write` dentro de PostgreSQL; la regresión de V3F-012 demuestra que un
  usuario ordinario no puede ejecutarla con éxito.
- `auth_allow_anonymous_sign_ins`: cuatro avisos globales. Las rutas V3F exigen
  además `is_registered_pachanga_user()` y la regresión de V3F-012 confirma que
  una sesión anónima no obtiene los read models. No se cambió la configuración
  global de Auth dentro de esta fase.

No se han ocultado fallos. Cualquier incidencia nueva de Preview, canary o
producción se registrará aquí antes de corregirse.
