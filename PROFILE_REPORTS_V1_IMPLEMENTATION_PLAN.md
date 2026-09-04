# Profile Reports V1: Conditional Implementation Plan

## 1. Estado y límite de este plan

Base documental: `0dce1c2c6b7a891ba3ab0d3e65c0146a04e3b035`.

Estado heredado del gate:

```text
PROFILE REPORTS V1 GATE: BLOCKED BY PRODUCT OR LEGAL DECISION
```

Este documento no es una orden de implementación. Define un modelo candidato,
contratos, regresiones y una secuencia condicional para evitar que una futura
orden improvise autoridad o privacidad. Ningún batch tiene rama, PR, migración,
fecha ni autorización ejecutable. Todos los flags conceptuales permanecen
`OFF` y no se crean en este gate.

Bloqueos de salida:

- política de menores y safety aprobada;
- responsable de moderación y backup designados;
- política/cobertura de urgencias aprobada;
- base jurídica y avisos de privacidad validados;
- retención, purge y legal hold aprobados;
- clasificación DSA y canal de contenido ilícito decididos;
- términos/normas de comunidad y reason codes aprobados;
- target allowlist y apelaciones aprobados.

## 2. Principios no negociables

- PostgreSQL/Supabase es la única autoridad.
- Profile usa intake específico y un adaptador hacia una única autoridad
  generalizada de casos; no crea una segunda autoridad.
- Conduct conserva su contrato contextual y no acepta targets falsos.
- Actor, permisos, target, revisión, visibilidad, fingerprint, prioridad y
  acciones se resuelven en servidor.
- Commands con `operationId`, expected revision, lock, hora de servidor,
  secuencia monotónica, evento y receipt canónico.
- Direct DML cerrado; RLS/RBAC fail-closed; `service_role` nunca en cliente.
- Realtime invalida; el cliente relee estado canónico.
- Offline no confirma, no encola y no persiste texto sensible por defecto.
- Ningún reporte modifica Rating, GRL, facetas, fiabilidad, Season Score,
  ranking, rewards, resultados, disciplina deportiva, Team Operational o
  billing.
- Ninguna campaña o cantidad de reportes impone acción automática.

## 3. Arquitectura condicional

```text
Entry point contextual
  -> Profile report command
  -> target resolver + eligibility + revision resolver
  -> immutable content snapshot
  -> profile intake + receipt
  -> adapter to generalized moderation case authority
  -> human decision
  -> typed content action command
  -> reporter/subject read models
  -> minimal notification + invalidation + canonical refetch
```

`GENERALIZED_MODERATION_AUTHORITY` significa generalizar el sujeto del case
engine de forma backward-compatible. No significa cambiar Conduct para que
acepte contenido sin contexto ni crear una tabla de casos paralela.

## 4. Objetos propuestos

Los nombres son pseudocontratos y deben reconciliarse con convenciones reales
en la futura fase de definición SQL. No hay SQL en este gate.

