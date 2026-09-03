# Official UI V3I Implementation Plan

## 1. Estado y límites

Estado heredado de la reconciliación:

```text
V3I STATUS: IMPLEMENTATION JUSTIFIED
```

Este documento convierte tres incumplimientos accesibles reproducidos en dos
lotes pequeños. No autoriza ni contiene implementación. La base funcional para
el primer lote será el `origin/main` vigente en el momento de ejecutarlo; la
base de este gate es `8d57b693bf98efbc03859ef84e99552dd8dc4b09`.

Límites globales:

- no reabrir `SOCIAL-RC-001..012`;
- no reanudar ni diseñar Wave 9C;
- no tocar Supabase, migraciones, RPC, RLS, flags, Stripe o datos;
- no cambiar autoridad, navegación primaria, historial, Demo session-local,
  manifest o Service Worker;
- no convertir los lotes en redesign, polish, cleanup o modernización;
- no presentar emulación como QA física.

## 2. IDs definitivos

| ID | Prioridad | Severidad | Lote | Resumen |
| --- | --- | --- | --- | --- |
| `OFFICIAL-UI-V3I-001` | P1 | Alta, Axe crítica | 001 | Conservar nombre accesible del selector de orden en Mercado compacto. |
| `OFFICIAL-UI-V3I-002` | P2 | Media, Axe moderada | 001 | Incluir acciones de cuenta compactas en un landmark correcto. |
| `OFFICIAL-UI-V3I-003` | P1 | Alta, Axe seria | 002 | Corregir contraste de los acentos de texto del tema claro de Demo. |

## 3. OFFICIAL-UI-V3I-001

### Evidencia y problema

- Contrato: `SOCIAL_CORE_VISUAL_CONTRACT_V1.md:51-58,98-106` exige nombre
  accesible para controles y cero controles sin nombre.
- Deuda documentada: `SOCIAL_CORE_RC_HOTFIX_001_REPORT.md:67` registra
  `select-name` crítica como preexistente.
- Código actual: `app/mercado/marketplace-client.tsx:1242-1252` envuelve el
  `select` en un label cuyo único texto es `Ordenar por`.
- CSS actual: `app/mercado/marketplace-v3d.module.css:211-214,241-243` oculta
  ese texto en portrait y landscape compacto.
- Reproducción: `/mercado`, 390 x 844, 360 x 800 y 844 x 390; Axe devuelve un
  nodo `select-name` crítico. A 1440 x 900 devuelve cero.

### Contrato esperado

El selector conserva un nombre accesible estable en todos los viewports aunque
la etiqueta visual se oculte para compactar. El texto visible y la lógica de
ordenación no cambian.

### Superficie y archivos previstos

- Ruta: `/mercado`.
- Componente: `MarketplaceClient`.
- Archivo de producto previsto:
  `app/mercado/marketplace-client.tsx`.
- CSS solo si la solución semántica mínima demuestra necesitarlo:
  `app/mercado/marketplace-v3d.module.css`.
- Regresión nueva compartida del lote:
  `tests/official-ui-v3i-compact-accessibility.test.ts`.
- `package.json` únicamente para registrar esa suite en `npm test`, sin cambiar
  dependencias ni otros scripts.

### Corrección mínima

Añadir al `select` un nombre persistente mediante `aria-label` o una relación
`aria-labelledby` cuyo nodo no quede oculto. Verificar el nombre calculado en
desktop y compacto para evitar duplicidad o copy excesivo.

### Contextos obligatorios

- Roles: visitante, jugador, team admin/owner y demás perspectivas con Mercado.
- Estados: signed-out, consulta no iniciada, loading, resultado y sin resultados.
- Datos: live read-only y Demo cuando reutilice la superficie; ninguna mutación.
- Offline: lectura cacheada/sin consultar se mantiene; no aparece éxito nuevo.
- Responsive: 1440 x 900, 1280 x 720, 1024 x 768, 390 x 844, 360 x 800 y
  844 x 390.
