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
