# Demo World V3.0 Organizer Onboarding Parity Report

Date: 2026-08-29 CEST

## Version and provenance

- Demo version: 3.
- Seed: `pachangas-iq-demo-world-v3-0-2026-27`.
- Chunk hash prefix: `f641bc1c787b0810`.
- Authority proof hash:
  `a5ca22830eb54198c608ba044e8aada8e278c4f6e18538729ea22b48cacdf433`.
- Temporary PostgreSQL migrations: 204.
- Organizer access operation receipts: 29 in the focused projection; 45 in
  the complete organizer private simulation.
- Remote writes: 0.

V2.9 is preserved under `public/demo-world/v2-9/`; V3.0 is the active manifest
under `public/demo-world/v3/`.

## Organizer scenarios

1. Club partner approved, one partnership grant, complete onboarding and first
   public League.
2. Club organizer paid interest, Checkout unavailable and no subscription
   grant.
3. Team organizer needs information, responds and receives an explicit
   temporary beta grant.
4. Rejected Team with no grant.
5. Withdrawn Club with no grant.
6. Team owner transfer during onboarding while organizer history remains
   stable.

The public demo shows plan, application state, safe history, decision, grant,
checklist, next action and first Competition. It excludes private notes,
message bodies, Auth UUIDs, emails, phones, Stripe identifiers, test prices and
secrets.

## Reuse and determinism

The Simulation World boots a temporary PostgreSQL database, invokes the real
RPC families, sanitizes the canonical snapshots and exports GET-only JSON.
Deterministic projection hashes are compared independently from volatile UUIDs
and timestamps. Partner approval produces one grant, paid interest produces
none, launch produces one draft and owner transfer does not change organizer
identity.

Rating, Rewards, Conduct, Billing live and sporting results remain unchanged.

## Visual QA

Local browser checks completed for 1440x900, 1920x1080, 390x844,
360x800, 667x375, 740x360, 844x390 and 932x430. The matrix covered
`/planes-organizador`, `/organizacion/solicitar-acceso`,
`/admin/organizer-access` and `/demo?tab=planes` (32 combinations):

- root overflow: 0;
- broken images: 0;
- console warnings/errors: 0;
- navigation duplication: 0;
- landscape uses explicit internal scrolling;
- organizer scenario rail remains horizontally scrollable without expanding
  the root.

## Production verification

- `https://pachangasiq.com/demo?tab=planes` serves manifest version 3, seed
  `pachangas-iq-demo-world-v3-0-2026-27` and full hash
  `f641bc1c787b08102ed14b2c15f58adcab86ad0fc031df360bd78593984bac1c`.
- Production exposes six organizer access scenarios, seven organizer billing
  scenarios and four public competitions. The public projection remains
  read-only and has `remoteWrites = 0`.
- Twenty-one production route/viewport combinations passed with zero root
  overflow, broken images, redirects or console errors. A later exact-hotfix
  reload passed again on the Organizer page and Demo V3 surface.
- Service Worker registration is active with no waiting or installing worker
  and controls the full production scope.
- With network blocked, the Demo document and eleven immutable V3 fragments
  were returned with `fromServiceWorker=true` and local cache. A non-cacheable
  control request failed both before and after navigation. Reconnection then
  returned a fresh `200` response.

Browser-level PWA behavior passes. Physical Android, iPhone and an installed
device PWA remain `PENDING` and are not reported as PASS.
