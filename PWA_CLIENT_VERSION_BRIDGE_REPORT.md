# PWA Client Version Bridge Report

## 1. Scope and traceability

| Item | Value |
| --- | --- |
| Branch | `codex/pwa-client-version-bridge` |
| Base commit | `abcd7d25f00959afb405b68bd56f02c2058e1fe2` (`origin/main`) |
| Audit date | 2026-08-02 23:47 CEST |
| Initial status | Clean worktree, branch created directly from the current `origin/main` |
| Environment | macOS, Node `v24.16.0`, npm `11.13.0`, Next.js `16.2.6` |
| External services | No project service was queried or modified. Only official Supabase, MDN and web.dev documentation was consulted. |
| Rating V2 | Not activated, imported or modified. The bridge remains compatible with the V1 data paths. |

This release is the compatibility bridge required before staging Rating System V2. It adds client identity, write telemetry, a minimum-version policy and a controlled PWA update flow without changing the V1 database contract.

## 2. Audit of the previous PWA

| Surface | Previous behavior | Finding |
| --- | --- | --- |
| Manifest | Fullscreen-first PWA with standalone/minimal/browser fallbacks, `orientation: any`, icons and shortcuts. | Installable and suitable for game mode. No client or worker release identity. |
| Service Worker | Static `public/sw.js`, cache `pachangas-iq-pwa-v3`, shell precache, network-first navigation and stale-while-revalidate static assets. | `skipWaiting()` ran during install. There was no waiting-worker handshake, write pause or single-reload guard. |
| Registration | Secure-origin guard and localhost development exclusion. | No `updateViaCache: "none"`, explicit `registration.update()`, `updatefound`, `waiting` or `controllerchange` coordination. Registration errors were swallowed. |
| Caches | Legal/app shell routes and static assets were cached. `/api`, `/auth`, Supabase, Stripe, Google and weather requests were excluded. | Live server data was not deliberately cached by the worker. Cache name was fixed rather than build-derived. |
| IndexedDB | No application use found. | No hidden IndexedDB write queue exists. |
| Local/session storage | Theme, Google auth nonce/return URL, profile name and the `pachanga-iq-v3` cached/read-model payload. | The main payload can contain drafts/cache and previously could be updated optimistically before server confirmation. Session storage is now used only for no-PII telemetry and the reload-once marker. |
| Installed mode | CSS/runtime distinguished browser/standalone/fullscreen for layout. | The mode was not attached to write attempts or telemetry. |
| Offline | The shell could remain available from cache. | Writes had no common fail-closed bridge; a failed autosave could leave an optimistic local projection visible. |
| RPC errors | Call sites handled errors inconsistently. | There was no single error contract for obsolete/offline clients and no global rollback trigger. |
| Pending updates | Browser-managed only. | A waiting worker could not coordinate with in-flight writes. |

### 2.1 Browser write inventory

The Supabase client now classifies every browser RPC currently invoked by the product. A regression test derives the invoked RPC names from the source and requires an exact match with this allowlist.

```text
accept_pachanga_admin_invite
append_pachanga_player_rating
complete_pachanga_player_advanced_assessment
complete_pachanga_player_initial_assessment
create_pachanga_admin_invite
create_pachanga_group_backup
finalize_pachanga_match_if_current
join_pachanga_team
patch_pachanga_match_lineup_state
patch_pachanga_match_player_paid
patch_pachanga_match_player_status
patch_pachanga_match_scorers
patch_pachanga_player_profile
request_pachanga_open_match
restore_pachanga_group_backup
review_pachanga_open_match_request
save_pachanga_payload_if_current
set_pachanga_member_role
sync_pachanga_market_profile
sync_pachanga_open_match
update_pachanga_member_name
upsert_pachanga_own_player_profile
```

Direct V1 table writes are also classified:

```text
table:pachanga_group_members:post
table:pachanga_groups:delete
table:pachanga_groups:post
```

Application API writes routed through the same bridge:

```text
api:billing-checkout
api:billing-portal
```

Authentication requests, reads, Stripe webhooks and server-side service operations are deliberately not treated as browser write intentions. Reads remain available when the client is incompatible.

## 3. Bridge contract

### 3.1 Immutable build versions

`next.config.ts` resolves the release and commit at build time and embeds immutable public constants:

```text
clientVersion        = <PACHANGAS_CLIENT_RELEASE_VERSION>+<commit-sha-12>
serviceWorkerVersion = <PACHANGAS_CLIENT_RELEASE_VERSION>+sw.<commit-sha-12>
```

The initial release core is `1.0.0`. Invalid release cores fail the build. Vercel/GitHub commit variables take precedence, with local `git rev-parse HEAD` as the deterministic local fallback.

### 3.2 Minimum supported client

`GET /api/client-policy` returns a server-timestamped policy with `Cache-Control: private, no-store, max-age=0, must-revalidate`. The default and documented initial policy is:

```text
minimumSupportedClientVersion = 1.0.0
```