| Objeto lógico | Schema/exposición | Owner y FK | Revisión/secuencia | Mutabilidad | RLS/grants | Retención | PII/protección | Read model/direct writes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Profile report intake | `private`; no Data API directo | Reporter server-side; FK lógica a subject, snapshot y case | `revision`, `server_sequence` | Estado transicional; identidad/categoría inmutables | Sin grants cliente; submit/read-own RPC | Según policy pendiente | Reporter ID y texto; protección reforzada | Reporter projection; cero direct writes |
| Moderation subject/target revision | `private` adapter/registry | Tipo + internal ID; FK al agregado canónico | Target revision/sequence resuelta | Inmutable por revisión | Solo resolver/case engine | Igual a lineage de caso | Puede enlazar persona/organización | Nunca read model público directo |
| Content snapshot | `private` | FK intake/target revision/asset | Inmutable; sequence de creación | Inmutable | Moderador asignado/security | Plazo específico pendiente | Solo campo público denunciado; cifrar texto si procede | Evidencia mínima; cero direct writes |
| Report event | `private` append-only | FK intake; actor opaco | `server_sequence` única | Inmutable | Sistema/security; projections | Audit policy pendiente | Sin payload libre salvo objeto privado separado | Alimenta projections; no WAL público |
| Case link | `private` | FK intake + existing/generalized case | Revisionado | Enlace activo/superseded | Case authority | Mientras caso/lineage | Sin reporter en read models | No direct writes |
| Moderation decision | `private` | FK case; moderator capability | Revision/sequence | Draft mutable; issued inmutable; correction supersedes | Moderator/security | Según recurso/defensa | Reason interno y externo separados | Reporter/subject decisions mínimos |
| Content action | `private` command ledger | FK decision + target adapter | Expected/confirmed target revision; sequence | Append-only attempts/results | Typed RPC; no generic update | Audit/action policy | Sin datos ajenos al campo | Target authority aplica; receipt canónico |
| Subject notice | `private` + own projection | FK decision/action + target owner | Revision/sequence | Append-only/superseded | Subject own read; moderator write RPC | Ventana de recurso | Sin reporter/notes/evidence | Subject read model; no direct writes |
| Reporter notice | `private` + own projection | FK intake/decision + reporter | Revision/sequence | Append-only/superseded | Reporter own read | Comunicación policy | Sin moderator/other reporters | Reporter status; no direct writes |
| Appeal | `private` | FK decision/action; appellant + reviewer | Revision/sequence | Estado transicional; submissions inmutables | Own submit/read + independent reviewer | Pendiente de canal | Puede contener texto privado | Appellant projection; cero direct writes |
| Command receipt/idempotency | `private` | Actor + command + operation key | Confirmed revision/sequence | Inmutable | Command authority | Ventana idempotencia aprobada | Sin token, cookie ni contenido | RPC response; no listado público |
| Invalidation | `public` mínima o tabla existente apta | Audience + aggregate ref | Revision/sequence | Append-only/compacted | Own/audience SELECT | Corta | Cero contenido/reporter | Realtime invalidation only |
| Retention strategy/job | `private` + scheduled authority | Policy version + affected object | Run revision/sequence | Runs append-only | Service role job; security audit | Es la autoridad de purge | Conteos, no contenido en logs | Health/control readback; no cliente |
| Observability health | `private` aggregate + control projection | Queue/capacity aggregate | Snapshot sequence/time | Recalculada por evento/job | Moderator/ops, sin evidence | Métricas agregadas | Sin UUID, texto ni identity | `UNKNOWN/OK/WARNING/CRITICAL` |

Necesidad de cifrado adicional, KMS/secret management y búsqueda sobre texto se
decide en el diseño de datos. Cifrar no sustituye minimización ni access control.

## 5. Contratos identificados

Estos IDs son especificaciones futuras, no tickets autorizados.

