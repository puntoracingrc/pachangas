# Official UI V3I Batch 002 - Demo Light Theme Contrast

## 1. Estado

`BATCH 002 STATUS: BLOCKED`

La implementacion y todos los gates locales estan completos. El unico gate pendiente en este punto documental es certificar la Preview correspondiente al HEAD funcional exacto. No se declara `READY FOR MERGE` antes de esa comprobacion.

## 2. SHA base real

- Base esperada y real: `580ecbe32a1722793d42fc45bc9e6d4f66886cc9`.
- `origin/main` contenia los merges de los PR `#265` y `#266`.
- Fecha de la comprobacion local final: `2026-09-03 21:18:49 CEST`.

## 3. Aislamiento Git

- Worktree: `/Users/macbookpro14/.codex/worktrees/pachangas-official-ui-v3i-batch-002`.
- Rama: `codex/official-ui-v3i-batch-002-demo-light-contrast`.
- Git dir: `/Users/macbookpro14/Documents/steam deck/.git/worktrees/pachangas-official-ui-v3i-batch-002`.
- Git common dir: `/Users/macbookpro14/Documents/steam deck/.git`.
- El checkout compartido ya estaba sucio y no se restauro, movio ni incluyo ninguno de sus cambios.
- El worktree temporal de reproduccion sobre la base fue retirado con `git worktree remove` y `git worktree prune` tras comprobar que estaba limpio.

## 4. Fuentes revisadas

Se revisaron completas las definiciones `OFFICIAL_UI_V3I_SCOPE_RECONCILIATION.md` y `OFFICIAL_UI_V3I_IMPLEMENTATION_PLAN.md`, los dos informes de Batch 001, los contratos Social Core/V3H/Hotfix, el CSS y los componentes Demo/selector/shell/Mercado, `package.json` y todas las suites enumeradas en la orden. El plan canonico se mantuvo vinculante.

## 5. Reconciliacion de los dos baselines

La reproduccion actual de `/demo?tab=inicio&perspective=admin` confirmo exactamente `28 / 27 / 26 / 22 / 22 / 2` nodos `color-contrast` serios para `1440x900 / 1280x720 / 1024x768 / 390x844 / 360x800 / 844x390`. Los tres nodos portrait mencionados por Batch 001 pertenecian a una observacion de Marketplace live, no a la reproduccion canonica de `OFFICIAL-UI-V3I-003`. Por tanto, no se redujo artificialmente este lote a tres nodos ni se amplio a contrastes live preexistentes.

## 6. Reconciliacion del test temporal de Batch 001

`TIME-SCOPED TEST RECONCILIATION`: se sustituyo solo el octavo y ultimo test de `tests/official-ui-v3i-compact-accessibility.test.ts`.

- Antes, lineas 109-120: prohibia para siempre registrar `official-ui-v3i-demo-light-contrast` y buscaba la ausencia de `OFFICIAL-UI-V3I-003` en el CSS.
- Ahora, lineas 109-121: verifica que Batch 001 cerro exclusivamente 001/002, dejo 003 como `NOT STARTED`, no modifico CSS y sigue registrando su suite exactamente una vez.
- Los siete tests anteriores son byte a byte iguales: SHA-256 del prefijo base y actual `444446c61ee06c041de8e7b35c5a1b513b28eddf8b450905a0592cc585a37eb6`.
- No se debilito ninguna cobertura de 001 o 002.

## 7. Reproduccion previa

- `npm ci`: PASS; `package-lock.json` no cambio.
- `npm test`: `853/853` (`20/20` Node y `833/833` TS/TSX).
- Failed / skipped / todo / cancelled: `0 / 0 / 0 / 0`.
- Typecheck: PASS.
- Build: PASS, `78` rutas.
- Lint global: PASS.
- `git diff --check`: PASS.
- Se uso build productiva local y dos repeticiones por escenario.

## 8. Tabla Axe previa

| Viewport | Light explicito | Light automatico | Dark explicito | Dark por defecto |
| --- | ---: | ---: | ---: | ---: |
| 1440x900 | 28 serios | 28 serios | 0 | 0 |
| 1280x720 | 27 serios | 27 serios | 0 | 0 |
| 1024x768 | 26 serios | 26 serios | 0 | 0 |
| 390x844 | 22 serios | 22 serios | 0 | 0 |
| 360x800 | 22 serios | 22 serios | 0 | 0 |
| 844x390 | 2 serios | 2 serios | 0 | 0 |