Missing or invalid versions are classified as `v1-unversioned`. SemVer comparison follows core and prerelease precedence and ignores build metadata such as `+sha`.

An incompatible write returns `CLIENT_UPDATE_REQUIRED`; an offline write returns `OFFLINE_WRITE_NOT_CONFIRMED`; inability to obtain server confirmation returns `WRITE_CONFIRMATION_UNAVAILABLE`. None is represented as a successful write.

### 3.3 Write metadata and authority

Every classified browser write first obtains the current no-store server policy. If allowed, the outgoing intention carries:

```text
X-Pachangas-Client-Version
X-Pachangas-Service-Worker-Version
X-Pachangas-Display-Mode
X-Pachangas-Operation
X-Pachangas-Write-Id
```

The active worker is reported conservatively as `v1-unversioned` until it answers `GET_VERSION`; the expected build version is never substituted for an older worker that may still control the page.

The bridge never computes authoritative sports data. It only gates and labels existing V1 intentions. Server responses remain authoritative. A rejected write emits `pachangas:pwa-write-rejected`; the main payload flow restores the last confirmed local projection and reloads the server snapshot.

No offline sports-operation queue was introduced. Only telemetry metadata may wait in `sessionStorage`, so an offline action cannot be displayed as confirmed or replayed later as a second source of truth.

## 4. No-PII telemetry

`POST /api/client-telemetry` accepts an exact allowlist only:

| Field | Meaning |
| --- | --- |
| `event` | Fixed value `write-intent` |
| `operation` | Known RPC/table/application operation identifier |
| `clientVersion` | SemVer build identity or `v1-unversioned` |
| `serviceWorkerVersion` | Worker build identity or `v1-unversioned` |
| `displayMode` | `browser`, `standalone` or `fullscreen` |
| `result` | Attempted, confirmed, RPC/network error, or explicit rejection reason |
| `writeId` | Random idempotency/correlation UUID; no user identity |
| `serverTime` | Added by the server; never trusted from the browser |

Unknown fields, unknown operations, malformed versions, invalid UUIDs and payloads above 2 KiB are rejected. User ids, profile ids, names, emails, payloads, assessment answers and sports data are not accepted or logged.

## 5. Controlled Service Worker update

The worker is now generated by `/sw.js` using the build-time version and served with `no-cache, no-store`. It no longer calls `skipWaiting()` during install.

The runtime performs this sequence:

1. Registers with `updateViaCache: "none"`.
2. Calls `registration.update()` on startup or explicit update.
3. Detects an installed waiting worker.
4. Pauses new writes.
5. Waits up to 30 seconds for active writes to settle.
6. Reads the waiting worker version through `MessageChannel`.
7. Sends `SKIP_WAITING` only after the wait succeeds.
8. Reloads once after `controllerchange`, keyed by worker version in `sessionStorage`.

The mandatory-update notice states that reads remain available and offers `Actualizar ahora`. Offline and updating states use separate messages and never claim a change was saved.

## 6. Security boundary

- The browser Supabase client continues to receive only the public publishable key.
- `SUPABASE_SERVICE_ROLE_KEY` is referenced only by existing server-only routes/helpers and is not imported by the bridge.
- A build-artifact scan must find neither `SUPABASE_SERVICE_ROLE_KEY` nor `service_role` in `.next/static`.
- Policy and telemetry use `no-store`; neither endpoint returns credentials or user data.
- The bridge does not grant permissions, alter RLS, add migrations or activate Rating V2.

## 7. Validation matrix

| Scenario | Evidence |
| --- | --- |
| Browser mode | Display-mode detector and bridge metadata test. |
| Installed PWA | Standalone/iOS standalone mapping and write metadata test. |
| Fullscreen | Fullscreen precedence test. |
| Client without version | Classified `v1-unversioned`, writes rejected with `CLIENT_UPDATE_REQUIRED`. |
| Client below minimum | Correct SemVer rejection. |
| Compatible client | `1.0.0+sha` accepted against `1.0.0`; metadata ignored for precedence. |
| Service Worker update | Write pause, active-write drain, `SKIP_WAITING` and expected version tested. |
| Single reload | Reload marker permits exactly one reload per worker version. |
| Pending write | Waiting worker does not activate until the operation settles. |
| RPC error | Returned as failure, telemetry records `rpc-error`, rollback event emitted. |
| Offline | Write is rejected and never sent; telemetry metadata may queue. |
| Reconnection | Online state/policy refresh and telemetry flush covered. No sports action is replayed. |
| Optimistic projection | Rejection restores the last committed payload and reloads canonical server state. |
| Reads with blocked writes | Non-write fetches bypass the bridge and the UI remains readable under a forced `2.0.0` policy. |
| PII | Strict telemetry schema rejects additional fields. |
| Write inventory | Source-derived RPC inventory must exactly equal the classifier allowlist. |

Local HTTP QA confirmed:

- Unversioned policy request: `v1-unversioned`, `writeAllowed: false`, `CLIENT_UPDATE_REQUIRED`.
- Compatible `1.0.0+abcd7d25f009`: `writeAllowed: true`.
- Policy, telemetry and Service Worker responses carry `no-store`.
- Worker source contains `1.0.0+sw.abcd7d25f009`, `GET_VERSION` and explicit `SKIP_WAITING` handling.
- A local minimum `2.0.0` displays the mandatory-update alert while the read-only demo and history remain visible.

Staging and controlled installed-PWA QA completed on 2026-08-03 01:11 CEST:

- Vercel Preview deployment `dpl_3km6w8S1Y2fWFGsswdMiEHti59Jj` is `READY`, targets Preview rather than Production and contains the bridge build `2d5e909149ce`.
- Requests without a version are readable but return `writeAllowed: false` and `CLIENT_UPDATE_REQUIRED`; compatible `1.0.0+qa` requests return `writeAllowed: true`. Both responses are `private, no-store`.
- Supabase staging accepted the bridge's custom CORS headers and an authenticated synthetic RPC write. No production row was read for or changed by this QA.
- A real Chromium app-mode profile started with the old cache `pachangas-iq-pwa-v3`, `display-mode: standalone` and a worker classified as `v1-unversioned`.
- Reopening that installed profile against the bridge replaced the cache with `pachangas-iq-pwa-1.0.0-sw.2d5e909149ce`, activated worker `1.0.0+sw.2d5e909149ce` and produced exactly one automatic reload plus one reload marker.
- Offline mode displayed that writes are not confirmed. Reconnection restored the compatible policy, while the same request without bridge headers remained blocked.
- Two authenticated staging clients advanced the same group from revision `2` to `3`; Realtime delivered revision `3`, both clients read the same marker and both converged on revision `3`.
- The first Realtime attempt coincided with cold initialization of the branch replication slot and timed out after the write reached revision `1`. Repeating after the service initialized succeeded twice (`1` to `2`, then `2` to `3`), including a final clean process exit. This cold-start behavior remains a staging observation for Rating V2 QA.

## 8. Validation results

Final command results are recorded after the closing validation pass:

| Gate | Result |
| --- | --- |
| Tests | PASS: 5 rendered-HTML tests and 30 TypeScript tests; 35 total, 0 failures |
| Typecheck | PASS: `npm run typecheck` |
| Build | PASS: Next.js production build, 17 routes generated including the three dynamic bridge endpoints |
| Focused lint | PASS for every bridge-owned/new file. `app/page.tsx` still reports its pre-existing 14 errors and 21 warnings, all outside this branch's changed fragments. |
| `git diff --check` | PASS |

`npm ci` reported 18 dependency audit findings already present in the locked dependency graph (1 low, 4 moderate and 13 high). No unrelated dependency upgrade or `audit fix` was applied in this focused bridge PR.

The final staged scope contains exactly 24 paths. It contains no SQL, migration, Rating V2 file, generated TypeScript build info or local diagnostic artifact.

## 9. Deployment boundary and follow-up

This branch is deployed only to an isolated Vercel Preview connected to an isolated Supabase development branch. It has not been promoted, merged or deployed to Production.

The bridge cannot retroactively instrument JavaScript that was loaded before the bridge existed. Final server-side V1 revocation remains the authority that prevents obsolete clients from bypassing the browser bridge once real users exist.

For this pre-launch release there are no real users or installed clients to preserve. The product owner has therefore waived the seven-day observation window and additional V1 server-side instrumentation for this release. Browser telemetry remains in place for future rollouts, while the current gate is one controlled old-PWA replacement test followed by staging verification of Supabase CORS, authenticated RPC behavior, offline rejection, reconnection, Realtime convergence and installed PWA replacement.

The isolated staging topology is:

- Vercel Preview branch: `codex/pwa-client-version-bridge`.
- Supabase preview branch: `pwa-bridge-staging` (`iozcjirlfytryzrcmrnq`), with no production data.
- Branch-specific Vercel Preview variables only; production and other preview branches retain their existing configuration.
- No production deployment or production database write is authorized by this report.

The bridge staging gate is complete. Rating V2 may proceed in the same isolated staging environment according to its runbook, starting with additive infrastructure and keeping the V1 closure migration deferred.

Related planning:

- Rating V2 draft PR: [#92](https://github.com/puntoracingrc/pachangas/pull/92)
- [Rating V2 staging and production runbook](https://github.com/puntoracingrc/pachangas/blob/codex/rating-system-v2/docs/rating-system-v2-deployment-runbook.md)

## 10. Sources

- [Supabase JavaScript custom fetch](https://supabase.com/docs/guides/api/automatic-retries-in-supabase-js)
- [Supabase changelog: JavaScript](https://supabase.com/changelog?tags=javascript)
- [MDN: ServiceWorkerRegistration.updateViaCache](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/updateViaCache)
- [web.dev: Update](https://web.dev/learn/pwa/update)
- [web.dev: Service worker lifecycle](https://web.dev/articles/service-worker-lifecycle)
