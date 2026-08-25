# Demo World V2 Data Contract

## Proposito

Demo World V2 es el read model publico, ficticio y de solo lectura que muestra
la League Private Beta de Pachangas IQ. No sustituye Demo World V1: V1 queda
congelada como release historica y V2 usa un seed, un manifest y un namespace
propios.

V2 separa de forma explicita dos capas:

1. **Simulation World**: PostgreSQL temporal, las 141 migraciones del producto,
   flags sinteticas, grant sintetico y RPC reales R1, R4A, R4B, R4C y R4D.
2. **Public Demo Snapshot**: exportacion estatica, sanitizada, versionada y
   servida exclusivamente mediante `GET` desde el mismo despliegue web.

## Identidad

| Campo | Valor V2 |
| --- | --- |
| Version | `2` |
| Temporada | `2026/27` |
| Modo | `demo-world-read-only` |
| Seed | `pachangas-iq-demo-world-v2-2026-27` |
| `demoNow` | `2027-03-18T18:00:00.000Z` |
| Hash del snapshot | `f6603605183f1446371ef55b97e7020909fcc91f81533e51e7860f869ca81b3b` |
| Hash de autoridad PostgreSQL | `9b91cedf18c725086da0fe37abf7c38c9ef8ae690179650b76414b5b69c769c1` |
| Migraciones aplicadas en simulacion | `141` |
| Escrituras remotas | `0` |

El tiempo, los IDs de operacion y los resultados del escenario son estables.
La generacion y la verificacion no usan `Date.now()` como autoridad.

## Distribucion fisica

| Recurso | Contenido |
| --- | --- |
| `manifest.json` | version, seed, hashes, conteos y URLs de chunks |
| `core.json` | primera pintura, equipos, campos, perspectivas, ranking e historias V1 conservadas |
| `players.json` | 331 perfiles ficticios, Rating V2 y cosmeticos |
| `matches.json` | partidos sociales, asistencia, alineaciones, resultados y Retos V1 conservados |
| `activity.json` | logros, cajas y avisos ficticios |
| `competitions.json` | grafo R1-R4D, jornadas, CanonicalMatches, read models de partido y StandingSnapshot |
| `clubs-referees.json` | Clubs, equipos asociados, arbitros publicos y relaciones |

Inicio carga solo `core.json`. Los dominios Liga, Clasificacion y Jornadas
cargan `competitions.json`; Club y Arbitros anaden
`clubs-referees.json`. Los chunks llevan el hash del manifest en la URL y el
Service Worker los trata como recursos inmutables de cualquier version
`/demo-world/vN/`.

## Autoridad y adaptacion publica

La prueba versionada
`scripts/demo-world/demo-world-v2-authority-proof.json` procede de las tablas
normalizadas creadas por las RPC reales. Conserva solamente topologia y
evidencia deportiva no sensible:

- cinco jornadas y quince CanonicalMatches;
- fechas original y efectiva;
- local, visitante y sede publica;
- decisiones oficiales y marcador;
- lineage de R4D;
- StandingSnapshot;
- recuentos de recibos idempotentes por familia.

El adaptador publico sustituye UUID sinteticos y perfiles de simulacion por IDs
`demo_*` e identidades ficticias ya publicables. No cambia emparejamientos,
resultados, jornadas, incidencias ni clasificacion. Enriquece los read models
de presentacion con las plantillas ficticias de V1; esos datos no vuelven a
PostgreSQL ni compiten con la prueba de autoridad.

## Liga protagonista

`LIGA BARRIOS IQ 2026/27` contiene:

| Entidad | Conteo |
| --- | ---: |
| Competition / Edition / Category / Stage / Group | 1 cada una |
| Entries / Delegates / Rosters | 6 cada una |
| Rounds | 5 |
| CanonicalMatches | 15 |
| resultados oficiales | 15 |
| Clubs | 3 |
| perfiles arbitrales | 8 |

Los seis equipos proceden del mundo V1: Cobalto Raval, Circuit Poblenou,
Bruixola Sants, Onze del Clot, Marina Fosca y Ferro Sant Andreu.

La distribucion R4D es 11 partidos normales, uno de ellos con retraso resuelto
dentro del margen, un aplazamiento jugado en nueva fecha, un cambio de sede,
un no-show reglamentario y una suspension/reanudacion sobre el mismo
CanonicalMatch.

## Clasificacion

PostgreSQL produce el StandingSnapshot desde OfficialResultDecision. El
snapshot publico conserva esa salida. Un oracle TypeScript independiente
recalcula `PJ`, `G`, `E`, `P`, `GF`, `GC`, `DG` y `PTS` exclusivamente para QA;
si difiere, la exportacion falla con
`DEMO_WORLD_V2_POSTGRES_STANDINGS_ORACLE_MISMATCH`.

## Clubs y arbitros

Cada Club tiene dos equipos, un perfil publico y relaciones con arbitros. Los
ocho perfiles arbitrales son ficticios y aparecen como disponibles o con
disponibilidad limitada.

`refereeAssignmentsEnabled` permanece `false`: un arbitro publico no se asigna
a ningun partido ni adquiere autoridad deportiva.

## Perspectivas y navegacion

Las perspectivas `player`, `admin`, `free-agent` y `league-organizer` son
estado local de presentacion. Nunca crean ni suplantan Auth.

La shell unica de `/demo` permite Inicio, Partido, Mercado, Equipo, Perfil,
Liga, Clasificacion, Jornadas, Club y Arbitros. Liga, jornadas, partidos,
clasificacion, Club y arbitros reutilizan renderers productivos mediante modo
`embedded`; no existen componentes paralelos `DemoLeagueTable` o
`DemoLeagueMatch`.

## Contrato read-only y privacidad

El navegador publico permite solo `GET`. No importa un cliente Supabase ni
ejecuta RPC, `POST`, `PUT`, `PATCH` o `DELETE`. La interaccion de perspectiva y
las acciones heredadas de Demo usan exclusivamente `sessionStorage`; no hay
cola offline ni confirmacion deportiva falsa.

El snapshot no contiene emails, telefonos, tokens, Auth IDs, `service_role`,
evidencia privada, reporter IDs ni notas internas. Las ubicaciones son
ficticias o zonas publicas generales y no consultan Google Places.

## Integridad ejecutable

`assertDemoWorldV2Snapshot` y `tests/demo-world-v2.test.ts` verifican:

- namespaces y referencias V1 conservadas;
- grafo completo Competition-Edition-Stage-Group-Entry-Roster-Round-Match;
- quince IDs canonicos unicos;
- tres partidos por jornada;
- goleadores que suman exactamente el marcador;
- OfficialResultDecision y StandingSnapshot coherentes;
- lineage de aplazamiento, sede, no-show y suspension;
- relaciones Club-Team y Club-Referee;
- ausencia de assignments arbitrales;
- hash del snapshot y hash de autoridad;
- carga lazy y solo `GET`;
- ausencia de PII y de rutas de escritura.

## Regeneracion

- `npm run demo-world:v2:simulate`: crea una base temporal, aplica 141
  migraciones, ejecuta SQL/RLS y RPC reales, exporta prueba y snapshot y elimina
  la base.
- `npm run demo-world:v2:verify`: repite el mismo mundo y exige identidad exacta
  con los artefactos versionados.
- `npm run test:demo-world:v2`: valida contrato, hashes, autoridad, formulas,
  navegacion, privacidad, lazy loading y Service Worker.
