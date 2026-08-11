# Pachangas IQ Visual Contract V1

## Product character

Pachangas IQ is a compact football operations app that can become a game-like interface in landscape. Its visual language is tactical, direct and material-aware. It is not a card-heavy marketing site. Product data stays calm; rewards and identity surfaces may carry more expression.

## Core tokens

| Token | Contract |
| --- | --- |
| Page background | Theme-aware `--background`; game mode uses the established dark field surface |
| Panel | `--panel` or a translucent mix of it; never white floating cards inside cards |
| Primary ink | `--ink` |
| Secondary ink | `--ink-soft`, with readable contrast in both themes |
| Product green | `--green` |
| Reward/action accent | `--lime`; it does not mean warning or error |
| Team colors | `--team-a`, `--team-b`; reserved for team identity and comparisons |
| Radius | 6px controls, 8px panels/modals; circles only for avatars, icon controls and status dots |
| Touch target | 44px preferred, 40px absolute practical floor in compact game mode |
| Focus | Visible 2px outline using lime/green contrast, never color change alone |
| Motion | Short feedback only; disabled or reduced under `prefers-reduced-motion` |

## Type hierarchy

- Page title: 28–40px desktop, 24–32px mobile, line-height close to 1.05.
- Compact game-mode title: 14–20px. Hero typography never enters tool panels.
- Section title: 14–18px, weight 800–900.
- Eyebrow/status: 10–11px uppercase, weight 850–950.
- Body: 13–16px with at least 1.35 line-height.
- Metadata: 10–12px; never below 9px in product UI.
- Letter spacing remains `0` except established uppercase micro-labels, which must stay readable.

## Spacing and density

- Base spacing units: 4, 6, 8, 12, 16, 20, 24 and 32px.
- Desktop operational pages use 16–24px panel padding.
- Portrait uses 12–16px and reserves bottom safe area plus navigation height.
- Landscape game mode uses 6–12px and keeps the primary action visible.
- Nested cards are prohibited. Subsections use dividers, bands or unframed groups.

## Actions

| Action | Presentation |
| --- | --- |
| Primary | Solid lime/green, one dominant action per decision area |
| Secondary | Transparent or panel background with visible border |
| Ghost | Borderless icon/text action for navigation and low-risk utilities |
| Danger | Restrained red border/text; solid red only for final destructive confirmation |
| Disabled | Clearly disabled, readable label, `not-allowed` cursor; never visually identical to loading |
| Saving | Preserve dimensions, disable repeat submission and show active progress copy |
| Saved | Short confirmed state/toast using product green |
| Stale | Human explanation plus reload/retry action; technical code remains diagnostic-only |

Equivalent commands use the same verbs: `Guardar`, `Restablecer`, `Cancelar`, `Cerrar` and `Volver`. `Aplicar` is reserved for non-persistent filters or previews.

## Navigation

- Primary destinations remain Inicio, Partido, Mercado, Equipo and Perfil.
- Landscape game mode uses the top rail plus contextual left submenu.
- A page-level header exposes current destination, one back route and optional secondary destination.
- `Volver` returns to the previous product surface; `Cerrar` dismisses an overlay without navigation.
- Bottom navigation must include safe-area padding and never cover the final scroll row.

## Cards, tabs and badges

- Repeated entity cards use one border, one surface and a stable minimum dimension.
- Tabs are segmented navigation, not primary CTAs. Active state combines contrast, border and `aria-current`/selection semantics.
- Chips describe state or filters; they are not buttons unless interactive semantics are explicit.
- `NEW` is a small reward indicator, not an error dot. It uses the same size and accessible label in Player and Team Cosmetics.
- Loading skeletons reserve final geometry and avoid layout shift.

## Empty, loading, error and offline states

- Empty states include a concise title, one sentence and at most one useful action.
- Loading keeps the final panel dimensions whenever practical.
- User-facing errors never expose PostgREST, SQL, RPC or environment wording.
- Offline cached reads remain visible with an explicit stale/offline label.
- Server writes are disabled offline and never appear confirmed before canonical acknowledgement.
- Feature flags off remove the unavailable command or replace the whole surface with a deliberate unavailable state.

## Overlays

- Product overlay levels are documented as page `0`, sticky navigation `20`, floating actions `30`, drawer/backdrop `60`, modal `80`, critical full-screen reward `100`.
- Overlays lock background scroll where appropriate and keep Close inside all safe areas.
- Toasts do not cover primary actions or bottom navigation.

## Responsive and PWA

- Required viewports: 1440x900, 390x844 and 844x390; spot-check 1920x1080 and 360x800.
- No non-intentional horizontal document scroll.
- Use dynamic viewport units and `env(safe-area-inset-*)` for fixed navigation and overlays.
- Standalone PWA and browser mode share layout; only browser chrome/fullscreen behavior differs.
- Zoom at 125%, 150% and 200% may reflow but cannot hide primary navigation or actions.

## Cosmetics

- `PlayerCardView` is the only player-card geometry authority.
- `TeamShieldView` is the only team-shield geometry authority.
- Editors share interaction patterns, NEW treatment, save state, error language, reset confirmation and responsive framing.
- Team shields may have more layers than player cards; shared interaction does not imply identical information architecture.
- Premium materials remain legible in light and dark themes and simplify through explicit LOD at 64, 48, 32 and 24px.
