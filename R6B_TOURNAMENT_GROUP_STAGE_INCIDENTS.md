# R6B Tournament Group Stage Incident Ledger

## Checkpoint

- Date: `2026-08-27`
- Base: `7f46951fd4144985b05c8029606574b82c655b73`
- Branch: `codex/tournament-group-stage-match-tracking-v1`
- Production migration ledger: `163` (pending fresh linked readback)
- Scope: Tournament Group Stage, canonical group matches, tracking,
  qualification, bracket template and Demo World V2.5.
- Explicitly excluded: knockout match generation, bracket progression,
  champion resolution, public discovery and payments.

## Recording policy

Every failure found during R6B must be recorded here before correction and
classified as one of:

- `PRODUCT_BUG`
- `SIMULATION_BUG`
- `TESTABILITY_GAP`
- `ENVIRONMENT_ISSUE`
- `NEEDS_PRODUCT_DECISION`

After correction, the entry must include its regression and may only be marked
`FIXED / REGRESSION_VERIFIED` after the original scenario passes.

## Incidents

No R6B incident has been observed at checkpoint time.