| ID | Problema | Contrato | Actor/target | Autoridad | Datos y privacidad |
| --- | --- | --- | --- | --- | --- |
| `PROFILE-REPORTS-V1-001` | Case engine actual está tipado a persona/Conduct | Generalizar subject type sin romper Conduct ni duplicar casos | Sistema, moderator; person/Team/Club/content | Generalized moderation case aggregate | Opaque subject ref; no reporter en case projections |
| `PROFILE-REPORTS-V1-002` | No existe intake Profile | Submit autenticado, idempotente, público allowlisted y sin relación deportiva | Auth reporter; public Profile target | Profile intake command | Actor auth server-side; texto corto privado |
| `PROFILE-REPORTS-V1-003` | Cliente podría falsificar target/revisión | Resolver server-side surface, owner, visibility, revision y field | Reporter; canonical target | Target resolver/adapters | Opaque public ref; errores no enumerables |
| `PROFILE-REPORTS-V1-004` | No hay evidencia de contenido denunciado | Snapshot inmutable del campo público/version/hash | System; target revision | Snapshot authority | Sin full profile, privados, Rating o precise location |
| `PROFILE-REPORTS-V1-005` | Duplicados/campañas inflan riesgo | Dedupe intake y cluster sin convertir volumen en culpabilidad | Reporter/cohorts; same fingerprint | Transactional antiabuse | Identidades correlacionadas solo security |
| `PROFILE-REPORTS-V1-006` | Reporter no tiene receipt/estado | Receipt y read model propio canónicos | Reporter; own intake | Reporter projection | Opaque ref; no moderator, sources o notes |
| `PROFILE-REPORTS-V1-007` | No hay decisión de contenido versionada | Human decision, external/internal reason, correction lineage | Moderator; case/content | Case decision authority | Reporter/target reciben proyecciones distintas |
| `PROFILE-REPORTS-V1-008` | No hay acciones tipadas sobre perfiles | Action adapters con expected target revision y rollback | Moderator; Market/Referee/Club/Team | Original target command authority | Solo campo/publication; preserve private/history |
| `PROFILE-REPORTS-V1-009` | Target no recibe razón/recurso | Subject notice comprensible y diferible por safety | Target owner; affected revision | Subject notice projection | Reporter/evidence hidden |
| `PROFILE-REPORTS-V1-010` | Recurso Profile no existe | Appeal/correction/reversal con reviewer independiente | Target o reporter cuando policy lo permita | Appeal aggregate | Text privado; lineage; no automatic restore |
| `PROFILE-REPORTS-V1-011` | Acceso podría filtrar evidencia | Private tables, minimal RPCs, explicit capabilities | Todos los roles | RLS/RBAC | Support/local admins no heredan identity/evidence |
| `PROFILE-REPORTS-V1-012` | Clientes necesitan converger | Minimal invalidations, own notices, canonical refetch | Reporter/target/moderator | Notification + invalidation authority | No PII/free text/legal classification in payload |
| `PROFILE-REPORTS-V1-013` | PWA puede aparentar éxito offline | Fail-closed submit, no queue/draft storage, controlled retry | Reporter client | Server command receipt | Sensitive draft memory-only unless user copies it |
| `PROFILE-REPORTS-V1-014` | No hay purge/capacity control | Versioned retention jobs and queue health/kill switch | Ops/security | Scheduled authority/platform flags | Aggregated metrics; auditable deletion |
| `PROFILE-REPORTS-V1-015` | Notice ilícito no está definido | Separate legal branch/form and obligations after legal gate | Any person/entity if applicable; public content | Shared cases with legal adapter | Contact/exceptions/purpose strictly defined |

## 6. Reproducción, aceptación y regresión por ID

| ID | Reproducción mínima | Criterios de aceptación | Regresiones | Archivos previstos | Áreas prohibidas |
| --- | --- | --- | --- | --- | --- |
| 001 | Intentar enlazar Club a case Conduct actual falla/falsea player target | Subject union validado; Conduct fixtures idénticos; una case authority | Conduct submit, triage, appeals, RLS | Migración aditiva, authority libs/tests, docs | Reescribir casos históricos o semántica Conduct |
| 002 | Usuario ve perfil público y no existe command Profile | Submit crea un intake/receipt una vez | Auth, replay, stale, private/self target | Migración command, server client, tests | UI pública/flag ON en primer lote |
| 003 | Payload manipula internal ID/revision | Server ignora/falla datos no allowlisted y resuelve target visible | IDOR, enumeration, blocked user, deleted/private target | Resolver adapters/tests | Target UUID libre o client severity |
| 004 | Perfil cambia entre vista y submit | Snapshot corresponde a revisión denunciada o devuelve stale explícito | Same-transaction revisions, asset hash, edit race | Snapshot model/tests | Full profile, contactos, Rating, coordinates |
| 005 | Repetir/campaña crea casos artificiales | One logical intake per key; clustered sources; no autoaction | Burst, same Team, reciprocal, coordinated, honest retry | Rate/dedupe authority/tests | N reports => guilty/action |
| 006 | Reporter no puede consultar estado | Own read model muestra receipt/status/decision permitida | Cross-user RLS, opaque IDs, corrected decision | Projection RPC/tests | Notes, moderator, other reporters |
| 007 | Dos moderadores deciden concurrently | Una revisión gana; stale rejects; correction supersedes | Concurrent decision, conflict, no_action/action | Decision commands/tests | Generic update, silent last-write-wins |
| 008 | Unpublish mientras owner edita | Typed adapter locks/reconciles target and returns canonical revision | All allowlisted targets, failure/rollback/expiry | Per-target adapters/tests | Account delete, memberships, Rating/results |
| 009 | Action aplicada sin notice | Notice created idempotently or safety deferral reason recorded | Identity leak, threat/minor deferral, retry | Notice projections/tests | Reporter identity/private description |
| 010 | Duplicate appeal/action race | One active appeal; independent review; reversal command explicit | Replay, stale, concurrent action, correction | Appeal authority/tests | Delete original decision or auto-restore danger |
| 011 | Team admin queries reporter identity | Denied; only security capability reads identity/evidence | Actor matrix SQL, direct DML, definer search path | RLS/grants/functions/tests | Broad authenticated grants/service key client |
| 012 | Two devices receive invalidation | Both canonical-refetch same revision without sensitive WAL | Reconnect, SUBSCRIBED, dedupe, preference rules | Notifications/invalidation/tests | Full evidence/notes in Realtime or push |
| 013 | Submit offline or RPC rejects | No confirmed state/queue; explicit retry/update-required | Browser/PWA, pending write, reconnect, SW update | Client policy/UI/E2E | localStorage authority or sensitive queue |
| 014 | Backlog exceeds staffed capacity | Health transitions and kill switch preserve existing case access | Thresholds, purge dry-run/apply, legal hold, metrics privacy | Jobs/health/control tests | Delete active/appealed case; raw PII metrics |
| 015 | Legal notice sent through community category | Routed to dedicated contract only when enabled | Anonymous/non-account path if required, receipt/reason/redress | Separate legal migration/UI/tests after gate | Claim DSA compliance or activate without legal review |