Todos los casos devolvieron HTTP 200 y cero overflow, imagenes rotas, consola, recursos fallidos o 4xx/5xx inesperados.

## 9. Inventario de nodos

En el escenario desktop canonico habia 28 nodos: 9 lime y 19 cyan. Incluian banner, marca, etiqueta `Solo lectura`, un texto del ProductContextSelector, eyebrows, `vs`, etiquetas de historias/actividad y marcadores historicos. El inventario ampliado encontro los mismos usos mixtos en Partidos, Retos, Mercado, Perfil y Avisos. Los fallos de Equipo restantes pertenecen al renderer oscuro del ranking y a colores neutros hardcoded preexistentes, no a los acentos light de este lote.

## 10. Tokens y usos afectados

- Texto directo: `color: var(--demo-lime)` y `color: var(--demo-cyan)`.
- Texto compartido: `--official-accent-text` y `--official-cyan-text`.
- ProductContextSelector: un fallo reproducido bajo scope Demo; ningun fallo exigio editar su CSS compartido.
- Pintura: fondos, bordes, badges y marca siguen usando `--demo-lime`/`--demo-cyan` sin cambio.
- Superficies oscuras dentro de light: invitacion de equipo y prueba social requerian una variante cyan propia sobre oscuro.
- No se encontro una razon para alterar tokens globales o superficies live.

## 11. Ratios previos

En Inicio/admin desktop, el lime original `#c8ef5d` rendia entre `1.215:1` y `1.316:1`; el cyan original `#51cfdf`, entre `1.539:1` y `1.852:1` sobre las superficies claras compuestas. Las etiquetas son texto pequeno y exigian `4.5:1`.

## 12. Estrategia elegida

Se eligio la opcion B: separar pintura de primer plano. Los tokens de marca/pintura permanecen congelados; tres aliases de texto se resuelven a la pintura en dark y a variantes accesibles en light. Esto evita degradar botones, badges, bordes, marca o paneles oscuros.

## 13. Colores finales y ratios

| Uso | Color | Ratio minimo medido |
| --- | --- | ---: |
| Lime de texto light | `#4d6800` | `5.295:1` |
| Cyan de texto light | `#006a73` | `5.273:1` |
| Cyan de texto sobre panel oscuro en light | `#55d2e1` | `4.635:1` |
| Texto oscuro sobre fondo lime | pintura `#c8ef5d` | `12.669:1` |
| Lime de pintura sobre fondo dark | `#c8ef5d` | `14.561:1` |
| Cyan de pintura sobre fondo dark | `#51cfdf` | `10.346:1` |

Los dos primeros se comprobaron contra `#eef2ef`, `#ffffff`, `#e4ece7`, panel, panel soft, cabecera y washes alpha lime. El minimo general de texto es superior a `4.5:1`; los graficos significativos superan `3:1`.

## 14. Cambios CSS exactos

- Se anadieron `--demo-lime-text`, `--demo-cyan-text` y `--demo-cyan-on-dark-text` dentro de `.shell`.
- En dark apuntan a los tokens de pintura existentes.
- En ambos scopes light valen `#4d6800`, `#006a73` y `#55d2e1`.
- `--official-accent-text` y `--official-cyan-text` apuntan a los aliases de foreground.
- Solo declaraciones `color` Demo afectadas fueron redirigidas; backgrounds y borders conservan la pintura original.
- Los selectores semanticos de Mercado, Match Experience y Social Inbox estan prefijados por scopes locales de Demo.

## 15. Confirmacion de las dos vias light

`data-theme="light"` y `@media (prefers-color-scheme: light)` bajo `:root:not([data-theme="dark"])` calculan exactamente `#4d6800 / #006a73 / #55d2e1`. Se probo ambas vias dos veces en los seis viewports. Dark explicito sigue ganando frente a una preferencia de sistema light.

## 16. Confirmacion de dark congelado

Dark mantiene exactamente `--demo-lime: #c8ef5d` y `--demo-cyan: #51cfdf`; sus aliases calculan esos mismos valores. Las capturas deterministas antes/despues fueron byte a byte iguales en 1440x900, 390x844 y 844x390.

