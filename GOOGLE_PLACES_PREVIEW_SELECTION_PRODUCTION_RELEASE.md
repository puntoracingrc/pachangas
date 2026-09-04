# Google Places Preview Selection - Production Release

## 1. Release identity

- Release timestamp (UTC): `2026-09-04T08:55:25Z`
- Classification: `REPRODUCED_PREVIEW_INTEGRATION_DEFECT`
- Issue: [#166 - Google Places: cerrar seleccion real en Preview](https://github.com/puntoracingrc/pachangas/issues/166)
- Functional PR: [#271 - Fix Google Places selection in Preview](https://github.com/puntoracingrc/pachangas/pull/271)
- Functional branch HEAD: `0d5e0be8c728a4d018c223de5c1d6b0569e00903`
- Squash merge and production `main`: `18f4fc48f140985396319316bc94935d389b240c`
- Production domain: [https://pachangasiq.com](https://pachangasiq.com)
- Production deployment: `dpl_41ELvFwSbvERPH55uhf7Vsn3XCsw`
- Immutable production URL: [https://pachangas-1gbkhke2y-persianas-almar-web-s-projects.vercel.app](https://pachangas-1gbkhke2y-persianas-almar-web-s-projects.vercel.app)
- Deployment state: `READY`
- Deployment target: `production`
- Deployment Git ref: `main`
- Deployment metadata SHA: `18f4fc48f140985396319316bc94935d389b240c`

## 2. Root cause and correction

The defect was reproduced in an isolated Preview and had combined configuration and client causes:

- `PREVIEW_KEY_ORIGIN_CONFIGURATION`
- `PREVIEW_ENVIRONMENT_INJECTION`
- `CLIENT_ERROR_HANDLING`
- `CLIENT_SELECTION_FLOW`
- `COMBINED_CONFIGURATION_AND_CODE`

The release preserves `PlaceAutocompleteElement` as the primary widget, `google.maps.places.Autocomplete` as the legacy fallback, `gmp-select` as the primary selection event, and `gmp-error` as the provider error event. It adds stale-selection invalidation, sanitised product errors, rejected `fetchFields` handling, listener deduplication, retry after script failure, and cleanup guards.

No provider, persistence model, manifest, Service Worker, schema, RPC, RLS, migration, feature flag, billing flow, Rating formula, reward, competition or Demo World contract changed.

## 3. Isolated Preview evidence

The exact functional HEAD was deployed at:

- Stable branch origin used for the Google test: `https://pachangas-git-codex-googl-ff0eb8-persianas-almar-web-s-projects.vercel.app`
- Immutable deployment: `https://pachangas-7534ehsii-persianas-almar-web-s-projects.vercel.app`
- Preview deployment: `dpl_rCLF6GkzWSAswXR7xhozfz1CehDf`
- Preview metadata SHA: `0d5e0be8c728a4d018c223de5c1d6b0569e00903`

The real-provider E2E used Google predictions returned during execution. It did not inject a `VenuePlace`, place ID, address or coordinates. Sanitised outcomes:

- Real predictions observed: `PASS` (at least one)
- Keyboard selection: `PASS`
- Pointer selection in an independent attempt: `PASS`
- `gmp-select`: `PASS` (two independently observed selections)
- `gmp-error`: `PASS` (visible fail-closed path verified)
- `toPlace()`: `PASS`
- `fetchFields()`: `PASS`
- Non-empty place ID, name and address: `PASS`
- Finite coordinates supplied by Google: `PASS`
- Region coherent with the Spain restriction: `PASS`
- Exact provider data published in evidence: `NO`
- Save disabled for free text without a selected prediction: `PASS`
- Save enabled after a valid selection: `PASS`
- Editing after selection invalidates the old place: `PASS`
- Field persisted through the official UI and authoritative RPC: `PASS`
- Match created with the saved field through the official UI and authoritative RPC: `PASS`
- Reload and canonical readback: `PASS`
- Duplicate field or match: `NO`
- Offline fake success or queued sporting write: `NO`
- Reconnect and fresh selection: `PASS`
- PWA standalone emulation, portrait and landscape: `PASS`

The disposable Supabase Preview branch was the only database used by this E2E. It was destroyed after verification. A final branch readback showed only the production `main` branch; no synthetic row or Auth session was written to production.

## 4. Google credential separation

- Preview key separate from production: `YES`
- Preview and production SHA-256 fingerprints different: `YES`
- Preview application restriction: `Websites / HTTP referrers`
- Preview origin scope: exact stable branch Preview origin with its required path wildcard
- General `*.vercel.app` wildcard: `NO`
- Preview APIs: `Maps JavaScript API`, `Places API (New)`
- Places API legacy enabled for the Preview key: `NO`; the primary widget completed the real E2E and no extra API permission was justified
- Billing operational during the real E2E: `YES`
- Quota operational during the real E2E: `YES`
- Production Google key modified: `NO`

Post-release cleanup removed the branch-scoped Vercel variable, the temporary stable alias and the dedicated Preview key. The key no longer appears in the active Google Cloud credential list. The production key and its authorised origins/APIs remain unchanged.

## 5. Production deployment verification

Vercel reported the exact `main` SHA as `READY`. Read-only smoke was performed against the custom production domain after deployment.

### Browser smoke

| Route | Viewport | Runtime errors/warnings | Broken images | Root overflow |
| --- | --- | ---: | ---: | ---: |
| `/` | 1440x900 | 0 | 0 | 0 |
| `/mercado` | 1440x900 | 0 | 0 | 0 |
| `/` | 390x844 | 0 | 0 | 0 |
| `/mercado` | 390x844 | 0 | 0 | 0 |
| `/` | 844x390 | 0 | 0 | 0 |
| `/mercado` | 844x390 | 0 | 0 | 0 |

No production form was submitted and no user, team, venue, match, invitation, reservation or notification was created.

### Production bundle separation

- JavaScript bundles inspected: `13`
- Combined inspected bytes: `1,298,168`
- Google web keys found: `1`
- Key fingerprint matched the production fingerprint: `YES`
- Preview key fingerprint present: `NO`
- Production Supabase reference present: `YES`
- Staging Supabase reference present: `NO`
- JWT-like secrets: `0`
- `service_role` literal: `0`
- Stripe secret patterns: `0`
- Webhook secret patterns: `0`

### PWA readback

- Manifest HTTP status: `200`
- Manifest content type: `application/manifest+json`
- Display mode: `fullscreen`
- Fallback display modes include `standalone`
- Scope and start URL: `/`
- Service Worker HTTP status: `200`
- Service Worker cache policy: `no-cache, no-store, must-revalidate`
- `Service-Worker-Allowed`: `/`
- Service Worker version: `2.0.0+sw.18f4fc48f140`

### Logs

- Unexpected production 4xx in the 30-minute release window: `0`
- Production 5xx in the 30-minute release window: `0`
- Browser console errors/warnings during the smoke: `0`

## 6. Verification gates

- Baseline before the issue: `868/868`
- Final `npm test`: `874/874 PASS`
- Node: `20/20 PASS`
- TS/TSX: `854/854 PASS`
- Failed / skipped / todo / cancelled: `0 / 0 / 0 / 0`
- Build routes: `78/78`
- Typecheck: `PASS`
- Build: `PASS`
- Focused lint: `PASS`
- Global lint: `PASS`
- `git diff --check`: `PASS`
- Real Google Preview E2E: `PASS`
- Focused regression suites: `151/151 PASS`
- Rendered HTML: `9/9 PASS`
- Source and deployment-bundle secret scans: `PASS`

The final functional diff contained exactly eight paths. `package.json` changed only to expose the deterministic and real Preview test commands. `package-lock.json` did not change.

## 7. Authority and data impact

- Supabase production modified: `NO`
- Migrations: `0`
- RPC/RLS/flags modified: `0`
- Stripe modified: `NO`
- Real users created: `0`
- Real venues created: `0`
- Real matches created: `0`
- Other real entities created: `0`
- Real notifications sent: `0`
- Provider responses fabricated: `0`

Field and match writes in staging were confirmed only after the central authoritative RPC returned success. Local state remained derived and was cleared before canonical reload/readback.

## 8. Cleanup and frozen contracts

- Disposable Supabase branch: `REMOVED`
- Synthetic staging data and Auth sessions: `REMOVED WITH BRANCH`
- Branch-scoped Vercel variables: `0`
- Temporary Vercel alias: `REMOVED`
- Dedicated Preview Google key: `REMOVED FROM ACTIVE CREDENTIALS`
- Unsanitised HAR, screenshots, `.env` files or credential logs retained: `0`
- Task processes and temporary browser profiles: `0`

`GVC-020` remains historically described and is now `FIXED_REGRESSION_VERIFIED`. Issue #165, SOCIAL-RC-001 through SOCIAL-RC-012, and OFFICIAL-UI-V3I-001 through OFFICIAL-UI-V3I-003 remain closed and frozen. Wave 9C was neither defined nor resumed.

Physical QA is intentionally unchanged:

- Android physical: `PENDING`
- iPhone physical: `PENDING`
- Physically installed PWA: `PENDING`

## 9. Issue closure

All technical and cleanup gates required to close issue #166 are satisfied. The issue is to be closed immediately after this one-file production report is merged, with a final sanitised comment linking both reports and the functional PR.

## 10. Evidence

- [Closure plan](./GOOGLE_PLACES_PREVIEW_SELECTION_PLAN.md)
- [Functional report](./GOOGLE_PLACES_PREVIEW_SELECTION_REPORT.md)
- [Functional PR #271](https://github.com/puntoracingrc/pachangas/pull/271)
- [Issue #166](https://github.com/puntoracingrc/pachangas/issues/166)

