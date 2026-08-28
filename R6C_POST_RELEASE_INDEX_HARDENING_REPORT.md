# R6C Post-release Index Hardening Report

## Estado

`PASS / ACTIONABLE FK DEBT 0`

## Metodo

Se revisaron las 13 tablas R6C y los avisos de FK sin indice registrados por
Supabase Advisors. No se crearon 71 indices a ciegas: cada FK se contrasto con
cardinalidad, prefijo de indices compuestos, filtros reales y `EXPLAIN` de los
flujos de bracket, node, match, reservation, slot y revision.

## Indices forward-only añadidos

1. `pachanga_tournament_reservation_schedule_slot_idx`
2. `pachanga_tournament_node_home_entry_idx`
3. `pachanga_tournament_node_away_entry_idx`
4. `pachanga_tournament_node_winner_entry_idx`
5. `pachanga_tournament_node_loser_entry_idx`
6. `pachanga_tournament_slot_resolved_entry_idx`
7. `pachanga_tournament_dependency_match_idx`

No se modificaron lifecycle, flags, resultados, progresion, formulas ni datos.
No se duplicaron indices cuyo prefijo ya cubria la FK.

## Resultado

| Comprobacion | Resultado |
| --- | --- |
| R6C actionable unindexed FK | `0` |
| Fresh bootstrap | PASS |
| Upgrade 176 -> 183 | PASS |
| Schema equivalence | PASS |
| Tournament regression | PASS |
| R6C authority/ACL regression | PASS |
| Scale y EXPLAIN focal | PASS |

La migracion es
`20260828072045_tournament_knockout_fk_index_hardening_v1.sql`, es
forward-only e idempotente mediante `create index if not exists`.

## Security Definer

Los entrypoints revisados mantienen `auth.uid()` resuelto en PostgreSQL,
`search_path` fijo, objetos cualificados y grants acotados. Los avisos que no
representaban una ruta insegura no se eliminaron reescribiendo funciones por
motivos cosmeticos. No se concede escritura directa a tablas deportivas.