## 17. ProductContextSelector

El selector compartido no se modifico. Recibe `--official-accent-text: #4d6800` y `--official-cyan-text: #006a73` solo bajo Demo light. Fuera de `.shell` conserva sus fallbacks y estilos vigentes. Estructura, copy, opciones, layout, truncamiento y comportamiento de SOCIAL-RC-011 permanecen intactos.

## 18. Archivos modificados

Diff funcional previsto de cinco rutas:

1. `app/demo-world/demo-world.module.css`.
2. `tests/official-ui-v3i-demo-light-contrast.test.ts`.
3. `package.json`.
4. `tests/official-ui-v3i-compact-accessibility.test.ts`.
5. `OFFICIAL_UI_V3I_BATCH_002_DEMO_LIGHT_CONTRAST_REPORT.md`.

`app/_components/product-context-selector.module.css` y `package-lock.json`: sin cambios.

## 19. Suite nueva

La suite nueva contiene 9 tests para: freeze dark; equivalencia light explicita/automatica; contraste sRGB y composicion alpha; contraste de pintura; aliases oficiales y selectores directos; scope Demo y selector compartido; autoridad/manifest/SW; registro unico de suites; y freeze historico de Batch 001. Se registra exactamente una vez en `npm test`.

## 20. Regresiones

OFFICIAL-UI-V3I-001 (`aria-label="Ordenar por"`) y 002 (`header.contextBar`) siguen presentes. V3H, ambos Hotfix Social Core, selector, cuatro destinos, banner unico, `select-name = 0`, `region = 0`, navegacion, recorridos, permisos, lenguaje y acciones sociales permanecen congelados. `SOCIAL-RC-001` a `SOCIAL-RC-012`: regression verified.

## 21. Resultados focalizados

| Grupo | Passed | Failed | Skipped | Todo | Cancelled |
| --- | ---: | ---: | ---: | ---: | ---: |
| Batch 002 | 9 | 0 | 0 | 0 | 0 |
| Batch 001 + 002 | 17 | 0 | 0 | 0 | 0 |
| V3H + Hotfix 001/002 + V3I | 44 | 0 | 0 | 0 | 0 |
| Demo v1/v2/v34/v35 | 53 | 0 | 0 | 0 | 0 |

## 22. Suite global

- Baseline: `853/853`.
- Final local: `862/862`.
- Node: `20/20`.
- TS/TSX: `842/842`.
- Incremento: exactamente 9 tests, todos de la nueva suite.
- Failed / skipped / todo / cancelled: `0 / 0 / 0 / 0`.

## 23. Typecheck

`npm run typecheck`: PASS con `tsc --noEmit --incremental false`.

## 24. Build y rutas

`npm run build`: PASS. Se generaron `78/78` rutas; no se anadio ninguna ruta.

## 25. Lint

- `npm run lint`: PASS. El unico mensaje informativo es la desoptimizacion de estilo de Babel para `app/page.tsx` por superar 500 KB; no es un error ni fue introducido por este lote.
- Lint focalizado sobre ambos tests V3I: PASS.

## 26. git diff --check

PASS. No hay whitespace errors.

## 27. Secret scan

PASS sobre las rutas modificadas/nuevas y sobre `.next/static` + `.next/server`: cero ficheros con patrones de credenciales Stripe, Supabase o JWT. No se conservaran capturas, perfiles o artefactos temporales. No se imprimio ningun secreto.

## 28. Tabla Axe final

| Viewport | Light explicito | Light automatico | Dark explicito | Dark por defecto |
| --- | ---: | ---: | ---: | ---: |
| 1440x900 | 0 | 0 | 0 | 0 |
| 1280x720 | 0 | 0 | 0 | 0 |
| 1024x768 | 0 | 0 | 0 | 0 |
| 390x844 | 0 | 0 | 0 | 0 |
| 360x800 | 0 | 0 | 0 | 0 |
| 844x390 | 0 | 0 | 0 | 0 |

Fueron 48 ejecuciones locales (dos repeticiones de cuatro modos por seis viewports), todas HTTP 200, sin overflow, imagenes rotas, consola, red ni respuestas 4xx/5xx inesperadas. Los incompletos Axe restantes son gradientes/pseudoelementos o elementos parcialmente ocultos en carruseles; la composicion matematica y los estilos computados dan ratios conformes.

