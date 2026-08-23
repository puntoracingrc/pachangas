# Official UI V2.1 Visual Decisions

## Accepted For Final Review

| Decision | Reason | Product effect |
| --- | --- | --- |
| Team shield is the Home protagonist | team identity must precede an individual roster member | authenticated users with a team see the canonical `TeamShieldView` |
| Strict fallback hierarchy | the first roster player is not a team identity | no team uses the own card, then a stable Pachangas IQ placeholder |
| Own card is secondary | personal identity remains useful without competing with the team | compact `Mi carta` action remains available |
| One dominant Home action | Demo World establishes a clear next sporting step | real state selects attendance, lineup, result, draft, creation or Market |
| Selector integrated in identity | switching teams is context, not a separate sporting section | the former Team Access row no longer interrupts Home |
| Team Access details drawer | code, invite and destructive controls are necessary but secondary | detailed administration opens on demand and stays permission guarded |
| Horizontal agenda and activity rails | repeated items scan better without page-section cards | real open and closed matches only; no synthetic activity |
| One persistent Match Hub | Next, Lineup, Result and Admin are modes of one match | context and navigation do not repeat inside each pane |
| Pitch and score as protagonists | sporting state precedes secondary forms | existing interactive field and result controls are retained |
| Market list/detail hierarchy | landscape needs filters, scan list and action detail | existing tabs, filters and server-backed panels remain intact |
| Own ranking first | users first need to understand their eligibility | canonical own-rank payload stays ahead of the public table |

## Canonical Identity Ownership

- Team name and shield: identity band.
- Team selector: identity controls.
- Role, code, synchronization and invite actions: Team Access drawer.
- Team level and roster count: compact metrics, not repeated prose.
- Connection state: one status location when it is relevant.

The product shell no longer repeats the identity-band metadata. The Home does
not derive its protagonist from `activeGroupPlayers[0]`.

## Density And Geometry

- Panels use the existing Official UI V2 semantic colors and a maximum radius
  of 8px.
- Desktop keeps the current header and constrained workspace.
- Portrait keeps one bottom navigation and natural vertical scrolling.
- Mobile Game Landscape keeps the current side HUD and a bounded internal
  workspace rather than a compressed desktop page.
- Shield sizing is responsive and bounded: prominent on desktop, compact enough
  to retain the action and metrics in portrait and low landscape.
- Horizontal scrolling is limited to intentional rails and result collections;
  the document itself does not overflow horizontally.
- Stable grid tracks, tool heights and bounded drawers prevent controls or cards
  from resizing the layout.

## Theme Decision

Authenticated users without an explicit preference default to dark. This is a
runtime fallback, not a stored preference.

Explicit `light`, `dark` and supported `system` choices remain authoritative and
persist across reload and orientation. Public landing and Control Center theme
behavior were not globally rewritten.

## Empty And Offline States

- A team without configured cosmetics receives the canonical base team shield.
- A user without a team receives the own card when available, otherwise the
  stable Pachangas IQ placeholder.
- Empty sections expose at most one valid next step.
- Home Activity does not fabricate notifications, rewards or team changes.
- Offline remains read-only and never presents a sports write as confirmed.

## Secondary Surfaces

Card, Shield, Notifications, Team and Referee Profile retain their existing
authority. V2.1 validates them in the shared lab and regression matrix rather
than creating parallel product state. Demo World remains unchanged.

## Evidence

- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_HOME_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MATCH_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MARKET_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MOBILE_GAME_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_DEMO_OFFICIAL_COMPARISON.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_AUTHENTICATED_FINAL_CONTACT_SHEET.png`

The authenticated-final sheet records exact deployed Preview fixture captures
and explicitly labels the Google `redirect_uri_mismatch` blocker. It is not a
claim that canonical staging authentication passed.

The target is structural parity in hierarchy, composition, density, object
prominence and next action. Pixel identity is not required, and Demo/lab
fixtures never become product data.
