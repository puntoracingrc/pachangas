# Official UI V3I Batch 001 - Compact Market and Shell Accessibility

## 1. Estado

`OFFICIAL-UI-V3I-001` y `OFFICIAL-UI-V3I-002` estan corregidos y validados localmente y en la Preview funcional exacta. El deployment `dpl_E572eVria4FbjUvwFAegATtngc1X` quedo `READY` con metadata `9a0935ecbb40f408c9bf5d4ec594f0d55d5b4697`.

`BATCH 001 STATUS: READY FOR MERGE`.

## 2. SHA base real

- Base: `origin/main`.
- SHA: `107d2be82dfd87dcc2832942d7b97bf462d47595`.
- La base coincide exactamente con el checkpoint esperado y contiene el merge del gate de definicion PR #264.
- Fecha de ejecucion local: 2026-09-03 CEST.

## 3. Aislamiento Git

- Rama: `codex/official-ui-v3i-batch-001-compact-accessibility`.
- Worktree: `/Users/macbookpro14/.codex/worktrees/pachangas-official-ui-v3i-batch-001`.
- Git dir: `/Users/macbookpro14/Documents/steam deck/.git/worktrees/pachangas-official-ui-v3i-batch-001`.
- Git common dir: `/Users/macbookpro14/Documents/steam deck/.git`.
- El checkout compartido se encontro con cambios preexistentes en el laboratorio de ficha y directorios sin seguimiento. No se modificaron, restauraron ni incorporaron.

## 4. Fuentes revisadas

Se revisaron completos los documentos `OFFICIAL_UI_V3I_SCOPE_RECONCILIATION.md`, `OFFICIAL_UI_V3I_IMPLEMENTATION_PLAN.md`, `SOCIAL_CORE_VISUAL_CONTRACT_V1.md`, `SOCIAL_CORE_PRODUCT_LANGUAGE_V1.md`, los informes V3H y Social Core Hotfix 001/002, y el codigo y regresiones indicados en la orden. El equivalente real de MobileAppNav es `app/mobile-app-nav.tsx`.

## 5. Reproduccion previa

Sobre una build productiva limpia de `107d2be...` se repitio dos veces la matriz requerida con Axe y el arbol de accesibilidad real. En los tres modos compactos el selector perdia su nombre cuando desaparecia el texto visual y las acciones de cuenta quedaban fuera de un landmark. Desktop y tablet no reproducian ninguno de los dos defectos.

El baseline tecnico fue 845/845 tests (Node 20/20 y TS/TSX 825/825), 0 fallos, 0 skipped, 0 todo y 0 cancelled; typecheck, build, lint y `git diff --check` pasaron; el build genero 78 rutas.

## 6. Tabla Axe previa por viewport

| Viewport | `select-name` | `region` | Nombre combobox | Banner accesible | Superficie primaria visible | Overflow | Imagenes rotas | Consola / red |
| --- | ---: | ---: | --- | ---: | --- | ---: | ---: | --- |
| 1440x900 | 0 | 0 | `ORDENAR POR` | 1 | Navegacion principal | 0 | 0 | 0 |
| 1280x720 | 0 | 0 | `ORDENAR POR` | 1 | Navegacion principal | 0 | 0 | 0 |
| 1024x768 | 0 | 0 | `ORDENAR POR` | 1 | Navegacion principal | 0 | 0 | 0 |
| 390x844 | 1 critical | 1 moderate | vacio | 0 | Navegacion principal movil | 0 | 0 | 0 |
| 360x800 | 1 critical | 1 moderate | vacio | 0 | Navegacion principal movil | 0 | 0 | 0 |
| 844x390 | 1 critical | 1 moderate | vacio | 0 | Navegacion de modo juego | 0 | 0 | 0 |

La auditoria completa tambien encontro tres nodos `color-contrast` preexistentes en 390x844 y 360x800. Se reprodujeron igual en el checkout limpio y quedan fuera de este lote.

## 7. OFFICIAL-UI-V3I-001

Estado: `FIXED`. El `<select>` de orden conserva `aria-label="Ordenar por"` en todos los viewports, aunque el `<span>` visual se oculte. El nombre aparece una sola vez y el control es localizable como combobox por su nombre.

