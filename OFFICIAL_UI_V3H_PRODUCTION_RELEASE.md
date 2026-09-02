# Official UI V3H Production Release

## Resultado

Official UI V3H Social Core Final Usability se publicó y verificó en `https://pachangasiq.com` el 2 de septiembre de 2026.

- Estado: `RELEASED / PRODUCTION VERIFIED`.
- PR funcional: `#258`, fusionado.
- Rama funcional: `codex/official-ui-v3h-social-core-rc`.
- Base inicial: `fd97b25b191391baf17a60499e34c38dbd0e11cc`.
- HEAD funcional validado: `234f10714acc85287ecece10dcefd1a155323006`.
- Merge funcional en `main`: `c55e35a2460840195242d2cfd0529554839397ea`.
- Árbol Git validado: `3d26117ada591cd8530d7aa5d759ad33dd9f9bdb` tanto en el HEAD funcional como en el merge de `main`.

## Despliegues

| Fase | Deployment | URL | Resultado |
| --- | --- | --- | --- |
| Preview final | `dpl_2KB31zPhx4C8HDHCuX36pr48qvG6` | `https://pachangas-9esxo5r63-persianas-almar-web-s-projects.vercel.app` | READY; RC validado |
| Producción integrada con Git | `dpl_DXfsB2qioFy7Yg7vxy8ZauqSzP9x` | `https://pachangas-pz7zbqawu-persianas-almar-web-s-projects.vercel.app` | READY, pero invalidada visualmente por CSS global obsoleto recuperado de caché |
| Producción sin caché | `dpl_F8paNkcfNM5jdK24bmCwRmBehsYR` | `https://pachangas-g1rjeusp5-persianas-almar-web-s-projects.vercel.app` | READY; alias productivos y smoke final correctos |

Alias productivos confirmados sobre el último artefacto:

- `https://pachangasiq.com`
- `https://www.pachangasiq.com`

## Incidente de caché

El primer deployment productivo referenciaba un chunk CSS global anterior aunque `origin/main` contenía el CSS V3H correcto y su árbol coincidía exactamente con el RC. La auditoría estructural no lo marcó porque no había overflow, errores ni imágenes rotas; la comprobación visual manual de la Landing sí detectó que el CTA principal medía 17 px, tenía `display:inline` y carecía de fondo.

Se conservó la evidencia, se clasificó como V3H-033 `ENVIRONMENT_ISSUE` y se reconstruyó el mismo árbol con `vercel deploy --prod --force`. Tras el redespliegue, el CTA calculado quedó en `display:flex`, 48 px, fondo `rgb(79, 127, 22)`, sin overflow ni imágenes rotas. La matriz productiva completa volvió a ejecutarse contra el alias público.

## Gates de código

| Gate | Resultado |
| --- | --- |
| Tests Node | 20/20 PASS |
| Tests TS/TSX | 805/805 PASS |
| Total | 825/825 PASS |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Typecheck | PASS |
| Build | PASS, 78/78 rutas |
| Lint focalizado | PASS |
| Lint global | PASS; solo nota informativa de Babel por archivo mayor de 500 KB |
| `git diff --check` | PASS |

## QA de Preview

- Landing, Revisión rápida, Partido, Alineación, Resultado, Admin, Retos, Mercado, Equipo, Perfil y Avisos: PASS.
- Desktop, portrait y landscape: PASS.
- Tema claro y oscuro en Retos: PASS.
- Trampa de foco, Escape y retorno al activador: PASS.
- Etiqueta `SIMULACIÓN`: persistente.
- Escrituras remotas, notificaciones externas, push, email, entidades reales y Stripe: cero.
- El Service Worker de la Preview protegida no pudo heredar el header OIDC en su petición interna; V3H-030 permanece como limitación del entorno Preview y se validó correctamente en producción pública.

## QA de producción

Matriz ejecutada sobre `https://pachangasiq.com` después del despliegue sin caché:

- Casos: 88/88.
- Superficies: 22.
- Viewports: desktop 1440×900, portrait 390×844, landscape 844×390 y PWA standalone emulada 390×844.
- Overflow horizontal: 0.
- Imágenes rotas: 0.
- Errores de consola: 0.
- Warnings de consola: 0.
- Peticiones fallidas: 0.
- Errores de navegación: 0.
- Violaciones de viewport: 0.
- Violaciones de game chrome: 0.
- Targets pequeños: 0.
- PWA controlada por Service Worker: 22/22.

La comprobación visual manual confirmó la Landing simplificada, el CTA correcto y la ausencia de regresión de estilo. La matriz incluyó Landing, Demo review/inicio, Partido/Alineación/Resultado/Admin, Retos, Mercado, Equipo, Perfil, Avisos, Plantilla, Invitaciones, Carta, Identidad y Ajustes de notificaciones.

## PWA y reconexión

- Manifest público: `display: fullscreen` con fallback `standalone`, `minimal-ui` y `browser`.
- Iconos `any`, `maskable` y `monochrome`: presentes.
- `sw.js`: HTTP 200, `Service-Worker-Allowed: /` y caché desactivada para la actualización del worker.
- Demo controlada por Service Worker: PASS.
- Offline: el shell y la Demo sanitizada continúan disponibles, sin overflow ni imágenes rotas.
- Operación no cacheable offline: rechazada; no existe éxito ficticio.
- Reconexión: PASS.
- `/api/client-policy`: HTTP 200 y `Cache-Control: private, no-store, max-age=0, must-revalidate`.

Android físico, iPhone físico y PWA instalada en un dispositivo real permanecen `PENDING`; no se presentan como PASS.

## Logs

Durante el smoke del deployment final:

- Runtime errors: 0.
- HTTP 4xx: 0.
- HTTP 5xx: 0.
- Errores o warnings de consola: 0.

## Autoridad y alcance

- Supabase modificado: no.
- Migraciones aplicadas: 0.
- Ledger de migraciones: no alterado; referencia previa 235.
- Stripe modificado: no.
- Flags modificados: no.
- Rating, Team Rewards, Player Cosmetics, Team Cosmetics, Conduct, billing y autoridad deportiva: intactos.
- Demo: datos ficticios, sesión local y cero escrituras remotas.
- V3I, Wave 9C y nuevas capacidades sociales: no iniciadas.

## Evidencia

- `OFFICIAL_UI_V3H_END_TO_END_REPORT.md`
- `OFFICIAL_UI_V3H_ALBERTO_REVIEW_GUIDE.md`
- `SOCIAL_CORE_V3H_USABILITY_AUDIT.md`
- `SOCIAL_CORE_PRODUCT_LANGUAGE_V1.md`
- `SOCIAL_CORE_VISUAL_CONTRACT_V1.md`
- `V3H_SOCIAL_CORE_INCIDENTS.md`
- `docs/official-ui-v3h/`

La evidencia temporal de navegador se retirará al cerrar la rama documental. Los seis contact sheets solicitados permanecen versionados en el repositorio.
