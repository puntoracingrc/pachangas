# OFFICIAL UI V3G SOCIAL INBOX REPORT

## Scope delivered

Official UI V3G converts the shell bell into a social Inbox at `/avisos` for
Match, Challenge, Market and Team activity. Notification preferences move to
`/ajustes/notificaciones`; `/perfil/avisos` remains a compatibility redirect.

The Inbox has only `Pendientes` and `Todos`, optional domain filters, stable
date groups, one primary deep-link action, an overflow menu for read/archive
commands and cursor pagination. The badge shows pending actions as 1-9 or 9+;
when only unread informational activity exists it shows a discreet dot.

## Product integration

- V3B remains Match authority.
- V3C remains Challenge and external-result authority.
- V3D remains Market request and match-invitation authority.
- V3F remains Team and membership authority.
- Home consumes the global canonical pending projection first and shows at most
  one social action. Existing V3B Match fallback remains only where the server
  has no personal notification row.
- Team cleanup removes the permanent code and normal `ACTIVE` wording from the
  hero without changing V3F authority.
- `platform_owner` receives the same own-user social projection as any user;
  advanced administration notices stay outside `/avisos`.

## Demo Social Inbox

Demo World adds a local-only Inbox journey with the required 26 steps:
attendance, challenge, Team invitation, Market activity, read/archive/all-read,
settings, offline, actor switch and reset. State is stored only in the existing
Demo session namespace.

Demo guarantees:

- `remoteWrites = 0`;
- `externalNotifications = 0`;
- `pushSent = 0`;
- `emailsSent = 0`;
- `realEntities = 0`;
- `StripeCalls = 0`.

The synthetic season hashes, results, standings, brackets, reservations and
bindings are unchanged. `/admin/demo` remains intact.

## PWA and offline

The Service Worker includes `/avisos` and `/ajustes/notificaciones` as route
shells. It excludes private Inbox RPC responses, Auth and commands. A confirmed
cached read can be shown offline with its last update; all read/archive/domain
writes fail closed with no queue and no optimistic success. Reconnection and
`controllerchange` trigger canonical refetch through the existing bridge.

## Accessibility and responsive contract

The shell bell has an accessible label and non-color-only count semantics.
Tabs, filters, cards, overflow menus, status text, live feedback and pagination
are keyboard reachable. Interactive controls retain the product minimum target
size, focus visibility, reduced-motion behavior and dark-shell contrast.

Required local and Preview QA matrix:

- 1440x900 and 1920x1080;
- 390x844 and 360x800;
- 667x375, 740x360, 844x390 and 932x430;
- standalone PWA emulation;
- empty, pending, all, filtered, offline and Demo states.

Physical Android, iPhone and installed-PWA QA remain `PENDING` until performed
on real devices; they are not presented as PASS.

The clean production build passed the complete browser matrix at 1440x900,
1920x1080, 390x844, 360x800, 667x375, 740x360, 844x390 and 932x430. Every
viewport reported zero root/body horizontal overflow, zero broken images, one
visible product navigation and a fully visible Inbox CTA. Browser logs were
empty. The exercised local journey covered bell entry, Match deep link, return,
read state independent from attention, archive preserving a pending domain
action, `Todos`, Challenge filtering, offline write rejection, reconnect and
the `/perfil/avisos` compatibility redirect.

## Local release gate

| Gate | Result |
| --- | --- |
| Node tests | 20/20 |
| TS/TSX tests | 798/798 |
| Combined | 818/818 |
| skipped / todo / cancelled | 0 / 0 / 0 |
| focused V3G | 17/17 |
| isolated cross-slice reconciliation | 77/77 |
| SQL/RLS rollback | PASS |
| concurrent replay | PASS |
| typecheck | PASS |
| build | PASS, 78 static pages generated |
| focused lint | 0 errors, 0 warnings |
| global lint | 0 errors, 0 warnings |
| `git diff --check` | PASS |

## Release boundary

- One additive forward-only migration, ledger 233 to 234.
- No old migration modified.
- Push and email delivery remain OFF.
- Stripe is untouched.
- Wave 9C remains paused.
- V3H is not started.
- Staging, Preview visual QA, production canary, deployment and final cleanup are
  pending and must be recorded in the production release report.
