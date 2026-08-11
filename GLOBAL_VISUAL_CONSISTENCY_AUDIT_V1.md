# Pachangas IQ Global Visual Consistency Audit V1

## Audit identity

- Initial `main`: `c85eb279dfe7043e680b6d1bb511bbf1b5359556`
- Branch: `codex/global-visual-consistency-premium-art-v1`
- Local audit completed: `2026-08-11 09:50:19 CEST`
- Scope: frontend visual consistency, responsive behavior and laboratory art only
- Production changes: none
- Supabase changes: none
- Backend contracts: unchanged
- Baseline evidence commit: `96c4400` (`Add visual consistency audit baseline`)

## Classification

- `BUG_VISUAL`: visible defect or illegible state.
- `BUG_RESPONSIVE`: overflow, overlap, clipping or inaccessible action at a target viewport.
- `INCONSISTENCIA`: equivalent interactions use different visual or textual contracts.
- `DEUDA_ESTRUCTURAL`: duplicated or scattered implementation that increases drift risk.
- `MEJORA_OPCIONAL`: useful change without a current usability failure.
- `PREFERENCIA_ARTISTICA`: subjective proposal that requires review before product adoption.

Severity uses `P0` for blocked use, `P1` for a severe visual failure, `P2` for a notable inconsistency and `P3` for polish.

## Visual inventory

| Pattern | Current product implementation | V1 contract owner / decision |
| --- | --- | --- |
| Page headers | Root hero, game top rail and standalone tool headers | Preserve domain hierarchy; standalone tools share state/feedback rather than one forced shell |
| Primary navigation | Desktop root actions, portrait bottom nav, landscape top rail | Existing destinations and responsive switch remain authoritative |
| Context navigation | Partido and Mercado left submenus, editor tabs | Segmented navigation with active semantics; not styled as primary CTAs |
| Buttons | Global product buttons plus compact game/editor variants | Primary/secondary/ghost/danger/disabled contract; 40px touch floor |
| Cards and panels | Match/player/ranking/market cards and operational panels | One surface and border per entity; no new cards-inside-cards |
| Chips and badges | Status/filter chips, role labels and cosmetic `NEW` | State stays descriptive; shared accessible `NewBadge` owns `NEW` semantics |
| Inputs/selectors | Match editor, Mercado filters, cosmetic controls | Visible labels, stable 40-44px touch geometry, readable disabled state |
| Modals/drawers | Account sheet, pitch/photo/status/reward/update overlays | Documented global overlay scale and safe-area close action |
| Toast/feedback | Existing local confirmations plus new shared product feedback | `ProductFeedback` owns corrected standalone save/error feedback |
| Empty/loading/error | Previously route-specific or absent | `ProductState` owns corrected standalone operational states |
| Notifications | Preferences route and global notification UI | Explicit service/loading/auth/error/empty states; notification business logic unchanged |
| Player editor | `/personalizar-carta` | `PlayerCardView` remains renderer; shared states, feedback and `NEW` |
| Team editor | `/equipo/identidad` | `TeamShieldView` remains renderer; shared states, feedback and `NEW` |
| Cards/shields/rankings | Root product, Mercado and laboratories | Existing renderers and sporting read models; no scoring rewrite |
| Premium laboratory | `/laboratorio-premium-art-pack` | Review-only catalog, noindex/nofollow, no ownership or mapping writes |

## Registered findings

Every finding was recorded before its corrective patch. `FIXED_REGRESSION_VERIFIED` means the active path was corrected and is covered by a focused test, the final browser matrix, or both. `MITIGATED` means the immediate product risk is removed while a deliberately bounded structural debt remains.

| Findings | P0 | P1 | P2 | P3 | Fixed and verified | Mitigated | Open |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 20 | 0 | 3 | 17 | 0 | 18 | 1 | 1 |