`Archivos previstos` describe tipos de cambio. Los nombres concretos no se
congelan hasta revisar el `main` de una futura orden; ninguno se crea aquí.

## 7. Secuencia condicional de batches

Todos los batches siguientes están en estado `DRAFT / NON-EXECUTABLE`.

### BATCH 001 — PRIVATE INTAKE AND SHARED CASE AUTHORITY

| Campo | Contrato condicional |
| --- | --- |
| Objetivo | Generalizar case subjects de forma compatible; crear intake, resolver, snapshot, receipts y read-own privados |
| IDs | 001–006 y parte de 011/014 |
| Rama futura | `NOT ASSIGNED — BLOCKED` |
| PR | `NOT ASSIGNED — BLOCKED` |
| Migraciones | Aditivas, nombres/número `TBD`; todo OFF; nunca reescribir ejecutadas |
| Tablas/funciones/read models | Objetos lógicos de secciones 3–4; commands y own projection mínimos |
| Endpoints/UI | Sin entrypoint público; harness sintético únicamente |
| Tests/staging | SQL/RLS/idempotencia/concurrencia/snapshots; Supabase aislado; no producción |
| Flags/datos | Foundation conceptualmente OFF; synthetic only; cleanup/readback 0 |
| Riesgos | Romper Conduct, IDOR, overcollection, authority duplication |
| Rollback | Flags siguen OFF; rollback aditivo probado; no borrar historia Conduct |
| Merge | Solo tras resolver todos los bloqueos y pasar matrices authority/privacy |
| Siguiente | 002 solo con 001 desplegado OFF, readback y seguridad aprobada |

### BATCH 002 — PROFILE ENTRYPOINTS AND REPORTER STATUS

| Campo | Contrato condicional |
| --- | --- |
| Objetivo | Target allowlist, CTA contextual, formulario, receipt/status y offline fail-closed |
| IDs | 002–006, 011–013 |
| Rama/PR | `NOT ASSIGNED — BLOCKED` |
| Migraciones | Solo si projections/contracts de 001 requieren hardening; `TBD` |
| Tablas/functions/read models | Reutiliza 001; no segunda authority |
| Endpoints/UI | Menú contextual en Market, Referee, Club y Team aprobados; no nav primaria |
| Tests/staging | Roles, targets, accessibility, portrait/landscape/PWA, offline/reconnect |
| Flags/datos | Public entrypoints e intake OFF; synthetic profiles only |
| Riesgos | Enumeración, accidental public launch, sensitive drafts, misleading receipt |
| Rollback | Entry flag OFF; read status permanece para accepted synthetic intakes |
| Merge | UX/safety/legal copy approved; no open critical privacy finding |
| Siguiente | 003 solo con capacidad operativa y appeals contract disponible |

