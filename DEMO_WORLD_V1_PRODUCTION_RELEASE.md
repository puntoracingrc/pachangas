# Demo World V1 Production Release

## Identidad del release

- Fecha de cierre: 2026-08-21 04:07 CEST.
- Base fisica inicial del worktree: `851418d688e4078d9fb9166174b961dc5c22d4d9`.
- `main` reconciliado antes de implementar: `7e7cfdf110110d63b92dfee2d5529ffa284c92e5`.
- Merge de Demo World V1, PR #140: `b4c13e9a6c4d750b617c2c8dac63759d0b6c2e06`.
- Merge del cierre DW-033, PR #150: `087cc03668b33c3f42dc77ec06e2bc597a6f1904`.
- Deployment funcional: `dpl_DpUWtVzWEZXcocT1Qd1BfXUv2SfP`.
- URL productiva: `https://pachangasiq.com/demo`.
- Supabase: no modificado; cero migraciones, RPC, Auth o filas Demo.

## Resultado

Demo World V1 es un read model ficticio, determinista y publico servido por la aplicacion real. `/demo` carga un manifest y cuatro dominios JSON same-origin; las interacciones viven solo en `sessionStorage`, nunca se presentan como confirmaciones del servidor y no existe cola offline. La raiz sin equipo ofrece un CTA compacto a `/demo`; la demo heredada queda como `INTERNAL_FIXTURE` sin consumidor publico.

La release conserva Rating V2, Season Score V3, ranking productivo, Attendance, Conduct, Billing, Platform Control Center y los sistemas de rewards sin modificar sus autoridades. Los premios provinciales y Premium Ball siguen desactivados.

## Gates

| Gate | Resultado |
| --- | --- |
| `npm run test:demo-world` | PASS, 22/22 |
| `npm test` | PASS, build + 20/20 base + 274/274 funcionales |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, Next.js 16.2.6, 33 paginas estaticas |
| Lint focalizado Demo/regresiones | PASS |
| Lint global | Deuda previa documentada; no ampliada por el bloque nuevo |
| `git diff --check` | PASS |
| Visual Audit Demo | PASS, 114/114 |
| Cero escrituras remotas | PASS, solo `GET` y acciones efimeras |
| Preview PR #140 | PASS |
| Preview PR #150 | PASS, SHA exacto `02cb59904c017224bf540e0821b8ba85be980207` |
| Produccion anonima | PASS |
| Produccion autenticada | PASS, equipo real y mundo Demo aislados |
| Runtime Vercel | 0 errores y 0 logs `error`/`fatal` en el deployment |

## QA de produccion

- `/` anonima: entrada `no-team`, CTA visible, demo heredada ausente y cero imagenes rotas.
- Portrait `390x844`: ancho de documento 390, CTA de 44 px y ningun control visible menor de 40 px.
- Landscape `844x390`: ancho 844, alto de contenido 390, CTA y login de 40 px, sin overflow.
- CTA: navega realmente a `/demo`.
- Demo: Inicio, Partido, Mercado, Equipo y Perfil cargan con cero imagenes rotas y sin overflow horizontal en portrait.
- Cuenta autenticada: `Futbol y Morros` permanece en la aplicacion real; la raiz no cae en la entrada `no-team`.
- `/demo` autenticada: muestra Cobalto Raval y no contiene el nombre del equipo real.
- PWA: manifest `display=fullscreen`, fallback `standalone`; Service Worker `2.0.0+sw.087cc03668b3`, `no-store`, precachea `/demo` y su manifest, y solo intercepta `GET`.

## Mappings de Team Rewards preservados

| Hito | Achievement | Reward | Estado |
| --- | --- | --- | --- |
| Primera victoria | `team.external.wins.001` | `team.shield.border.copper` | Sin cambios |
| 10 Retos | `team.external.matches.010` | `team.shield.ornament.banner` | Sin cambios |
| 25 partidos | `team.matches.025` | `team.shield.ornament.laurels` | Sin cambios |
| 50 partidos | `team.matches.050` | `team.shield.border.silver` | Sin cambios |
| Primera porteria a cero | `team.external.clean_sheets.001` | `team.shield.effect.edge_glow` | Sin cambios |

