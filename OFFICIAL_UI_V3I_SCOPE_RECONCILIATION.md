# Official UI V3I Scope Reconciliation

## 1. Resumen ejecutivo

Este gate reconstruye el alcance mínimo justificable de Official UI V3I desde
`origin/main`, los contratos sociales vigentes, los cierres de V3H y de los dos
hotfixes, el código invocado actualmente y una comprobación read-only focalizada
en producción. No implementa ningún cambio de interfaz.

Resultado:

- 3 candidatos cumplen la regla de evidencia A + B1.
- 12 elementos `SOCIAL-RC-001` a `SOCIAL-RC-012` permanecen cerrados y
  congelados.
- 0 regresiones de release fueron reproducidas.
- 2 lotes pequeños e independientemente fusionables son suficientes.
- Wave 9C no tiene una definición canónica localizada y no se ha reanudado.
- Android físico, iPhone físico y PWA físicamente instalada siguen `PENDING`.

La decisión no nace de una preferencia estética. Los tres candidatos incumplen
el contrato de accesibilidad existente y se reproducen en el producto actual.

## 2. Checkpoint exacto

Auditoría documental realizada el `2026-09-03T18:06:20+02:00`.

| Comprobación | Resultado |
| --- | --- |
| Repositorio | `puntoracingrc/pachangas` |
| `pwd` inicial | `/Users/macbookpro14/Documents/steam deck` |
| `git rev-parse --show-toplevel` | `/Users/macbookpro14/Documents/steam deck` |
| `git rev-parse --git-dir` | `.git` |
| `git rev-parse --git-common-dir` | `.git` |
| Rama del checkout compartido | `main` |
| `git fetch origin --prune` | Ejecutado sin modificar el checkout compartido |
| `git rev-parse origin/main` | `8d57b693bf98efbc03859ef84e99552dd8dc4b09` |
| Worktrees antes del aislamiento | 23 registrados; todos preservados |
| Worktree de este gate | `/Users/macbookpro14/.codex/worktrees/pachangas-official-ui-v3i-definition` |
| Rama aislada | `codex/official-ui-v3i-definition` |
| HEAD inicial del worktree | `8d57b693bf98efbc03859ef84e99552dd8dc4b09` |
| Entorno | macOS, `zsh`, Git, GitHub CLI y navegador Playwright read-only |
| Servicios consultados | GitHub y superficies públicas de `pachangasiq.com`; Supabase y Stripe no consultados |

Estado inicial preservado del checkout compartido:

```text
## main...origin/main [behind 654]
 M app/laboratorio-ficha-jugador/_engine/player-rating-engine.ts
 M app/laboratorio-ficha-jugador/page.module.css
 M app/laboratorio-ficha-jugador/page.tsx
?? .codex-worktrees/
?? supabase/.temp/
```

Esos cambios no se restauraron, movieron, incluyeron ni editaron. El worktree
aislado nació limpio.

## 3. SHA base real

La base real y el SHA conocido coinciden:

```text
8d57b693bf98efbc03859ef84e99552dd8dc4b09
```

Los merges funcional y documental del Batch 002 siguen contenidos en esa base:

- funcional: `b959bda37c63e1d3a87463e9af6c3acf0e2a1b97`;
- documental/final: `8d57b693bf98efbc03859ef84e99552dd8dc4b09`.

## 4. Fuentes revisadas

### Cierres y contratos

