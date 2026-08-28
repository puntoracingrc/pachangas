# Public Competitions V1 - Implementation Report

## Estado

`RELEASE CANDIDATE / LOCAL AND STAGING PASS`

Wave 7A convierte la Competition canonica existente en un producto publico
moderado. No crea un segundo dominio deportivo: publication, consent, public
read models y registration requests referencian Competition, Edition,
RuleRevision, CompetitionEntry, CanonicalMatch, standings y bracket existentes.

## Alcance implementado

- visibilidad `private`, `unlisted` y `public` independiente del slug;
- lifecycle `draft -> pending_review -> approved -> published`, con rechazo,
  suspension, restauracion y archivo;
- consentimiento versionado con actor servidor, finalidad y fingerprint;
- revision de plataforma separada de la autoridad del organizador;
- directorio paginado y filtrable en `/competiciones`;
- hub publico en `/competiciones/[slug]` para Liga y Torneo;
- tabs aplicables de resumen, formato, equipos, calendario, resultados,
  clasificacion, cuadro, reglamento, arbitros e inscripcion;
- Configuration Center y Control Center para publication, privacidad y salud;
- sitemap y robots limitados a publicaciones publicas aprobadas y activas;
- invalidacion Realtime seguida de refetch canonico;
- cache PWA de lecturas y bloqueo de escrituras offline.

## Autoridad y seguridad

El navegador envia intencion semantica, `operationId` y revision esperada. Las
RPC resuelven `auth.uid()`, grants, lifecycle, capacidad y estado canonico en
PostgreSQL. Las tablas nuevas revocan acceso directo a `public`, `anon` y
`authenticated`; las lecturas pasan por read RPC sanitizadas y las mutaciones
por command RPC con bloqueo, secuencia de servidor, auditoria e idempotencia.

No forman parte del payload publico:

- roster, Attendance, lesiones o disponibilidad;
- email, telefono, Auth UUID o staff privado;
- evidencias, deliberacion o motivos privados;
- tarifas arbitrales, operaciones internas o ubicaciones no consentidas;
- Rating, Season Score o ranking territorial.

## Producto publico

El directorio admite tipo, modalidad, estado, zona, formato y disponibilidad.
Solo una publication `public + published + approved`, no suspendida ni
archivada, puede aparecer e indexarse. `unlisted` es accesible por enlace y
`noindex`; `private` no se expone por la ruta publica.

El hub consume snapshots preparados por servidor. Resultados muestra solo la
OfficialResultDecision vigente; standings y bracket proceden de snapshots
canonicos y no se recalculan en React. Arbitros se muestran solo con assignment
confirmada, perfil publico y consentimiento. La disciplina publica permanece
apagada.

## Gates verificados

| Gate | Resultado |
| --- | --- |
| Fresh bootstrap / upgrade 176 -> 183 | PASS |
| Schema equivalence | PASS |
| SQL, RLS, RBAC e idempotencia | PASS |
| Concurrencia | PASS |
| Scale y performance | PASS |
| Staging League E2E autenticado | PASS |
| Staging Tournament E2E | PASS |
| Privacidad anonima | PASS |
| Realtime canonical refetch | PASS |
| PWA browser/offline/reconnect | PASS |
| PWA instalada fisica | PENDING |
| QA visual ocho viewports | PASS |
| Root overflow / imagenes / consola | 0 / 0 / 0 |

## Pruebas finales

- `npm test`: Node `20/20`, TS/TSX `573/573`, total `593/593`;
- skipped/todo/cancelled: `0/0/0`;
- focused Wave 7A: `20/20`;
- typecheck: PASS;
- build Next.js: PASS, 54 paginas;
- lint focalizado: PASS;
- lint global: 40 hallazgos preexistentes, `22 errors + 18 warnings`;
- `git diff --check`: PASS.

## Limites conservados

No se implementan pagos, Stripe, planes del organizador, registro individual,
public discipline, autoaccept, ida y vuelta ni doble eliminacion. Rating,
Rewards, Conduct y Billing no se modifican.