- Navegación/historial: sin cambios en tabs, filtros, detalle, Back o Forward.

### Pruebas y regresiones

- Nueva prueba de nombre accesible con etiqueta visual visible y oculta.
- Axe focalizado en `/mercado` para `select-name`.
- Mantener `tests/official-ui-v3h-social-core.test.ts`.
- Mantener `tests/social-core-rc-hotfix-001.test.ts`.
- Mantener `tests/social-core-rc-hotfix-002.test.ts`, en especial
  `SOCIAL-RC-003`, `004`, `008` y `010`.

### Criterios de aceptación

- Axe `select-name`: 0 nodos en los seis viewports.
- El selector anuncia un nombre inequívoco con lector/árbol accesible.
- El valor y las opciones siguen siendo los mismos.
- La cabecera no desborda y el campo de búsqueda conserva las medidas cerradas
  por `SOCIAL-RC-003`.
- No hay cambios en consultas, filtros, orden, permisos o autoridad.

### Rollback

Revertir el cambio de nombre accesible si produce un nombre duplicado, rompe el
control nativo, altera layout o hace fallar cualquier regresión Social RC. El
rollback no toca datos porque el cambio es exclusivamente semántico.

### No tocar

Filtros, algoritmos de orden, query phases, textos visibles, geolocalización,
detalle modal, rutas, navegación primaria, Supabase y PWA.

## 4. OFFICIAL-UI-V3I-002

### Evidencia y problema

- Contrato: `SOCIAL_CORE_VISUAL_CONTRACT_V1.md:7-14,98-106` exige cabecera
  social y landmarks.
- Deuda documentada: `SOCIAL_CORE_RC_HOTFIX_001_REPORT.md:67` registra `region`
  moderada como preexistente.
- Código actual: `app/_components/official-product-shell-v2.tsx:306-346` sitúa
  `AccountActions` dentro de `header` en desktop y dentro de un `div.contextBar`
  en compacto.
- Reproducción: `/mercado`, 390 x 844, 360 x 800 y 844 x 390; Axe devuelve un
  nodo `region` sobre Avisos. A 1440 x 900 devuelve cero.

### Contrato esperado

Las acciones visibles de identidad/cuenta pertenecen a una cabecera o landmark
apropiado en cada modo, sin crear dos banners visibles ni alterar los cuatro
destinos primarios.

### Superficie y archivos previstos

- Rutas: cualquier ruta que use `OfficialProductShellV2`; matriz focal inicial
  `/`, `/mercado`, `/retos` y `/avisos` cuando sean públicas o sintéticas.
- Componente: `OfficialProductShellV2` y su `AccountActions` existente.
- Archivo de producto previsto:
  `app/_components/official-product-shell-v2.tsx`.
- CSS solo si la semántica mínima lo necesita:
  `app/_components/official-product-shell-v2.module.css`.
- Regresión compartida:
  `tests/official-ui-v3i-compact-accessibility.test.ts`.
- `package.json` únicamente para registrar la nueva suite.

### Corrección mínima

Dar semántica de cabecera/landmark a la barra compacta visible, conservando la
cabecera desktop existente y garantizando que solo una variante visible aporta
la región esperada en cada layout.

### Contextos obligatorios

- Roles: signed-out, jugador, free-agent, team admin/owner, referee,
  organizador y plataforma cuando la shell los admita.
- Estados: campana sin sesión, sin pendientes, con pendientes y avatar/contexto.
- Datos live/Demo: solo cambia semántica de shell; cero mutaciones.
- Offline: shell y acciones conservan estado; no se modifica la política.
- Responsive: seis viewports canónicos y standalone emulada.
- Navegación/historial: exactamente cuatro destinos; selector compartido,
  Back/Forward y deep links intactos.

### Pruebas y regresiones

- Nueva prueba DOM que exige una región apropiada para las acciones compactas y
  evita banners visibles duplicados.
