# Official UI V2.1 Evidence Inventory

## Before Hygiene

Measured at branch HEAD `c6733f6cb39c950ff70c590c5a6072e562554ea7`
before authenticated staging evidence was added.

| Measure | Value |
| --- | ---: |
| PR diff paths | 278 |
| Sum of blobs in PR diff | 20,339,580 bytes |
| Files under `docs/official-ui-v2-1` | 249 |
| Bytes under `docs/official-ui-v2-1` | 19,372,386 |
| Raw capture files | 243 |
| Raw capture bytes | 15,095,379 |
| Contact sheets | 6 |
| Contact-sheet bytes | 4,277,007 |

The SHA-256 inventory found 21 exact duplicate portrait/PWA pairs. The wider
matrix also contained intermediate viewport passes already represented by the
machine-readable matrices and contact sheets.

## Removal

- Removed raw files: 179.
- Removed raw bytes: 9,400,725.
- Exact duplicates removed: all 21 identified duplicate pairs lost their
  redundant PWA copy.
- Removed categories: replaced viewport repetitions, intermediate passes and
  raw fixture frames already summarized in final contact sheets.
- No product code, report, matrix, JSON result, final contact sheet or
  authenticated staging capture was removed.

The contact-sheet generator now copies an explicit allowlist instead of
repopulating every raw capture on the next run.

## After Hygiene

Measured after adding the canonical staging matrix and rebuilding the
authenticated contact sheet.

| Measure | Value |
| --- | ---: |
| Files under `docs/official-ui-v2-1` | 93 |
| Bytes under `docs/official-ui-v2-1` | 10,109,744 |
| Capture files | 86 |
| Capture bytes | 6,720,376 |
| Canonical authenticated staging captures | 18 |
| Canonical authenticated staging bytes | 1,018,575 |
| Contact sheets | 6 |
| Contact-sheet bytes | 3,387,156 |

The final Git diff size is recalculated after the closing commit; the PR body
is the authoritative location for that final number because the commit cannot
contain its own blob accounting.

## Retained Evidence

- Six final contact sheets.
- Full Markdown/JSON matrices and rotation results.
- Representative desktop, portrait and low-landscape images.
- Owner/player/offline fixture images labelled as fixtures.
- Eighteen canonical staging images without PII: nine no-team/no-profile and
  nine owner/base-shield/configured-shield captures.
- Regression and performance summaries.
