# V3H Social Core Incidents

## Política

Cada incidencia se registró en este ledger antes de corregirse; el inventario inicial también permanece en `SOCIAL_CORE_V3H_USABILITY_AUDIT.md`. V3H no modifica backend, autoridad deportiva ni datos productivos.

| ID | Clase | Estado | Corrección | Regresión |
| --- | --- | --- | --- | --- |
| V3H-001 | CLUTTER | fixed | Landing reducida a mensaje, Demo, acceso, descubrimiento y tres pasos | `official-ui-v3h-social-core`: landing |
| V3H-002 | COPY | fixed | Banner social usa `SIMULACIÓN · datos ficticios · sesión local` | test Demo + QA visual |
| V3H-003 | CLUTTER | fixed | `Revisión rápida` es la acción principal; reinicio/salida quedan secundarios | test Demo + QA visual |
| V3H-004 | COPY | fixed | Equipo social usa nombre/ranking deportivo; versiones y `read model` solo permanecen en `/admin/demo` | test Demo social filtering |
| V3H-005 | INCONSISTENT | fixed | Selector social limita perspectivas a usuario nuevo, jugador, admin y owner | test Demo social filtering |
| V3H-006 | INCONSISTENT | fixed | Mercado Demo conserva el shell oscuro/transparente en game landscape | QA 844×390 |
| V3H-007 | CLUTTER | fixed | Activos/Historial es la única navegación local; dirección es un filtro select | test Retos + QA portrait/landscape |
| V3H-008 | CONFUSING | fixed | Retos deriva un único estado vacío/unavailable con una salida | test Retos empty branch |
| V3H-009 | RESPONSIVE | fixed | Geolocalización de Mercado se compacta como control icónico accesible en portrait | test Mercado + QA 390×844 |
| V3H-010 | ACCESSIBILITY | fixed + regression_verified | Targets prioritarios de Mercado pasan a 44 px y el resto del núcleo social queda en 40 px mínimo sin degradar landscape | 24 combinaciones apaisadas, 0 targets pequeños |
| V3H-011 | INCONSISTENT | fixed | Auditor visual separa `/avisos` de `/ajustes/notificaciones` | test visual audit routes |
| V3H-012 | BLOCKING | fixed | Demo incorpora siete recorridos locales con navegación, reinicio y pruebas de cero escritura | test Demo + QA dialog/keyboard |
| V3H-013 | LEGITIMATE DIFFERENCE | accepted | Carta, escudo, alineación y resultado conservan riqueza deportiva | tests V3 existentes |
| V3H-014 | LEGITIMATE DIFFERENCE | accepted | Se conserva Mobile Game Landscape y se verifica overflow/contraste | auditor visual V3H final |
| V3H-015 | TESTABILITY_GAP | fixed + regression_verified | El auditor espera `navigator.serviceWorker.ready` sin límite en desarrollo | Build productivo PWA: 8/8 superficies `standalone` y controladas por Service Worker |
| V3H-016 | TESTABILITY_GAP | fixed + regression_verified | El auditor abre primero el partido canónico y después pulsa el submenú | 24 combinaciones de Alineación/Resultado/Admin pasan |
| V3H-017 | ACCESSIBILITY | fixed + regression_verified | La restauración se difiere hasta que el diálogo está desmontado y conserva el activador original | teclado real: trampa de foco, Escape y retorno al botón |
| V3H-018 | BLOCKING | fixed + regression_verified | La intención `review=1` se aplica tras hidratación sin alterar la Demo pública | navegación real Landing → Probar Demo → diálogo visible y enfocado |
| V3H-019 | ACCESSIBILITY | fixed + regression_verified | Legales, descubrimiento landscape y filtros de Retos Demo quedan en 40 px mínimo | 16 combinaciones en ocho viewports, 0 targets pequeños |
| V3H-020 | TESTABILITY_GAP | fixed + regression_verified | `rendered-html` conserva el titular y el botón de sesión de V3G, por lo que rechaza la landing V3H válida | `rendered-html` 9/9 y batería 824/824 |
| V3H-021 | TESTABILITY_GAP | fixed + regression_verified | Social Inbox exige la guarda de `Primeros pasos`, pero no reconoce la guarda adicional de `Revisión rápida` | Suite social focalizada 23/23 y batería 824/824 |
| V3H-022 | TESTABILITY_GAP | fixed + regression_verified | Social Inbox conserva el contrato apaisado de 36 px y rechaza el mínimo accesible de 40 px aplicado por V3H | Suite social focalizada 23/23 y batería 824/824 |
| V3H-023 | TESTABILITY_GAP | fixed + regression_verified | La regresión V3E conserva la etiqueta genérica `Empezar` y no reconoce la acción V3H `Revisión rápida` | Suites sociales cruzadas 45/45 y batería 824/824 |
| V3H-024 | TESTABILITY_GAP | fixed + regression_verified | La regresión V3C conserva el copy largo de ausencia de equipo y rechaza el estado vacío V3H | Suites sociales cruzadas 61/61 y batería 824/824 |
| V3H-025 | TESTABILITY_GAP | fixed + regression_verified | Demo V1 conserva la entrada `/demo` y el copy anterior, y rechaza el deep link guiado de V3H | Demo V1 + V3H 29/29 y batería 824/824 |
| V3H-026 | CODE_QUALITY | fixed + regression_verified | El deep link `review=1` abre el diálogo con un `setState` síncrono dentro de un efecto | Lint focalizado limpio y deep link visible/enfocado tras hidratación |
| V3H-027 | CODE_QUALITY | fixed + regression_verified | El cleanup de foco consulta `dialogRef.current`, que puede apuntar a otro nodo al desmontar | Lint focalizado limpio; trampa, Escape y retorno al activador verificados |
| V3H-028 | TESTABILITY_GAP | fixed + regression_verified | La prueba V3H conserva la comparación positiva anterior al arreglo de lint y no exige apertura diferida/cancelable | V3H 6/6 y batería 824/824 exigen frame y cancelación |
| V3H-029 | TESTABILITY_GAP | fixed + regression_verified | La prueba V3H conserva `dialogRef.current` dentro del cleanup y rechaza la captura estable introducida por V3H-027 | V3H 6/6 y batería 824/824 exigen captura estable |
| V3H-030 | ENVIRONMENT_ISSUE | accepted | Deployment Protection acepta la página con OIDC, pero el registro interno de `/sw.js` no hereda ese header y la Preview protegida no obtiene controller | PWA productiva local 8/8 PASS; repetir SW en `pachangasiq.com` público tras el merge |
| V3H-031 | RESPONSIVE | fixed + regression_verified | Al ocultar cabecera y banner en Mobile Game Landscape, la Demo pierde la etiqueta persistente `SIMULACIÓN` | V3H 6/6, lint limpio y 4/4 landscape sin overflow ni targets pequeños |

`verifying` solo puede cambiar a `fixed + regression_verified` cuando terminen la matriz visual, teclado, temas y reduced motion del SHA exacto.
