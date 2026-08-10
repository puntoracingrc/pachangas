# Team Shield Cosmetics Lab V0.1

Estado: LABORATORIO VISUAL IMPLEMENTADO. NOINDEX/NOFOLLOW.

Ruta: `/laboratorio-cosmeticos-escudo`.

El laboratorio usa `TeamShieldView`, `TeamShieldConfig` y el Shared Cosmetics
Editor reales. No compara ni conserva el renderer antiguo. Sus guardados son
simulados y nunca modifican PostgreSQL.

## Base Nueva

- 8 formas: Clasico IQ, Redondo, Alto, Suizo, Hex IQ, Diamante, Modern Crest y
  Barrio Shield.
- 6 colores normales gratuitos.
- 3 fondos, 4 patrones, 5 simbolos y 2 bordes base.
- Iniciales de hasta cuatro caracteres y ano opcional.
- Preview central, tabs, miniaturas, swatches, reset, estado sin guardar y
  seleccion visual; no es una coleccion de selects.

## Propuestas V0.1

Total: 28.

| Decision | Cantidad |
| --- | ---: |
| MANTENER | 16 |
| REVISAR | 12 |
| DESCARTAR | 0 |

LAB ONLY: Cromo, Alas y Holo.

## Candidatas V1

Las 16 candidatas reales son:

1. Acero
2. Cobre
3. Plata
4. Navy
5. Carbono
6. Grid IQ
7. Retro
8. Torre Elite
9. Estrella Future
10. Corona Geometrica
11. Tres Estrellas
12. Laureles
13. Banner
14. Glint
15. Scan
16. Edge Glow

Bronce, Oro, Negro Mate, Cromo, Perla, Pizarra, Hex Mesh, Doble Rayo, Alas,
Rayos Laterales, Placa y Holo quedan en REVISAR.

## Evaluacion

- Identidad: lenguaje propio IQ, sin logos de clubes ni copia de productos.
- Combinabilidad: slots y anchors controlados; maximo un efecto.
- Pequeno: LOD oculta detalle en 24/32/48 sin cambiar la identidad.
- Grande: materiales, ornamentos, iniciales y ano permanecen legibles.
- Movil horizontal: editor a dos columnas; acciones dentro de 844x390.
- Movil vertical: preview primero y controles tactiles en grid.
- Reduced motion: efectos quedan estaticos y legibles.
- Rendimiento: CSS, gradients, masks/clip-path y SVG ligero; sin WebGL/canvas.

## Evidencia Visual

- `artifacts/team-shield-cosmetics-qa/lab-desktop-1440x900.png`.
- `artifacts/team-shield-cosmetics-qa/lab-portrait-390x844.png`.
- `artifacts/team-shield-cosmetics-qa/lab-landscape-844x390.png`.
- `artifacts/team-shield-cosmetics-qa/lab-landscape-reduced-motion.png`.
- `artifacts/team-shield-cosmetics-qa/lab-full-catalog.png`.

La Vercel Preview `dpl_Es9eQsUuiWbYucwJhLk88v1haVWt` reproduce el
laboratorio en el commit funcional `e9e045d3f693364089b8886037be7658fdb82985`.
La QA remota confirma `200`, `noindex`, cero overflow de documento, cero
warnings/errores de consola y ausencia de solapes en 844x390 tras compactar la
navegacion de categorias a dos filas.

Las capturas prueban Base IQ, Barrio, Future IQ, Noche, materiales, patrones,
complementos, efectos, catalogo y LOD 24/32/48/64.

## Decision Pendiente

Las 16 candidatas son propuesta de Release Candidate, no economia activa. La
asignacion logro -> cosmetico sigue separada en
`TEAM_COSMETIC_REWARD_MAPPING_PROPOSAL.md` y requiere decision de producto.