Premium Ball continua OFF. Ninguna de las 29 propuestas del Premium Art Pack se convirtio en reward, propiedad o catalogo activo.

## Entrega contractual

| # | Entregable | Evidencia final |
| ---: | --- | --- |
| 1 | `main` inicial | Base fisica `851418d...`; main reconciliado `7e7cfdf...` |
| 2 | Rama | `codex/demo-world-v1`; follow-up `codex/demo-world-v1-release-fix` |
| 3 | PR | #140 y #150, ambos fusionados |
| 4 | HEAD final funcional | `087cc03668b33c3f42dc77ec06e2bc597a6f1904` |
| 5 | Arquitectura | Snapshot estatico versionado + adapter read-only |
| 6 | Data adapter | `app/demo/_components/demo-world-app.tsx` y loader V1 |
| 7 | Generador | `scripts/generate-demo-world-v1.ts` determinista |
| 8 | Seed | `pachangas-iq-demo-world-v1-2026-27` |
| 9 | Snapshot hash | `34158b4f56a3011c9010b0952f74043435e9f896f0b7ea5fd90e0dfacdfac3ae` |
| 10 | Snapshot size | 603.252 bytes sin manifest; 49.244 Brotli con manifest/chunks |
| 11 | Equipos | 30 |
| 12 | Jugadores | 331 |
| 13 | Partidos | 128 |
| 14 | Retos | 48 |
| 15 | Mercado | 48 perfiles, 1 agente libre, 24 equipos y 8 partidos publicos |
| 16 | Temporada Demo | 2026/27; `demoNow=2027-03-18T18:00:00Z` |
| 17 | Provincias/territorios | Territorios Demo Barcelona, Valles, Girona y Maresme; no se presentan como rankings oficiales |
| 18 | Perspectiva jugador | Implementada, sin autoridad real |
| 19 | Perspectiva admin | Implementada, simulada y aislada |
| 20 | Perspectiva sin equipo | Implementada, sin invitaciones admin |
| 21 | Selector persona | Tres perspectivas; tambien disponible en modo juego |
| 22 | Reset | Borra la unica clave de `sessionStorage` Demo |
| 23 | Acciones simuladas | Asistencia, avisos, Admin, cajas, NEW y equipamiento local |
| 24 | Zero remote writes | PASS; no POST/PUT/PATCH/DELETE/RPC |
| 25 | Zero PII | PASS por validacion recursiva |
| 26 | Zero Auth ficticio | PASS; no usuarios ni sesiones Auth Demo |
| 27 | Identidades visuales | 30 equipos con personalidad y configuracion propia |
| 28 | Escudos unicos | 30/30 |
| 29 | Cartas | 331 read models; porteros con GRL `null` explicito |
| 30 | Loadouts unicos | 187/331 |
| 31 | Distribucion cosmetica | 77 base, 62 ligera, 78 media, 114 alta; 0 Premium/Oro |
| 32 | Team Reward consistency | Cinco mappings exactos, sin cambios |
| 33 | Achievements | 75 |
| 34 | Boxes | 28 |
| 35 | Demo box opening | 3D bajo demanda, recompensa determinista |
| 36 | NEW | Inventario y marca NEW efimeros y reiniciables |
| 37 | Notifications | 12 avisos ficticios, sin centro productivo |
| 38 | Attendance demo | 168: 126 played, 14 excused, 14 late, 14 no-show |
| 39 | Conduct demo | Sin reports, cases ni sanciones; solo historial descriptivo |
| 40 | Ranking provincial demo | Season Score V3 congelado, formula 55/30/15 |
| 41 | Elegibles | Top 10 sobre 32 entradas y ficha #27 |
| 42 | No elegibles | Caso explicito disponible |
| 43 | Pending | Provisional y pendiente de verificacion disponibles |
| 44 | Premios Demo | 0; `awardsEnabled=false` |
| 45 | Stories | 12 historias canonicas |
| 46 | Contact sheet escudos | Disponible en `/demo/contact-sheet?kind=teams` |
| 47 | Contact sheet cartas | Disponible en `/demo/contact-sheet?kind=players` |
| 48 | Payload | Manifest + `core`, `players`, `matches`, `activity` |
| 49 | Lazy loading | Inicio carga core; dominios profundos se difieren |
| 50 | Performance | <700 KB canonico; chunks hasheados y caja 3D diferida |
| 51 | SEO/noindex | `/demo` y contact sheet `noindex,nofollow` |
| 52 | Desktop | PASS 1440x900 y 1920x1080 |
| 53 | Portrait | PASS 390x844 y 360x800 |
| 54 | Landscape | PASS 844x390, modo juego |
| 55 | PWA | PASS fullscreen/standalone, SW versionado |
| 56 | Light/Dark | PASS sistema y tema explicito |
| 57 | Reduced motion | PASS, transiciones y scroll suave desactivables |
| 58 | Visual Audit | PASS 114/114 |
| 59 | Bugs descubiertos | DW-001 a DW-033 conservados permanentemente |
| 60 | Bugs corregidos | Todos salvo DW-017, baseline global ajeno y documentado |
| 61 | Test 2 minutos | PASS: entrada, equipo, partido, Mercado, ranking, avisos |
| 62 | Test 10 minutos | PASS: perspectivas, historicos, cartas, cajas, NEW y reset |
| 63 | Rating invariant | Rating V2 reutilizado; formula no modificada |
| 64 | Ranking production invariant | 0 filas/recalculos productivos Demo |
| 65 | Rewards invariant | 0 grants productivos; mappings preservados |
| 66 | Conduct invariant | 0 reports, cases o restrictions productivos |
| 67 | Billing invariant | 0 checkout, subscriptions o invoices |
| 68 | Control Center invariant | 0 roles o eventos administrativos concedidos |
| 69 | Tests | PASS, 22/22 Demo y 274/274 funcionales |
| 70 | Typecheck | PASS |
| 71 | Build | PASS, 33 paginas estaticas |
| 72 | Lint focalizado | PASS; deuda global previa separada |
| 73 | Preview | #140 y #150 verificadas sobre SHA exacto |
| 74 | Demo antigua reemplazada | PASS; raiz compacta y legacy `INTERNAL_FIXTURE` |
| 75 | Merge | PR #140 y #150 fusionados |
| 76 | `main` final funcional | `087cc03668b33c3f42dc77ec06e2bc597a6f1904` |
| 77 | Deployment Vercel | `dpl_DpUWtVzWEZXcocT1Qd1BfXUv2SfP`, READY |
| 78 | QA `pachangasiq.com` | PASS anonima, autenticada, desktop y movil |
| 79 | Report | `DEMO_WORLD_V1_REPORT.md` actualizado |
| 80 | Data contract | `DEMO_WORLD_V1_DATA_CONTRACT.md` |
| 81 | Stories | `DEMO_WORLD_V1_STORIES.md` |
| 82 | Production release | Este documento |
| 83 | Produccion modificada | Frontend, assets/snapshot Demo y PWA; sin backend ni DB |
| 84 | Worktree final | Se retira tras fusionar este informe y validar su deployment |

## Incidencias y limites

- DW-033 se descubrio en el smoke anonimo posterior al primer merge. Se registro en un commit previo a la solucion, se corrigio en #150 y su regresion esta verificada.
- DW-017 sigue abierto como deuda visual global preexistente fuera del alcance Demo: 222 targets menores de 40 px en 38 combinaciones, principalmente tabs desktop de Mercado y footer legal.
- No se detectaron errores runtime, imagenes rotas, overflow horizontal ni contaminacion entre cuenta real y Demo en el deployment funcional.

## Estado de sistemas preservados

Rating V2, Season Score V3, ranking provincial productivo, Core Social, Attendance, Conduct/Reports, Billing, Platform Control Center, Player Cosmetics, Team Cosmetics y Team Cosmetic Rewards permanecen intactos. No se aplicaron migraciones ni consultas de escritura a Supabase.
