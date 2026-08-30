# Wave 9B Season Venue Allocation Incidents

Fecha de apertura: 2026-08-30 CEST

## Checkpoint

- base: `592a3dcc1147df41fb05c21703f131e66fc75a0a`;
- rama: `codex/recurring-venue-bulk-allocation-v1`;
- ledger productivo inicial: `220`;
- tests iniciales conocidos: `699/699`;
- entidades reales permitidas: `0`;
- Stripe y Live Checkout: `UNTOUCHED / OFF`;
- PR excluidos: `#6`, `#131`, `#132`;
- checkout compartido: sucio y preservado, sin incorporar sus cambios.

## Politica

Todo fallo encontrado se registra antes de corregirse como `PRODUCT_BUG`,
`SIMULATION_BUG`, `TESTABILITY_GAP`, `ENVIRONMENT_ISSUE` o
`NEEDS_PRODUCT_DECISION`. Tras la correccion debe incluir el escenario original
y quedar en `fixed + regression_verified`.

No se corrigen silenciosamente errores de SQL, simulacion, producto, QA,
migracion, release o cleanup.

## Incidencias

Ninguna en el checkpoint inicial.
