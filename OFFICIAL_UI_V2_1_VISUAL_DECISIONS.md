# Official UI V2.1 Visual Decisions

## Accepted For The Proposal

| Decision | Reason | Product effect |
| --- | --- | --- |
| One dominant Home action | Demo establishes a clear next sporting step | real state selects attendance, lineup, result, draft, creation or Market |
| Identity before administration | team and player object should establish context immediately | card or placeholder, team name and four metrics fit in the first viewport |
| Horizontal agenda and activity rails | repeated items scan better without turning sections into cards | real open and closed matches only; no synthetic activity |
| Compact Team Access drawer | group ID, invite and destructive controls are necessary but secondary | selector remains visible; administration opens on demand |
| One persistent Match Hub | Próximo, Alineación, Resultado and Admin are modes of one match | context and navigation do not repeat inside each pane |
| Pitch and score as protagonists | sporting state should precede secondary forms | existing interactive field and result controls are retained |
| Market list/detail hierarchy | landscape needs filters, scan list and action detail | existing tabs, filters and server-backed child panels remain intact |
| Own ranking first | the user first needs to understand their own eligibility | canonical own-rank payload is reordered before the public table |

## Density And Geometry

- Panels use the existing Official UI V2 semantic colors and a maximum radius of 8px.
- Desktop keeps the current header and constrained workspace.
- Portrait keeps one bottom navigation and natural vertical scrolling.
- Mobile Game Landscape keeps the current side HUD and uses a fixed internal workspace instead of a vertically rotated desktop page.
- Horizontal scrolling is limited to intentional rails and result collections; the document itself must not overflow horizontally.
- Stable grid tracks, fixed tool heights and bounded object stages prevent controls or cards from resizing the layout.

## Theme Decision

The visual lab defaults to dark because it is the closest comparison to Demo World. `theme=light` remains fully rendered and was included in the automated matrix.

No product-wide default theme was changed. An explicit saved preference continues to win. Changing the authenticated default to dark remains a human product decision after visual review.

## Empty And Offline States

- Empty sections state what is absent and expose at most one valid next step.
- Home Activity does not fabricate notifications, rewards or team changes.
- Offline is a visual/read-only state in the lab; it does not claim a sporting write succeeded.
- Missing card data renders a stable Pachangas IQ placeholder instead of an invented player.

## Secondary Surfaces

Carta, Escudo, Avisos, Equipo and Perfil arbitral already followed much of the object-first language. V2.1 validates them in the shared lab and regression matrix instead of rewriting their authority. Control Center intentionally keeps its administrative table density.

## Evidence

- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_HOME_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MATCH_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MARKET_PARITY_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_MOBILE_GAME_CONTACT_SHEET.png`
- `docs/official-ui-v2-1/OFFICIAL_UI_V2_1_DEMO_OFFICIAL_COMPARISON.png`

The target is structural parity in hierarchy, composition, density, object prominence and next action. Pixel identity is not required, and Demo fixtures never become product data.
