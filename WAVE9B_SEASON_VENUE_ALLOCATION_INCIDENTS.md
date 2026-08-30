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

### W9B-001 - npm audit reports preexisting dependency advisories

- Classification: `ENVIRONMENT_ISSUE`
- Status: `open / preexisting / non-blocking`
- Original reproducer: run `npm ci` on exact base
  `592a3dcc1147df41fb05c21703f131e66fc75a0a`.
- Impact: installation succeeds, but npm reports `18` advisories: `1` low,
  `4` moderate and `13` high. Wave 9B has not installed or changed a package.
- Required correction: do not run a broad or breaking `npm audit fix` inside
  this product slice. Keep `package.json` and `package-lock.json` unchanged,
  run the full product gates, and close this incident only after the final diff
  proves Wave 9B introduced zero dependency changes.

### W9B-002 - Baseline test result lost after output truncation

- Classification: `TESTABILITY_GAP`
- Status: `fixed + regression_verified`
- Original reproducer: run `npm test` through a bounded interactive command;
  the build and Node suite were visible, but the TS/TSX output exceeded the
  transport buffer and the completed process could no longer be queried.
- Impact: the exact baseline total and final exit code are not auditable from
  the first run, so it cannot be counted as a completed gate.
- Required correction: repeat the exact command while preserving full output
  in a temporary log, report only its parsed summary, then delete the log after
  the result is recorded in this ledger.
- Resolution: the rerun produced `20/20` Node tests and `679/679` TS/TSX tests,
  for an exact total of `699/699`; fail, cancelled, skipped and todo were all
  zero, the build passed, and the command returned exit code `0`.
- Regression verification: the complete output was retained until its two TAP
  summaries and exit code were parsed independently.

### W9B-003 - zsh wrapper used a reserved variable

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: capture the `npm test` exit code in a variable named
  `status` under `zsh`.
- Impact: `zsh` rejects the assignment because `status` is read-only, causing
  the wrapper to exit `1` without reporting the underlying test result.
- Required correction: use a non-reserved variable, rerun the exact test suite,
  and add a regression check that the wrapper reports both the TAP summary and
  the actual exit code.
- Resolution: the wrapper now uses `rc`, which is writable under `zsh`.
- Regression verification: the corrected wrapper reported both TAP summaries
  and `EXIT_CODE=0` in the same completed process.

### W9B-004 - Temporary log cleanup command rejected by tool policy

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: request `rm -f` for the isolated test log under `/tmp`.
- Impact: no product file or test result is affected, but the temporary log
  remains until removed through an accepted single-file cleanup operation.
- Required correction: remove the exact file with `unlink`, verify it no longer
  exists, and leave all repository evidence untouched.
- Resolution: removed only `/tmp/pachangas-wave9b-baseline-tests.log` with
  `unlink`.
- Regression verification: an independent existence check returned success for
  the file being absent.

### W9B-005 - Audit search included a non-existent source directory

- Classification: `ENVIRONMENT_ISSUE`
- Status: `fixed + regression_verified`
- Original reproducer: run the Wave 9B inventory search against `app`, `lib`,
  `supabase` and `tests` when this repository has no top-level `lib` directory.
- Impact: `rg` reported the missing directory while still returning the useful
  matches from the other roots; no product source was changed.
- Required correction: derive the source roots from the checkout and repeat the
  inventory only against directories that exist.
- Resolution: repeated the inventory against the verified roots `app`,
  `supabase` and `tests` only.
- Regression verification: the corrected search completed with exit code `0`
  and enumerated `342` relevant paths without missing-directory diagnostics.