- [OFFICIAL_UI_V3H_END_TO_END_REPORT.md](./OFFICIAL_UI_V3H_END_TO_END_REPORT.md)
- [SOCIAL_CORE_V3H_USABILITY_AUDIT.md](./SOCIAL_CORE_V3H_USABILITY_AUDIT.md)
- [V3H_SOCIAL_CORE_INCIDENTS.md](./V3H_SOCIAL_CORE_INCIDENTS.md)
- [OFFICIAL_UI_V3H_PRODUCTION_RELEASE.md](./OFFICIAL_UI_V3H_PRODUCTION_RELEASE.md)
- [OFFICIAL_UI_V3H_ALBERTO_REVIEW_GUIDE.md](./OFFICIAL_UI_V3H_ALBERTO_REVIEW_GUIDE.md)
- [SOCIAL_CORE_PRODUCT_LANGUAGE_V1.md](./SOCIAL_CORE_PRODUCT_LANGUAGE_V1.md)
- [SOCIAL_CORE_VISUAL_CONTRACT_V1.md](./SOCIAL_CORE_VISUAL_CONTRACT_V1.md)
- [SOCIAL_CORE_RC_HOTFIX_001_PLAN.md](./SOCIAL_CORE_RC_HOTFIX_001_PLAN.md)
- [SOCIAL_CORE_RC_HOTFIX_001_REPORT.md](./SOCIAL_CORE_RC_HOTFIX_001_REPORT.md)
- [SOCIAL_CORE_RC_HOTFIX_001_PRODUCTION_RELEASE.md](./SOCIAL_CORE_RC_HOTFIX_001_PRODUCTION_RELEASE.md)
- [SOCIAL_CORE_RC_HOTFIX_002_PLAN.md](./SOCIAL_CORE_RC_HOTFIX_002_PLAN.md)
- [SOCIAL_CORE_RC_HOTFIX_002_REPORT.md](./SOCIAL_CORE_RC_HOTFIX_002_REPORT.md)
- [SOCIAL_CORE_RC_HOTFIX_002_PRODUCTION_RELEASE.md](./SOCIAL_CORE_RC_HOTFIX_002_PRODUCTION_RELEASE.md)

### Código y pruebas actuales

- `app/_components/product-navigation-contract.ts`
- `app/_components/product-context-selector.tsx`
- `app/_components/product-context-selector.module.css`
- `app/_components/official-product-shell-v2.tsx`
- `app/_components/official-home-game-dashboard.tsx`
- `app/_components/official-match-game-hub.tsx`
- `app/_components/official-match-experience.tsx`
- `app/_components/official-market-game-view.tsx`
- `app/demo-world/demo-world-app.tsx`
- `app/demo-world/demo-social-quick-review.tsx`
- `app/demo-world/demo-world.module.css`
- `app/retos/page.tsx`
- `app/mercado/marketplace-client.tsx`
- `app/mercado/marketplace-v3d.module.css`
- `app/equipo/social-team-client.tsx`
- `app/perfil/profile-client.tsx`
- `app/avisos/page.tsx`
- `tests/official-ui-v3h-social-core.test.ts`
- `tests/social-core-rc-hotfix-001.test.ts`
- `tests/social-core-rc-hotfix-002.test.ts`
- pruebas existentes de Official UI V2/V2.1/V3A/V3B/V3C/V3E/V3F,
  navegación, responsive, PWA y Demo registradas en `package.json`.

### Historial y PR

Se revisaron `git log`, `git show`, los diffs y metadatos de GitHub de:

| PR | Propósito | HEAD | Merge |
| --- | --- | --- | --- |
| `#258` | Official UI V3H funcional | `234f10714acc85287ecece10dcefd1a155323006` | `c55e35a2460840195242d2cfd0529554839397ea` |
| `#259` | Cierre documental V3H | `a49b4cfacc3357fcbce3f4d187e78a63f5e74e8e` | `c762948cad6fc80579189c4e6f33b41de13820a4` |
| `#260` | Hotfix Batch 001 | `052b5cc7a8f904d1d10b84f539bac963dbe41050` | `32e9035d8f1a90ce2d3f3da19190f9bbfb584128` |
| `#261` | Cierre documental Batch 001 | `33cad56dbf3fa4321480d21a23bda5e07edca98a` | `fe6430a8f02dadf4300645d07713d91bcbc15cd0` |
| `#262` | Hotfix Batch 002 | `0e20d3d08f2f7b3d3fbbb12458b6633f5dc4eabc` | `b959bda37c63e1d3a87463e9af6c3acf0e2a1b97` |
| `#263` | Cierre documental Batch 002 | `3ca50e3b33c30943591aae84d71d25f53b642e20` | `8d57b693bf98efbc03859ef84e99552dd8dc4b09` |

Las búsquedas en repositorio, issues y PR no localizaron una especificación de
V3I ni de Wave 9C más allá de afirmar que no se habían iniciado.

## 5. Estado de V3H

V3H está `RELEASED / PRODUCTION VERIFIED`. Sus recorridos sociales, cuatro
destinos principales, Demo local, responsive emulado, PWA emulada y contratos
de producto están cerrados. El ledger V3H no deja una tarea funcional asignada
expresamente a V3I. Las incidencias V3H están corregidas con regresión o
aceptadas como diferencias legítimas.