### BATCH 003 — MODERATION ACTIONS AND SUBJECT APPEAL

| Campo | Contrato condicional |
| --- | --- |
| Objetivo | Queue común, decisions, typed content actions, notices, appeal/correction/restoration |
| IDs | 007–012 y 014 |
| Rama/PR | `NOT ASSIGNED — BLOCKED` |
| Migraciones | Decisions/actions/notices/appeals/health aditivos; `TBD` |
| UI | Extensión capability-gated de `/admin/conduct`; own subject/reporter status |
| Tests/staging | Concurrency, stale, role separation, every adapter, notices, appeal race, expiry |
| Flags/datos | Moderation/appeals OFF; synthetic cases; cleanup or durable staging only |
| Riesgos | Wrong-target action, reporter leak, auto-restoration, moderator conflict |
| Rollback | Actions fail-closed; reversible publication commands; no destructive account action |
| Merge | Human operations runbook, reviewer separation and retention jobs approved |
| Siguiente | 004 solo tras capacity canary and urgent policy dry run |

### BATCH 004 — CONTROLLED PRIVATE BETA

| Campo | Contrato condicional |
| --- | --- |
| Objetivo | Preview/staging, shadow/private allowlist, capacity metrics and kill switch |
| IDs | Todos salvo 015 |
| Rama/PR | `NOT ASSIGNED — BLOCKED` |
| Migraciones | Hardening/indexes only if evidence requires; `TBD` |
| UI | Explicit actors only; no directory-wide public CTA initially |
| Tests/staging | Two users/devices, moderator, target, abuse, urgent dry run, retention dry run, cleanup |
| Flags/datos | Foundation then moderation then appeals then tiny intake allowlist; never direct UPDATE |
| Riesgos | Backlog, no on-call, accidental real report, synthetic visibility |
| Rollback | Kill intake, retain case access/appeals, remove allowlist, verify no fake success |
| Merge/activation | Queue `OK`, P95 <=60% capacity, urgent unassigned 0, legal/safety sign-off |
| Siguiente | Gradual product activation by explicit separate order |

### BATCH 005 — ILLEGAL CONTENT NOTICE

| Campo | Contrato condicional |
| --- | --- |
| Objetivo | Canal legal separado con location, substantiation, contact/exception, receipt, decision and redress |
| IDs | 015 plus shared decisions/notices/appeals |
| Rama/PR | `NOT ASSIGNED — SEPARATE LEGAL GATE REQUIRED` |
| Migraciones/UI | Solo tras clasificación/aplicabilidad; no compartir ciegamente comunidad UI |
| Tests | Anonymous/non-account eligibility if required, child-safety exception, statement/review, abuse |
| Flags/datos | Legal notice flag independiente OFF; synthetic only until approved |
| Riesgos | Incumplimiento, exceso de PII, false legal promise, urgent mishandling |
| Rollback | Intake legal OFF sin eliminar notices aceptados; fallback contact aprobado |
| Merge/activación | Legal owner/contact, process, transparency and redress approved |
| Siguiente | Ninguno definido por este gate |

## 8. Plan de pruebas futuro

### AUTORIDAD

- Actor real viene de Auth; actor/role falsos en payload se rechazan/ignoran.
- Target, field, visibility y revision se resuelven server-side.
- Category allowlist y details requirements por target.
- Snapshot exacto de revisión; múltiples snapshots con mismo timestamp se
  ordenan por server sequence/confirmed revision, no solo `created_at`.
- Operation replay devuelve receipt original; payload conflictivo falla.
- Expected revision stale falla y obliga canonical refetch.
- Direct DML, broad grants y unauthorized `SECURITY DEFINER` fallan.
- Dos dispositivos no crean dos intakes lógicos ni dos decisiones vigentes.

### PRIVACIDAD

- Reporter identity oculta a target, otros reporters, Team/Club admins,
  moderator ordinario cuando no la necesita y support.
