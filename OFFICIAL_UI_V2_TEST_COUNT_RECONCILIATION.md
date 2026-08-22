# Official UI V2 - Test Count Reconciliation

Fecha: 2026-08-22

## 1. Conclusion exacta

La cifra anterior de **360** era correcta para los checkpoints `fc2fe94` y `2f8fa73`:

```text
node --test:  20
tsx --test:  340
total:        360
```

La cifra **342** publicada en el informe RC no era el total de `npm test`. Era solamente el segundo resumen TAP, correspondiente a `tsx --test`. El script encadena dos runners y cada uno imprime su propio total. El resumen del primer runner, `node --test`, aporta otros 20 tests.

El HEAD actual tiene dos regresiones nuevas en `tests/referee-official-ui-v2-integration.test.ts`. Por tanto, el total canonico actual es:

```text
node --test:  20
tsx --test:  342
total:        362
```

**Tests perdidos: NO.** No se ha restaurado ningun test porque no desaparecio ninguno. Desde `fc2fe94` hay dos tests y 22 assertions mas.

## 2. Checkpoints y entorno

| Dato | Valor |
| --- | --- |
| Gate combinado | `fc2fe949107b7f91c1f2febcf86a538aab21bff8` |
| Inicio RC final | `2f8fa73be58524d3dc7ea9e710e3a762b4d2dba9` |
| HEAD conciliado | `d2ffc94720e15cc659ed8e7c48f1a389d2ab8353` |
| Node.js | `24.16.0` |
| npm | `11.13.0` |
| `tsx` | `4.22.1`, misma version fijada en los tres checkpoints |
| `package.json` blob | `e38f6ca931f3f970b689fd4073ee849c91a28e3b` en los tres checkpoints |
| `package-lock.json` blob | `9ac16e4747db91a720e273ed1b2731c2640f91ba` en los tres checkpoints |

El script `npm test`, la lista de archivos, el runner y el lockfile son byte a byte iguales en los tres checkpoints.

## 3. Inventario completo de `npm test`

| Test file | fc2fe94 | 2f8fa73 | d2ffc94 | Subtests antes | Subtests ahora | Motivo |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `tests/achievement-catalog-v2.test.ts` | 5 | 5 | 5 | 5 | 5 | Sin cambios |
| `tests/achievement-catalog-v3.test.ts` | 6 | 6 | 6 | 6 | 6 | Sin cambios |
| `tests/achievements-crests-contract.test.ts` | 12 | 12 | 12 | 12 | 12 | Sin cambios |
| `tests/adaptive-compatibility.test.ts` | 3 | 3 | 3 | 3 | 3 | Sin cambios |
| `tests/admin-view-preview.test.tsx` | 3 | 3 | 3 | 3 | 3 | Sin cambios |
| `tests/challengeable-team-contract.test.ts` | 4 | 4 | 4 | 4 | 4 | Sin cambios |
| `tests/club-foundation-v1.test.ts` | 19 | 19 | 19 | 19 | 19 | Sin cambios |
| `tests/competition-organizer-foundation-v1.test.ts` | 15 | 15 | 15 | 15 | 15 | Sin cambios |
| `tests/conduct-reports-no-show-v1.test.ts` | 5 | 5 | 5 | 5 | 5 | Sin cambios |
| `tests/conduct-triage-v1-1.test.ts` | 7 | 7 | 7 | 7 | 7 | Sin cambios |
| `tests/core-social-flows-closure-v1.test.ts` | 3 | 3 | 3 | 3 | 3 | Sin cambios |
| `tests/database-bootstrap.test.mjs` | 5 | 5 | 5 | 5 | 5 | Sin cambios |
| `tests/demo-world-v1.test.ts` | 22 | 22 | 22 | 22 | 22 | Dos assertions PWA nuevas; mismos subtests |
| `tests/match-guest-access.test.ts` | 6 | 6 | 6 | 6 | 6 | Sin cambios |
| `tests/network-diversity-v31.test.ts` | 14 | 14 | 14 | 14 | 14 | Sin cambios |
| `tests/notification-foundation.test.ts` | 7 | 7 | 7 | 7 | 7 | Sin cambios |
| `tests/official-ui-v2.test.ts` | 6 | 6 | 6 | 6 | 6 | Siete assertions visuales nuevas; mismos subtests |
| `tests/platform-control-center-v1.test.ts` | 15 | 15 | 15 | 15 | 15 | Sin cambios |
| `tests/player-card-cosmetics-lab.test.mjs` | 6 | 6 | 6 | 6 | 6 | Sin cambios |
| `tests/player-cosmetics-v1.test.ts` | 6 | 6 | 6 | 6 | 6 | Sin cambios |
| `tests/player-rating-engine.test.ts` | 13 | 13 | 13 | 13 | 13 | Sin cambios |
| `tests/pwa-client-version-bridge.test.ts` | 10 | 10 | 10 | 10 | 10 | Sin cambios |
| `tests/pwa-client-version-routes.test.ts` | 4 | 4 | 4 | 4 | 4 | Sin cambios |
| `tests/ranking-productization-v1.test.ts` | 10 | 10 | 10 | 10 | 10 | Sin cambios |
| `tests/rating-system-v2.test.ts` | 22 | 22 | 22 | 22 | 22 | Sin cambios |
| `tests/referee-official-ui-v2-integration.test.ts` | 8 | 8 | 10 | 8 | 10 | Dos regresiones nuevas: tema y zona horaria |
| `tests/referee-platform-v1.test.ts` | 18 | 18 | 18 | 18 | 18 | Sin cambios |
| `tests/rendered-html.test.mjs` | 9 | 9 | 9 | 9 | 9 | Sin cambios |
| `tests/reward-box-demo.test.ts` | 4 | 4 | 4 | 4 | 4 | Sin cambios |
| `tests/reward-economy-simulation.test.ts` | 4 | 4 | 4 | 4 | 4 | Sin cambios |
| `tests/reward-economy-v1-1-simulation.test.ts` | 2 | 2 | 2 | 2 | 2 | Sin cambios |
| `tests/season-ranking-attacks.test.ts` | 5 | 5 | 5 | 5 | 5 | Sin cambios |
| `tests/season-ranking-elite.test.ts` | 11 | 11 | 11 | 11 | 11 | Sin cambios |
| `tests/season-ranking-engine.test.ts` | 9 | 9 | 9 | 9 | 9 | Sin cambios |
| `tests/season-ranking-v3.test.ts` | 13 | 13 | 13 | 13 | 13 | Sin cambios |
| `tests/team-cosmetic-rewards-v1.test.ts` | 7 | 7 | 7 | 7 | 7 | Sin cambios |
| `tests/team-shield-cosmetics-v1.test.ts` | 8 | 8 | 8 | 8 | 8 | Sin cambios |
| `tests/team-shield-premium-borders-v1.test.ts` | 5 | 5 | 5 | 5 | 5 | Sin cambios |
| `tests/team-social-contract.test.ts` | 6 | 6 | 6 | 6 | 6 | Sin cambios |
| `tests/territory-award-readiness.test.ts` | 18 | 18 | 18 | 18 | 18 | Sin cambios |
| `tests/visual-consistency-v1.test.ts` | 5 | 5 | 5 | 5 | 5 | Sin cambios |
| **Total Node** | **20** | **20** | **20** | **20** | **20** | Tres archivos MJS |
| **Total TSX** | **340** | **340** | **342** | **340** | **342** | Dos regresiones anadidas |
| **Total canonico** | **360** | **360** | **362** | **360** | **362** | Ninguna perdida |

