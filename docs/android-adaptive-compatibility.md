# Android adaptive compatibility for Pachangas IQ

This checklist translates the current Android adaptive guidance into Pachangas IQ rules.

## Sources

- Android 16 behavior changes: orientation, resizability, and aspect ratio restrictions are ignored on large screens.
- Edge-to-edge Android guidance: content may draw behind system bars; important controls must respect insets.
- Window size classes: use compact, medium, expanded, large, and extra-large breakpoints based on the available window, not the physical device.
- Adaptive app quality Tier 2: optimized apps adapt to all display sizes and device state transitions.

## Runtime Rules

- Do not lock orientation. Portrait is the fast app view; landscape is the game/manager view.
- Treat the window as dynamic. Rotation, split screen, desktop windowing, and fold/unfold can change the size class while the app is open.
- Use `visualViewport` plus safe-area CSS variables for browser bars, installed PWA mode, display cutouts, and edge-to-edge system bars.
- Keep server-authoritative data live. Service worker caching is for shell and static assets, not Supabase, Stripe, auth, or API decisions.
- Feature-detect optional APIs at runtime: service worker, share, clipboard, camera, and storage estimate.

## Window Size Classes

| Class | Width |
| --- | --- |
| Compact | `< 600` |
| Medium | `600-839` |
| Expanded | `840-1199` |
| Large | `1200-1599` |
| Extra-large | `>= 1600` |

| Class | Height |
| --- | --- |
| Compact | `< 480` |
| Medium | `480-899` |
| Expanded | `>= 900` |

## Pachangas QA Matrix

| Scenario | Viewport | Expected behavior |
| --- | ---: | --- |
| Small phone portrait | 360x780 | Bottom mobile nav visible, no legal footer, one-column flows, no horizontal overflow. |
| Small phone landscape | 667x375 | Game nav visible, compact controls, no footer, no browser-bar assumptions. |
| Large phone game landscape | 844x390 | Partido mode keeps top nav stable, roster rails usable, field keeps landscape proportions. |
| Foldable portrait-like window | 717x720 | Medium-width layout does not assume tablet landscape; main actions remain reachable. |
| Tablet split or small landscape tablet | 1024x600 | Expanded-width layout uses extra room without stretching cards into unreadable rows. |
| Large tablet landscape | 1280x800 | Ranking, mercado, perfil, and partido can use wider panels without clipping. |
| Desktop or ChromeOS wide window | 1700x950 | Content remains measured, not edge-to-edge stretched across the whole desktop. |

## Browser Smoke Command

Run the app locally, then run:

```bash
COMPAT_BASE_URL=http://127.0.0.1:3000 npm run compat:browser
```

The smoke test opens Chrome headless when available and checks the matrix above for:

- page content present
- no global horizontal overflow
- mobile/game navigation present where expected
- manifest exposes Android install metadata
- runtime size classes written to the document

If Chrome is not installed on the machine, the command exits with a clear setup error instead of silently passing.
