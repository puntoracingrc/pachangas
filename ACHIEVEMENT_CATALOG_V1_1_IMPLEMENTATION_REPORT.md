# Informe de implementación: logros colectivos V1.1

## Referencia

- SHA inicial de `main`: `d820cccc8ff70586bfbcb95d1cc2ad279bf2a873`.
- Rama: `codex/achievement-catalog-v1-1`.
- Catálogo previo: `achievement_catalog_v2`, 101 escalones activos.
- Migración forward-only: `20260808205638_achievement_catalog_v3.sql`.
- La migración V2 desplegada no se modifica.

## Implementación

- 45 definiciones individuales V2 quedan activas e intactas.
- 56 definiciones colectivas V2 quedan inactivas y auditables.
- 60 definiciones colectivas V3 quedan activas.
- `team.matches` agrega Pachangas internas y Retos.
- Las estadísticas `internal` y `external` permanecen separadas.
- Las rachas y rivales distintos usan solo Retos.
- Dominio absoluto es Reto-only, aditivo y `rare`.
- `reward_components` modela una ocurrencia con N cajas.
- La unicidad de caja es grant, usuario y `component_index`.
- El sellado, apertura, snapshot, corrección y UI trabajan por `box_id`.
- La migración solo backfillea estadísticas globales; no concede grants ni cajas históricas.

## Autoridad

PostgreSQL resuelve componentes, rareza efectiva, destinatarios, contenido sellado e idempotencia. El navegador solo consume el snapshot canónico y abre una caja mediante la RPC existente con `operationId` y revisión esperada.

No existe cálculo definitivo local, cola offline deportiva ni escritura directa de rating, facetas o assessments.

## Pruebas implementadas

- Casos exactos de goles 1–20 y representabilidad 2–250.
- Una ocurrencia de logro con N componentes y N cajas.
- Reprocesado con cero cajas nuevas.
- Concurrencia con dos evaluadores y convergencia canónica.
- Dominio absoluto: 4-0, 5-0 y 8-0 positivos; 3-0, 5-1, 4-1 y 0-0 negativos.
- Coexistencia de cinco logros en un Reto 4-0.
- 0-0 concede portería a cero sin victoria, goleada ni dominio.
- Trayectoria global 17 internos + 7 Retos + 1 partido.
- Rachas competitivas aisladas de partidos internos.
- Rivales y rivales vencidos distintos.
- Corrección revoca todos los componentes sin borrar evidencia.
- RLS oculta cajas a usuarios ajenos.
- Rating V2 permanece byte a byte sin cambios en sus campos canónicos.

## Validación local

- Esquema consolidado más todas las migraciones de agosto: aplicado.
- SQL funcional V3: aprobado.
- RLS y correcciones: aprobado.
- Concurrencia e idempotencia: aprobado.
- Typecheck: aprobado.
- Tests focalizados V1.1: aprobados.
- Simulación de 54 escenarios: aprobada.
- Build y batería completa: 111 tests aprobados.
- Lint focalizado de las rutas modificadas: aprobado.
- Lint global: 23 errores y 20 avisos preexistentes en rutas ajenas, principalmente `app/page.tsx`, `app/legal-data.tsx`, `app/mercado/page.tsx` y `app/theme-toggle.tsx`.
- `git diff --check`: aprobado.
- Diff intencional: 12 rutas, todas documentadas y pertenecientes a V1.1.
- RLS: activo en definiciones, grants y destinatarios; un destinatario solo puede leer sus propias cajas.
- Funciones privadas V3: sin `EXECUTE` para `anon` ni `authenticated`.
- Índices: unicidad efectiva por grant, usuario y componente, además de `box_id` único.
- Historial remoto: producción y staging coinciden y terminan en `20260808185802_achievement_catalog_v2`.
- `supabase migration list --linked`: bloqueado localmente por `LegacyProfileLoadError`; el historial se comprobó con la API oficial de Supabase.

## Preview y staging

- PR borrador: `#113`.
- Preview Vercel del commit `0dfbb56927299d5cb297d41df05f5e6076570263`: `READY`.
- QA responsive: escritorio 1440x900, iPhone vertical 390x844, iPhone horizontal 844x390 e iPad horizontal 1180x820.
- Overflow horizontal global: ausente en los cuatro tamaños.
- Errores de consola en Preview: ninguno.
- Staging Supabase: `iozcjirlfytryzrcmrnq` (`pwa-bridge-staging`).
- Migración V3 aplicada y su historial alineado con el repositorio en `20260808205638`.
- Batería SQL completa en staging dentro de una transacción revertida: aprobada.
- Concurrencia de evaluación: un cliente concede cuatro ocurrencias legítimas y el segundo converge con cero; no existen grants ni cajas duplicados.
- Dos usuarios autenticados: cada actor solo lee sus cajas; un usuario ajeno no puede abrir la caja de otro.
- Dos dispositivos del mismo usuario: repetir el mismo `operationId` devuelve el mismo `boxId` y revisión confirmada.
- Realtime: la apertura produjo un `UPDATE` canónico de `pachanga_progression_user_state` con revisión monotónica.
- Advisors: sin avisos nuevos atribuibles a V1.1. Permanecen avisos previos del proyecto; las RPC de apertura autenticadas son superficie pública intencional y validan actor, caja, revisión e idempotencia.

## Producción

- PR `#113`: fusionado mediante squash.
- SHA de `main`: `a80f993b478d3703682b1295dcc7604bbf4e5e78`.
- Migración remota: `20260808205638_achievement_catalog_v3`, alineada con staging y repositorio.
- Vercel Production: `READY` en el deployment `dpl_B4HhjWGARe14jSQfB7yzx2vXFw2F`.
- Dominio canónico: `https://pachangasiq.com`.
- Smoke SQL: 45 definiciones individuales V2 activas, 60 colectivas V3 activas, Dominio absoluto único y cero definiciones colectivas V2 activas.
- Rating V2: sus cinco campos canónicos permanecen presentes y la migración no los modifica.
- Advisors posteriores: ningún aviso nuevo atribuible a V1.1.
- Smoke web: escritorio, móvil vertical y móvil horizontal sin overflow global, errores de consola ni errores de runtime.
- Datos de QA en staging: dos usuarios, dos grupos, perfiles, partido, grants y cajas sintéticas eliminados tras la prueba.

## Rutas del diff

1. `ACHIEVEMENT_CATALOG_V1_1.md`
2. `ACHIEVEMENT_CATALOG_V1_1_IMPLEMENTATION_REPORT.md`
3. `REWARD_ECONOMY_V1_1_SIMULATION.md`
4. `app/equipo/identidad/page.tsx`
5. `app/team-identity-contract.ts`
6. `package.json`
7. `supabase/migrations/20260808205638_achievement_catalog_v3.sql`
8. `tests/achievement-catalog-v3-concurrency.mjs`
9. `tests/achievement-catalog-v3-db.sql`
10. `tests/achievement-catalog-v3-model.ts`
11. `tests/achievement-catalog-v3.test.ts`
12. `tests/reward-economy-v1-1-simulation.test.ts`

## Riesgos restantes

- El volumen de duplicados cosméticos crece con cuatro partidos semanales y un catálogo pequeño.
- La compatibilidad del cambio de clave primaria de destinatarios debe verificarse en staging con cajas V2 históricas y cajas V3 múltiples.
- La QA autenticada debe confirmar Realtime y apertura secuencial en dos dispositivos antes de producción.