## 8. OFFICIAL-UI-V3I-002

Estado: `FIXED`. La `contextBar` existente usa ahora `<header>` con la misma clase y los mismos hijos. Compacto obtiene un banner sin añadir wrappers, duplicar `AccountActions` ni mover identidad, Avisos, avatar o selector de contexto.

## 9. Solucion implementada

La solucion consta de dos cambios semanticos: un nombre accesible persistente en el selector y el elemento semantico adecuado en la barra compacta. No cambia filtros, consultas, estado, permisos, navegacion, datos, layout ni comportamiento offline.

## 10. Archivos modificados

1. `app/mercado/marketplace-client.tsx`.
2. `app/_components/official-product-shell-v2.tsx`.
3. `tests/official-ui-v3i-compact-accessibility.test.ts`.
4. `package.json`.
5. `OFFICIAL_UI_V3I_BATCH_001_COMPACT_ACCESSIBILITY_REPORT.md`.

## 11. CSS

CSS modificado: `NO`. Los dos cambios semanticos son suficientes y las comparaciones visuales son identicas.

## 12. Pruebas nuevas

La nueva suite aporta 8 casos y cubre el nombre persistente, independencia del texto ocultable, opciones y estado existentes, banner desktop/compacto, ausencia de duplicacion, enlaces/badge/permisos, los cuatro destinos primarios, registro de regresiones congeladas y exclusiones del lote.

- Suite nueva: 8/8 PASS.
- Failed / skipped / todo / cancelled: 0 / 0 / 0 / 0.

## 13. Regresiones V3H, Batch 001 y Batch 002

El grupo de cuatro suites pasa 35/35, con 0 fallos, skipped, todo o cancelled. Los archivos historicos no fueron modificados. `SOCIAL-RC-001` a `SOCIAL-RC-012` permanecen cerrados y congelados.

## 14. Resultado global

- Baseline: 845/845.
- Final local: 853/853.
- Node: 20/20.
- TS/TSX: 833/833.
- Failed / skipped / todo / cancelled: 0 / 0 / 0 / 0.

## 15. Typecheck

`npm run typecheck`: PASS.

## 16. Build y rutas

`npm run build`: PASS. Se mantienen 78 rutas, sin rutas nuevas.

## 17. Lint

- `npm run lint`: PASS. Solo emitio la nota informativa preexistente de Babel por el tamano de `app/page.tsx`.
- Lint focalizado de los dos componentes y la suite nueva: PASS, 0 avisos y 0 errores.

## 18. git diff --check

`git diff --check`: PASS.

## 19. Secret scan

PASS sobre el diff funcional, archivos nuevos, informe y bundle cliente. No se localizaron claves Stripe, secretos de webhook, JWT, service-role, credenciales en URL, cabeceras de autenticacion, emails privados ni claves privadas. No se han usado cuentas reales, credenciales ni servicios de datos.

## 20. Tabla Axe final local por viewport

| Viewport | `select-name` | `region` | Nombre combobox | Violacion critical/serious nueva | Overflow | Imagenes rotas | Consola / red |
| --- | ---: | ---: | --- | ---: | ---: | ---: | --- |
| 1440x900 | 0 | 0 | `Ordenar por` | 0 | 0 | 0 | 0 |
| 1280x720 | 0 | 0 | `Ordenar por` | 0 | 0 | 0 | 0 |
| 1024x768 | 0 | 0 | `Ordenar por` | 0 | 0 | 0 | 0 |
| 390x844 | 0 | 0 | `Ordenar por` | 0 | 0 | 0 | 0 |
| 360x800 | 0 | 0 | `Ordenar por` | 0 | 0 | 0 | 0 |
| 844x390 | 0 | 0 | `Ordenar por` | 0 | 0 | 0 | 0 |

Los tres nodos de contraste preexistentes en cada viewport portrait siguen presentes sin variacion; no son una violacion nueva de Batch 001.

## 21. Landmarks y navegacion por viewport