## 29. Perspectivas y pestanas

Inicio, Partidos, Retos, Mercado, Perfil y Avisos quedaron en cero contrastes serios/criticos en desktop, portrait y landscape. Player, team-owner y free-agent en Inicio portrait tambien quedaron en cero. Los siete recorridos de Revision rapida pasaron en portrait y landscape; sus dialogos tuvieron `color-contrast/select-name/region = 0/0/0`. Equipo redujo los nodos de acento, pero conserva `26/22/1` nodos preexistentes del renderer oscuro de ranking en desktop/portrait/landscape y un `scrollable-region-focusable` preexistente en landscape; no son causados por los tokens Demo light y quedan fuera del objetivo unico.

## 30. Comparacion visual

- Demo light: cambiaron solo `0.3336%`, `0.7995%` y `0.1853%` de pixeles en 1440x900, 390x844 y 844x390, limitados a foregrounds de acento.
- Geometria, bounding boxes, texto, layout y copy: cero diferencias.
- Demo dark: SHA-256 antes/despues identico en los tres viewports (`8ee4f213...`, `2ff127d8...`, `87499348...`).
- ProductContextSelector: contraste corregido mediante aliases sin cambio estructural.

## 31. Superficies live

La comparacion local base/cambio de `/mercado` signed-out dio cero pixeles, texto y geometria distintos en 390x844 y 844x390. El scan amplio confirmo cero fugas de tokens y cero nuevas violaciones. Se conservaron como deuda preexistente 18 nodos light portrait en Mercado live y 1 en Retos live; sus resultados fueron identicos antes/despues y no se tocaron por ser ajenos a V3I-003.

## 32. PWA/offline

Manifest y Service Worker devolvieron HTTP 200. Una ventana Chrome real `--app` informo `standalone` en light/dark portrait/landscape, con contraste/select-name/region `0/0/0`. El worker quedo activo y controlador, con una sola cache; elimino una cache legacy de Batch 001. El CSS nuevo sobrevivio al reload offline, mostro el aviso offline, no genero claves pendientes ni fake success y convergio al reconectar. Los unicos fallos de red fueron los RSC esperados mientras el transporte estaba forzado offline. Manifest, worker y politica de cache no fueron modificados.

## 33. Autoridad y contadores

La Demo sigue siendo sintetica y session-local; no se cambio autoridad, datos ni backend.

- `remoteWrites = 0`
- `externalNotifications = 0`
- `pushSent = 0`
- `emailsSent = 0`
- `realEntities = 0`
- `StripeCalls = 0`

Supabase: no modificado. Migraciones: 0. RPC/RLS/flags: no modificados. Stripe: no modificado. Entidades reales y notificaciones reales: 0.

## 34. Rollback

El rollback funcional consiste en revertir exclusivamente los aliases/foregrounds light, el registro de la nueva suite y la reconciliacion del octavo test. No toca 001/002, datos, selector compartido, PWA ni backend. Debe activarse ante cualquier contraste canonico serio/critico, fuga dark/live, cambio de layout, regression Social RC o fallo PWA.

## 35. QA fisica pendiente

- Android fisico: `PENDING`.
- iPhone fisico: `PENDING`.
- PWA fisicamente instalada: `PENDING`.

La ejecucion standalone automatizada no se presenta como QA fisica.

## 36. Limites

No hubo cambios de producto, layout, copy, navegacion, dataset, mutaciones, backend, Supabase, migraciones, RPC, RLS, flags, Stripe, Vercel, manifest, Service Worker, assets ni superficies live. No se inicio ni definio Wave 9C. Las incidencias neutras preexistentes del renderer de ranking de Equipo no se corrigieron silenciosamente ni ampliaron el lote.

## 37. Conclusion

La solucion local satisface el objetivo exclusivo `OFFICIAL-UI-V3I-003`: separa pintura y foreground dentro de Demo, elimina los contrastes canonicos de light explicito y automatico, mantiene dark pixel-identico y no afecta live. El estado permanece `BLOCKED` unicamente hasta certificar la Preview del HEAD exacto; despues, si todos los gates remotos reproducen estos resultados, podra cambiar a `BATCH 002 STATUS: READY FOR MERGE`.