El incidente `V3H-033` de CSS productivo obsoleto quedó corregido mediante un
deployment sin caché y no se reproduce. `V3H-030` describe una limitación OIDC
de una Preview protegida, validada después en producción pública; es una
cuestión de entorno, no una tarea V3I.

## 6. Estado de Batch 001

Batch 001 cerró `SOCIAL-RC-001`, `004`, `006`, `008` y `010`. Su informe dejó
explícitamente fuera dos deudas Axe preexistentes de Mercado: `select-name`
crítica y `region` moderada. No las corrigió para respetar el alcance del
hotfix. Esa exclusión, unida a la reproducción actual, proporciona evidencia
para dos candidatos nuevos sin reabrir los IDs cerrados.

## 7. Estado de Batch 002

Batch 002 cerró `SOCIAL-RC-002`, `003`, `005`, `007`, `009`, `011` y `012`, y
volvió a comprobar los cinco IDs del Batch 001. Su informe mantuvo como baseline
26 nodos preexistentes de contraste en tema claro a 1024 px. La reproducción
actual devuelve exactamente 26 nodos en ese contexto, por lo que es deuda
preexistente, no regresión del Batch 002.

Baseline certificado conservado:

- Node: 20/20.
- TS/TSX: 825/825.
- Total: 845/845.
- Failed/skipped/todo/cancelled: 0/0/0/0.
- Typecheck, build, lint, `git diff --check` y secret scan: PASS.

Este gate no repite esa batería porque no modifica archivos ejecutables.

## 8. FROZEN CLOSED WORK

| ID | Estado | Cierre | Regresión | Componentes congelados | Contrato que V3I conserva |
| --- | --- | --- | --- | --- | --- |
| `SOCIAL-RC-001` | CLOSED/FROZEN | Batch 001 | `tests/social-core-rc-hotfix-001.test.ts` | `demo-world-app.tsx`, navegación Demo | Back/Forward usa historial real y conserva Demo/deep link. |
| `SOCIAL-RC-002` | CLOSED/FROZEN | Batch 002 | `tests/social-core-rc-hotfix-002.test.ts` | first-time journey, quick review, Demo app | Usuario nuevo activa su perspectiva declarada sin heredar Admin. |
| `SOCIAL-RC-003` | CLOSED/FROZEN | Batch 002 | `tests/social-core-rc-hotfix-002.test.ts` | búsqueda y ubicación de Mercado | Campo útil y controles nombrados de 44 x 44 en compacto. |
| `SOCIAL-RC-004` | CLOSED/FROZEN | Batch 001 | `tests/social-core-rc-hotfix-001.test.ts` | estado de consulta de Mercado | Sin sesión muestra `Sin consultar`; no inventa un cero autoritativo. |
| `SOCIAL-RC-005` | CLOSED/FROZEN | Batch 002 | `tests/social-core-rc-hotfix-002.test.ts` | first-time journey e inbox Demo | La UI muestra lenguaje de producto, no nombres internos. |
| `SOCIAL-RC-006` | CLOSED/FROZEN | Batch 001 | `tests/social-core-rc-hotfix-001.test.ts` | inbox Demo, partido exacto | Aviso de asistencia abre y resuelve el partido correcto localmente. |
| `SOCIAL-RC-007` | CLOSED/FROZEN | Batch 002 | `tests/social-core-rc-hotfix-002.test.ts` | detalle de reto y bloqueo local | Una acción primaria, contrapropuesta secundaria y destructivas agrupadas. |
| `SOCIAL-RC-008` | CLOSED/FROZEN | Batch 001 | `tests/social-core-rc-hotfix-001.test.ts` | `market-detail-sheet.tsx` y diálogo Demo | Foco inicial/contenido, Escape, fondo inerte y retorno al activador. |
| `SOCIAL-RC-009` | CLOSED/FROZEN | Batch 002 | `tests/social-core-rc-hotfix-002.test.ts` | Inicio y proyección de partidos Demo | `Ver próximo partido` abre el partido canónico exacto. |
| `SOCIAL-RC-010` | CLOSED/FROZEN | Batch 001 | `tests/social-core-rc-hotfix-001.test.ts` | solicitud de plaza en Mercado/Demo | Estado único `sending -> pending`, sin doble envío ni éxito offline. |
| `SOCIAL-RC-011` | CLOSED/FROZEN | Batch 002 | `tests/social-core-rc-hotfix-002.test.ts` | selector de contexto compartido | Título, tipo, rol, detalle, estado y siguiente acción siguen disponibles. |
| `SOCIAL-RC-012` | CLOSED/FROZEN | Batch 002 | `tests/social-core-rc-hotfix-002.test.ts` | garantías de quick review | Región nombrada, foco, flechas, Home/End, Escape y retorno de foco. |

