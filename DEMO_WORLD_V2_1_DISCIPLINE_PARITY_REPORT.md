# Demo World V2.1 Discipline Parity Report

## Estado

`RELEASE CANDIDATE LOCAL / PRODUCTION PENDING`

Demo World V2.1 extiende el mismo mundo determinista de V2 con la autoridad
real de Competition Discipline V1. No crea una segunda Liga, no recalcula
disciplina en el navegador y no escribe en Supabase remoto.

## Checkpoint

| Dato | Valor |
| --- | --- |
| Fecha | `2026-08-25` |
| Base | `00dc908be0cb87ed0814becdc7ec06c48ec8102b` |
| Rama | `codex/product-demo-parity-wave-3-release` |
| Version Demo | `2.1` |
| Seed | `pachangas-iq-demo-world-v2-1-2026-27` |
| Migraciones Simulation World | `146` |
| Hash de autoridad | `0ca037a292e643bebd9738e1ae072f776e7e1ecc29da776f9291435b7b35fa6b` |
| Hash publico | `f68d9279271275afc262b144cb7784957b5a9606e5fd74df02907ef45f5c1886` |
| Escrituras remotas | `0` |

La simulacion crea PostgreSQL temporal, aplica el ledger completo, ejecuta R1,
R4A, R4B, R4C, R4D y R5, exporta un snapshot sanitizado y destruye la base. Una
segunda ejecucion en modo verify obtiene exactamente los mismos hashes.

## Historias disciplinarias

La Liga protagonista conserva 6 equipos, 5 jornadas y 15 CanonicalMatches. La
disciplina queda distribuida de forma deliberadamente escasa:

| Evidencia | Resultado |
| --- | ---: |
| Eventos vigentes | `20` |
| Amarillas | `16` |
| Rojas | `2` |
| Azules | `2` |
| Correcciones append-only | `1` |
| Sanciones | `4` |
| Eventos de cumplimiento | `2` |
| Apelaciones privadas simuladas | `2` |
| Recibos R5 | `33` |

Historias cubiertas:

- dos amarillas sin sancion;
- tercera amarilla, bloqueo de una jornada y regreso posterior;
- roja directa con decision de comite;
- sancion cumplida y elegibilidad restaurada;
- amarilla corregida a azul sin borrar el hecho original;
- apelacion confirmada y apelacion modificada;
- reduccion por apelacion que conserva una unidad ya cumplida;
- alineacion que sustituye al sancionado y recupera al titular al terminar.

La cronologia de elegibilidad del jugador de umbral es:

```text
J1 primary -> J2 primary -> J3 primary -> J4 alternate -> J5 primary
```

## Paridad de producto

- La navegacion de Liga incorpora `Disciplina`.
- El resumen usa `CompetitionDisciplineClient`, el mismo renderer productivo.
- Cada partido abre sus tarjetas y sanciones en
  `LeagueMatchOperationsClient`, tambien productivo.
- Los estados de jugador Demo son de solo lectura y no enlazan a rutas reales.
- Los permisos de mutacion son todos `false`.
- El navegador recibe read models canonicos ya preparados; no deriva counters,
  sanciones, cumplimiento ni elegibilidad.

## Privacidad

El snapshot publico no contiene:

- appeals ni identidad del apelante;
- motivos privados o deliberacion;
- evidence refs;
- operation IDs;
- usuarios Auth, emails o telefonos;
- tokens, secretos o `service_role`;
- IDs de producto reales.

La proyeccion publica conserva unicamente hechos, sanciones, cumplimiento y
estado deportivo necesarios para explicar la Liga ficticia.

## Regresion determinista

