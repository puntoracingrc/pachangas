# Rating V2 Initial Assessment Onboarding Plan

Fecha: 2026-09-03 23:13:31 CEST

## 1. Checkpoint

- Repositorio: `puntoracingrc/pachangas`.
- Rama de trabajo: `codex/rating-v2-atomic-first-assessment-onboarding`.
- Worktree aislado: `/Users/macbookpro14/.codex/worktrees/pachangas-rating-v2-atomic-first-assessment`.
- SHA base real: `7670a69e2f3b5c96b0d47aef76e6c8388b71983a`.
- `origin/main` coincide con el checkpoint solicitado.
- Issue [#165](https://github.com/puntoracingrc/pachangas/issues/165): `OPEN`, sin comentarios ni PR de cierre.
- El checkout compartido tiene cambios preexistentes del laboratorio de ficha y no se modifica.

## 2. Fuentes revisadas

- Issue #165, cuerpo, timeline y referencia cruzada.
- `RATING_SYSTEM_V2_IMPLEMENTATION_REPORT.md` y
  `docs/rating-system-v2-deployment-runbook.md`. Los dos nombres históricos
  indicados en la orden no existen en el `main` actual; este es el informe real
  equivalente localizado.
- Las 24 migraciones Rating V2, su cierre V1 y las migraciones posteriores de
  perfil/onboarding. Los nombres históricos `20260805...` de la orden no
  existen en este historial reconciliado; no se editará ninguna migración
  existente.
- `INDEPENDENT_PLAYER_SOCIAL_PROFILE_V1_REPORT.md`,
  `ATOMIC_SOCIAL_TEAM_CREATION_V1_REPORT.md`,
  `OFFICIAL_UI_V3E_SOCIAL_ONBOARDING_REPORT.md`,
  `OFFICIAL_UI_V3F_TEAM_HOME_AND_ROSTER_REPORT.md` y
  `OFFICIAL_UI_V3F_PRODUCTION_RELEASE.md`.
- UI, endpoint, contrato TypeScript, funciones PostgreSQL, RLS, grants,
  revokes, tests Rating V2 y ledger remoto de Supabase.

## 3. Flujo actual y call graph

1. `app/page.tsx` abre el test y calcula solo una previsualización local.
2. `completeInitialPlayerAssessment` llama una sola vez a
   `persistSharedEngineAssessment`.
3. El navegador envía intención autenticada a `POST /api/ratings/assessment`
   mediante `clientWriteFetch`, con `operationId` y revisión esperada.
4. `app/api/ratings/assessment/route.ts` autentica, valida el sobre y recalcula
   el resultado desde las respuestas originales mediante
   `calculateSharedAssessmentResult`.
5. El servidor invoca, con cliente server-only,
   `persist_pachanga_player_assessment_authoritative_v2`.
6. La envoltura valida actor, membresía, replay y revisión; bloquea
   `pachanga_groups` y delega en
   `persist_pachanga_player_assessment_v2`.
7. La implementación interna intenta crear el perfil mediante
   `upsert_pachanga_own_player_profile` antes de insertar la evaluación.
8. El guard de esa función exige que la evaluación inicial ya exista y aborta
   toda la transacción.

El cliente ya utiliza una única llamada canónica. No se prevé cambiar UI,
endpoint, CSS, Service Worker ni fórmula.

## 4. Autoridad implicada

### RPC y funciones

- `persist_pachanga_player_assessment_authoritative_v2`: envoltura
  `SECURITY DEFINER`, `search_path=pg_catalog`, ejecutable solo por
  `service_role`.
- `persist_pachanga_player_assessment_v2`: implementación interna sin
  `EXECUTE` para `anon`, `authenticated` ni `service_role`.
- `upsert_pachanga_own_player_profile`: helper interno ejecutable solo por su
  propietario y `service_role`; contiene el guard de evaluación inicial.
- `pachanga_recalculate_player_rating_v2`,
  `sync_pachanga_player_profile_to_groups`,
  `record_pachanga_group_event`,
  `remember_pachanga_operation` y
  `pachanga_authoritative_response_v2`: autoridades existentes que se
  conservarán.

### Tablas

- `pachanga_groups` y `pachanga_group_members`.
- `pachanga_player_profiles`.
- `pachanga_player_assessments`.
- `pachanga_operation_receipts`.
- `pachanga_group_events`.

### Triggers, grants y RLS

- No existe trigger de assessment que resuelva el orden; el bloqueo está en el
  cuerpo de `upsert_pachanga_own_player_profile`.
- Perfil y assessment tienen RLS activa y únicamente políticas `SELECT`
  propias para `authenticated`; no existe política de escritura.
- Existen privilegios históricos de tabla para `authenticated`, pero RLS
  mantiene el DML directo fail-closed. Se probará con actores autenticados.
- Las funciones internas no son invocables por clientes. La envoltura de
  assessment permanece server-only y no se expondrá `service_role` al bundle.

## 5. Orden actual y punto del defecto

Orden actual para `initial`:

`validar -> lock -> comprobar replay -> upsert perfil -> insertar assessment -> actualizar perfil -> recalcular -> sincronizar -> evento -> receipt`.

El guard se ejecuta dentro del primer `upsert perfil`. En un actor nuevo no
encuentra perfil, jugador importado ni assessment inicial y lanza:

`Complete the initial player assessment before creating a new profile`
(`SQLSTATE P0001`).

## 6. Reproducción

Se construyó una base PostgreSQL 17.6 aislada desde el baseline y todas las
migraciones de `origin/main`. Dos actores sintéticos independientes, miembros
de sendos grupos, comenzaron sin perfil, assessment, rating, evento, receipt ni
notificación. Ambos invocaron la misma autoridad usada por la aplicación con
payload determinista válido y revisión 0.

Resultado en ambos intentos:

- éxito: no;
- SQLSTATE: `P0001`;
- mensaje: `Complete the initial player assessment before creating a new profile`;
- perfiles parciales: 0;
- assessments huérfanos: 0;
- eventos: 0;
- receipts: 0;
- notificaciones: 0.

El literal histórico `rating_initial_assessment_required` ya no es el mensaje
actual, pero el bloqueo semántico es el mismo.

## 7. Clasificación provisional

**REPRODUCED_AUTHORITY_DEFECT**

Producción se inspeccionó solo en lectura: PostgreSQL 17.6, ledger de 235
migraciones, guard presente y hashes de las funciones coincidentes con el
esquema actual. No se consultaron ni modificaron datos personales.

## 8. Corrección prevista

Una única migración forward-only redefinirá exclusivamente la autoridad de
assessment necesaria:

1. validar actor, membresía, tipo, motor y resultado completo antes de escribir;
2. bloquear por actor y tipo;
3. comprobar idempotencia y fingerprint de la intención;
4. para `initial`, insertar el assessment con vínculo de perfil temporalmente
   nulo;
5. llamar al upsert protegido: la evaluación ya existe dentro de la misma
   transacción y satisface el guard sin desactivarlo;
6. obtener y bloquear el perfil creado o existente;
7. enlazar el assessment al perfil;
8. persistir exactamente las mismas facetas, rating y resumen V2;
9. recalcular, sincronizar, emitir un evento y guardar el receipt canónico;
10. confirmar todo o revertir todo.

Para `advanced` se conservará el orden y comportamiento actual. La repetición
exacta devolverá el receipt existente; reutilizar el mismo `operationId` con
una intención distinta devolverá conflicto explícito sin escribir. Se
reutilizará `pachanga_operation_receipts`; no se creará un segundo ledger.

## 9. Postcondiciones

- Un perfil universal por usuario.
- Un assessment inicial por usuario.
- Assessment enlazado al perfil correcto.
- Una revisión, un evento y un receipt por operación confirmada.
- Ficha/read model canónico disponible al devolver la respuesta.
- Cero estados parciales ante validación, excepción o revisión obsoleta.
- Direct writes y helpers internos continúan fail-closed.
- Fórmulas, facetas, escala 0-100, ventanas y reglas de Rating V2 sin cambios.

## 10. Archivos previstos

- `RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_PLAN.md`.
- `RATING_V2_INITIAL_ASSESSMENT_ONBOARDING_REPORT.md`.
- Una migración nueva
  `*_rating_v2_atomic_initial_assessment_onboarding.sql`.
- Pruebas focalizadas de contrato, PostgreSQL y concurrencia bajo
  `tests/rating-v2-initial-onboarding-*`.
- `package.json` solo si es necesario registrar las nuevas suites en la
  batería normal.

No se prevén cambios en `app/`, CSS, assets, datasets, migraciones históricas
ni `package-lock.json`. Cualquier desviación se justificará antes de editar.

## 11. Pruebas previstas

- Dos usuarios completamente nuevos y un usuario con perfil existente.
- Actor anónimo, actor ajeno, DML directo y helper interno.
- Payload válido, inválido, faceta fuera de rango y campo obligatorio ausente.
- Error inducido y rollback integral.
- Replay exacto, payload incompatible, timeout/retry y doble submit.
- Dos llamadas y varias llamadas simultáneas del mismo actor; dos actores.
- Revisión obsoleta, ausencia de deadlocks y convergencia canónica.
- Assessment avanzado, Rating V2, carta/read model, perfil social y membresía.
- Offline fail-closed, reconexión, Realtime con refetch.
- Upgrade sobre esquema actual y fresh bootstrap; comparación y hash de
  esquema.
- Suites Rating V2 y relacionadas, `npm test`, typecheck, build, lint global y
  focalizado, `git diff --check` y secret scan.

## 12. Staging

Usar un entorno Supabase desechable sin datos reales y una Preview del HEAD
exacto. Crear dos actores Auth sintéticos eliminables y recorrer aplicación y
autoridad reales. Verificar Auth, RLS, revisión, replay, concurrencia,
Realtime/refetch, offline/reconexión y limpieza final a cero. Si la plataforma
requiere crear una rama de pago, se respetará su gate de coste antes de crearla.

## 13. Producción

Solo después de gates locales y staging verdes:

1. abrir PR funcional draft y verificar Preview;
2. dejarlo ready y fusionarlo;
3. aplicar únicamente la nueva migración al proyecto Pachangas;
4. comprobar ledger, checksum/nombre, definición, ACL, RLS, índices y Advisors;
5. esperar el deployment del SHA fusionado y verificar metadata;
6. hacer readback estructural y smoke no destructivo;
7. no ejecutar escritura productiva si no puede garantizarse `ROLLBACK` y
   cero efectos externos;
8. revisar logs y residuos;
9. cerrar #165 solo tras la verificación;
10. crear y fusionar el PR documental de exactamente un Markdown.

## 14. Riesgos y mitigaciones

- **Estado parcial:** una única transacción PostgreSQL y pruebas de fallo
  inducido.
- **Replay incompatible:** fingerprint server-side ligado al receipt existente.
- **Carrera:** advisory lock por actor, constraints únicos y lock de grupo.
- **Regresión advanced:** conservar rama avanzada y añadir regresión.
- **Privilege escalation:** mantener revokes actuales, RLS y cliente
  server-only.
- **Drift fresh/upgrade:** aplicar la migración a ambos recorridos y comparar
  definición/ACL/esquema.
- **Impacto productivo:** migración aditiva/redefinición compatible con el
  frontend actual y rollback por nueva migración compensatoria, nunca editando
  historial.

## 15. Rollback

Priorizar roll-forward. Ante incompatibilidad antes de producción, no fusionar
ni migrar. Tras aplicar la migración, una compensatoria versionada podrá
restaurar la definición anterior sin tocar datos, pero reintroduciría el
bloqueo; por eso se preferirá una corrección forward-only o mantenimiento
temporal. Ningún rollback abrirá DML directo ni convertirá caché/payload en
autoridad.

## 16. Áreas prohibidas

No se tocarán Official UI V3I, Social RC, Wave 9C, diseño, navegación, Mercado,
Retos, Demo World, cartas, logros, recompensas, escudos, Conduct, competiciones,
venues, pagos, Stripe, notificaciones externas, Service Worker, manifest,
Google Places ni otros issues.

## 17. Criterio de cierre

#165 solo se cerrará con perfil y assessment inicial atómicos verificados en
PostgreSQL, concurrencia, staging y producción; escrituras directas cerradas;
tests y deployment verdes; cero datos/residuos reales; informe funcional e
informe productivo fusionados.