| ID | Route/surface | User mode | Viewport | Type | Severity | Description | Correction and evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GVC-001 | `/equipo/identidad`, `/personalizar-carta` | visitor / disconnected | portrait, landscape | BUG_VISUAL | P1 | Raw infrastructure copy (`Supabase no está configurado`) reached the user. | Shared product state and `userFacingError`; focused test plus `after` captures. | FIXED_REGRESSION_VERIFIED |
| GVC-002 | `/mercado` | visitor | all | BUG_VISUAL | P1 | `Google Places pendiente` exposed implementation detail as a user error. | Neutral `Ciudad o zona` copy and sanitized failures; focused test and matrix. | FIXED_REGRESSION_VERIFIED |
| GVC-003 | `/perfil/avisos` | visitor / loading | portrait, landscape | BUG_VISUAL | P2 | The page could become a blank surface with only its header. | Explicit loading, signed-out, unavailable, error and empty states; `after/avisos-*`. | FIXED_REGRESSION_VERIFIED |
| GVC-004 | `/equipo/identidad` | player without team | portrait, landscape | BUG_VISUAL | P2 | The no-team state was mostly empty and lacked a primary action. | Actionable no-team/unavailable states using the shared state component; `after/equipo-identidad-*`. | FIXED_REGRESSION_VERIFIED |
| GVC-005 | product editors | player/admin | all | INCONSISTENCIA | P2 | Player and team editors independently implemented status and feedback. | Shared state/feedback contract adopted without forcing identical domain navigation. | FIXED_REGRESSION_VERIFIED |
| GVC-006 | global interactive controls | mobile | portrait, landscape | BUG_RESPONSIVE | P2 | Repeated controls exposed touch boxes below the practical 40px floor. | Compact target token plus route-specific corrections; final mobile counts are zero. | FIXED_REGRESSION_VERIFIED |
| GVC-007 | `/laboratorio-cosmeticos-escudo` | lab | desktop/mobile | BUG_RESPONSIVE | P2 | The slot rail clipped final options without a clear affordance. | Scrollable rail, stable padding and 40px controls; lab captures and matrix. | FIXED_REGRESSION_VERIFIED |
| GVC-008 | `/mercado` game mode | visitor/member | 844x390 | BUG_RESPONSIVE | P2 | Dense cards used oversized disabled actions and truncated scan data. | Compact game-mode cards, labels and filters; `after/mercado--landscape.jpg`. | FIXED_REGRESSION_VERIFIED |
| GVC-009 | notifications and standalone tools | visitor/member | all | INCONSISTENCIA | P2 | Standalone tools lacked one error/empty/loading contract. | `ProductState` and `ProductFeedback` shared across the corrected operational pages. | FIXED_REGRESSION_VERIFIED |
| GVC-010 | global CSS | all | all | DEUDA_ESTRUCTURAL | P2 | Overlay layers mixed unrelated z-index scales without a contract. | Global overlay tokens now document and own principal nav/modal/reward/update/lab layers. Local component stacking remains numeric and isolated. | MITIGATED |
| GVC-011 | player/team cosmetics | owner/admin | all | INCONSISTENCIA | P2 | `NEW` semantics needed one size, placement and announcement contract. | Shared accessible `NewBadge` and editor controls; focused cosmetics tests. | FIXED_REGRESSION_VERIFIED |
| GVC-012 | demo landing | visitor/demo | 390x844 | BUG_VISUAL | P2 | Disabled Google authentication looked weak and ambiguous. | Explicit disabled contrast and stable dimensions; final portrait/PWA matrix. | FIXED_REGRESSION_VERIFIED |
| GVC-013 | visual QA | all | all | DEUDA_ESTRUCTURAL | P2 | Browser QA covered the root shell but not critical standalone routes. | New 26-surface matrix with persistent machine-readable evidence. | FIXED_REGRESSION_VERIFIED |
| GVC-014 | visual QA cleanup | internal QA | all | DEUDA_ESTRUCTURAL | P2 | Chrome could finish results and still fail cleaning temporary LevelDB. | Process-close wait plus retrying cleanup; repeated 172-row runs exit zero. | FIXED_REGRESSION_VERIFIED |
| GVC-015 | Partido and Mercado subpanes | demo admin/player | all | DEUDA_ESTRUCTURAL | P2 | Route-only automation missed stateful subpanes under the same URL. | Exact-selector actions and active-state verification for Alineación, Resultado, Admin, Partidos and Retos. | FIXED_REGRESSION_VERIFIED |
| GVC-016 | Partido pitch | mobile portrait | 360x800, 390x844 | BUG_RESPONSIVE | P2 | Pitch zoom and player tokens exposed 30-34px touch widths. | Stable 40px pitch controls/tokens; portrait, small portrait and PWA counts are zero. | FIXED_REGRESSION_VERIFIED |
| GVC-017 | visual QA theme fixture | internal QA | all | DEUDA_ESTRUCTURAL | P2 | Applying theme before hydration created a harness-only hydration mismatch. | Theme fixture now applies after hydration; final console errors/warnings are zero. | FIXED_REGRESSION_VERIFIED |
| GVC-018 | visual QA subpane actions | internal QA | all | DEUDA_ESTRUCTURAL | P2 | Text-only actions could select global Admin and captures could preserve compositor scroll. | Scoped selectors, active-state assertion, two-frame scroll reset and viewport-only capture. | FIXED_REGRESSION_VERIFIED |
| GVC-019 | shared product errors | disconnected visitor/member | all | BUG_VISUAL | P1 | Browser wording `Failed to fetch` used the inverse word order of the sanitizer pattern and could escape as raw technical copy. | Both word orders and common network wording are sanitized; focused regression test. | FIXED_REGRESSION_VERIFIED |
| GVC-020 | Google Places inputs | authenticated Preview | desktop/mobile | DEUDA_ESTRUCTURAL | P2 | The remote Google library warned that the active `google.maps.places.Autocomplete` widget is legacy and unavailable to new customers. | Registered from exact-SHA Preview console before correction. Migration and remote regression pending. | OPEN |

