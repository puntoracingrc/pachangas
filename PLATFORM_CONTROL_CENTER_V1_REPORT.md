# Platform Control Center V1

Estado: implementación, Supabase staging y Preview autenticada validados; PR borrador pendiente de revisión.

## Trazabilidad

- Inicio: 2026-08-11 17:00:15 CEST.
- Base exacta: `origin/main` en `851418d688e4078d9fb9166174b961dc5c22d4d9`.
- Rama: `codex/platform-control-center-v1`.
- PR borrador: [#141](https://github.com/puntoracingrc/pachangas/pull/141).
- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-platform-control-center-v1`.
- Migraciones V1: `20260811150309_platform_control_center_v1.sql` y reparación aditiva `20260811172700_platform_control_center_overview_restriction_fix.sql`.
- Preview autenticada: `https://pachangas-nqu44pvnj-persianas-almar-web-s-projects.vercel.app` (`dpl_GYuXW4FJvgRBu8zP9bpBanM6SmY5`).
- Supabase staging: branch project `iozcjirlfytryzrcmrnq`; producción no se usó para migraciones ni QA.
- Producción modificada: **NO**.
- Demo World V1: fuera de esta rama.
- Rating V2, fórmulas, facetas, assessments y evidencias: **sin cambios**.

## Arquitectura

```text
Navegador autenticado
  -> POST /api/platform-admin/session (JWT Supabase)
  -> cookie HttpOnly temporal
  -> página/API server-side
  -> capability check PostgreSQL
  -> RPC/read model canónico
  -> respuesta private/no-store

Mutación administrativa
  -> intención + operationId + expectedRevision + motivo
  -> RPC transaccional con lock
  -> estado canónico + serverSequence
  -> ledger privado
```

El navegador no recibe `service_role` ni tokens de Stripe, Vercel o Supabase Management. Los roles globales viven en `private.pachanga_platform_admin_roles`; ser owner/admin de un equipo no concede acceso al Control Center.

## Inventario reutilizado

| Dominio | Estado V1 | Decisión |
| --- | --- | --- |
| Conducta, attendance, warnings, restricciones, apelaciones y triage | IMPLEMENTADO | Se reutilizan las RPC canónicas y `/admin/conduct`; no existe Moderation V2 paralela. |
| Synthetic World | IMPLEMENTADO COMO LAB | Solo `platform_owner`, solo si el entorno lo habilita; mantiene 404 en producción deshabilitada. |
| Usuarios Auth y perfiles universales | IMPLEMENTADO | Listado y detalle transversales, paginados y consultados en servidor. |
| Equipos, miembros, partidos internos y Retos | IMPLEMENTADO | Listas globales y detalles con navegación cruzada. |
| Rating V2 | IMPLEMENTADO, SOLO LECTURA | Se muestran carta, facetas, fiabilidad y snapshots existentes; no se recalcula. |
| Season Score/TOPS productivo | AUSENTE | Se marca `LAB`/`OFF`; no se presentan datos sintéticos como oficiales. |
| Achievements, cajas, player/team cosmetics y Team Rewards | IMPLEMENTADO, SOLO LECTURA | Se muestra trazabilidad reciente; no hay concesión manual. |
| Notificaciones | IMPLEMENTADO | Métricas y anuncios a usuario, equipo o admins de equipo con borrador, preview e idempotencia. Envío global deshabilitado. |
| Billing local | IMPLEMENTADO | Reutiliza los campos de `pachanga_groups`; no crea una segunda suscripción. |
| Stripe live | PARCIAL | Observabilidad server-side por muestra y reconciliación; sin refunds, cancelaciones ni cambios de precio. |
| Supabase/Vercel health | PARCIAL | Solo métricas verificables. Uso sin límite conocido se muestra sin porcentaje. |
| Errores de cliente | IMPLEMENTADO V1 | Sink agregado, sin PII, limitado y con retención de 30 días. |
| Dispositivos aproximados por error | AUSENTE | No se crea identificador persistente para evitar tracking innecesario. |

## Superficies

- `/admin`: resumen por Hoy, 7 días, 30 días o histórico disponible.
- `/admin/users` y `/admin/users/:id`: Auth, perfil, Rating, equipos, partidos, rewards, avisos, estado y rol global.
- `/admin/teams` y `/admin/teams/:id`: owner/admins/miembros, historial visible, partidos, Retos, Mercado, rewards y billing.
- `/admin/matches` y detalle: participantes, goleadores, snapshots de Rating, hechos de progresión, achievements, rewards y avisos.
- `/admin/challenges` y detalle: timeline, propuestas, resultado, attestations, evidencias y progresión.
- `/admin/conduct`: sistema canónico existente.
- `/admin/rankings`, `/admin/rewards`, `/admin/notifications`, `/admin/billing`, `/admin/system`, `/admin/flags`, `/admin/audit`.
- 20 rutas `/api/platform-admin/...`, todas dinámicas, autorizadas en servidor y `no-store`.

## Autoridad y seguridad

- 6 roles globales: `platform_owner`, `platform_admin`, `moderator`, `support`, `finance`, `ops`.
- 7 tablas privadas, 1 secuencia, 5 índices y 29 funciones en la migración base; la segunda migración reemplaza aditivamente el read model de Home para usar `effective_until`, el campo canónico de Conduct V1.
- El diff validado contiene 70 rutas intencionales; no incluye `.temp`, dumps, caches ni artefactos de build.
- Las mutaciones permitidas requieren motivo, confirmación, `operationId` y revisión esperada.
- El ledger conserva actor, rol, acción, objetivo, motivo, before/after, respuesta, operación, secuencia y fecha.
- No hay borrado genérico, consola SQL, edición arbitraria de JSON ni acciones financieras/infrastrucura.
- PII y Stripe IDs se redactan según capability incluso cuando el servidor usa `service_role` para leer.
- Los mensajes SQL o de conectores desconocidos no se reflejan crudos al navegador.
- El ban/suspensión no lo decide automáticamente Conducta. La acción global es explícita y reversible.

## Métricas de Home

| Métrica | Definición V1 |
| --- | --- |
| Usuarios | Total de `auth.users`; altas según `created_at` y periodo. |
| Equipos | Total de grupos; activo significa que tiene al menos una membresía actual. |
| Jugadores | Perfiles universales vinculados a un usuario. |
| Partidos | Total del read model; actividad del periodo significa `updated_at`, no creación. El esquema no conserva una fecha canónica de creación para todos los partidos. |
| Retos | Total; creados en periodo por `pachanga_team_challenges.created_at`; aceptados es el estado actual. |
| Mercado | Equipos challengeables habilitados y perfiles con `market_enabled`. |
| Temporada | No hay temporada global canónica; la opción muestra todo el histórico disponible y lo declara. |

No se usa el término DAU. No se inventan históricos, límites ni porcentajes.

## Validación local

| Gate | Resultado actual |
| --- | --- |
| Test focalizado | 14/14 tras corregir el contrato de Home, búsqueda Auth y anonimizar identificadores dinámicos en rutas de telemetría. |
| SQL/RLS/adversarial | PASS en transacción con rollback. |
| Escala | 10.000 usuarios, 1.000 equipos, 0 locks en espera; 57,09 ms primera página, 39,39 ms última y 10,70 ms equipos filtrados. Umbral: 10 s. |
| Concurrencia | PASS final en una base PostgreSQL aislada: replay convergente, una sola entrega y rechazo explícito de revisiones obsoletas. Base y dump temporales eliminados. |
| Typecheck | PASS. |
| Build | PASS; 18 páginas admin y 20 APIs administrativas compiladas. |
| Lint focalizado | PASS. |
| `git diff --check` | PASS. |
| Suite global | PASS: build + 261 tests (20 Node y 241 TSX), incluidos Rating V2, social, conducta, rewards y cosmetics. |
| Lint global | 23 errores y 20 avisos preexistentes en `app/page.tsx`, `app/mercado/page.tsx`, `app/legal-data.tsx` y `app/theme-toggle.tsx`; cero hallazgos en el alcance focalizado. |
| Migraciones staging | PASS: las versiones `20260811150309` y `20260811172700` aparecen en el historial remoto. |
| RBAC staging | PASS: 52 comprobaciones HTTP para visitor, normal, team admin y seis roles de plataforma; permitidos `200`, denegados `401/403` seguros. |
| Mutaciones staging | PASS: suspender/reactivar con Auth, cambiar/restaurar flag y borrador/preview/envío; reintentos sin duplicados y ledger 1:1. |
| Privacidad staging | PASS: PII por capability, IDs Stripe redacted, payload de grupo ausente, búsqueda segura y cero grants cliente sobre `private`. |
| Responsive | PASS en las 17 superficies principales a 1440x900, 1920x1080, 390x844 y 844x390; cero overflow global y cero imágenes rotas. |
| PWA standalone | PASS real en Chromium app mode 390x816: manifest, Service Worker activo/controlador, sesión owner, `/admin` y cero errores runtime. |
| Preview/QA autenticada | PASS en el deployment indicado; búsqueda global, detalles cruzados, Synthetic World cerrado con 404 y consola sin errores. |

## Límites conocidos

- El read model interno no tiene `created_at`; Home informa partidos totales y actualizados, no inventa “creados”.
- La suspensión revoca el Control Center inmediatamente y sincroniza `ban_duration` en Supabase Auth. Un access token ya emitido puede seguir siendo válido hasta expirar; el producto no promete revocación instantánea de todos los JWT.
- El ban V1 usa una duración de Auth muy larga y un estado privado reversible, no borra al usuario.
- Stripe consulta hasta 100 suscripciones, 50 PaymentIntents, 50 invoices, 25 refunds y 25 disputes. `hasMore` se muestra y una entidad fuera de muestra queda `UNKNOWN`.
- El Preview no dispone de `STRIPE_ADMIN_RESTRICTED_KEY` de test. Se verificó el fallback seguro `UNKNOWN` y que Billing sigue operativo, pero no se ejecutó el E2E externo de Stripe test mode.
- MRR/ARR son estimaciones de la muestra de suscripciones activas/trialing; no equivalen a efectivo cobrado.
- “Cobrado hoy/mes”, churn fiable, límites de plan Supabase/Vercel y crecimiento histórico de DB están AUSENTES.
- Los listados principales tienen filtros y paginación server-side. Algunos streams diagnósticos V1 muestran solo las filas recientes y no son exportaciones exhaustivas.

## Cierre de fase

- Owner, roles, equipo, partido y anuncios usados en QA son fixtures sintéticos de staging.
- Producción, sus datos, sus roles y sus migraciones permanecen intactos.
- La reparación descubierta en Preview es una migración nueva; no se reescribió la migración ya ejecutada.
- El PR permanece en borrador, sin merge ni despliegue de producción.
