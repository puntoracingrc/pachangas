# Official UI V2 Demo Convergence Report

## Resultado

`READY FOR VISUAL REVIEW`

- Origin/main inicial: `da6dace3a1a5d20de9fdba0d34174f916a2b2c61`.
- Rama: `codex/official-ui-v2-demo-convergence`.
- PR draft: [#158](https://github.com/puntoracingrc/pachangas/pull/158).
- HEAD final: commit que contiene este informe; SHA exacto en el PR y en la entrega final.
- Preview de rama: [Official UI V2](https://pachangas-git-codex-offic-7de519-persianas-almar-web-s-projects.vercel.app).
- Deployment funcional verificado: [Vercel Preview `a1d04708`](https://pachangas-kfstmay7i-persianas-almar-web-s-projects.vercel.app), estado `READY`.
- Producción modificada: **NO**.
- Supabase producción: **NO**.
- Supabase staging: **NO**.
- Merge: **NO**.
- R3 Referee Platform: **NO TOCADO**.

## Qué Se Implementó

1. Contrato y tokens semánticos en `app/_design-v2`.
2. `OfficialProductShellV2` con composiciones desktop, portrait y game landscape.
3. Componentes visuales compartidos, sin acoplarlos a datos Demo.
4. Shell aplicado a Inicio autenticado, Partido, Mercado, Ranking, Avisos, Identidad de equipo y Personalizar carta.
5. Control Center identificado como `PLATFORM_ADMIN`, sin convertirlo en HUD.
6. Laboratorio `/laboratorio-official-ui-v2`, `noindex,nofollow`, con fixtures exclusivamente visuales.
7. Capturas Before, Demo y After; hojas generales y específica landscape.
8. Tests de contrato visual, breakpoints, aislamiento y conservación de la lógica productiva.

## Pantallas Auditadas

- Inicio autenticado.
- Partido / Próximo / Alineación / Resultado / Admin.
- Mercado.
- Ranking.
- Avisos.
- Identidad de equipo.
- Personalización de carta.
- Landing pública.
- Control Center.
- Demo World.
- Google Places, por conservación de las superficies y mensajes existentes.

## Navegación

### Desktop

- Cabecera de producto común.
- Inicio, Partido, Mercado, Equipo y Perfil.
- Accesos directos a Ranking y Avisos.
- Contexto y estado visibles sin barra adicional.

### Portrait

- Conserva `MobileAppNav` como única autoridad de navegación inferior.
- Safe area y padding final evitan que la barra tape la última fila.
- Las superficies siguen siendo completas; no exigen girar.

### Mobile Game Landscape

- Rail de `88px`, context bar, área principal y paneles laterales.
- Sin cabecera, sidebar o footer de escritorio.
- Alineación prioriza campo y banquillo.
- Resultado prioriza marcador y goleadores.
- Carta y escudo se presentan como objetos de juego con controles laterales.
- Mercado y Ranking usan filtros/listados compactos, no tablas de desktop comprimidas.

## Detección Y Giro

- Teléfono landscape: `568–932px` de ancho y hasta `600px` de alto.
- Tablet táctil landscape: `768–1368px` y hasta `1024px`.
- Entradas: `visualViewport`, orientación, tamaño y puntero coarse; sin `userAgent`.
- A 125 % y 150 % de zoom, un desktop con puntero fino permanece `DESKTOP`.
- El árbol funcional se monta una sola vez. La prueba portrait → landscape → portrait mantuvo URL y el filtro `Sant Cugat` sin recarga ni pérdida de valor.

## Visual QA

### Viewports

| Grupo | Viewports | Resultado |
| --- | --- | --- |
| Desktop | `1440×900`, `1920×1080` | PASS |
| Portrait | `390×844`, `360×800` | PASS |
| Landscape obligatorio | `667×375`, `740×360`, `812×375`, `844×390`, `896×414`, `932×430` | PASS |
| Zoom | 125 %, 150 % sobre `1440×900` | PASS |

La matriz landscape midió cuatro superficies críticas en los seis tamaños: 24 comprobaciones, `0` overflow, `0` controles cortados y `0` imágenes rotas. Los extremos adicionales desktop/portrait añadieron 20 comprobaciones en las diez superficies.

### Temas Y Movimiento

- Tema oscuro: PASS.
- Tema claro: PASS; fondo y texto cambian a valores explícitos legibles.
- `prefers-reduced-motion`: PASS; duraciones efectivas `0.01ms`.

### Consola Y Recursos

- Errores Runtime/Log/Network en el pase final: `0`.
- Imágenes rotas: `0`.
- Capturas After con lienzo incompleto: `0/50`.
- Overflow horizontal documental: `0` en la matriz medida.
- Controles fuera del viewport sin scroller intencional: `0`.

### Preview Vercel

- Commit funcional desplegado: `a1d04708d58a24fc62ecb44140797805baca3100`.
- Estado Vercel: `READY`; checks del PR `Vercel` y `Vercel Preview Comments`: PASS.
- Laboratorio revisado en `1440x900`, `390x844` y `844x390`: modos `DESKTOP`, `MOBILE_PORTRAIT` y `MOBILE_GAME_LANDSCAPE` correctos.
- Dieciocho comprobaciones visuales sobre Inicio, Partido, Mercado, Ranking, Avisos, Equipo y Carta: `0` overflow, `0` controles cortados y `0` imágenes rotas.
- Navegación real: `/`, Mercado, Ranking, Avisos, Identidad, Personalizar carta, cuatro vistas del laboratorio, `/demo` y `/admin`: PASS.
- `/laboratorio-official-ui-v2`, `/demo` y `/admin` mantienen `noindex,nofollow`.
- La Preview está protegida por Vercel Authentication; la validación se realizó con acceso temporal de Preview, sin alterar producción.

## PWA

- Manifest local válido: fullscreen + fallback standalone/minimal-ui/browser, orientación libre, iconos normal/maskable/monochrome y shortcuts.
- `/sw.js`: `200`, `Service-Worker-Allowed: /`, `Cache-Control: no-cache, no-store, must-revalidate`.
- Bridge, actualización de worker, una sola recarga, offline sin fake success y version gate pasan en la batería existente.
- El motor de emulación disponible no puede convertir una pestaña normal en una PWA realmente instalada. Android/iPhone físico y PWA instalada real quedan como `PHYSICAL_QA_PENDING`; no se afirma que hayan pasado.

## Estados Y Permisos

- Visitante: landing pública conservada.
- Autenticado sin datos completos: estados empty/loading existentes conservados.
- Jugador, admin y owner: los guards y handlers originales no cambiaron.
- Sin permisos: estado restringido y ausencia de controles falsos.
- Offline/stale: lectura derivada disponible y escritura no confirmada.
- Platform owner: variante `PLATFORM_ADMIN` conservada.

No se ejecutaron mutaciones productivas. La validación funcional se apoya en tests de contratos/handlers, lectura de rutas y QA visual, no en acciones reales contra Supabase.

## Tests

| Check | Resultado |
| --- | --- |
| `npx tsx --test tests/official-ui-v2.test.ts` | PASS, 6/6 |
| `node --test tests/rendered-html.test.mjs` | PASS, 9/9 |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, 36 páginas estáticas generadas |
| `npm test` | PASS, build + 334 tests |
| Lint focalizado de la capa V2 | PASS, 0 errores y 0 avisos |
| `git diff --check` | PASS |

El lint ampliado que incluye los dos componentes monolíticos heredados reporta 15 errores y 23 avisos ya presentes en `app/page.tsx` y `app/mercado/page.tsx` (hooks/pureza y varios `<img>` antiguos). La capa V2 nueva no añade ninguno. No se corrigió esa deuda ajena a esta migración.

El runner legado `compat:browser` abre un perfil limpio sin autenticación y exige `main[data-mobile-tab]`, por lo que aterriza correctamente en la landing pública y falla su supuesto de sesión. La matriz responsive de esta fase se ejecutó sobre el laboratorio aislado y las rutas oficiales legibles; queda registrado como deuda de testabilidad del runner, no como fallo del layout V2.

## Autoridades Intactas

El diff no contiene SQL, migraciones, RPC, esquemas, fórmulas ni contratos de dominio. La batería confirma:

- Rating V2 y fiabilidad intactos.
- Partido, resultado, asistencia y alineación intactos.
- Conducta/no-show intactos.
- Logros, cajas y recompensas intactos.
- Los cinco Team Cosmetic Reward mappings siguen exactamente iguales.
- Premium Ball continúa sin activarse.
- Player Cosmetics y Team Cosmetics conservan inventario, loadout, NEW y revisiones.
- Season Score V3 y ranking intactos.
- Billing, Clubs y Competiciones intactos.

Inventario previo al commit: 95 rutas, incluidas 69 capturas PNG y 3 contact sheets solicitados.

## Evidencia

- [Auditoría visual](./DEMO_WORLD_OFFICIAL_UI_AUDIT_V1.md).
- [Contrato Official UI V2](./PACHANGAS_OFFICIAL_UI_V2_CONTRACT.md).
- `docs/official-ui-v2/OFFICIAL_UI_V2_CONTACT_SHEET.png`.
- `docs/official-ui-v2/OFFICIAL_UI_V2_MOBILE_GAME_LANDSCAPE_CONTACT_SHEET.png`.
- `docs/official-ui-v2/OFFICIAL_UI_V2_BEFORE_DEMO_AFTER_CONTACT_SHEET.png`.
- 69 capturas totales: 19 Before/Demo y 50 After finales.

## Declaraciones Finales

- Mobile Game Landscape preservado: **SÍ**.
- Desktop reducido utilizado: **NO**.
- Demo World sigue funcional e independiente: **SÍ**.
- Datos Demo importados a la oficial: **NO**.
- Producción modificada: **NO**.
- Supabase modificado: **NO**.
- Merge realizado: **NO**.
- QA física Android: `PHYSICAL_QA_PENDING`.
- QA física iPhone: `PHYSICAL_QA_PENDING`.