| Modo | Banners accesibles visibles | Superficie primaria visible y nombrada | Destino activo | Avisos/avatar dentro del banner |
| --- | ---: | --- | --- | --- |
| Desktop 1440/1280 | 1 | `Navegacion principal` | Mercado | SI |
| Tablet 1024 | 1 | `Navegacion principal` | Mercado | SI |
| Portrait 390/360 | 1 | `Navegacion principal movil` | Mercado | SI |
| Landscape 844 | 1 | `Navegacion de modo juego` | Mercado | SI |

Los cuatro destinos primarios siguen siendo Inicio, Partidos, Retos y Mercado. `/`, `/retos` y `/avisos`, junto con perspectivas sinteticas signed-out, free-agent, jugador, team admin y team owner, se abrieron sin overflow, imagenes rotas ni overlay de error. Los controles prioritarios de busqueda y ubicacion conservan 44 px de altura y el boton de ubicacion mide 44x44 px.

## 22. Comparacion visual

Se capturaron antes y despues `/mercado` y una shell con cuenta sintetica en portrait y landscape, con movimiento reducido y estado determinista. Las cuatro parejas son byte a byte identicas:

- Mercado portrait: SHA-256 `3228b321f29b21e08367f41cae7945e249a6a435bf17fa09225470249051a3a7`.
- Mercado landscape: SHA-256 `db20e88d5d1df718f0272690f28c9d819ffd11cd5331e780efd221aca315cd99`.
- Shell sintetica portrait: SHA-256 `e88e9677d2a9b1811f5e349edbf2bb13a4fe8005b60a7c2c4cb55ec3e26b1b74`.
- Shell sintetica landscape: SHA-256 `6b3a0cd50caac59154b67fdaa956c146798a9a3754e6700c4b9d9e417993287d`.

Pixel delta: 0 en las cuatro comparaciones. No hay cambio visual deliberado.

## 23. PWA y offline

La PWA emulada con Chrome real pasa localmente y en la Preview funcional exacta en 390x844 y 844x390:

- `display-mode: standalone` en ambos viewports.
- Service Worker controlador en ambos viewports.
- Manifest y `/sw.js`: HTTP 200.
- Una unica cache local vigente: `pachangas-iq-pwa-2.0.0-sw.107d2be82dfd`.
- Una unica cache Preview vigente: `pachangas-iq-pwa-2.0.0-sw.9a0935ecbb40`.
- `/mercado` cacheado recarga offline y conserva `Ordenar por`.
- Una peticion unica no cacheada falla offline, demostrando el corte real de red.
- La reconexion y recarga posterior pasan.
- No hay fake success ni cola de mutaciones deportivas; no se ejecuto ninguna mutacion.

## 24. Autoridad y contadores

El lote no toca autoridad ni datos. La cache sigue siendo lectura derivada y las escrituras offline permanecen bloqueadas.

- `remoteWrites = 0`
- `externalNotifications = 0`
- `pushSent = 0`
- `emailsSent = 0`
- `realEntities = 0`
- `StripeCalls = 0`
- Supabase, migraciones, RPC, RLS, flags y Stripe modificados: `NO`.

## 25. Limites

`OFFICIAL-UI-V3I-003`, Batch 002, contraste del tema claro Demo, Wave 9C, backend y redisenos no se han iniciado. No se realizo QA fisica ni se alteraron manifest o estrategia de Service Worker.

## 26. Rollback

- V3I-001: retirar solo `aria-label="Ordenar por"` del selector.
- V3I-002: devolver solo `header.contextBar` a `div.contextBar`.

No existe rollback de datos porque no se modifican datos.

## 27. QA fisica pendiente

- Android fisico: `PENDING`.
- iPhone fisico: `PENDING`.
- PWA fisicamente instalada: `PENDING`.

La emulacion standalone no se presenta como QA fisica.

## 28. Conclusion

Los dos defectos se reproducen de forma determinista y quedan resueltos mediante cambios semanticos minimos. La suite completa y las regresiones sociales pasan, el aspecto es identico, la Preview funcional exacta esta certificada y no hay cambios de datos ni autoridad. Batch 001 queda listo para fusionar tras el readback final del PR.
