# Public Competition Read Models V1 - Implementation Report

## Estado

`RELEASE CANDIDATE / SAFE PROJECTIONS VERIFIED`

## Fuente de verdad

Las tablas `pachanga_public_competition_read_models` y
`pachanga_public_competition_fixture_read_models` son proyecciones derivadas.
No compiten con Competition, Edition, Entry, CanonicalMatch,
OfficialResultDecision, StandingSnapshot o bracket como fuente de verdad.

Los triggers de fuentes canonicas reconstruyen la entidad afectada y emiten
invalidacion. El cliente recibe revision/secuencia y vuelve a leer la RPC
canonica; nunca aplica un payload WAL como estado deportivo definitivo.

## Contratos de lectura

- `get_pachanga_public_competition_directory_v1`;
- `get_pachanga_public_competition_v1`;
- `get_pachanga_public_competition_calendar_v1`;
- `get_pachanga_public_competition_standings_v1`;
- `get_pachanga_public_competition_bracket_v1`;
- `get_pachanga_public_competition_sitemap_v1`;
- lecturas autenticadas de publication, solicitudes, queue y Control Center.

Las tablas no conceden lectura directa. Las RPC publicas retornan solo la
proyeccion reducida y las RPC privadas comprueban actor/capability.

## Seleccion canonica y cache

El read model persiste revision, server sequence y `updated_at`. La eleccion del
estado vigente no depende de `created_at` por si solo. Directorio y hubs pueden
cachearse y revalidarse; una mutacion invalida solo la Competition afectada.

PWA puede abrir snapshots cacheados de directorio, hub, calendario, standings
y bracket. Las escrituras permanecen online-only y sin cola deportiva offline.

## SEO y privacidad

Solo `public + published + approved + active` es indexable. Sitemap excluye
private, unlisted, drafts, pending, rejected, suspended y archived. Las rutas
unlisted usan `noindex, nofollow`.

La proyeccion publica no incluye roster, Attendance, contacto, Auth UUID,
evidencia, notas, fees, ubicacion exacta privada ni payload administrativo.

## Rendimiento con volumen

Rollback de carga representativa:

| Read model | Volumen | p95 |
| --- | ---: | ---: |
| Directory | 10000 competitions | `41.428 ms` |
| Public hub | 10000 competitions | `0.948 ms` |
| Calendar | 100000 fixtures/results | `0.380 ms` |
| Standings | snapshot canonico | `0.553 ms` |
| Bracket | snapshot canonico | `0.123 ms` |

## Staging y visual

League y Tournament reales del entorno efimero fueron leidos por sus contratos
publicos. Tournament con 32 fixtures, 32 resultados oficiales, cuatro grupos y
cuatro rondas de bracket permanecio `unlisted/noindex` y ausente de directorio y
sitemap. La matriz responsive final no encontro overflow raiz, imagenes rotas,
controles inaccesibles, warnings de hidratacion ni errores de consola.

