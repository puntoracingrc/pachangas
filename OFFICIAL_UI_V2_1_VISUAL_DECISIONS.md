# Official UI V2.1 Visual Decisions

## Frozen Decisions

| Decision | Product effect |
| --- | --- |
| Team shield is Home's protagonist | team users see canonical `TeamShieldView`, never a roster member as identity |
| Own card is secondary | `Mi carta` remains accessible without competing with team identity |
| One dominant action | real match/attendance state selects the next step |
| Selector integrated in identity | switching teams does not interrupt the agenda |
| Team Access in a bounded drawer | code, role, invite and destructive controls remain permission guarded |
| One Match Hub | Proximo, Alineacion, Resultado and Admin preserve one context/navigation |
| Market list/detail hierarchy | filters, scan list and contextual action remain compact |
| Own ranking first | eligibility is shown before the public table |
| Dark authenticated fallback | dark applies only when no explicit preference exists |

## Identity Fallback

1. User with team: canonical team shield.
2. Team without cosmetic loadout: canonical base shield.
3. User without team and with profile: own player card.
4. User without team/profile: stable Pachangas IQ placeholder and one next action.

The fallback never reads `activeGroupPlayers[0]` as team identity.

## Geometry

- Official V2 semantic palette and radii no larger than 8px.
- Desktop uses the existing constrained workspace.
- Portrait uses one bottom navigation and natural vertical scrolling.
- Mobile Game Landscape uses the side HUD and bounded internal scrolling.
- Document-level horizontal overflow is forbidden.
- Horizontal rails are limited to intentionally repeated content.
- Stable tracks and bounded drawers prevent control movement.

## Theme

Authenticated users without a stored choice default to dark without persisting
that fallback. Explicit `light`, `dark` and supported `system` preferences remain
authoritative. Orientation does not change theme.

## Empty, Offline And Error States

- Empty states expose at most one primary next action.
- Offline is read-only and never confirms a sporting write.
- Server diagnostics are mapped to product language.
- A missing player profile shows `Tu carta aún no está creada`, not the RPC
  message.
- Protected Card and Shield routes offer login and preserve their deep link.

## Evidence Semantics

The authenticated contact sheet separates:

- canonical Supabase staging readback;
- visual owner/player/offline fixtures;
- Demo World;
- current Official V2;
- V2.1 proposal.

Fixture rows are labelled and never count as canonical authentication. The six
final contact sheets are under `docs/official-ui-v2-1`; raw evidence retention is
defined by `OFFICIAL_UI_V2_1_EVIDENCE_INVENTORY.md`.

## Scope Boundary

No visual decision changes sports authority, Rating V2, Team Rewards, Player
Cosmetics, Team Cosmetics, Market permissions, Demo World authority or Control
Center access. R4A #162 remains untouched.