## Final matrix

The canonical final evidence is:

- `artifacts/visual-audit-v1/after/results.json`
- `artifacts/visual-audit-v1/after/matrix.md`
- `artifacts/visual-audit-v1/after/*.jpg`
- `artifacts/visual-audit-v1/after/premium-art-pack-contact-sheet.jpg`

| Coverage | Result |
| --- | ---: |
| Surface states | 26 |
| Route pathnames | 14 |
| User/display modes | 7 |
| Viewport/accessibility contexts | 10 |
| Total combinations | 172 |
| Horizontal overflows | 0 |
| Console errors | 0 |
| Console warnings | 0 |
| Broken images | 0 |
| Failed requests | 0 |
| Navigation/action failures | 0 |
| Fixed/sticky viewport violations | 0 |
| Game chrome controls clipped | 0 |

Covered modes are demo admin, demo player, visitor, visitor without team, laboratory, forced light and forced dark. Covered contexts are 1440x900, 1920x1080, 390x844, 360x800, 844x390, simulated standalone PWA, 125%, 150%, 200% effective zoom and reduced motion.

### Touch target evidence

| Context | Samples below 40px |
| --- | ---: |
| 390x844 portrait | 0 |
| 360x800 small portrait | 0 |
| 390x844 standalone PWA | 0 |
| 844x390 game mode | 0 |
| 1440x900 desktop | 137 |
| 1920x1080 desktop | 137 |
| 125% / 150% / 200% effective zoom | 25 / 24 / 11 |

The desktop/zoom samples are diagnostic, not mobile touch failures: they are fine-pointer inline links and local compact controls. Zoom validation passed the blocking criteria of no clipping, horizontal overflow, broken navigation, viewport escape or hidden action. Future conversion of every desktop inline link into a 40px box would be a product-density decision, not a correctness repair.

## Game Mode / Landscape UX

### What already worked

- The 844x390 layout is a real alternate composition with a stable top rail and contextual left submenu.
- Alineación correctly gives the horizontal pitch visual priority and uses the existing card/shield renderers.
- Partido and Mercado keep separate scroll owners rather than forcing document-level horizontal scroll.
- The dark tactical background, team colors and lime action accent read as the same product.

### What was corrected

- Partido Alineación and Admin controls now keep the 40px compact touch floor.
- The final `Cerrar` tool no longer escapes the lower viewport edge.
- Pitch zoom and player tokens no longer expose 30-34px touch geometry.
- Mercado player cards, filters and disabled actions are denser without removing information architecture.
- Stateful subpanes are now separate automated surfaces, and screenshots retain the top rail/context consistently.

### Deliberate limits

- No navigation architecture or full game-mode redesign was introduced.
- Next.js's circular development indicator appears in local captures only; it is not application UI and must be absent in the Vercel Preview build.

## PWA, themes and motion

