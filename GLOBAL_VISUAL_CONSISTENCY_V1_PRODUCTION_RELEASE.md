# Global Visual Consistency V1 - Production Release

## Release identity

- Release date: 2026-08-11 (Europe/Madrid)
- Initial `main`: `c85eb279dfe7043e680b6d1bb511bbf1b5359556`
- PR: [#138](https://github.com/puntoracingrc/pachangas/pull/138)
- Exact PR HEAD audited: `e083561c314659f0b1c2567b8ea8bb1c8733ce37`
- PR base audited: `c85eb279dfe7043e680b6d1bb511bbf1b5359556`
- Merge commit and final functional `main`: `52dc831e0bb7120a939f200290af199d52ab3a02`
- Vercel production deployment: `5847642367`
- Deployment URL: `https://pachangas-7rjyoensy-persianas-almar-web-s-projects.vercel.app`
- Canonical production URL: `https://pachangasiq.com`

The PR remained directly based on the current `main`, was `MERGEABLE` and `CLEAN`, and was marked ready only after the final local and Preview gates passed.

## Technical gates

| Gate | Result |
| --- | --- |
| `npm test` | PASS, 227/227 tests |
| `npm run typecheck` | PASS |
| `npm run build` | PASS, 31 application routes generated |
| Focused lint for the new and migrated surfaces | PASS |
| `git diff --check origin/main...HEAD` | PASS |
| Initial and pre-merge `git status` | Clean |
| Vercel Preview checks | PASS |
| Vercel production deployment | SUCCESS |

`app/mercado/page.tsx` retains two pre-existing `react-hooks/set-state-in-effect` errors and one pre-existing `@next/next/no-img-element` warning. They were isolated and reproduced during this release; they are not introduced by the visual-consistency diff and are not hidden as a clean global lint result.

## Preview validation

The exact PR HEAD was exercised in the authenticated Vercel Preview at:

`https://pachangas-ptfvcyxo0-persianas-almar-web-s-projects.vercel.app`

Validated geometries:

- Desktop: `1440x900`
- Mobile portrait: `390x844`
- Mobile landscape/game mode: `844x390`
- PWA standalone: exact same production build and HEAD, `390x844`, through the CDP visual auditor

Preview Deployment Protection prevented the separate CDP browser used by the standalone auditor from consuming the protected Preview URL. Therefore the standalone matrix ran against the exact locally built HEAD, while the Preview `manifest.webmanifest` and `sw.js` were checked directly through Vercel's authenticated bypass and both returned HTTP 200. Nine standalone surfaces passed with zero console errors, warnings, broken images, horizontal overflow, small targets or game-chrome violations.

## Routes and states checked

| Surface | Desktop | Portrait | Landscape | Production |
| --- | ---: | ---: | ---: | ---: |
| `/` and demo Inicio | PASS | PASS | PASS | PASS |
| Mercado | PASS | PASS | PASS | PASS |
| Partido / Proximo | PASS | PASS | PASS | PASS |
| Partido / Alineacion | PASS | PASS | PASS | PASS |
| Partido / Resultado | PASS | PASS | PASS | PASS |
| Partido / Admin | PASS | PASS | PASS | PASS |
| Avisos | PASS | PASS | PASS | PASS |
| `/personalizar-carta` | PASS | PASS | PASS | PASS |
| `/equipo/identidad` | PASS | PASS | PASS | PASS |
| `/laboratorio-premium-art-pack` | PASS | N/A | N/A | PASS |

The authenticated demo contained complete teams and match history. The four match submenus selected the expected state in landscape game mode. Across the requested production surfaces there were zero runtime console errors, zero broken images and zero document-level horizontal overflow.

## PWA and Google Places

- Production manifest: HTTP 200.
- Production Service Worker: HTTP 200, registered, active and controlling the page.
- Manifest display mode remains `fullscreen` with `standalone`, `minimal-ui` and `browser` fallbacks.
- Mobile navigation remains available without overflow in portrait and landscape.
- Mercado renders `gmp-place-autocomplete` in desktop, portrait and landscape.
- No Google Places technical warning appeared in Preview or production on the migrated surfaces.

## Protected contracts

The five active Team Cosmetic Reward mappings remain exactly:

1. `team.external.wins.001` -> `team.shield.border.copper`
2. `team.external.matches.010` -> `team.shield.ornament.banner`
3. `team.matches.025` -> `team.shield.ornament.laurels`
4. `team.matches.050` -> `team.shield.border.silver`
5. `team.external.clean_sheets.001` -> `team.shield.effect.edge_glow`

Premium Ball remains `READY_PENDING_PHYSICAL_QA` and inactive. It is not present in the production renderer or migrations.

The Premium Art Pack contains 29 bounded proposals. They enter production only as optimized assets and a `noindex,nofollow` laboratory outside normal navigation. No proposal becomes a reward, owned item, entitlement, active catalog entry or sporting modifier.

Rating V2, Team Rewards, Player Cosmetics and Team Cosmetics remain intact. The full test suite passed after integration, no rating formula, facet, assessment, vote or evidence contract was changed, and no sporting data is derived from cosmetics.

## Incidents and scope

- No release-blocking product incident was found.
- One browser automation evaluation timed out while traversing production; the tab remained healthy and the four match states were revalidated individually.
- The intentional cropped brand mark extends slightly beyond its own visual box, but never expands the document width or creates horizontal scrolling.
- No Supabase project, schema, data, migration, RPC, RLS policy or environment was touched in this release.

## Final result

PR #138 was merged, Vercel completed the production deployment, and `pachangasiq.com` was verified against the deployed functionality. Global Visual Consistency V1 is released without activating any new economy or sporting behavior.