- Notas y descripción privada no aparecen en reporter/target projections.
- Snapshot solo contiene campos públicos allowlisted.
- Target privado/inexistente devuelve respuesta no enumerable.
- Realtime, notifications, telemetry, errors y logs carecen de PII/free text.
- Security access y exports quedan auditados y minimizados.
- DSAR/rectification/deletion/legal hold conservan derechos de terceros.

### ABUSO

- Duplicate exacto, nueva revisión, nueva categoría y honest retry.
- Rate/burst/daily limits transaccionales.
- Campaña mismo Team, múltiples Teams, reports recíprocos y bombing.
- Usuario bloqueado reporta solo target público conocido sin desbloquearlo.
- Self-report redirige; outsider/private target falla.
- URL, Unicode/control chars, HTML, XSS, SQL/log injection y oversize text.
- Trusted flagger solo mediante estatus oficial verificable si aplica.
- Una denuncia y `N` denuncias no disparan autoaction.

### MODERACIÓN

- `no_action`, action allowlisted, partial failure, correction y supersession.
- Dos moderadores concurrentes; stale decision rechazada.
- Profile edit durante review; decision usa revision denunciada y current.
- Action/profile edit race; lock y expected revision.
- Appeal/action race, duplicate appeal, reviewer conflict y expiry.
- Restore solo por command explícito y no para contenido peligroso sin review.
- Safety deferral impide notice prematuro al target.

### DOMINIOS

- Conduct submit/context/triage/appeal conserva resultados exactos.
- Competition Reports/Discipline sin cambios.
- Team Operational State/appeals sin cambios.
- Rating V2, GRL, facetas, reliability, Season Score y ranking bit-for-bit sin
  mutación por reports.
- Rewards/logros/cajas/cosméticos intactos.
- Billing/Stripe no recibe ninguna llamada.
- No membership, ownership, match result, standing o discipline mutation.

### PWA

- Offline: no receipt, no success, no queue, no storage sensitive draft.
- RPC error o update-required elimina cualquier preview optimista.
- Reconnect permite retry explícito y canonical read.
- Service Worker update pausa writes pendientes y solo recarga una vez.
- Cliente antiguo puede leer pero no interpretar permission error como success.

### E2E

- Reporter, target, outsider, blocked user, minor-safe scenario, urgent
  scenario, moderator, security y support.
- Player Market, referee, Club y Team; cada projection/surface apunta al mismo
  target canónico.
- Portrait 390x844, landscape 844x390, desktop 1440x900 y standalone.
- Submit, receipt, cluster, decision, action, notices, appeal, correction,
  restoration and cleanup.
- Zero console errors, overflow, broken navigation, secret/PII leakage.
- Synthetic World/Demo only until explicit private beta authorization.

## 9. Datos, staging y canary

- Supabase local/branch aislado y determinista para SQL/RLS/concurrency.
- Fixtures sintéticos sin emails reales, Auth IDs reales ni contenido sensible.
- No notificaciones a usuarios reales.
- Production canary, si una orden posterior lo permite, solo transacción con
  rollback o entidades sintéticas eliminables y readback final cero.
- Demo World puede mostrar estados sanitizados, nunca un caso real ni un intake
  escribible.
- Ningún batch usa localStorage como evidencia o autoridad.
- El cleanup debe demostrar cero intakes, cases, actions, appeals, notices,
  sessions y operations QA pendientes.

## 10. Observabilidad y capacidad

Read model interno mínimo:

- incoming reports/cases por target/category sin identidad;
- duplicate and correlated-source ratio;
- backlog y capacity forecast;
- oldest unassigned/normal case age;
- urgent unassigned count/age;
- appeals overdue;
- action/notice failure count;
- retention jobs due/failed;
- invalidation/refetch convergence;
- queue health `UNKNOWN`, `OK`, `WARNING`, `CRITICAL`.

No se registran free text, reporter/target identity, evidence, Authorization,
cookies, IP o exact location en métricas. `UNKNOWN` bloquea intake. El kill
switch detiene nuevos reportes y mantiene lectura, decisiones, notices y
apelaciones existentes.

## 11. Matriz de decisiones bloqueantes

