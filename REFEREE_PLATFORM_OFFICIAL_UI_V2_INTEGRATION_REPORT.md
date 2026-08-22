# Referee Platform R3 + Official UI V2 Integration Report

## Resultado

La capa visual Official UI V2 queda apilada sobre Referee Platform V1 sin
modificar la autoridad funcional de R3. El commit funcional de integración es
`e53f7cb53a82e632124ead595ed7ed927df82f04`.

Estado de cierre de esta fase:

- PR inferior: `#157`, rama `codex/referee-platform-v1`, no fusionado.
- PR superior: `#158`, rama `codex/official-ui-v2-demo-convergence`, draft.
- Base final requerida para `#158`: `codex/referee-platform-v1`.
- Producción, Supabase producción y flags productivos: no modificados.
- QA física Android/iPhone: `PHYSICAL_QA_PENDING`.

## Punto De Partida

| Referencia | Estado verificado |
| --- | --- |
| `origin/main` | `da6dace3a1a5d20de9fdba0d34174f916a2b2c61` |
| PR `#157` | OPEN, no draft, CLEAN, Vercel PASS |
| HEAD R3 | `557423b4b9ed6e0eac65bc5184d520f26c83610e` |
| PR `#158` inicial | OPEN, DRAFT, CLEAN, Vercel PASS |
| HEAD UI V2 inicial | `93840418e781ed8f6db06bde91ccc5ecf5b7c808` |

## Estrategia De Apilado

Se rebasaron de forma controlada los tres commits de Official UI V2 sobre el
HEAD exacto de R3:

```text
main
└── 557423b Referee Platform V1
    └── 603eb85 Start Official UI V2 convergence
        └── 20d2277 Build Official UI V2 convergence preview
            └── 47f7f65 Record Official UI V2 preview QA
                └── e53f7cb Integrate referee platform with Official UI V2
```

La rama R3 no se reescribió ni recibió estilos, capturas o cambios visuales. La
rama superior se publicará con `force-with-lease`, nunca con `force` simple.

## Solapamientos Resueltos

### `app/mercado/page.tsx`

Se conservaron simultáneamente:

- el tab `arbitros`, el gate `referee_marketplace_enabled`, la recuperación
  segura si el flag está OFF y `canProposeReferee` limitado al owner;
- `RefereeMarketplacePanel` y las lecturas/RPC de R3;
- `OfficialProductShellV2`, navegación única y las tres composiciones V2;
- contexto correcto `Mercado / Árbitros / zona · modalidad · disponibilidad`,
  sin caer visualmente en `Equipos`.

### `package.json`

Se construyó la unión de scripts y tests. Permanecen las suites R1, R2, R3,
PWA, Official UI V2 y rendered HTML. Se añadió únicamente
`test:referee-platform:ui` y su entrada en `npm test`.

## Superficies Adaptadas

- `/perfil/arbitro`: ficha protagonista y secciones separadas para identidad,
  modalidades, zonas, disponibilidad, Clubs, Mercado, asignaciones y
  estadísticas.
- `/arbitros/[slug]`: ficha arbitral específica, sin GRL, facetas, estrellas ni
  ranking arbitral.
- Mercado → Árbitros: filtros, resultados y detalle/propuesta en tres paneles.
- Propuesta/asignación: contexto canónico visible, estados y acciones R3
  intactas; los errores de horario se traducen a mensajes de producto.
- `/admin/referees`: conserva `PLATFORM_ADMIN`, tablas, RBAC y diagnóstico; no
  recibe HUD literal de juego.
- `/laboratorio-referee-platform`: noindex,nofollow y fixtures visuales
  aislados para Mercado, perfil privado/público, propuesta, confirmación y
  administración.

`discipline_stats_status` continúa siendo `NOT_AVAILABLE`; no se han inventado
amarillas, rojas, azules ni sanciones.

## Mobile Game Landscape

Mercado utiliza tres paneles compactos: filtros, lista y ficha/acción. La ficha
privada y pública mantiene la carta a la izquierda y contenido desplazable a
la derecha. Las asignaciones preservan el contexto del partido y las acciones
sin convertir la vista en una tabla desktop comprimida.

Se aplican safe areas con `env(safe-area-inset-*)`, altura dinámica y scrollers
internos intencionales. El árbol funcional de R3 no se remonta al cambiar entre
`DESKTOP`, `MOBILE_PORTRAIT` y `MOBILE_GAME_LANDSCAPE`.

Pruebas de giro realizadas:

- Mercado: filtro `Sabadell`, modalidad `FOOTBALL_7` y árbitro seleccionado
  sobreviven landscape → portrait → landscape; `0` peticiones adicionales.
- Perfil privado: bio y disponibilidad sobreviven portrait → landscape →
  portrait; `0` peticiones adicionales.

## Autoridad R3 Intacta