- Axe focalizado para `region` en portrait/landscape y desktop.
- Suites Official UI V3H y Batch 001/002 completas.
- Regresión explícita de cuatro destinos, `aria-current`, selector y Avisos.

### Criterios de aceptación

- Axe `region`: 0 nodos en los seis viewports.
- Existe una sola cabecera visible y una navegación primaria nombrada por modo.
- Avisos y avatar conservan nombre, destino, permisos y badge.
- Cero cambio visual involuntario, overflow o modificación de safe areas.
- `SOCIAL-RC-001`, `002`, `005` y `011` siguen verdes.

### Rollback

Revertir la semántica de la barra si crea landmarks duplicados, cambia layout,
oculta acciones o rompe navegación/lector. No se modifica estado persistente.

### No tocar

Destinos primarios/contextuales, selector, permisos, badge, rutas, estilos de
identidad, Mobile Game Landscape, manifest, Service Worker o backend.

## 5. OFFICIAL-UI-V3I-003

### Evidencia y problema

- Contrato: `SOCIAL_CORE_VISUAL_CONTRACT_V1.md:91-106` exige que dark/light
  conserven contraste y que no existan controles sin semántica accesible.
- Deuda documentada: `SOCIAL_CORE_RC_HOTFIX_002_PRODUCTION_RELEASE.md:58-69`
  conserva 26 nodos de contraste preexistentes a 1024 px.
- Código actual: `app/demo-world/demo-world.module.css:1-22,3075-3102` cambia
  fondos y texto en light, pero no redefine `--demo-lime` ni `--demo-cyan`.
- Reproducción en `/demo?tab=inicio&perspective=admin`, tema claro:
  28 nodos serios a 1440 x 900, 27 a 1280 x 720, 26 a 1024 x 768,
  22 a 390 x 844 y 360 x 800, y 2 a 844 x 390.

### Contrato esperado

Los acentos de texto de Demo cumplen AA sobre sus fondos claros conservando su
función semántica y la identidad actual. Dark, reduced motion y forced colors no
se degradan.

### Superficie y archivos previstos

- Ruta principal: `/demo`, tema claro.
- Componentes: `DemoWorldApp` y el `ProductContextSelector` dentro de Demo.
- Archivo de producto previsto: `app/demo-world/demo-world.module.css`.
- `app/_components/product-context-selector.module.css` solo si una medición
  demuestra que los tokens locales de Demo no pueden resolver el uso; no es la
  opción inicial.
- Regresión nueva: `tests/official-ui-v3i-demo-light-contrast.test.ts`.
- `package.json` únicamente para registrar la nueva suite.

### Corrección mínima

Definir variantes locales de primer plano para `--demo-lime`, `--demo-cyan` y
sus aliases oficiales dentro de `:root[data-theme="light"] .shell`, medidas
contra los fondos reales. No cambiar composición, copy ni superficies.

### Contextos obligatorios

- Roles/perspectivas: admin, jugador, owner, usuario nuevo y las perspectivas
  ya disponibles en Revisión rápida.
- Estados: Inicio, Partidos, Retos, Mercado, Equipo, Perfil y Avisos de Demo,
  solo en los usos afectados por los mismos tokens.
- Datos: exclusivamente sintéticos y locales a la sesión.
- Offline: Demo cacheada sigue read-only/session-local; cero éxito remoto.
- Responsive: seis viewports canónicos.
- Temas: light principal, dark de regresión, reduced motion y forced colors.
- Navegación/historial: sin cambios; `SOCIAL-RC-001`, `002`, `009` y `011`
  permanecen congelados.

### Pruebas y regresiones

- Nueva prueba de tokens light locales y ausencia de fuga global.
- Axe focalizado en Demo light con umbral 0 crítico/serio.
- Comparación dark para evitar una regresión de identidad/contraste.
- Mantener `tests/official-ui-v3h-social-core.test.ts` y Batch 001/002.
- Verificar el selector de contexto sin alterar su label completo.