- Standalone PWA is exercised with `display-mode: standalone` at 390x844 using the same safe-area and viewport tokens as the app.
- Browser/PWA layout, bottom navigation and final scroll reachability pass without horizontal overflow or clipped fixed controls.
- Existing Service Worker/update behavior was not rewritten; this is a visual pass and does not create offline sporting writes.
- Forced light and dark fixtures complete without hydration warnings. Premium materials retain their renderer-owned identity.
- Reduced-motion runs complete without browser errors; the contract requires player/shield effects to become static.

## Demo and cosmetics

- Demo admin and demo player modes are both exercised. The current demo remains a visual fixture; no Demo World or guided tutorial was added.
- Player and Team Cosmetics now share unavailable/error/feedback and accessible `NEW` behavior without flattening their different layer models.
- Long-form card/shield diversity is represented in the Premium Art contact sheet through current renderer components and synthetic labels.
- The five active Team Cosmetic Reward mappings remain unchanged and are checked by the focused test suite.

### Before and after

The baseline contains 54 combinations and is preserved under `artifacts/visual-audit-v1/before/`. The final pass expands the same evidence model to 172 combinations. Representative comparisons:

| Surface | Before | After |
| --- | --- | --- |
| Mercado landscape | `before/mercado--landscape.jpg` | `after/mercado--landscape.jpg` |
| Player cosmetics portrait | `before/personalizar-carta--portrait.jpg` | `after/personalizar-carta--portrait.jpg` |
| Team identity portrait | `before/equipo-identidad--portrait.jpg` | `after/equipo-identidad--portrait.jpg` |
| Notifications landscape | `before/avisos--landscape.jpg` | `after/avisos--landscape.jpg` |
| Shield lab desktop | `before/lab-escudos--desktop.jpg` | `after/lab-escudos--desktop.jpg` |

## Reproduction

```bash
VISUAL_AUDIT_BASE_URL=http://127.0.0.1:3000 \
VISUAL_AUDIT_OUTPUT=artifacts/visual-audit-v1 \
VISUAL_AUDIT_LABEL=after npm run audit:visual
```

Focused reruns can use comma-separated `VISUAL_AUDIT_VIEWPORTS` and `VISUAL_AUDIT_SURFACES` keys. Screenshots capture only the visible viewport; the premium art contact sheet deliberately captures the complete laboratory page.

## Validation gates

- Focused product/visual suite: **33/33 passing**.
- Full `npm test`: **passing**, including the production build, **227/227 TypeScript tests** and **20/20 Node tests**.
- Typecheck: **passing** with `tsc --noEmit --incremental false`.
- Focused ESLint on all new and corrected TypeScript/JavaScript routes except Mercado: **passing with zero findings**.
- Mercado focused ESLint: two pre-existing `react-hooks/set-state-in-effect` findings and one pre-existing `no-img-element` warning. The affected state-setting structure and image were already present in initial `main`; this pass changes only neutral copy and error sanitization around them.
- Final browser matrix: **172/172 combinations completed**, with zero horizontal overflow, console errors, console warnings, failed images, failed requests, navigation failures, viewport escapes or clipped game controls.
- Asset budget: **13 dedicated assets / 52,702 bytes**, with no GLB, Three.js or permanent WebGL runtime.
- Final branch scope: **112 changed paths** versus initial `main`, including baseline/final evidence and delivery assets.
- `git diff --check`: **passing** immediately before publication.

## Remaining visual debt

- GVC-010 remains intentionally `MITIGATED`: local z-index values inside a card/shield/reward composition are not global overlay layers and were not flattened into the application scale.
- The PWA context is a browser `display-mode: standalone` simulation. Physical iOS and Android sensor/browser chrome behavior is outside this frontend-only pass.
- Authenticated Supabase mutations were not exercised; demo admin/player and disconnected/no-team states were used to avoid backend or production changes.
- The Premium Art Pack is a laboratory proposal. No reviewed art has been wired to reward ownership or production catalog rows.

## Protected product contracts

- Rating V2, Season Score, TOPS and sporting facts are outside the write scope.
- The five active Team Cosmetic Reward mappings remain unchanged and are asserted by test.
- `PlayerCardView` and `TeamShieldView` remain the rendering authorities.
- Premium Ball stays `READY_PENDING_PHYSICAL_QA` and laboratory-only.
- Labs remain `noindex`, `nofollow` and outside normal navigation.
