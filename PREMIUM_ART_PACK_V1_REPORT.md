# Pachangas IQ Premium Art Pack V1 Report

## Scope and result

This phase delivers a reviewable laboratory pack without granting ownership, changing reward mappings or activating future product domains.

- Proposals: **29** (`21 MANTENER`, `7 REVISAR`, `1 DESCARTAR`).
- Dedicated delivery assets: **13** (`11 SVG`, `2 WebP`), **52,702 bytes** total.
- Blender prerenders: `Corona Elite` (13,916 bytes WebP) and `Medallon Future` (32,326 bytes WebP).
- Runtime: no Three.js, GLB, global canvas or permanent WebGL.
- Rendering authorities: existing `PlayerCardView` and `TeamShieldView`.
- Review surface: `/laboratorio-premium-art-pack`, `noindex`, `nofollow` and absent from normal navigation.
- Review contact sheet: `artifacts/visual-audit-v1/after/premium-art-pack-contact-sheet.jpg`.

## Proposal catalog

| Name | Type | Collection | Technique | Reuse | Performance | LOD | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Balon Orbital IQ | Simbolo | Future IQ | 2D | Player + team | SVG 607 B | Outline + pentagon at 32px | MANTENER |
| Puerta del Barrio | Simbolo | Futbol de Barrio | 2D | Team | SVG 576 B | Outer arch at 32px | MANTENER |
| Nodo Future IQ | Simbolo | Future IQ | 2D | Player + team | SVG 560 B | Hexagon + core at 32px | MANTENER |
| Brujula de Partido | Simbolo | Noche de Partido | 2D | Team | SVG 511 B | Four points at 32px | REVISAR |
| Torre Elite Mk II | Simbolo | Futbol de Barrio | Pseudo-3D | Team | Inline CSS/SVG | Silhouette without windows at 32px | MANTENER |
| Rayo Doble Tactico | Simbolo | Noche de Partido | Pseudo-3D | Player + team | CSS clip-path | One bolt at 24px | MANTENER |
| Monograma Bloque | Simbolo | Retro | Pseudo-3D | Player + team | HTML/CSS | Flat two-letter mark at 24px | MANTENER |
| Insignia Anidada | Simbolo | Retro | Pseudo-3D | Team | CSS | Two outlines at 32px | REVISAR |
| Estrella Vector IQ | Simbolo | Future IQ | Pseudo-3D | Player + team | CSS clip-path | Four points at 24px | MANTENER |
| Corona Geometrica | Simbolo | Base IQ | Pseudo-3D | Player + team | CSS clip-path | Three solid peaks at 32px | REVISAR |
| Corona Barrio | Corona | Futbol de Barrio | 2D | Team | SVG 597 B | Silhouette + base at 48px | MANTENER |
| Corona Elite | Corona | Noche de Partido | Blender prerender | Player + team | WebP 13,916 B | Prerender large; later flat silhouette below 48px | MANTENER |
| Corona Future IQ | Corona | Future IQ | 2D | Team | SVG 620 B | Main circuit trace at 48px | MANTENER |
| Corona Retro Club | Corona | Retro | 2D | Team | SVG 633 B | Remove rivets at 48px | MANTENER |
| Estrella Singular | Estrella | Base IQ | Pseudo-3D | Player + team | CSS | Same silhouette from 24px | MANTENER |
| Trio de Estrellas | Estrella | Retro | Pseudo-3D | Team | HTML/CSS | One star at 24-32px | MANTENER |
| Medallon Future | Estrella | Future IQ | Blender prerender | Player + team | WebP 32,326 B | Large WebP; flat patch below 48px | MANTENER |
| Parche Estrella | Estrella | Noche de Partido | 2D | Player + team | SVG 566 B | Remove stitching at 32px | REVISAR |
| Laureles Minted | Laureles | Retro | 2D | Team | SVG 620 B | Branches + four leaves at 48px | MANTENER |
| Laureles Compactos | Laureles | Retro | 2D | Team | Reuses same SVG | Hide alternate leaves | MANTENER |
| Banner de Reto | Banner | Futbol de Barrio | 2D | Team | SVG 550 B | Plain center plate at 48px | MANTENER |
| Ribbon Future IQ | Banner | Future IQ | 2D | Team | SVG 620 B | Remove outer ribbon at 48px | REVISAR |
| Placa Barrio | Banner | Futbol de Barrio | Pseudo-3D | Team | CSS | Single rectangle at 32px | REVISAR |
| Cobre Forjado | Material | Futbol de Barrio | Pseudo-3D | Player + team | CSS + current texture | Flat copper at 24-32px | MANTENER |
| Plata Satinada | Material | Retro | Pseudo-3D | Player + team | CSS + current texture | Two tones at 24-32px | MANTENER |
| Carbono Tactico | Material | Future IQ | Pseudo-3D | Player + team | Two CSS gradients | Matte black without weave at 32px | MANTENER |
| Cromo Navy | Material | Future IQ | Pseudo-3D | Player + team | CSS gradient | Solid navy at 24-48px | REVISAR |
| Edge Glow Controlado | Efecto | Future IQ | Pseudo-3D | Player + team | Static box-shadow | Static halo at 24-48px | MANTENER |
| Holo Loop Continuo | Efecto | Noche de Partido | Pseudo-3D | Player + team | Permanent animation | Not applicable | DESCARTAR |

## Blender pipeline

`tools/premium-art-pack-v1/render_assets.py` regenerates the two source renders. Blender 5.1 compatibility required resolving the Principled material node by type and using the supported Eevee engine identifier. Source PNGs are transient build material; only compressed WebP delivery files belong in `public/`.

The chosen hybrid keeps premium depth where it matters and uses SVG/CSS for small LODs. A future production catalog should add a dedicated flat fallback for the two prerenders before using them below 48px.

## Protected reward mappings

The laboratory renders, but does not modify, the exact five active mappings:

| Existing event | Existing reward |
| --- | --- |
| First challenge win | Copper |
| 10 challenges | Banner |
| 25 matches | Laurels |
| 50 matches | Silver |
| First clean sheet | Edge Glow |

No proposal creates a tournament, TOPS or season mapping. Premium Ball remains `READY_PENDING_PHYSICAL_QA`; sensor and GLB behavior stay outside production.

## Review decision

The `MANTENER` group is technically suitable for a later catalog/product review, not automatic release. `REVISAR` pieces need art direction or a stronger small-size fallback. `Holo Loop Continuo` is rejected because permanent motion competes with sporting information and violates the performance/reduced-motion direction.