### Criterios de aceptación

- Axe `color-contrast` crítico/serio: 0 en los nodos afectados de los seis
  viewports.
- El tema dark conserva sus colores y cero regresiones nuevas.
- Los cambios de color quedan limitados a Demo light.
- Cero overflow, texto cortado, cambio de densidad o imagen rota.
- Los contadores Demo siguen todos a cero y no hay escritura remota.

### Rollback

Revertir solo los tokens light nuevos si alguna superficie pierde contraste,
significado o aislamiento. No persistir un ajuste parcial que arregle Inicio y
degrade otras pestañas Demo.

### No tocar

Dataset Demo, mutaciones, navegación, copy, layout, densidad, tema oscuro,
selector global, superficies live, assets, PWA y backend.

## 6. Lote 001

### Identidad

- Nombre exacto: `OFFICIAL UI V3I — IMPLEMENTATION BATCH 001: COMPACT MARKET AND SHELL ACCESSIBILITY`
- Rama: `codex/official-ui-v3i-batch-001-compact-accessibility`
- PR recomendado: `Fix compact Market and shell accessibility`
- IDs: `OFFICIAL-UI-V3I-001`, `OFFICIAL-UI-V3I-002`.

### Objetivo y archivos previsibles

Cerrar los dos defectos semánticos que aparecen juntos en la shell pública
compacta, sin modificar comportamiento o apariencia.

- `app/mercado/marketplace-client.tsx`
- `app/_components/official-product-shell-v2.tsx`
- CSS de esos componentes solo si resulta estrictamente necesario.
- `tests/official-ui-v3i-compact-accessibility.test.ts`
- `package.json` solo para registrar la suite.

### Tests focalizados

- nombre calculado del selector con label visible/oculto;
- landmarks desktop/portrait/landscape;
- cero banners visibles duplicados;
- Axe `select-name` y `region`;
- navegación primaria, selector, Avisos y filtros intactos.

### Suites de regresión

- `tests/official-ui-v3h-social-core.test.ts`;
- `tests/social-core-rc-hotfix-001.test.ts`;
- `tests/social-core-rc-hotfix-002.test.ts`;
- suite global vigente, typecheck, build, lint focalizado/global y
  `git diff --check`.

### Matriz QA

| Contexto | Viewports | Checks |
| --- | --- | --- |
| `/mercado` signed-out | seis canónicos | nombre, landmarks, filtros, 44 x 44, overflow, consola, Axe |
| Shell con cuenta sintética/Demo | desktop, portrait, landscape | campana, avatar, badge, navegación, selector |
| PWA standalone emulada | 390 x 844, 844 x 390 | shell controlada, sin cambio de estrategia ni éxito offline |

### Prohibiciones

No cambiar copy visible, layout, filtros, ordenación, destinos, permisos,
backend, manifest, Service Worker, Wave 9C ni trabajo Social RC cerrado.

### Condiciones para fusionar

- diff limitado a los archivos previstos y justificado;
- los dos IDs tienen regresión automatizada;
- Axe focalizado devuelve cero para `select-name` y `region`;
- batería completa, typecheck, build, lint y `git diff --check` en verde;
- Preview exacta sin overflow, errores de consola ni imágenes rotas;
- PR independientemente revertible.

### Comprobación productiva

Tras merge y deployment READY del SHA exacto: smoke de `/mercado` en desktop,
390 x 844, 360 x 800 y 844 x 390; confirmar nombre accesible, landmarks, HTTP,
consola, manifest y SW. No crear cuentas o datos.

### Punto de parada

No comenzar Lote 002 hasta que el deployment de Lote 001 esté READY, ambos IDs
estén verificados y `SOCIAL-RC-001..012` sigan verdes.

## 7. Lote 002

### Identidad