| Gate | Resultado |
| --- | --- |
| `npm run test:demo-world:v2` | `11/11 PASS` |
| `npm run demo-world:v2:verify` | `PASS / snapshotIdentical=true` |
| `npm run test:competition-discipline` | `14/14 PASS` |
| `npm test` | `506/506 PASS` (`20 Node + 486 TSX`) |
| SQL/RLS/adversarial | `PASS` |
| Appeal service accounting | `PASS` |
| Concurrencia R5 | `7/7 carreras deterministas` |
| Escala R5 | `10.000 eventos / rollback PASS` |
| Typecheck / build / lint focal | `PASS / PASS / PASS` |
| Lint global | deuda heredada: `22 errores / 18 warnings` |
| Remote writes | `0` |

El contrato comprueba que standings, Rating V2, Conduct y Rewards permanecen
sin cambios por tarjetas o sanciones.

## Incidencias permanentes

| ID | Clase | Hallazgo | Correccion | Estado |
| --- | --- | --- | --- | --- |
| DW2.1-001 | PRODUCT_BUG | Una apelacion que reducia una sancion parcialmente cumplida podia volver a exigir la unidad ya servida. | Hotfix forward-only y regresion SQL sobre revision inmutable y fila canonica. | fixed + regression_verified |
| DW2.1-002 | PRODUCT_BUG | La UI comparaba estados de elegibilidad en minusculas aunque el read model podia devolverlos en mayusculas. | Normalizacion antes de decidir disponibilidad. | fixed + regression_verified |
| DW2.1-003 | PRODUCT_BUG | Un estado de jugador dentro de Demo podia enlazar a una ruta real de Competition. | El renderer productivo admite preview de solo lectura sin enlace. | fixed + regression_verified |
| DW2.1-004 | SIMULATION_BUG | La preparacion inicial intentaba mutar directamente una revision de roster inmutable. | Finalizacion mediante el helper canonico privado usado por el motor. | fixed + regression_verified |
| DW2.1-005 | TESTABILITY_GAP | Ejecutar fixtures historicos R4D y R5 como un unico fixture reutilizaba IDs reservados. | La simulacion prueba el grafo R5 real y la suite R5 completa se ejecuta en una base temporal independiente dentro del mismo gate. | fixed + regression_verified |
| DW2.1-006 | PRODUCT_BUG | El detalle de Jornadas en Demo enlazaba IDs ficticios hacia una ruta productiva de Competition. | Navegacion interna inyectable en el renderer compartido, conservando el enlace normal en producto. | fixed + regression_verified |
| DW2.1-007 | PRODUCT_BUG | El marcador de partido seguia anunciando que Disciplina no estaba disponible aunque R5 ya estuviera cargada. | Etiqueta derivada de la presencia del snapshot R5, con copy neutro en el resto de contextos. | fixed + regression_verified |
| DW2.1-008 | PRODUCT_BUG | A 390 px la lista compartida de hechos disciplinarios ocultaba jugador, minuto y estado, dejando visible solo la sancion derivada. | La vista portrait conserva jugador y minuto, oculta solo el estado redundante y mantiene la sancion; regresion CSS y QA 390x844. | fixed + regression_verified |
| DW2.1-009 | ENVIRONMENT_ISSUE | El indicador de Next.js local se superpone a la esquina inferior en QA landscape. | No pertenece al build productivo; cierre pendiente de comprobar su ausencia en el deployment Vercel. | open / production_verification_pending |

## Invariantes

- una sola identidad de CanonicalMatch;
- RuleRevision como autoridad de tipos y umbrales;
- correcciones y servicio append-only;
- orden autoritativo por server sequence y un ID estable, nunca solo por
  `created_at`;
- standings no cambian por tarjetas;
- Rating V2, Rewards, Conduct, Billing y cosmeticos permanecen intactos;
- Referee Assignments, pagos y Tournament Engine permanecen OFF/no
  implementados segun su contrato.

## Cierre pendiente

La migracion forward-only, el merge, el deployment, la version final del
Service Worker y el smoke de `pachangasiq.com/demo` se registraran en los
informes de produccion una vez completado el release coordinado.
