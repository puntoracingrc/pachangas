# Demo World V2 Report

## Checkpoint

- Fecha: 2026-08-25, Europe/Madrid.
- Base inicial y `origin/main`: `cc171293e3839b54fe9e0079b480ee78eca2b100`.
- Rama: `codex/demo-world-v2-league-parity`.
- Worktree aislado:
  `/Users/macbookpro14/.codex/worktrees/pachangas-demo-world-v2`.
- Node: `v24.16.0`.
- Supabase productivo: no modificado durante implementacion y simulacion.
- Simulation World: PostgreSQL local temporal; 141 migraciones.

## Reconciliacion

El checkout compartido se encontro 354 commits por detras y con cambios del
laboratorio de Rating. No se modifico ni limpio. Se inventariaron los PR
abiertos: #131 y #132 son laboratorios 3D apilados, y #6 es una rama Demo
antigua sustituida; ninguno era integrable dentro de esta fase.

No se absorbieron ramas, worktrees ni migraciones ajenas.

## Resultado funcional

Demo World V2 conserva 30 equipos y 331 jugadores de V1 y anade:

- tres Clubs con perfil publico y seis relaciones Club-Team;
- ocho perfiles arbitrales ficticios y relaciones Club-Referee;
- perspectiva local `league-organizer`;
- una Competition protagonista con Edition, Category, Stage, Division y Group;
- seis Entries, Delegates y Rosters;
- cinco Rounds y quince CanonicalMatches;
- quince resultados oficiales y un StandingSnapshot reconstruible;
- aplazamiento, cambio de sede, no-show, suspension/reanudacion y una llegada
  tardia resuelta dentro del margen, con lineage y recibos autoritativos;
- navegacion Liga, Clasificacion, Jornadas, Club y Arbitros dentro de la shell
  existente;
- renderers productivos de calendario, partido, clasificacion, Club y arbitro.

Referee Assignments permanece desactivado. No se ha creado una Liga secundaria
porque era opcional y duplicaba peso sin ampliar la cobertura de motores.

## Simulation World

`npm run demo-world:v2:simulate`:

1. crea una base PostgreSQL temporal en el servidor local existente;
2. aplica el baseline y las 141 migraciones en su orden historico;
3. ejecuta las suites SQL/RLS en los limites R1/R4A/R4B/R4C/R4D;
4. activa flags y grants unicamente dentro del mundo sintetico;
5. crea y publica la Liga mediante RPC de Scheduling;
6. recorre squads, attendance, partido, resultado e incidencias mediante RPC
   de Match Operations y Operational Exceptions;
7. extrae una prueba sanitizada, genera el snapshot y destruye la base.

Resultado determinista:

| Evidencia | Valor |
| --- | --- |
| Hash de autoridad | `9b91cedf18c725086da0fe37abf7c38c9ef8ae690179650b76414b5b69c769c1` |
| Hash publico | `f6603605183f1446371ef55b97e7020909fcc91f81533e51e7860f869ca81b3b` |
| Recibos Scheduling | 5 |
| Recibos Match Operations | 266 |
| Recibos Operational Exceptions | 13 |
| Escrituras remotas | 0 |

`npm run demo-world:v2:verify` repite la simulacion en otra base temporal y
confirma que prueba y snapshot son identicos.

## Registro permanente de incidencias

