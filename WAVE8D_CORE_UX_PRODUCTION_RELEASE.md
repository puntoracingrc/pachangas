# Wave 8D Core UX Production Release

## Release record

- Initial `main`: `a3e5abe7ab37d21f4b3f10edcb6de7d5504979bd`.
- Functional commit: `63b60da7cde9ad71ee0906f82013392678f51973`.
- Functional PR: [#232](https://github.com/puntoracingrc/pachangas/pull/232), merged.
- Production release `main`: `dda599b0640e964663adbeb6149cedf42fe14387`.
- Vercel deployment: `dpl_HaHPEHZEXS3Dz6BTM34YqKgn4Rea`, `READY`.
- Deployment URL: `https://pachangas-b0650rdf1-persianas-almar-web-s-projects.vercel.app`.
- Production aliases: `https://pachangasiq.com` and `https://www.pachangasiq.com`.
- Supabase project verified read-only: `qonbngfrnrqgmxbdfbea` (`Pachangas`).
- Supabase migrations created/applied by Wave 8D: 0 / 0.
- Supabase ledger: 212 local and 212 remote, with 0 local-only, 0 remote-only, and 0 mismatches.

## Gates

| Gate | Result |
| --- | --- |
| `npm ci` | PASS |
| Node tests | 20/20 |
| TS/TSX tests | 662/662 |
| Total | 682/682 |
| Skipped / todo / cancelled | 0 / 0 / 0 |
| Typecheck | PASS |
| Build | PASS, 62 static pages |
| Global lint | 0 errors / 0 warnings |
| `git diff --check` | PASS |
| Preview visual QA | PASS on desktop, portrait, and landscape |
| Axe | 0 violations on seven representative surfaces |
| Secret scan | PASS |

## Production verification

The exact merged SHA was checked on the public domain at `1440x900`,
`390x844`, and `844x390`. The smoke covered the official home, Demo home,
Mercado, Partido, Competiciones, Clubs, organizer access, referee profile,
referee assignments, notifications, and the guided-review tour.

All 11 surfaces returned coherent navigation, 0 root overflow, 0 broken
images, and 0 fresh console warnings or errors. HTTP runtime traffic observed
after deployment contained only `200` and `304` responses. Vercel reported 0
runtime error clusters and 0 warning/error runtime log entries for the release
deployment.

## PWA and offline contract

- Manifest: `200`, installable, `display: fullscreen`, with `standalone`,
  `minimal-ui`, and `browser` fallbacks.
- Service Worker: `200`, `Cache-Control: no-cache, no-store, must-revalidate`.
- Productive worker version: `2.0.0+sw.dda599b0640e`.
- Demo V3.3 manifest and app shell are precached.
- `/api`, `/auth`, Supabase, Stripe, Google, non-GET requests, and URL-bearing
  private navigation are excluded from runtime caching.
- Offline writes remain unconfirmed and are never queued as sporting success;
  reconnection reloads canonical state. This is covered by the PWA bridge and
  product-domain regressions.
- Physical Android, iPhone, and installed-PWA QA remain `PENDING` and were not
  represented as passed.

## Authority and privacy invariants

- V3.2 authority hash remains
  `763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1`.
- Demo V3.3 publishes 8 guided tours, `remoteWrites: 0`, no Auth IDs, and no PII.
- Rating, rewards, player/team cosmetics, conduct, billing, standings,
  brackets, discipline, referee statistics, and Team Operational State are
  unchanged.
- Real entities used: 0. External notifications: 0. Stripe operations: 0.
  Live Checkout remains OFF.

## Final delivery

| # | Item | Result |
| ---: | --- | --- |
| 1 | Initial main | `a3e5abe7ab37d21f4b3f10edcb6de7d5504979bd` |
| 2 | Final functional main | `dda599b0640e964663adbeb6149cedf42fe14387` |
| 3 | PRs | Functional PR #232 merged; this report is merged separately as documentation-only closure |
| 4 | Migrations created | 0 |
| 5 | Ledger | 212/212, no drift |
| 6 | Demo/official audit | Completed in `OFFICIAL_DEMO_V3_2_PARITY_AUDIT.md` |
| 7 | Previous navigation | Duplicated technical/domain destinations documented |
| 8 | Final navigation | Canonical and role-aware |
| 9 | Roles | Player, owner, free agent, organizer, referee, Club organizer, and reviewer contexts covered |
| 10 | Role-aware Home | Active |
| 11 | Primary action | One canonical next action per context |
| 12 | Context selector | Unified |
| 13 | Desktop | Stable at 1440x900 and 1920x1080 |
| 14 | Portrait | Stable at 390x844 and 360x800 |
| 15 | Landscape | Stable at 667x375, 740x360, 844x390, and 932x430 |
| 16 | Deep links | Stable |
| 17 | Rotation | URL/context state preserved by contract and viewport QA |
| 18 | Visual states | Unified named state system active |
| 19 | Offline | Read-only fallback; no authoritative offline queue |
| 20 | Permissions | Role-aware visibility; server authority unchanged |
| 21 | Feature disabled | Canonical disabled state active |
| 22 | Feedback | One shared canonical feedback component |
| 23 | `app/page` refactor | Conservative stabilization completed |
| 24 | Mercado refactor | URL hydration and navigation stabilized |
| 25 | `legal-data` refactor | Lint-safe without behavior change |
| 26 | Previous lint | 22 errors + 18 warnings |
| 27 | Final lint | 0 errors + 0 warnings |
| 28 | Accessibility | Axe: 0 violations on seven representative surfaces |
| 29 | Keyboard | Focus/controls reviewed in representative surfaces |
| 30 | Contrast | Light/dark representative surfaces reviewed |
| 31 | Performance | Demo loads current plus adjacent checkpoint only |
| 32 | Hydration | Mercado direct links, history, and restoration pass |
| 33 | PWA | Manifest and versioned Service Worker live; physical install pending |
| 34 | Demo V3.3 | Live |
| 35 | Tours | 8 active guided reviews |
| 36 | Perspectives | Published role perspectives normalized and restorable |
| 37 | Shareable URL | Tour, checkpoint, week, competition, surface, and view state supported |
| 38 | V3.2 authority hash | Preserved |
| 39 | Tests | 682/682 |
| 40 | Typecheck | PASS |
| 41 | Build | PASS |
| 42 | Lint | PASS, 0/0 |
| 43 | Visual QA | PASS locally, exact Preview, and production |
| 44 | Contact sheets | Five redacted sheets committed under `docs/wave8d/` |
| 45 | Staging | No authenticated staging branch required; exact protected Preview used |
| 46 | Production smoke | PASS on 11 surfaces |
| 47 | Logs | 0 runtime errors; 0 warning/error entries; no 4xx/5xx observed |
| 48 | Deployment | `dpl_HaHPEHZEXS3Dz6BTM34YqKgn4Rea` READY |
| 49 | Service Worker | `2.0.0+sw.dda599b0640e`, live and non-cacheable |
| 50 | Cleanup | Release worktree retained only until this report is merged; final removal is recorded in the task closure |
| 51 | Real entities used | 0 |
| 52 | External notifications | 0 |
| 53 | Demo remote writes | 0 |
| 54 | Stripe touched | NO |
| 55 | Rollback | Not required; previous production deployment remains a Vercel rollback candidate |
| 56 | Next Wave started | NO |

## Final matrix

| Check | Result |
| --- | --- |
| Role-aware navigation active | YES |
| Role-aware Home active | YES |
| Single primary action | YES |
| Unified context selector | YES |
| Stable deep links | YES |
| Stable portrait | YES |
| Stable landscape game mode | YES |
| Unified visual states | YES |
| Global lint errors / warnings | 0 / 0 |
| Demo World V3.3 active | YES |
| Guided tours active | YES |
| V3.2 authority hash preserved | YES |
| Real entities used | 0 |
| External notifications | 0 |
| Demo remote writes | 0 |
| Stripe touched | NO |
| Functional release merged | YES |
| Functional release deployed | YES |

Wave 8D is `PRODUCTION_VERIFIED`. No subsequent Wave was started.
