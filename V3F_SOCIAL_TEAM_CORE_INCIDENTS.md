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

No se han ocultado fallos. Incidencias remotas se añadirán aquí antes de
cualquier hotfix de staging o producción.
