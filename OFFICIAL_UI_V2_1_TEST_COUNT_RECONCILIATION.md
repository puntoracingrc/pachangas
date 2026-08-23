# Official UI V2.1 Test Count Reconciliation

## Scope

- Base audited: `origin/main` at `a4f2468d9b779db6a4391df7cec4cc34e4162fbe`.
- Starting branch HEAD audited: `a1b6f5223f6d2ec70e390073aa2a030755732b28`.
- Closing code HEAD revalidated: `d1b44b4490f943a0e4f0792a392e0380ef845589`.
- Date: 2026-08-23 (CEST).
- Command: `npm test`, preserving the complete TAP output for each revision.

`npm test` runs two independent TAP runners after the production build. The
summary printed by the final TSX runner is therefore not the total for the
whole command; the canonical total is the sum of both successful runners.

## Reconciliation

| Revision | Node runner | TSX runner | Canonical total | Failed | Skipped | Todo | Cancelled |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `origin/main` | 20 | 343 | 363 | 0 | 0 | 0 | 0 |
| V2.1 starting and closing code HEADs | 20 | 354 | 374 | 0 | 0 | 0 | 0 |

The Node runner contains:

- `tests/rendered-html.test.mjs`;
- `tests/database-bootstrap.test.mjs`;
- `tests/player-card-cosmetics-lab.test.mjs`.

The TSX runner contains the TypeScript suites listed explicitly in
`package.json`.

## Delta

| File | Change | Tests added | Tests removed |
| --- | --- | ---: | ---: |
| `tests/official-ui-v2-1.test.ts` | New suite | 10 | 0 |
| `tests/demo-world-v1.test.ts` | Responsive regression | 1 | 0 |
| Other modified test files | Assertions and compatibility adjustments | 0 | 0 |
| **Total** |  | **11** | **0** |

The V2.1 branch does not remove a test suite from the `npm test` command.

## Canonical Result

- Tests lost: **0**.
- Failed: **0**.
- Skipped/todo/cancelled: **0**.
- Canonical V2.1 total: **374/374 PASS**.
- Breakdown: **20/20 Node + 354/354 TSX**.

Any earlier `354/354` statement described only the final TSX runner. It was
not a valid representation of the complete `npm test` total.
