# Pachangas IQ Global Visual Consistency Audit V1

## Audit identity

- Initial `main`: `c85eb279dfe7043e680b6d1bb511bbf1b5359556`
- Branch: `codex/global-visual-consistency-premium-art-v1`
- Scope: frontend visual consistency, responsive behavior and laboratory art only
- Production changes: prohibited
- Backend contracts: read-only unless a visual bug proves a narrowly scoped dependency

## Classification

- `BUG_VISUAL`: visible defect or illegible state.
- `BUG_RESPONSIVE`: overflow, overlap, clipping or inaccessible action at a target viewport.
- `INCONSISTENCIA`: equivalent interactions use different visual or textual contracts.
- `DEUDA_ESTRUCTURAL`: duplicated or scattered implementation that increases drift risk.
- `MEJORA_OPCIONAL`: useful change without a current usability failure.
- `PREFERENCIA_ARTISTICA`: subjective proposal that requires review before product adoption.

Severity uses `P0` for blocked use, `P1` for a severe visual failure, `P2` for a notable inconsistency and `P3` for polish.

## Registered findings

Every issue below was registered before its corrective patch.

| ID | Route/surface | User mode | Viewport | Type | Severity | Description | Before evidence | After evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GVC-001 | `/equipo/identidad`, `/personalizar-carta` | visitor / disconnected | portrait, landscape | BUG_VISUAL | P1 | Raw infrastructure copy (`Supabase no está configurado`) reaches the user instead of a product error state. | Baseline screenshot + DOM copy | Pending | REGISTERED |
| GVC-002 | `/mercado` | visitor | all | BUG_VISUAL | P1 | `Google Places pendiente` is red technical implementation copy and looks like a user error. | Baseline screenshot + DOM copy | Pending | REGISTERED |
| GVC-003 | `/perfil/avisos` | visitor / loading | portrait, landscape | BUG_VISUAL | P2 | The page can become a large blank surface with only its header; no useful empty/loading/auth state is visible. | Baseline screenshot | Pending | REGISTERED |
| GVC-004 | `/equipo/identidad` | player without team | portrait, landscape | BUG_VISUAL | P2 | No-team state leaves most of the viewport empty and offers no clear primary next action. | Baseline screenshot | Pending | REGISTERED |
| GVC-005 | product editors | player/admin | all | INCONSISTENCIA | P2 | Player and team editors share the same interaction model but independently implement status, save feedback and page framing. | Source inventory | Pending | REGISTERED |
| GVC-006 | global interactive controls | mobile | portrait, landscape | BUG_RESPONSIVE | P2 | Several text links, lab swatches and compact controls expose touch boxes below the practical 40px floor. | Automated target metrics | Pending | REGISTERED |
| GVC-007 | `/laboratorio-cosmeticos-escudo` | lab | desktop | BUG_RESPONSIVE | P2 | The slot tab rail visibly clips its final options inside the editor instead of exposing a clear scroll affordance. | Baseline screenshot | Pending | REGISTERED |
| GVC-008 | `/mercado` game mode | visitor/member | 844x390 | BUG_RESPONSIVE | P2 | Dense player cards use two-line disabled actions and truncated metadata, reducing scanability in the most constrained mode. | Baseline screenshot | Pending | REGISTERED |
| GVC-009 | notifications and standalone tools | visitor/member | all | INCONSISTENCIA | P2 | Standalone operational pages do not share one page-header/empty-state/error-state contract. | Route comparison | Pending | REGISTERED |
| GVC-010 | global CSS | all | all | DEUDA_ESTRUCTURAL | P2 | Overlay layers use several unrelated z-index scales (`30`, `80`, `1150`, `1200`, `2000`) without a documented contract. | Static token inventory | Pending | REGISTERED |
| GVC-011 | player/team cosmetics | owner/admin | all | INCONSISTENCIA | P2 | `NEW` semantics are shared in data but size, placement and accessible announcement require one explicit UI contract. | Source and product comparison | Pending | REGISTERED |
| GVC-012 | demo landing | visitor/demo | 390x844 | BUG_VISUAL | P2 | Disabled Google authentication has weak contrast and can look like an enabled action whose label is faded. | Baseline screenshot | Pending | REGISTERED |
| GVC-013 | visual QA | all | all | DEUDA_ESTRUCTURAL | P2 | Existing automated browser QA covers the root shell only; critical standalone routes and editors can regress without detection. | `tests/adaptive-browser-smoke.mjs` | `scripts/visual-audit-v1.mjs` | FIXED_REGRESSION_PENDING |

## Audit matrix

Baseline local run (`before`):

| Metric | Result |
| --- | ---: |
| Route/user/viewport combinations | 54 |
| Non-intentional document overflows | 0 |
| Console errors | 0 |
| Console warnings | 0 |
| Broken images | 0 |
| Fixed/sticky viewport violations | 0 |
| Small-target samples | 452 |

The small-target total is diagnostic rather than a pass/fail count. It includes repeated controls across routes and desktop footer links. Product corrections prioritize mobile controls and repeated interactive patterns; inline desktop navigation is reviewed contextually instead of being enlarged blindly.

The canonical machine-readable matrix is generated with:

```bash
VISUAL_AUDIT_BASE_URL=http://127.0.0.1:3000 \
VISUAL_AUDIT_LABEL=before npm run audit:visual
```

It records route, user mode, viewport, overflow, browser errors, warnings, broken images, viewport violations and small touch targets. The final report will consolidate authenticated staging and PWA standalone evidence with this local matrix.

## Protected product contracts

- Rating V2, Season Score, TOPS and sporting facts are outside the write scope.
- The five active Team Cosmetic Reward mappings remain byte-for-byte unchanged.
- `PlayerCardView` and `TeamShieldView` remain the rendering authorities.
- Premium Ball stays `READY_PENDING_PHYSICAL_QA` and laboratory-only.
- Labs remain `noindex`, `nofollow` and outside normal navigation.