- Nombre exacto: `OFFICIAL UI V3I — IMPLEMENTATION BATCH 002: DEMO LIGHT THEME CONTRAST`
- Rama: `codex/official-ui-v3i-batch-002-demo-light-contrast`
- PR recomendado: `Fix Demo light-theme contrast`
- ID: `OFFICIAL-UI-V3I-003`.

### Objetivo y archivos previsibles

Cerrar únicamente el contraste preexistente de Demo light mediante tokens
locales medidos.

- `app/demo-world/demo-world.module.css`;
- selector CSS compartido solo si se demuestra imprescindible;
- `tests/official-ui-v3i-demo-light-contrast.test.ts`;
- `package.json` solo para registrar la suite.

### Tests focalizados

- tokens light locales y aliases;
- Axe light en seis viewports;
- dark, reduced motion y forced colors de regresión;
- no fuga de estilos a superficies live;
- contadores y autoridad Demo intactos.

### Suites de regresión

- suites de Lote 001;
- `tests/official-ui-v3h-social-core.test.ts`;
- ambos hotfixes Social Core;
- suite global, typecheck, build, lint y `git diff --check`.

### Matriz QA

| Contexto | Viewports | Checks |
| --- | --- | --- |
| Demo light Inicio | seis canónicos | contraste, overflow, consola, imágenes, jerarquía |
| Demo light superficies afectadas | desktop, portrait, landscape | etiquetas, marcadores, selector, acciones |
| Demo dark | seis canónicos | delta visual/contraste no regresivo |
| PWA standalone emulada | portrait y landscape | caché, offline, reconexión, cero fake success |

### Prohibiciones

No rediseñar paleta, densidad, composición o navegación; no tocar datos Demo,
superficies live, backend, manifest, SW, Wave 9C o QA física.

### Condiciones para fusionar

- `OFFICIAL-UI-V3I-003` con regresión automatizada;
- cero violaciones Axe críticas/serias en los nodos afectados;
- dark y superficies live sin regresión;
- batería completa y gates técnicos verdes;
- Preview exacta y PR revertible de forma aislada.

### Comprobación productiva

Tras deployment READY: `/demo?tab=inicio&perspective=admin` en light/dark y los
viewports canónicos, con HTTP 200, Axe focalizado, cero errores de consola,
manifest/SW correctos y contadores de seguridad a cero.

### Punto de parada

Cerrar V3I documental y productivamente. No iniciar Wave 9C hasta que exista una
definición canónica independiente y una orden explícita.

## 8. Gates comunes y autoridad

Cada lote debe demostrar:

- servidor autoritativo y caché derivada intactos;
- Demo local, sintética y sin escrituras remotas;
- `remoteWrites = 0`;
- `externalNotifications = 0`;
- `pushSent = 0`;
- `emailsSent = 0`;
- `realEntities = 0`;
- `StripeCalls = 0`;
- Android físico, iPhone físico y PWA física continúan `PENDING` salvo prueba
  real posterior;
- no hay cambios en Supabase, migraciones, RPC/RLS/flags o Stripe.

## 9. NEXT EXECUTABLE ORDER

Nombre exacto:

```text
OFFICIAL UI V3I — IMPLEMENTATION BATCH 001: COMPACT MARKET AND SHELL ACCESSIBILITY
```

Objetivo: eliminar los defectos Axe `select-name` y `region` de la experiencia
compacta sin cambiar apariencia, navegación, filtros, permisos o autoridad.

IDs:

- `OFFICIAL-UI-V3I-001`;
- `OFFICIAL-UI-V3I-002`.

Límites: dos componentes, una regresión focalizada y CSS solo si resulta
imprescindible. Quedan fuera Demo light, Wave 9C, backend, PWA strategy, QA
física y cualquier trabajo `SOCIAL-RC-001..012`.

Debe ir primero porque corrige un fallo crítico y otro moderado en la shell
pública compacta, comparte una única matriz de reproducción y es independiente
del ajuste visual local de Demo del Lote 002.

No se implementa este lote en el presente gate.
