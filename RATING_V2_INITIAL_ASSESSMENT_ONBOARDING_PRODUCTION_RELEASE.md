# Rating V2 Initial Assessment Onboarding Production Release

Fecha: 2026-09-04 CEST

## Clasificacion y alcance

- Clasificacion final: `REPRODUCED_AUTHORITY_DEFECT`.
- Issue: [#165](https://github.com/puntoracingrc/pachangas/issues/165).
- Base real: `7670a69e2f3b5c96b0d47aef76e6c8388b71983a`.
- PR funcional: [#269](https://github.com/puntoracingrc/pachangas/pull/269).
- Commit de implementacion: `5ab66fe4628f435f098ec5ed520c00836f9799df`.
- HEAD funcional: `56973b1702bfb7d8669876c98093ade83ffc4056`.
- Merge funcional y `main` productivo: `7b1b927446e05d980497c36141902bc49f23d113`.
- Plan: [RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_PLAN.md](./RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_PLAN.md).
- Informe funcional: [RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_REPORT.md](./RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_REPORT.md).

El cambio se limita al bloqueo circular de la primera evaluacion. No modifica
formulas, facetas, escala 0-100, ventanas de valoracion, UI, Social Core,
Official UI V3I ni Wave 9C.

## Defecto reproducido

Dos actores sinteticos nuevos, autenticados y sin perfil ni evaluacion,
invocaron la misma autoridad que usa la aplicacion. Ambos fallaron con:

- SQLSTATE: `P0001`.
- Mensaje: `Complete the initial player assessment before creating a new profile`.
- Perfil parcial: 0.
- Evaluacion huerfana: 0.
- Snapshot, evento, receipt y notificacion: 0.

El cliente ya realizaba una sola llamada. El orden interno de PostgreSQL
intentaba ejecutar `upsert_pachanga_own_player_profile` antes de insertar la
evaluacion inicial exigida por ese mismo guard.

## Autoridad corregida

El call graph productivo queda:

1. `app/page.tsx` envia una unica intencion a `POST /api/ratings/assessment`.
2. El endpoint deriva el actor de la sesion, recalcula desde respuestas
   originales y usa un cliente server-only.
3. `persist_pachanga_player_assessment_authoritative_v2` valida la revision y
   entra en `persist_pachanga_player_assessment_authoritative_v2_impl`.
4. La implementacion bloquea el grupo, verifica replay y fingerprint, y llama
   a `persist_pachanga_player_assessment_v2`.
5. Para `initial`, la evaluacion valida se inserta con enlace de perfil nulo;
   dentro de la misma transaccion se crea el perfil protegido, se bloquea y se
   enlaza la evaluacion.
6. Las autoridades existentes recalculan Rating V2, sincronizan el read model,
   emiten un unico evento y guardan el receipt.
7. Todo confirma o todo revierte.

La migracion redefine exclusivamente:

- `public.persist_pachanga_player_assessment_v2`.
- `public.persist_pachanga_player_assessment_authoritative_v2_impl`.

La RPC publica `persist_pachanga_player_assessment_authoritative_v2`, el guard
`upsert_pachanga_own_player_profile`, triggers, tablas, indices y politicas RLS
no cambian.

## Migracion y ledger

- Migracion forward-only:
  `20260903211715_rating_v2_atomic_initial_assessment_onboarding.sql`.
- SHA-256 del archivo:
  `22f2838e3059baa7bb9813dd26b2349269c487c630884aa2dbfea89b3b684234`.
- Ledger anterior: 235; ultima
  `20260902102800_social_inbox_receipt_notification_index_v1`.
- Ledger posterior: 236; ultima
  `20260903211715_rating_v2_atomic_initial_assessment_onboarding`.
- Registro remoto final: 6 statements; MD5 agregado
  `5f4e679b8215404cdc2f34655bd3812d`.

La API de migraciones registro inicialmente el SQL correcto con la version
generada `20260903225145`. La discrepancia se detecto antes de continuar. Se
reconcilio solo el historial mediante `supabase migration repair`: primero se
marco `20260903211715` como aplicada y despues `20260903225145` como revertida.
No se reaplico SQL, no se reescribio una migracion historica y el readback final
confirma una unica version correcta y cero filas para la version generada.

El intento de `pg_dump` completo quedo esperando al transporte Docker local y
se cancelo sin alterar el remoto. El rollback de esta migracion de solo
funciones queda reconstruible con las definiciones anteriores versionadas en
`20260803053451_rating_system_v2_assessments.sql` y
`20260803053937_rating_v2_http_conflicts.sql`, junto con los hashes productivos
previos registrados. Se priorizaria roll-forward con esas definiciones, sin
reabrir DML directo.

## Readback PostgreSQL

- Proyecto: `qonbngfrnrqgmxbdfbea`, `ACTIVE_HEALTHY`, PostgreSQL 17.6.
- Hash final de `persist_pachanga_player_assessment_v2`:
  `429056ea0ec389b04ae1e096843cf8f0`.
- Hash final de `persist_pachanga_player_assessment_authoritative_v2_impl`:
  `c96b377142ca123412eb47a154207c67`.
- Hash de la envoltura publica, sin cambios:
  `995e56ed3e15e6c04f7a4e3133875b7d`.
- Schema hash fresh/upgrade:
  `b15fb054abba913fad4e5598378b6d5a48d8f8fa6a06f4184b5d8e2546493c59`.

Las funciones redefinidas pertenecen a `postgres`, mantienen
`SECURITY DEFINER`, volatilidad `VOLATILE`, parallel unsafe y
`search_path=pg_catalog`; la implementacion autoritativa conserva
`lock_timeout=750ms`.

## Grants, revokes y RLS

- La envoltura publica solo es ejecutable por `service_role`.
- Los dos helpers redefinidos no son ejecutables por `PUBLIC`, `anon`,
  `authenticated` ni `service_role`.
- `pachanga_player_profiles` y `pachanga_player_assessments` mantienen RLS.
- Solo existen politicas `SELECT` propias para `authenticated`.
- No hay politicas `INSERT`, `UPDATE`, `DELETE` ni `ALL`.
- Los grants de tabla heredados no abren escritura porque RLS permanece
  fail-closed.

Un canary no destructivo ejecuto intentos DML como `authenticated` dentro de
una transaccion. Perfil y evaluacion fueron rechazados por privilegios/RLS y la
transaccion termino en `ROLLBACK`; el readback posterior devolvio 0 perfiles y
0 evaluaciones para el UUID sintetico. No se creo un usuario Auth y no hubo WAL
confirmado, Realtime externo ni notificaciones.

Los Advisors posteriores no atribuyen ningun hallazgo a las funciones
modificadas. Permanecen avisos preexistentes del proyecto; los dos avisos que
mencionan estas tablas corresponden a la configuracion global de anonymous
sign-ins y a sus politicas de lectura, que ademas exigen usuario Pachangas
registrado. Referencia: [Supabase Database Advisors](https://supabase.com/docs/guides/database/database-advisors).

## Pruebas y equivalencia

- Baseline: 862/862, Node 20/20 y TS/TSX 842/842.
- Final: 868/868, Node 20/20 y TS/TSX 848/848.
- Failed / skipped / todo / cancelled: 0 / 0 / 0 / 0.
- Typecheck: PASS.
- Build: PASS, 78/78 rutas.
- Lint global y focalizado: PASS; solo la nota Babel preexistente por el
  tamano de `app/page.tsx`.
- `git diff --check`: PASS.
- Secret scan de diff, migracion, tests, informes, bundle y temporales: PASS.
- Fresh bootstrap: PASS.
- Upgrade exacto: PASS.
- Equivalencia fresh/upgrade: PASS con el schema hash indicado.
- Suites Rating V2 historicas, DB/RLS, perfil social, Auth, Realtime, offline,
  PWA, Social RC y Official UI V3I: PASS.

Concurrencia PostgreSQL real cubrio llamadas simultaneas identicas, payload
incompatible con el mismo `operationId`, operaciones distintas del mismo
actor, fanout de seis, dos actores independientes y respuesta perdida. El
resultado fue un perfil, una evaluacion, un evento y un receipt por actor, sin
deadlocks ni duplicados.

La idempotencia usa el ledger existente `pachanga_operation_receipts`. El mismo
`operationId` y payload devuelve el resultado canonico; un payload diferente
produce `PT409` sin segunda escritura. Offline falla cerrado, no encola la
operacion y no muestra exito ficticio. Realtime invalida y el cliente relee el
snapshot canonico.

## Staging y Preview

La rama Supabase desechable `rating-v2-issue-165-20260903` uso PostgreSQL 17.6
y cinco identidades `.test` sinteticas. El E2E autenticado cubrio usuario nuevo,
usuario existente, dos sesiones, retry, doble submit, concurrencia, revision
obsoleta, payload invalido, direct DML, perfil, ficha, Realtime, offline y
reconexion. Resultado: PASS.

Antes de destruir staging habia 5 usuarios, 4 grupos, 3 perfiles, 3
evaluaciones, 3 eventos, 3 receipts y 0 notificaciones, todos sinteticos. La
rama fue eliminada y sus variables Preview branch-scoped fueron retiradas. El
readback productivo encuentra 0 residuos `rating165`.

- Preview E2E ejecutable: `dpl_8Lg3ikVpQsPFpzns5MTXNKLtLYZM`, SHA
  `29de4fd4028d7d90571c482c1b75c9712a854076`.
- URL Preview E2E:
  `https://pachangas-erv2koe4x-persianas-almar-web-s-projects.vercel.app`.
- Preview del HEAD final: `dpl_pZpKPGx9Lf8XL4vGahAxPdX2A1e8`, SHA
  `56973b1702bfb7d8669876c98093ade83ffc4056`, estado `READY`.
- URL Preview final:
  `https://pachangas-gtmdlmubr-persianas-almar-web-s-projects.vercel.app`.

La QA visual de Preview paso en 1440x900, 390x844, 360x800 y 844x390: 0
overflow, 0 controles cortados, 0 imagenes rotas, 0 overlays y 0 errores o
warnings de consola. Android fisico, iPhone fisico y PWA fisicamente instalada
permanecen `PENDING`, fuera del alcance autorizado.

## Produccion

- Deployment funcional: `dpl_3YRym39bhfPkBNSc4bh7tWMLtYrX`.
- URL inmutable:
  `https://pachangas-drlq5w98w-persianas-almar-web-s-projects.vercel.app`.
- Metadata SHA: `7b1b927446e05d980497c36141902bc49f23d113`.
- Estado y target: `READY` / `production`.
- Dominios asignados: `pachangasiq.com` y `www.pachangasiq.com`.
- Service Worker: `2.0.0+sw.7b1b927446e0`.

El smoke no destructivo obtuvo HTTP 200 para `/`, `/perfil` y `/sw.js`, titulos
correctos, contenido real, 0 overlays, 0 imagenes rotas y 0 secretos en HTML o
Service Worker. Los logs del deployment muestran 38 respuestas 200, 17
respuestas 304, 0 errores runtime, 0 4xx inesperados y 0 5xx en la ventana del
release.

No se ejecuto el onboarding canonico con escritura en produccion porque no
existe un actor Auth sintetico que pueda garantizar cero efectos externos. El
E2E completo se realizo en staging autenticado; produccion se valido mediante
readback estructural y el canary DML transaccional con rollback descrito.

## Seguridad, datos y residuos

- Usuarios, perfiles, evaluaciones, fichas, equipos y entidades reales creados:
  0.
- Notificaciones, push, emails, SMS y WhatsApp reales enviados: 0.
- Stripe y pagos: 0.
- Migraciones historicas modificadas: 0.
- `package-lock.json` modificado: no.
- Service Worker, manifest, UI, rewards, achievements, Conduct, competiciones y
  venue operations modificados: no.
- Residuos sinteticos en staging y produccion: 0.

El PR funcional modifica exactamente nueve rutas: dos documentos, una
migracion, cinco suites/runners y `package.json`. La unica adaptacion de una
suite historica permite limpiar tablas inmutables de Wave 8B; no altera ninguna
asercion de producto.

## Cierre y limites

El issue #165 se mantiene abierto durante la escritura de este documento para
respetar el gate mas estricto: se comentara y cerrara inmediatamente despues de
fusionar este informe. La evidencia funcional y productiva ya cumple el
criterio de correccion nueva verificada.

`SOCIAL-RC-001` a `SOCIAL-RC-012` y `OFFICIAL-UI-V3I-001` a
`OFFICIAL-UI-V3I-003` permanecen cerrados y congelados. Wave 9C no se ha
definido ni reanudado. El punto de parada es el cierre productivo y documental
del issue #165.