Ninguno se reabre por diferencias cosméticas. La comprobación focalizada no
reprodujo una regresión de estos contratos.

## 9. Contratos estables

### Navegación

- Inicio, Partidos, Retos y Mercado son exactamente los cuatro destinos
  primarios.
- Perfil, Equipo, Avisos y administración son destinos contextuales.
- El selector compartido es la única entrada de cambio de contexto.
- Back/Forward conserva contexto y detalle; un deep link no rompe la shell.
- V3I no añade una quinta pestaña ni reordena el producto.

### Autoridad

- El servidor es autoridad para datos reales.
- La caché local es una lectura derivada.
- Offline bloquea escrituras y nunca presenta éxito ficticio.
- No se añade una cola deportiva offline ni una segunda autoridad local.

### Demo

- Datos sintéticos y mutaciones de sesión local.
- Solo `Reiniciar Demo` resetea la sesión completa.
- Cero escrituras remotas, entidades reales, notificaciones externas, push,
  email y llamadas Stripe.
- El carácter de simulación sigue visible.

### Identidad visual

- Las superficies no tienen que compartir densidad.
- Mobile Game Landscape, Carta, escudo, alineación y resultados pueden ser más
  visuales que Mercado o Ajustes.
- Toda corrección es local e incremental; no existe un rediseño global V3I.

### Accesibilidad y PWA

- Targets prioritarios de 44 x 44, foco visible, orden lógico, diálogos seguros,
  Escape, landmarks, nombres accesibles, reduced motion y forced colors.
- No se aceptan violaciones críticas o serias nuevas.
- Manifest y estrategia de Service Worker permanecen intactos.
- No se añade Background Sync deportivo ni se presenta emulación como QA física.

## 10. Método de evidencia

Se aplicó la regla requerida:

- A: contrato verificable.
- B1: incumplimiento reproducible ahora.
- B2: exclusión o aplazamiento explícito.

La comprobación read-only se limitó a los dos defectos Axe ya documentados. No
creó datos ni ejecutó una certificación visual general. Se utilizó Axe 4.11.4
contra las superficies públicas actuales; todos los HTTP fueron 200 y hubo cero
warnings/errores de consola en los escenarios examinados.

## 11. Elementos encontrados y clasificación completa

| Registro | Categoría | Resultado |
| --- | --- | --- |
| `V3I-CAND-001` | `V3I_IMPLEMENTATION_CANDIDATE` | El orden de Mercado pierde nombre accesible cuando se oculta su texto en compacto. |
| `V3I-CAND-002` | `V3I_IMPLEMENTATION_CANDIDATE` | Las acciones de cuenta compactas quedan fuera de un landmark. |
| `V3I-CAND-003` | `V3I_IMPLEMENTATION_CANDIDATE` | El tema claro de Demo conserva acentos de tema oscuro con contraste insuficiente. |
| `SOCIAL-RC-001..012` | `ALREADY_FIXED` | 12/12 cerrados, congelados y cubiertos por regresión. |
| `V3H-033` | `ALREADY_FIXED` | Incidente de caché CSS resuelto y verificado en producción. No se suma al conteo canónico Social RC. |
| `WAVE9C-SCOPE` | `WAVE_9C` | `WAVE 9C: CANONICAL SCOPE NOT FOUND`; cero tareas inferidas. |
| `PHYSICAL-ANDROID` | `PHYSICAL_QA` | Android físico `PENDING`. |
| `PHYSICAL-IPHONE` | `PHYSICAL_QA` | iPhone físico `PENDING`. |
| `PHYSICAL-PWA` | `PHYSICAL_QA` | PWA físicamente instalada `PENDING`. |
| `OPS-DEPENDENCIES` | `OPERATIONS_OR_SECURITY` | 19 hallazgos históricos de dependencias; no son alcance V3I. |
| `OPS-PREVIEW-OIDC` | `OPERATIONS_OR_SECURITY` | Limitación del SW bajo Preview protegida; producción pública ya validada. |
| `NOT-JUSTIFIED-GLOBAL-POLISH` | `NOT_JUSTIFIED` | Homogeneizar, modernizar o pulir globalmente carece de requisito y reproducción concretos. |