| ID decisión | Decisión | Owner requerido | Recomendación | Consecuencia de alternativa/rechazo |
| --- | --- | --- | --- | --- |
| D01 | Menores y safety | Alberto + responsable legal/safety | Aprobar policy completa antes de intake | Sin ella, stop gate permanente |
| D02 | Moderation staffing | Alberto | Primary + backup nombrados, formación y capabilities | Sin owner, health `UNKNOWN` e intake OFF |
| D03 | Urgent operations | Security/legal/Alberto | Horario, plazo, fallback y mensajes reales | Excluir graves no resuelve notice legal; activación bloqueada |
| D04 | Base jurídica | Asesoría privacidad | Aprobar por dato/canal, no una base única genérica | No se puede persistir intake/evidencia |
| D05 | Retención | Privacy/legal/security | Plazo por capa, purge probado, hold acotado | No se crean tablas permanentes |
| D06 | DPIA | Responsable del tratamiento | Screening y DPIA si procede antes de beta | Riesgo alto no evaluado; activación OFF |
| D07 | DSA classification | Asesoría jurídica | Determinar hosting/platform/tamaño/aplicabilidad | Batch 005 y claims prohibidos |
| D08 | Legal notice channel | Legal + producto | Entrada separada, accesible cuando corresponda | `illegal_content` fuera de comunidad |
| D09 | Legal owner/contact | Titular | Completar identidad/contacto funcionales | Notices, escalation y rights incompletos |
| D10 | Community standards | Producto + legal | Reglas versionadas y reason codes humanos | Decisions carecen de criterio publicable |
| D11 | V1 target allowlist | Alberto + safety/legal | Market, Referee, Club, Team; Venue diferido | Sin allowlist no hay entrypoints |
| D12 | Appeals windows/scope | Legal + producto | Target appeal; reporter review cuando aplique | Actions dependientes permanecen OFF |
| D13 | Reporter no-action review | Legal + producto | Separar comunidad de canal legal | Reporter projection no puede prometer recurso |
| D14 | Temporary publication action | Producto/moderación | Solo visibilidad/publicación, con expiración | No usar cuenta/Team restriction como atajo |
| D15 | Privacy notices/DSAR | Privacy/legal | Actualizar antes de intake y probar rights workflow | No private beta |

Resolver parcialmente la tabla no autoriza ningún batch. Deben resolverse todas
las dependencias del batch y mantenerse las invariantes globales.

## 12. Condiciones de preparación de una futura orden

Una nueva orden solo puede declarar Batch 001 ejecutable si adjunta:

1. Decisiones D01–D06, D09–D12 y D15 aprobadas y versionadas.
2. Confirmación explícita de que Batch 005 sigue separado salvo D07–D08.
3. Responsable, backup, capacidad semanal y kill-switch owner.
4. Target allowlist exacta.
5. Policy/reason codes y appeal windows exactos.
6. Retention table y legal-hold authority exactos.
7. Base `origin/main` actual, aislamiento Git y no solape con otros PR.
8. Prohibición reiterada de tocar Rating/Ranking/Rewards/Discipline/Team
   Operational/Billing.

Hasta entonces no deben reservarse nombres de ramas/PR/migraciones ni crear
flags vacíos “para adelantar”.

## 13. Validación de este gate

- Baseline técnico certificado heredado: 876/876.
- Executable files changed: 0.
- SQL changed: 0.
- Tests changed: 0.
- `package.json` changed: 0.
- `package-lock.json` changed: 0.
- Supabase/data/flags/RPC/RLS changed: 0.
- No tests runtime se repiten porque el diff es exclusivamente documental.
- La validación exigida es diff exacto de dos Markdown, `git diff --check`,
  secret/PII scan, links y tablas.

## 14. NEXT EXECUTABLE ORDER

```text
NONE — RESOLVE PROFILE REPORTS V1 PRODUCT, LEGAL, MINOR-SAFETY, RETENTION AND MODERATION OPERATIONS DECISIONS
```

Los Batches 001–005 anteriores son una secuencia condicional no ejecutable. No
se debe iniciar `PRIVATE INTAKE AND SHARED CASE AUTHORITY` ni ninguna parte de
su schema hasta que una orden posterior documente y apruebe los bloqueos.