| ID | Clase | Estado | Hallazgo | Correccion | Regresion |
| --- | --- | --- | --- | --- | --- |
| DW2-001 | ENVIRONMENT_ISSUE | fixed + regression_verified | Aplicar todo el ledger antes de suites historicas hacia fallar contratos que esperaban el esquema de cada fase. | Ledger aplicado por bloques R1-R4D y suites ejecutadas en su limite historico. | `demo-world:v2:simulate` completa 141 migraciones. |
| DW2-002 | PRODUCT_BUG | fixed + regression_verified | El regex generado del Service Worker perdia el escape de `\\d` y no reconocia chunks versionados. | Regex template escapado para cualquier `/demo-world/vN/`. | Test V2 inspecciona el SW generado. |
| DW2-003 | PRODUCT_BUG | fixed + regression_verified | Los renderers oficiales incrustados heredaban variables claras sobre fondo oscuro. | Scope oscuro explicito dentro de `.demoProductView`. | Test CSS y QA desktop/portrait/landscape. |
| DW2-004 | PRODUCT_BUG | fixed + regression_verified | `height: 100%` circular colapsaba el hero de Liga en 844x390 y solapaba titulo, botones y contenido. | Altura calculada desde `100dvh` y nav compacta. | Test CSS y medicion DOM sin overlap. |
| DW2-005 | TESTABILITY_GAP | fixed + regression_verified | El primer generador podia fabricar resultados y tabla sin demostrar procedencia PostgreSQL. | Prueba de autoridad versionada, hash enlazado al snapshot y oracle independiente. | Test compara proof, recibos, standings y provenance. |
| DW2-006 | SIMULATION_BUG | fixed + regression_verified | El extractor del fixture R4B usaba un marcador que habia cambiado. | Limite estable antes de `r4b_invariants_before` con asercion de drift. | Simulacion completa. |
| DW2-007 | SIMULATION_BUG | fixed + regression_verified | Crear la Liga antes de la suite R4D contaminaba una asercion de aislamiento que esperaba un solo CanonicalMatch. | La Liga se crea despues de todas las suites historicas. | R4D SQL y mundo Demo pasan en la misma base. |
| DW2-008 | PRODUCT_BUG | fixed + regression_verified | Un empate intermedio requeria una decision de desempate manual durante cada actualizacion de standings. | RuleRevision Demo permite posiciones compartidas durante el calculo incremental; los criterios finales siguen ordenando la tabla. | Quince resultados aceptados y snapshot final reconstruido. |
| DW2-009 | SIMULATION_BUG | fixed + regression_verified | Preferencias y una restriccion de disponibilidad heredadas del fixture R4B priorizaban partidos fuera del orden cronologico de jornadas. | La preparacion de la base temporal elimina solo esos datos de prueba antes de generar el calendario Demo. | Test exige ventanas originales estrictamente crecientes por jornada y `demo-world:v2:verify` reproduce el snapshot. |
| DW2-010 | PRODUCT_BUG | fixed + regression_verified | El encabezado de Arbitros heredaba texto oscuro de la Demo clara dentro del panel productivo oscuro en modo juego. | Colores explicitos `--official-text`, `--official-muted` y `--official-cyan` limitados a `.demoProductView`. | Test CSS y QA visual 844x390. |
| DW2-011 | SIMULATION_BUG | fixed + regression_verified | La temporada Demo esta congelada en el pasado y el RPC real clasificaba la llegada sintetica como fuera de plazo usando el reloj actual del servidor. | Solo en la base efimera, la operacion aproxima temporalmente el inicio al reloj del servidor, ejecuta `late_arrival.report` y `late_arrival.confirm_arrival`, y restaura despues las fechas canonicas deterministas. | Test exige un unico `arrived_within_policy`, conserva `exceptionType: none` y `demo-world:v2:verify` reproduce ambos hashes. |

## Privacidad y autoridad

- Cero Auth real, emails, telefonos, tokens, PII o `service_role` en el bundle.
- Cero `POST`, `PUT`, `PATCH`, `DELETE`, RPC o mutacion Supabase desde `/demo`.
- IDs publicos exclusivamente `demo_*`.
- El navegador no recalcula ni confirma resultados definitivos.
- `sessionStorage` solo conserva interaccion efimera de la demo.
- El StandingSnapshot se produce en servidor y el oracle existe solo en tests.
- Raw WAL no es autoridad; el snapshot publico ya esta congelado por hash.

## QA local completada

- Liga, Clasificacion, Jornadas, Club, Arbitros y partido canonico en
  `1440x900`, `390x844` y `844x390`.
- Cero overflow raiz, imagen rota, overlay de Next o solape tras el fix.
- Tema claro y oscuro con contraste explicito en renderers incrustados.
- Carga inicial lazy y chunks secundarios por dominio.
- Demo V1 permanece intacta.
- Lint focal: cero errores y cero avisos.
- Lint global: deuda heredada de 22 errores y 18 avisos, fuera del diff V2.
- Bateria global: 471/471, cero skipped, todo o cancelled.

## Estado de release

La implementacion local y la Simulation World estan completas. Merge, Vercel,
smoke de `pachangasiq.com/demo`, version final de Service Worker y limpieza del
worktree se registran en `DEMO_WORLD_V2_PRODUCTION_RELEASE.md` al cerrar la
release de Fase A.