No se localizaron elementos `BACKEND_OR_PRODUCT_ROADMAP` ni `OUT_OF_SCOPE`
adicionales que deban convertirse en tareas. Tampoco se reprodujo ningún
`RELEASE_BLOCKER_REGRESSION`.

Conteo operativo:

- candidatos V3I: 3;
- `ALREADY_FIXED`: 13 (12 IDs Social RC y `V3H-033`);
- regresiones posibles/reproducidas: 0;
- tareas Wave 9C definidas: 0;
- QA física: 3;
- backend/product roadmap: 0;
- operaciones/seguridad: 2;
- no justificadas: 1;
- registros excluidos del plan V3I: 7.

## 12. Evidencia por candidato

### V3I-CAND-001 - Nombre accesible del orden de Mercado compacto

| Campo | Evidencia |
| --- | --- |
| Fuente contractual | `SOCIAL_CORE_VISUAL_CONTRACT_V1.md`, controles e iconos con nombre accesible (líneas 51-58) y cero controles sin nombre (98-106). |
| Fuente de deuda | `SOCIAL_CORE_RC_HOTFIX_001_REPORT.md`, sección Axe: `select-name` crítica ya presente y no corregida fuera del lote. |
| Archivo/sección | `app/mercado/marketplace-client.tsx:1242-1252`; `app/mercado/marketplace-v3d.module.css:211-214,241-243`. |
| Comportamiento actual | El `select` depende del texto `Ordenar por` de su `label`; las media queries aplican `display: none` al texto y el control pierde su nombre calculado. |
| Comportamiento esperado | El control conserva un nombre accesible independiente de que la etiqueta visual se compacte. |
| Ruta/superficie | `/mercado`, cabecera de resultados. |
| Componente | `MarketplaceClient`. |
| Impacto | Tecnología asistiva anuncia un combo sin nombre; Axe lo clasifica como crítico. |
| Reproducción | Abrir `/mercado` a 390 x 844, 360 x 800 o 844 x 390 y ejecutar Axe; aparece `select-name`, 1 nodo. A 1440 x 900 no aparece porque el texto es visible. |
| Roles | Visitante sin sesión y cualquier rol que use Mercado. |
| Prueba relacionada | `tests/official-ui-v3h-social-core.test.ts` y `tests/social-core-rc-hotfix-002.test.ts` cubren compactación/44 px, pero no el nombre del selector de orden tras ocultar el texto. |
| Por qué no está cerrado | Fue registrado como deuda preexistente y quedó expresamente fuera de Batch 001/002. |
| Corrección mínima previsible | Dar al `select` un nombre persistente mediante `aria-label` o `aria-labelledby` que no apunte a un nodo oculto. |
| Riesgo | Duplicar o volver verboso el nombre en desktop, o alterar la compactación de `SOCIAL-RC-003`. |
| Límites | No cambiar filtros, ordenación, datos, estado de consulta, layout, textos visibles ni RPC. |

Resultado actual focalizado:

| Viewport | HTTP | Consola | Axe |
| --- | ---: | ---: | --- |
| 1440 x 900 | 200 | 0 | 0 |
| 1280 x 720 | 200 | 0 | 0 |
| 1024 x 768 | 200 | 0 | 0 |
| 390 x 844 | 200 | 0 | `select-name` crítica, 1 nodo |
| 360 x 800 | 200 | 0 | `select-name` crítica, 1 nodo |
| 844 x 390 | 200 | 0 | `select-name` crítica, 1 nodo |

### V3I-CAND-002 - Landmark para acciones de cuenta compactas