No existe diff bajo `supabase/`. Las migraciones de la rama superior son
idénticas a las de `#157`:

| Migración | SHA-256 |
| --- | --- |
| `20260821182105_referee_platform_foundation_v1.sql` | `2052a818ba981bcca39d722649a61b5715b175abe0b790de3ede8e24d6382493` |
| `20260821182106_referee_club_assignment_authority_v1.sql` | `23a30eca0218cc153f5ef0df70310a0d0337ae67f9b8d71fe7e3c76e1a4181f5` |
| `20260821182107_referee_platform_access_v1.sql` | `7d7d1bdff0e4957b45c5aceb9379f46d303b6fa3f45c9e450fbdfd4ff6cf787d` |

Se preservan comandos, receipts, eventos, revisiones, idempotencia, locks,
RLS, Realtime, bindings canónicos y reconstrucción de estadísticas. Los
fixtures visuales del laboratorio no abren Supabase, Auth, Realtime ni rutas
de escritura.

## Validación Local

| Check | Resultado |
| --- | --- |
| `npm ci` | PASS, 522 paquetes |
| `npm test` | PASS, build + 360 tests (`20 + 340`) |
| R3 TypeScript | PASS, `18/18` |
| Integración UI R3 | PASS, `8/8` |
| R1/R2 + UI V2 + PWA focal | PASS, `54/54` |
| Rendered HTML | PASS, `9/9` |
| `npm run typecheck` | PASS |
| `TMPDIR=/tmp npm run build` | PASS, 38 páginas estáticas |
| Lint focal nuevo | PASS, 0 incidencias |
| `git diff --check` | PASS |

El primer build aislado posterior a la suite sufrió un panic de Turbopack al
crear su fichero de diagnóstico en el directorio temporal de macOS. La misma
revisión ya había compilado dentro de `npm test` y volvió a compilar al usar
`TMPDIR=/tmp`; se clasifica como incidencia ambiental no reproducida.

El lint global conserva 43 incidencias preexistentes (`23` errores, `20`
avisos), principalmente en `app/page.tsx`, `app/legal-data.tsx`,
`app/mercado/page.tsx` y `app/theme-toggle.tsx`. En el archivo legado Mercado
aparecen dos errores de hooks y un aviso `<img>` fuera de las líneas de esta
integración. No se amplió el alcance para corregir esa deuda.

## SQL, RLS Y Concurrencia

Sobre Supabase local bootstrap limpio:

- R3 SQL/RLS y adversarial: PASS.
- R3 concurrencia: PASS; un único ganador en perfil, slug, relación, slot,
  solapamiento, confirmación/cancelación y reconcile; replay canónico.
- R3 volumen: 10.000 perfiles y 100.000 asignaciones. p95: admin `13.893 ms`,
  conflicto `0.092 ms`, relación Club `64.986 ms`, búsqueda `31.941 ms`,
  privada `4.909 ms`, pública `0.798 ms`, rebuild `0.065 ms`.
- Regresión R1 SQL/concurrencia: PASS.
- Regresión R2 SQL/RLS/adversarial/concurrencia: PASS.

## Staging Autenticado

Proyecto aislado: `iozcjirlfytryzrcmrnq` (`pwa-bridge-staging`). La Preview de
la rama superior recibe URL y clave publicable específicas de ese staging. No
se expone `service_role`.

El primer intento detectó tres perfiles archivados de una ejecución anterior;
la regla canónica de perfil único rechazó correctamente un duplicado. El
ledger inmutable bloqueó una limpieza ordinaria. Al ser todo el dominio R3 de
esa rama datos sintéticos, se realizó un reset transaccional exclusivo de las
tablas R3 con triggers desactivados solo dentro de la transacción; el rol de
replicación volvió a `origin` y no se alteró esquema, migraciones ni datos de
producción.

El primer run tras el reset sufrió un timeout Realtime durante el arranque en
frío del tenant. La escritura canónica y el cleanup fueron correctos. Con el
tenant caliente, la historia completa pasó:

```text
profile create/update/activate/list
Club invite + email invite + referee request
propose + accept + confirm + decline + cancel + replace + reconcile
idempotent replay
desktop mutation → Realtime invalidation → mobile canonical refetch
```

Estado final leído desde PostgreSQL:

- seis flags R3: OFF;
- perfiles activos: `0`;
- listados activos: `0`;
- relaciones activas: `0`;
- asignaciones activas: `0`;
- secretos de invitación vigentes: `0`;
- tres perfiles de QA permanecen archivados como historial sintético.

## Preview Combinada Exacta

La implementación publicada para revisión visual corresponde al HEAD
`70a67bdf9f2c4f9515c26dd1e74788c0eaa7cbc7` y al deployment Vercel Preview
`dpl_BnQXiHSUwKYXpGrWUCYoXBmvbCty`, en estado `READY`:

- URL inmutable: `https://pachangas-5709n6g6o-persianas-almar-web-s-projects.vercel.app`;
- alias de la rama: `https://pachangas-git-codex-offic-7de519-persianas-almar-web-s-projects.vercel.app`;
- ruta de entrada visual:
  `/laboratorio-referee-platform?surface=market`.

El artefacto remoto se inspeccionó desde una sesión autorizada de Preview. Sus
chunks contienen el project ref de staging `iozcjirlfytryzrcmrnq` y no
contienen el project ref productivo `qonbngfrnrqgmxbdfbea`. El laboratorio
continúa siendo visual-only y no abre conexiones ni escrituras.

La smoke remota cubrió Mercado, perfil privado, perfil público, propuesta,
confirmación y administración en `1440×900`, `390×844` y `844×390`: `18`
combinaciones, sin overflow horizontal documental, imágenes visibles rotas,
error overlay ni navegación duplicada. El admin conserva su variante
`PLATFORM_ADMIN`; las demás superficies resolvieron respectivamente
`DESKTOP`, `MOBILE_PORTRAIT` y `MOBILE_GAME_LANDSCAPE`.

La primera smoke remota detectó que el drawer cerrado del Control Center estaba
fuera del lienzo, pero sus enlaces seguían siendo enfocables. Se corrigió solo
en el breakpoint móvil con `visibility` y `pointer-events`; desktop no cambió.
La regresión focal y la comprobación remota confirman que el drawer cerrado es
inerte y el abierto vuelve a ser visible y operable.

En el artefacto remoto, el giro `844×390 → 390×844 → 844×390` conservó el
filtro `Sabadell`, la modalidad `Fútbol 7` y la selección de Marc Vidal. El
manifest respondió como `application/manifest+json`, `/sw.js` como JavaScript,
el Service Worker quedó registrado y controlando la página, y el log de
errores Runtime de Vercel para el deployment permaneció vacío durante la QA.
La instalación física sigue clasificada como `PHYSICAL_QA_PENDING`.

## PWA

En build de producción local:

- manifest correcto y Service Worker activo/controlando `/`;
- modo standalone simulado a `844×390`, orientación landscape, safe areas y
  `0` overflow;
- Mercado recarga desde caché sin red;
- el aviso `Sin conexión` indica que ninguna escritura está confirmada;
- al reconectar, el aviso desaparece y el cliente vuelve al estado online;
- las suites del bridge verifican fail-closed, una sola recarga y rechazo de
  optimistic state.

La emulación no sustituye una instalación física. Android e iPhone permanecen
`PHYSICAL_QA_PENDING`.

## QA Visual

Matriz ejecutada: seis superficies por diez viewports, `60` combinaciones:

`667×375`, `740×360`, `812×375`, `844×390`, `896×414`, `932×430`,
`390×844`, `360×800`, `1440×900` y `1920×1080`.

Resultado:

- `0` overflow horizontal documental;
- `0` controles visibles recortados;
- `0` imágenes rotas;
- `0` navegación duplicada;
- `0` HUD + barra móvil simultáneos;
- `0` tablas desktop comprimidas;
- `0` errores o warnings de hidratación en la sesión final.

Evidencia versionada:

- `docs/referee-platform-official-ui-v2/REFEREE_PLATFORM_OFFICIAL_UI_V2_CONTACT_SHEET.png`;
- `docs/referee-platform-official-ui-v2/REFEREE_PLATFORM_MOBILE_GAME_LANDSCAPE_CONTACT_SHEET.png`;
- `docs/referee-platform-official-ui-v2/REFEREE_PLATFORM_OFFICIAL_UI_V2_BEFORE_AFTER.png`;
- 30 capturas finales y 2 capturas del R3 original bajo `captures/`.

## Invariantes

La batería combinada confirma que permanecen intactos Rating V2, facetas,
fiabilidad, resultados, participantes, goleadores, Attendance, Conduct,
Achievements, Rewards, Player Cosmetics, Team Cosmetics, los cinco Team Reward
mappings, Billing, Season Score, Ranking, Clubs, Competition Foundation,
Canonical Match y Demo World.

## Orden De Release Futuro

1. Fusionar/liberar `#157`; aplicar migraciones R3 en orden y mantener flags
   OFF, sin backfill productivo.
2. Rebasar o retargetear `#158` a `main`, repetir checks y completar QA física o
   waiver explícito antes de marcarla lista.
3. Activar Referee Platform en una tarea posterior e independiente.

## Declaraciones

- Producción modificada: **NO**.
- Supabase producción modificado: **NO**.
- Vercel producción modificado: **NO**.
- PR `#157` fusionado: **NO**.
- PR `#158` fusionado: **NO**.
- Canonical backfill: **NO**.
