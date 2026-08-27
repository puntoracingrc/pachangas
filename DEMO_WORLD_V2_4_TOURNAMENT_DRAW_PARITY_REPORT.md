# Demo World V2.4 Tournament Draw Parity Report

## Version canonica

- Version: `2.4`.
- Seed: `pachangas-iq-demo-world-v2-4-2026-27`.
- Fecha sintetica: `2027-03-18T18:00:00.000Z`.
- Hash publico: `e3fa89f32278fac9d49eca3635ff19255a06f76b7cd65eff12b916c958c0141b`.
- Hash de autoridad PostgreSQL:
  `991173f97e638a5ac9d55764284f331d61fffc95c799b60850f156cda23f612f`.
- Migraciones simuladas: `163`.
- Escrituras remotas de Demo: `0`.

## Torneo sintetico

| Entidad | Cantidad |
| --- | ---: |
| Tournaments | 1 |
| Participantes | 16 |
| Grupos | 4 |
| Pots | 4 |
| DrawRevisions | 5 |
| Manual locks | 2 |
| Tournament matches | 0 |

El mundo ejecuta las RPC R6A reales en PostgreSQL temporal. Representa
SEEDED_POTS e HYBRID, locks, quality, seed/audit revelado y un caso
`DRAW_UNSATISFIABLE`. El snapshot publico no contiene actor Auth ni motivos
privados.

## Paridad

- un equipo de cada pot por grupo;
- dos equipos del mismo Club separados;
- seed y checksums reconstruibles;
- locks conservados en HYBRID;
- cero duplicados y cero ausencias;
- quality explicable;
- no hay endpoints Demo de escritura;
- chunks GET-only, lazy y versionados por hash;
- V2.1, V2.2 y V2.3 permanecen intactos.

## Gate local

| Gate | Resultado |
| --- | --- |
| `test:demo-world:v2` | `14/14 PASS` |
| `demo-world:v2:verify` | `PASS` |
| Snapshot reconstruido dos veces | `IDENTICO` |
| Tournament matches | `0` |
| Remote writes | `0` |
| Rating/Rewards/Conduct/Billing | `SIN CAMBIOS` |

El mismo snapshot canonico paso el smoke remoto de staging en `/demo` junto a
`/torneos`, `/torneos/crear`, `/laboratorio-tournament-draw`, manifest y Service
Worker. La Preview manual anterior no selecciono las variables Supabase
limitadas a la rama y fue reemplazada por una Preview Git exacta.

La Preview Git de reemplazo quedo `READY` en el commit exacto, cargo el ref de
staging correcto y devolvio HTTP 200 para Demo V2.4, manifest y Service Worker.
El smoke visual remoto no encontro overflow, imagenes rotas ni errores de
consola en desktop, portrait o Mobile Game Landscape.

## Producto

La superficie Demo permite consultar Tournament, Draw Desk, grupos, seeds,
quality y audit con el mismo contrato visual que el producto. No activa una
beta real, no concede grants y no simula partidos de Tournament.

La misma superficie se verifico en produccion con el SHA
`68dc360acf5dcce6cd7ffb6be4fa4b4d14d20cd7`: HTTP 200, cero imagenes rotas,
errores de consola, warnings de hidratacion u overflow raiz no intencional en
desktop, portrait y landscape. La navegacion offline de Demo desde el Service
Worker y la reconexion pasaron en navegador. La PWA instalada fisica permanece
pendiente y no se presenta como pasada.