| Campo | Evidencia |
| --- | --- |
| Fuente contractual | `SOCIAL_CORE_VISUAL_CONTRACT_V1.md`, cabecera social (líneas 7-14) y landmarks (98-106). |
| Fuente de deuda | `SOCIAL_CORE_RC_HOTFIX_001_REPORT.md`, Axe `region` moderada preexistente y no corregida. |
| Archivo/sección | `app/_components/official-product-shell-v2.tsx:306-346`. |
| Comportamiento actual | En desktop `AccountActions` vive dentro de `header`; en compacto se renderiza dentro de un `div.contextBar` genérico. El enlace Avisos queda fuera de landmarks. |
| Comportamiento esperado | La cabecera/acciones visibles en compacto pertenecen a un landmark semántico único y coherente. |
| Ruta/superficie | Shell compacta; reproducido públicamente en `/mercado`. |
| Componente | `OfficialProductShellV2`, `AccountActions`. |
| Impacto | Usuarios de navegación por regiones no encuentran las acciones de cuenta dentro de una estructura semántica reconocible. |
| Reproducción | Abrir `/mercado` a 390 x 844, 360 x 800 o 844 x 390 y ejecutar Axe; aparece `region`, 1 nodo, sobre Avisos. A 1440 x 900 no aparece. |
| Roles | Visitante, jugador, owner/admin y demás perspectivas que reciben acciones de cuenta. |
| Prueba relacionada | Las suites Official UI validan cuatro destinos y responsive, pero no el landmark del `contextBar` visible. |
| Por qué no está cerrado | Fue deuda Axe explícita del Batch 001 y no formó parte de los doce defectos Social RC. |
| Corrección mínima previsible | Convertir únicamente la barra compacta visible en una cabecera/landmark apropiado, evitando dos landmarks visibles del mismo tipo. |
| Riesgo | Duplicar banners accesibles, alterar grid/safe areas o modificar la navegación primaria. |
| Límites | No cambiar destinos, selector, campana, avatar, permisos, historial, responsive visual ni estrategia PWA. |

Resultado actual focalizado:

| Viewport | HTTP | Consola | Axe |
| --- | ---: | ---: | --- |
| 1440 x 900 | 200 | 0 | 0 |
| 1280 x 720 | 200 | 0 | 0 |
| 1024 x 768 | 200 | 0 | 0 |
| 390 x 844 | 200 | 0 | `region` moderada, 1 nodo |
| 360 x 800 | 200 | 0 | `region` moderada, 1 nodo |
| 844 x 390 | 200 | 0 | `region` moderada, 1 nodo |

### V3I-CAND-003 - Contraste del tema claro de Demo

| Campo | Evidencia |
| --- | --- |
| Fuente contractual | `SOCIAL_CORE_VISUAL_CONTRACT_V1.md`, dark/light conservan contraste y significado (líneas 91-96) y sin violaciones críticas o serias nuevas. |
| Fuente de deuda | `SOCIAL_CORE_RC_HOTFIX_002_PRODUCTION_RELEASE.md`, 26 nodos de contraste preexistentes a 1024 px, delta 0. |
| Archivo/sección | `app/demo-world/demo-world.module.css:1-22,3075-3102`; consumo compartido en `app/_components/product-context-selector.module.css`. |
| Comportamiento actual | El tema claro cambia fondo, superficies, texto y muted, pero conserva `--demo-lime: #c8ef5d` y `--demo-cyan: #51cfdf`, pensados para fondo oscuro. Esos acentos se usan como texto sobre superficies claras. |
| Comportamiento esperado | El tema claro conserva jerarquía y significado con contraste AA, sin rediseñar la paleta ni degradar el tema oscuro. |
| Ruta/superficie | `/demo?tab=inicio&perspective=admin`, tema claro; afecta etiquetas, eyebrows, selector y marcadores dentro de Demo. |
| Componente | `DemoWorldApp` y `ProductContextSelector` bajo los tokens locales de Demo. |
| Impacto | Texto funcional y deportivo resulta difícil de leer; Axe lo clasifica como serio en múltiples nodos. |
| Reproducción | Fijar tema claro, abrir la ruta Demo y ejecutar Axe: 28 nodos a 1440 x 900, 27 a 1280 x 720, 26 a 1024 x 768, 22 a 390 x 844 y 360 x 800, y 2 a 844 x 390. |
| Roles | Todas las perspectivas sintéticas de Demo que seleccionen tema claro. |
| Prueba relacionada | `tests/official-ui-v3h-social-core.test.ts` comprueba Retos light/dark; no certifica contraste de toda la portada Demo. |
| Por qué no está cerrado | Batch 002 lo documentó como baseline preexistente y mantuvo delta cero; no pertenecía a sus siete IDs. |
| Corrección mínima previsible | Sobrescribir solo los tokens de primer plano necesarios bajo `data-theme=light` y verificar los usos derivados. |
| Riesgo | Cambiar identidad visual, afectar dark, forced colors o componentes compartidos fuera de Demo. |
| Límites | No cambiar contenido, composición, densidad, navegación, dataset, mutaciones, selector compartido global ni superficies live. |

Resultado actual focalizado:

| Viewport | HTTP | Consola | Axe `color-contrast` serio |
| --- | ---: | ---: | ---: |
| 1440 x 900 | 200 | 0 | 28 nodos |
| 1280 x 720 | 200 | 0 | 27 nodos |
| 1024 x 768 | 200 | 0 | 26 nodos |
| 390 x 844 | 200 | 0 | 22 nodos |
| 360 x 800 | 200 | 0 | 22 nodos |
| 844 x 390 | 200 | 0 | 2 nodos |

## 13. Elementos aceptados para V3I

| ID provisional | Decisión | Motivo |
| --- | --- | --- |
| `V3I-CAND-001` | Aceptado | Contrato de nombre accesible + reproducción crítica actual + deuda previa explícita. |
| `V3I-CAND-002` | Aceptado | Contrato de landmarks + reproducción moderada actual + deuda previa explícita. |
| `V3I-CAND-003` | Aceptado | Contrato de contraste light/dark + reproducción seria actual + baseline previo explícito. |

## 14. Elementos rechazados y razón

- Rediseño global, modernización, homogeneización de densidad, paleta, sombras o
  espaciado: `NOT_JUSTIFIED`; no hay incumplimiento contractual reproducible.
- Reescritura de componentes cerrados en `SOCIAL-RC-001..012`: `ALREADY_FIXED`;
  solo se tocarían ante una regresión reproducida en un hotfix separado.
- Cambios de manifest, Service Worker o Background Sync: fuera del contrato V3I
  y expresamente prohibidos.
- Dependencias y limitación OIDC de Preview: `OPERATIONS_OR_SECURITY`.

## 15. Wave 9C

```text
WAVE 9C: CANONICAL SCOPE NOT FOUND
```

No se localizó documento, issue, PR, rama ni conjunto de tests que defina su
objetivo o sus tareas. Solo existen referencias históricas que dicen `NO`,
`paused`, `not started` o `not resumed`.

- objetivo: no localizado;
- dependencias: no localizadas;
- estado: no iniciada/reanudada;
- motivo de pausa: no documentado más allá del orden de releases sociales;
- relación real con V3I: no demostrada;
- requisito de finalizar V3I: no demostrable;
- retomable independientemente: no determinable sin definición canónica.

No se infiere ni diseña ningún contenido de Wave 9C.

## 16. QA físico

| Elemento | Estado | Tratamiento |
| --- | --- | --- |
| Android físico | PENDING | `PHYSICAL_QA`; no bloquea este gate documental. |
| iPhone físico | PENDING | `PHYSICAL_QA`; no bloquea este gate documental. |
| PWA físicamente instalada | PENDING | `PHYSICAL_QA`; no se sustituye por emulación. |

Ninguno de los tres candidatos depende exclusivamente de hardware físico; sus
incumplimientos semánticos y de contraste son reproducibles en navegador.

## 17. Backend y producto

No se ha localizado una necesidad de Supabase, SQL, RPC, RLS, Auth, pagos,
Rating, autoridad deportiva o nueva función de producto para resolver los tres
candidatos. El conteo `BACKEND_OR_PRODUCT_ROADMAP` es 0.

## 18. Regresiones detectadas

No se ha reproducido una regresión de release. El conteo
`RELEASE_BLOCKER_REGRESSION` es 0.

Los tres incumplimientos aceptados son deudas preexistentes registradas en los
informes de los hotfixes; no son regresiones nuevas ni reabren un ID Social RC.

## 19. Riesgos

- Una corrección semántica amplia podría duplicar landmarks o nombres.
- Un cambio visual de tokens compartidos podría escapar de Demo o degradar dark.
- Mezclar los tres candidatos en una refactorización global rompería el carácter
  local, incremental y revisable del gate.
- Modificar pruebas históricas en vez de añadir regresiones V3I debilitaría el
  freeze de los doce IDs cerrados.
- Confundir Axe emulado con QA física falsearía los gates de dispositivos.

La mitigación es dividir el trabajo en dos lotes, añadir regresiones nuevas,
mantener las suites V3H/Batch 001/Batch 002 y detenerse entre lotes.

## 20. Conclusión

Existen tres incumplimientos actuales, reproducibles y respaldados por contratos
ya vigentes. Son pequeños, locales y no requieren backend ni una reescritura.
Por tanto, sí existe una implementación V3I mínima justificable.

V3I STATUS: IMPLEMENTATION JUSTIFIED