## 4. Cambios de cobertura

No hay archivos de test anadidos, retirados ni renombrados entre los tres checkpoints. Solo cambian estos archivos:

| Archivo | fc2fe94 -> 2f8fa73 | 2f8fa73 -> d2ffc94 | Assertions antes | Assertions ahora |
| --- | --- | --- | ---: | ---: |
| `tests/demo-world-v1.test.ts` | Dos assertions de fallback PWA | Sin cambios | 146 | 148 |
| `tests/official-ui-v2.test.ts` | Sin cambios | Marca, contraste, Resultado y tokens | 39 | 46 |
| `tests/referee-official-ui-v2-integration.test.ts` | Sin cambios | Dos tests y trece assertions para tema e hidratacion | 51 | 64 |

Balance desde `fc2fe94`: **+2 tests, +22 assertions, 0 tests eliminados**.

## 5. Ejecucion historica y actual

| Ejecucion | Tests | Pass | Fail | Skip | Todo | Cancelled |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `fc2fe94`, grupo TSX completo | 340 | 340 | 0 | 0 | 0 | 0 |
| `2f8fa73`, grupo TSX completo | 340 | 340 | 0 | 0 | 0 | 0 |
| `d2ffc94`, grupo TSX completo | 342 | 342 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `rendered-html.test.mjs` | 9 | 9 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `database-bootstrap.test.mjs` | 5 | 5 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `player-card-cosmetics-lab.test.mjs` | 6 | 6 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `referee-platform-v1.test.ts` | 18 | 18 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `official-ui-v2.test.ts` | 6 | 6 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `referee-official-ui-v2-integration.test.ts` | 10 | 10 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `demo-world-v1.test.ts` | 22 | 22 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `pwa-client-version-bridge.test.ts` | 10 | 10 | 0 | 0 | 0 | 0 |
| `d2ffc94`, `pwa-client-version-routes.test.ts` | 4 | 4 | 0 | 0 | 0 | 0 |

Las tres suites modificadas tambien se ejecutaron individualmente en `fc2fe94` y `2f8fa73`: Demo World 22/22, Official UI V2 6/6 e integracion R3 8/8.

## 6. Tests focales fuera de `npm test`

El unico archivo TypeScript con tests que no entra en el script raiz es `tests/synthetic-world.test.ts`. Se ejecuta mediante `npm run test:synthetic-world`; en esta conciliacion paso 22/22. No formaba parte del total 360 y tampoco forma parte del total canonico 362.

El repositorio tambien conserva suites SQL, RLS, adversariales, de concurrencia, escala y staging bajo scripts `test:*`. Son gates especializados y no deben sumarse al total de `npm test`, porque varios vuelven a ejecutar archivos ya incluidos y otros requieren bases aisladas. Sumarlos produciria doble conteo.

## 7. Respuestas requeridas

| Pregunta | Respuesta |
| --- | --- |
| Por que antes se informaron 360 | Era `20 Node + 340 TSX`; el dato era correcto para esos checkpoints. |
| Por que aparecieron 342 | Se copio solo el subtotal final de TSX y se omitio el resumen Node. |
| Se elimino cobertura | **NO**. Hay dos tests y 22 assertions mas. |
| Cambio `package.json` | **NO**. Mismo blob en los tres checkpoints. |
| Cambio el runner | **NO**. Mismo lockfile y `tsx 4.22.1`. |
| Hay tests skipped/todo/cancelled | **NO** en las ejecuciones conciliadas. |
| Total correcto en `fc2fe94` y `2f8fa73` | **360**. |
| Total canonico actual | **362**. |
