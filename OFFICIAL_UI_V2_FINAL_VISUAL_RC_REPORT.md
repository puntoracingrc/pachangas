# Official UI V2 - Final Visual Release Candidate

Fecha de cierre local: 2026-08-22 09:14 CEST

## 1. Estado del candidato

| Dato | Valor |
| --- | --- |
| Repositorio | `puntoracingrc/pachangas` |
| `origin/main` auditado | `0d8ceecd2e24016cf11a3dd6d4bf959c2611fbfa` |
| Rama | `codex/official-ui-v2-demo-convergence` |
| PR | [#158 - Converge Official UI V2 with Demo World](https://github.com/puntoracingrc/pachangas/pull/158) |
| HEAD inicial | `2f8fa73be58524d3dc7ea9e710e3a762b4d2dba9` |
| Divergencia inicial con `main` | `0 behind / 9 ahead` |
| Estado inicial PR | `OPEN`, `DRAFT`, `CLEAN`, `MERGEABLE`, Vercel `SUCCESS` |
| Preview inicial | `https://pachangas-og9v1mrce-persianas-almar-web-s-projects.vercel.app` |
| HEAD funcional auditado | `d35250faf66a6462c2190c67f09fcb6c22a3e59b` |
| Produccion modificada | **NO** |
| Supabase staging/produccion modificado | **NO** |
| Merge realizado | **NO** |
| Preview funcional auditada | `https://pachangas-n202afbi5-persianas-almar-web-s-projects.vercel.app` |
| Deployment auditado | `dpl_ANP3QURrovDkWxNXvbUYiqd44D2i` (`READY`) |

La rama seguia basada exactamente en el `main` conocido al comenzar y `origin/main` no avanzo durante el cierre. No fue necesario rebase ni merge de actualizacion.

## 2. Entorno y alcance

- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-official-ui-v2-demo-convergence`.
- Checkout principal sucio: no se ha tocado.
- macOS 15.7.7 (24G720), Node.js 24.16.0 y npm 11.13.0.
- Browser QA: Chromium del navegador integrado, build local de produccion y Preview Vercel.
- Base de datos: Supabase local en Docker solo para pruebas R3/RLS/concurrencia; el estado se restauro al terminar.
- Alcance persistente del pulido final: presentacion, responsive, accesibilidad, navegacion e integracion visual objetiva.
- El diff completo del PR contra `main` contiene **0 rutas `supabase/`**, 0 migraciones, 0 SQL, 0 RPC y 0 cambios RLS.

No se han anadido League Engine, Tournament Engine, Discipline, funciones arbitrales, filtros de Mercado, rewards, cosmeticos, planes, Stripe, Clubs activos ni flags productivos.

## 3. Correcciones del pulido final

| Defecto encontrado | Correccion | Regresion |
| --- | --- | --- |
| La accion de finalizar quedaba visualmente diluida en Resultado | Marcador horizontal estable y boton `Finalizar partido` dentro del bloque protagonista | `tests/official-ui-v2.test.ts` |
| Resultado se deformaba en landscape estrecho | Grid y score sin saltos destructivos; controles de goleadores con dimension estable | `tests/official-ui-v2.test.ts` |
| Superficies claras conservaban textos y bordes pensados para oscuro | Variables semanticas light/dark en shell, primitivas, labs, perfiles y Mercado arbitral | Tests Official UI V2 y matriz clara |
| Marca compacta tenia contraste insuficiente en tema claro | Marca con acento luminoso sobre placa oscura estable | Axe + regresion focal |
| Icono visible de producto/admin/Club no representaba correctamente la marca | Uso consistente del asset PWA oficial; SVG monocromo corregido para usos mask | Regresion textual y 0 imagenes rotas |
| Detalle arbitral desplazable no era alcanzable por teclado | Region etiquetada y enfocables sus detalles | Axe + test R3/UI |
| Mercado arbitral exponia una jerarquia ARIA `listbox/option` invalida | Grupo semantico y botones nativos con `aria-pressed` | Axe + test R3/UI |
| Texto secundario del Control Center quedaba por debajo del contraste minimo | Color semantico de texto admin | Axe + test R3/UI |
| Colores fijos del laboratorio arbitral y perfiles no convergian entre temas | Superficies, controles, estados y detalle usan tokens Official UI V2 | Matriz clara/oscura |
| Perfil privado y asignacion arbitral hidrataban la fecha con zonas horarias distintas en servidor y navegador | Formato determinista con la zona canonica de la asignacion y fallback `Europe/Madrid` | Test R3/UI + consola de Preview |

El pulido modifica 19 rutas de codigo/tests antes de incorporar este informe y las cinco hojas de evidencia. No introduce dependencias ni nuevos chunks de JavaScript.

## 4. Conclusion de revision humana

La jerarquia final se entiende como `contexto -> estado principal -> siguiente accion -> detalle`. Inicio conduce al proximo partido; Partido distingue Proximo, Alineacion, Resultado y Admin; Mercado conserva busqueda y resultados; Carta y Escudo son el objeto protagonista; el perfil arbitral no se confunde con una carta de jugador.

El resultado ya no parece un conjunto de modulos con el mismo peso: asistencia, campo, marcador, carta, escudo y propuesta arbitral dominan su superficie respectiva. Los estados secundarios y el historial quedan subordinados. Demo World sigue siendo la autoridad estetica y no aparece una tercera identidad.

## 5. Superficies revisadas

| Superficie | Desktop | Portrait | Landscape | Observacion |
| --- | --- | --- | --- | --- |
| Inicio autenticado | PASS | PASS | PASS | CTA de asistencia visible y actividad secundaria |
| Partido / Proximo | PASS | PASS | PASS | Contexto, revision, asistencia y convocatoria reconocibles |
| Alineacion | PASS | PASS | PASS | Campo horizontal protagonista, banquillo y cierre compactos |
| Resultado | PASS | PASS | PASS | Marcador, goleadores y finalizacion sin competencia visual |
| Admin partido | PASS | PASS | PASS | Estado y operaciones separados |
| Mercado | PASS | PASS | PASS | Filtros compactos y tarjetas escaneables |
| Ranking | PASS | PASS | PASS | Posicion propia y tabla con prioridad correcta |
| Avisos | PASS | PASS | PASS | Filtros, criticidad y accion por aviso |
| Personalizar carta | PASS | PASS | PASS | `PlayerCardView`/objeto a la izquierda y acciones a la derecha |
| Identidad de equipo | PASS | PASS | PASS | Escudo protagonista, inventario y guardado visibles |
| Mercado de arbitros | PASS | PASS | PASS | Filtros, lista, detalle y propuesta owner-only conservados |
| Perfil arbitral privado | PASS | PASS | PASS | Perfil, cobertura y asignaciones; sin GRL ni rating |
| Perfil arbitral publico | PASS | PASS | PASS | Identidad arbitral, Clubs y agenda; disciplina no disponible |
| Propuesta/asignacion | PASS | PASS | PASS | Aceptar/rechazar o cancelar segun estado |
| Control Center | PASS | PASS | PASS | Navegacion propia de plataforma, sin mezclar shell de producto |
| Demo World | PASS | PASS | PASS | Aislado, navegable y sin competir con producto oficial |
| Landing publica | PASS | PASS | PASS | Sin regresion de navegacion o assets |

Los estados vacios genericos, offline y permiso insuficiente se revisaron visualmente en el laboratorio de tokens. Los estados reales de Mercado sin resultados, ranking no elegible, arbitros sin resultados, asignaciones vacias y Clubs vacios conservan copy y acciones especificas en sus componentes y tests. No se crearon fixtures persistentes en staging para forzar cuentas reales sin equipo o sin permisos.

## 6. Responsive y Mobile Game Landscape

- Desktop: 1440x900 y 1920x1080.
- Portrait: 390x844 y 360x800.
- Landscape: 667x375, 740x360, 812x375, 844x390, 896x414 y 932x430.
- Matriz automatizada: 221 combinaciones principales entre rutas, viewports y temas, sin fallo duro.
- Smoke del deployment final: 51/51 combinaciones, 17 superficies en 1440x900, 390x844 y 844x390; 0 fallos, 0 imagenes rotas, 0 overflow y 0 errores o warnings de consola.
- Resultado: 0 overflow de `body`, 0 imagenes rotas, 0 footer, 0 doble navegacion y 0 CTA principal fuera de pantalla.
- En las seis anchuras landscape, el shell oficial declara `MOBILE_GAME_LANDSCAPE`; no reutiliza una sidebar desktop comprimida.
- La alineacion conserva un campo realmente horizontal, circulo central circular, banquillo lateral y accion de cierre visible.
- Carta y Escudo mantienen composicion `objeto + inventario + acciones`.
- Las zonas densas de Referee Platform usan scroll interno intencional; la pagina no desborda horizontalmente.

Safe areas y controles se validaron en viewports emulados. La comprobacion real de notch y barras de sistema queda dentro de la QA fisica pendiente.

## 7. Tema, movimiento y accesibilidad

- Tema oscuro: 17 superficies prioritarias en desktop, portrait y todos los landscape requeridos.
- Tema claro: 17 superficies en 1440x900, 390x844 y 667x375; 51 combinaciones sin fallo duro.
- Datos largos: nombre arbitral, municipio, biografia, modalidades y zonas envuelven el contenido sin superposicion ni truncado destructivo en el cuerpo principal.
- `prefers-reduced-motion: reduce`: 0 elementos visibles con animacion o transicion decorativa superior a 1 ms en la superficie medida; el feedback funcional permanece.
- Axe: 15 superficies/configuraciones de alto valor, **0 violations** tras las correcciones.
- Los analisis de contraste que Axe marca como incompletos por fondos con imagen/gradiente se revisaron visualmente.
- Focus visible, labels, controles nativos, regiones, estados y orden de tabulacion se comprobaron de forma focal.
- El drawer cerrado del Control Center permanece no visible y no operable segun sus tests de integracion.

## 8. Giro, estado y teclado virtual

Se selecciono `Marc Vidal` y el filtro `Valles Occidental` en Mercado de arbitros. El ciclo 390x844 -> 844x390 -> 390x844 conservo ruta, filtro y seleccion, cambiando solo el modo de layout.

Una biografia arbitral en edicion conservo borrador y foco. Con teclado virtual simulado a 390x500 y 844x250, el campo activo y la accion de guardado siguieron siendo alcanzables mediante scroll interno. No se observaron RPC, propuestas, notificaciones ni guardados repetidos durante el giro.

## 9. PWA

- Build local de produccion con Service Worker real.
- Manifest: `display: fullscreen`, fallbacks `standalone`, `minimal-ui` y `browser`, orientacion `any`, cinco iconos.
- Service Worker activo y controlador en `/sw.js`, `updateViaCache: none` y `Cache-Control: no-cache, no-store, must-revalidate`.
- Browser normal y modo standalone emulado en portrait y landscape: PASS.
- Navegacion offline de `/demo?tab=ranking`: PASS mediante cache del Service Worker.
- Offline real emulado: la API central falla, la UI muestra `Sin conexion` y no presenta ninguna escritura como confirmada.
- Reconexion: `/api/client-policy` vuelve a 200 con `private, no-store` y se elimina el aviso offline.
- Tests PWA: rechazo de escritura, ausencia de fake success, operacion pendiente, actualizacion del worker y una sola recarga.

La emulacion standalone valida el contrato web, pero no sustituye una instalacion fisica.

## 10. Performance visual

Medicion sobre `npm start` y build de produccion local:

| Ruta | DOMContentLoaded | Load | Recursos transferidos observados | CLS observado |
| --- | ---: | ---: | ---: | ---: |
| Inicio | 114 ms | 125 ms | 1.85 MB | 0 |
| Alineacion | 41 ms | 45 ms | 1.85 MB | 0 |
| Mercado | 30 ms | 37 ms | 1.85 MB | 0 |
| Mercado arbitros | 86 ms | 101 ms | 2.04 MB | 0 |
| Demo World | 33 ms | 42 ms | 1.85 MB | 0 |

- Imagen de carta optimizada por Next: 23.6 KB, completa, 400x500 natural.
- Escudo de la fixture: 77.6 KB, completo, 256x256 natural.
- Icono de marca PWA reutilizado: 71.2 KB y cacheable; no se incorpora un asset de runtime nuevo.
- Comparacion descomprimida con la Preview inicial: mismo numero de chunks JS (13), +3.2 KB de JavaScript y +73.0 KB total, explicado casi por completo por la marca PNG visible.
- Cambio de orientacion: primera transicion fria 652 ms; transiciones posteriores 21-124 ms, mediana 37 ms.
- No hay animaciones permanentes ni renders masivos introducidos por este pulido.

Estas cifras son una referencia local de RC, no Web Vitals de usuarios reales.

## 11. Pruebas y gates

| Gate | Resultado |
| --- | --- |
| `npm ci` | PASS en reintento tras limpiar solo caches regenerables del worktree; 522 paquetes |
| `npm test` | PASS, **342/342** tests actuales |
| `npm run typecheck` | PASS |
| `npm run build` | PASS |
| Official UI V2 + integracion visual R3 focal | PASS, 16/16 |
| R1/R2/R3 + UI/PWA focal | PASS, 86/86 |
| Rendered HTML | PASS, 9/9 |
| SQL/RLS R3 + adversarial | PASS en Supabase local |
| Idempotencia y concurrencia R3 | PASS en Supabase local |
| Estado local tras SQL | Restaurado exactamente; 113/113 migraciones locales |
| Lint focalizado | PASS, 0 hallazgos |
| Lint global | 43 heredados: 23 errores y 20 warnings; 0 nuevos del RC |
| `git diff --check` | PASS |

La orden esperaba 360 tests o mas, pero la suite actual del repositorio contiene 342. No se han inventado tests para alcanzar una cifra nominal: los 342 pasan y las baterias focales anteriores tambien pasan. `npm audit` informa 21 vulnerabilidades de dependencia heredadas (1 low, 4 moderate, 16 high); no se aplico `npm audit fix` fuera de alcance.

## 12. Invariantes funcionales

Se conservaron sin cambios Rating V2, facetas, fiabilidad, partidos, resultados, participantes, Attendance, Conduct, Achievements, Rewards, Player Cosmetics, Team Cosmetics, Billing, Season Score, Ranking, Clubs, Competitions y Canonical Match.

Los cinco mappings activos de Team Cosmetic Rewards siguen siendo exactamente:

1. `first_challenge_win` -> `team.shield.border.copper`.
2. `ten_challenges` -> `team.shield.ornament.banner`.
3. `twenty_five_matches` -> `team.shield.ornament.laurels`.
4. `fifty_matches` -> `team.shield.border.silver`.
5. `first_clean_sheet` -> `team.shield.effect.edge_glow`.

Premium Ball permanece inactivo. Las 29 propuestas Premium Art siguen siendo assets/laboratorio `noindex,nofollow`; ninguna se convierte en reward, propiedad o catalogo activo.

Mercado de arbitros conserva gating, fallback de `?tab=arbitros`, `canProposeReferee`, propuesta owner-only y los componentes productivos reales. Disciplina sigue mostrando `Estadisticas disciplinarias disponibles cuando se active el motor de disciplina`; nunca inventa ceros.

## 13. Evidencia visual

- `docs/official-ui-v2/OFFICIAL_UI_V2_FINAL_DESKTOP_CONTACT_SHEET.png`
- `docs/official-ui-v2/OFFICIAL_UI_V2_FINAL_PORTRAIT_CONTACT_SHEET.png`
- `docs/official-ui-v2/OFFICIAL_UI_V2_FINAL_MOBILE_GAME_LANDSCAPE_CONTACT_SHEET.png`
- `docs/referee-platform-official-ui-v2/REFEREE_PLATFORM_OFFICIAL_UI_V2_FINAL_CONTACT_SHEET.png`
- `docs/official-ui-v2/OFFICIAL_UI_V2_FINAL_BEFORE_DEMO_FINAL_CONTACT_SHEET.png`

Las capturas individuales temporales se eliminaron despues de componer las hojas; no contienen datos productivos ni personales.

## 14. QA fisica y decisiones pendientes

| Plataforma | Estado |
| --- | --- |
| Android real | `PHYSICAL_QA_PENDING` |
| iPhone real | `PHYSICAL_QA_PENDING` |

El RC no se declara `READY FOR PRODUCTION`. La futura release necesita QA fisica o un waiver humano explicito.

Decisiones visuales reservadas a aprobacion humana:

1. Densidad final del Inicio.
2. Tamano protagonista definitivo de carta y escudo.
3. Posicion exacta del rail landscape.
4. Intensidad de fondos y efectos ambientales.
5. Cantidad visible de informacion secundaria antes de scroll.

## 15. Conclusion

El candidato cumple el objetivo visual: desktop se comporta como producto coherente, portrait como aplicacion completa y landscape como un modo de juego propio. La Preview exacta del HEAD funcional auditado esta `READY` y queda preparada para aprobacion visual humana, manteniendo el PR abierto y en draft. El commit documental que contiene este propio informe se registra de forma autoritativa en el PR #158 para evitar una referencia circular dentro del archivo.

Estado objetivo tras publicar y validar la Preview final:

`OPEN / DRAFT / BASE main / CLEAN / MERGEABLE / VERCEL SUCCESS / READY FOR HUMAN VISUAL APPROVAL`.
