# Team Shield Cosmetics V1 - Visual Polish Report

Fecha: 2026-08-10.

PR: #130 (`codex/team-shield-cosmetics-v1`).

Commit inicial auditado: `91f72829cc1405dd5f9a89d1c1d8a6305a82a4ef`.

Estado: pulido visual listo para revision humana. No fusionado. No desplegado a
produccion.

## Perimetro

Esta pasada solo modifica el renderer visual compartido, el catalogo de
propuestas, el laboratorio, sus pruebas y la evidencia documental. No modifica
`TeamShieldConfig V1`, inventario, loadouts, vistos, permisos, RLS, RPC,
Realtime, idempotencia, concurrencia, PWA bridge, Rating V2 ni datos deportivos.

Supabase staging no ha recibido migraciones ni cambios de datos durante esta
fase. Los flags de produccion permanecen intactos.

## Hallazgos Y Correcciones

| Hallazgo | Riesgo visual | Correccion | Estado |
| --- | --- | --- | --- |
| Glint y Scan dependian demasiado del instante de animacion | El efecto podia parecer ausente en captura o reduced motion | Estado base reconocible y barrido animado separado | Corregido |
| Holo era casi indistinguible detenido | No justificaba una rareza premium | Borde iridiscente contenido, capa estatica y animacion opcional | REVISAR |
| Edge Glow tenia poca lectura en 82 px | Se confundia con un borde Navy normal | Doble halo exterior y linea interior cian | Corregido |
| Acabados metalicos compartian demasiado lenguaje | Acero, plata, cromo y perla se confundian | Barridos, grano y reflejos especificos por material | Corregido |
| Los simbolos de estrella compartian la misma silueta | Perdida de identidad entre Clasico y Future IQ | Estrella IQ y Estrella Future redibujadas | Corregido |
| Torre Elite tenia una coronacion poco clara | Parecia un trazo accidental | Torre y coronacion geometrica redibujadas | Corregido |
| Ornamentos laterales rozaban etiquetas compactas | Ruido y posible solape | Ancho lateral reducido de 116% a 106% | Corregido |
| Paleta secundaria se recortaba en 844x390 | Controles incompletos en modo juego | Identidad 2x2 y seis swatches por fila | Corregido |

## Simbolos

Los simbolos graficos se renderizan como SVG nativo propio y el monograma como
tipografia, sin logos de clubes ni simbolos protegidos.

- Base legible: Balon IQ, Monograma, Estrella IQ, Rayo y Torre.
- Candidatas V1: Torre Elite y Estrella Future.
- Estudios nuevos, aun LAB ONLY: Corona IQ, Escudo Interior y Orbita IQ.
- Futuro premium: necesita una segunda ronda artistica con variantes de trazo,
  mas pruebas a 24 px y validacion humana antes de asociar recompensas.

## Efectos

| Efecto | Grande | Pequeno | Reduced motion | Decision provisional |
| --- | --- | --- | --- | --- |
| Sin efecto | Referencia limpia | Referencia limpia | Igual | MANTENER |
| Glint | Reflejo diagonal breve | Reflejo estatico | Reflejo estatico | MANTENER |
| Scan | Reticula y linea cian | Marca cian fija | Linea fija | MANTENER |
| Edge Glow | Halo exterior e interior | Contorno reforzado | Igual | MANTENER |
| Holo | Borde iridiscente contenido | Acabado metalico frio | Iridiscencia estatica | REVISAR / LAB ONLY |

No se han usado particulas, destellos aleatorios ni lenguaje de casino.

## LOD Y Legibilidad

- 24 px: simbolo primario; se ocultan iniciales, ano y ornamentos.
- 32 px: simbolo e iniciales; se ocultan ano y adornos delicados.
- 48 px: identidad completa basica; se ocultan ornamentos laterales.
- 64 px: simbolo, iniciales, ano y ornamentos compatibles.
- 82 px o superior: renderer completo.

El ano sigue siendo opcional. Laureles, alas, banners y placas no se fuerzan en
tamanos donde perderian lectura.

## Combinaciones

La contact sheet general incluye 15 combinaciones en cinco familias: Clasico,
Barrio, Future IQ, Noche y Retro.

- LIMPIO: una forma, un material, un simbolo y trama nula o discreta.
- MEDIO: una trama o un ornamento, con efecto opcional.
- CARGADO: varios ornamentos y efecto; se muestra para detectar limites, no como
  recomendacion automatica de producto.

Las combinaciones cargadas conservan lectura, pero deben seguir tratandose como
casos de revision humana antes de formar presets finales.

## Clasificacion Provisional

MANTENER (16): Acero, Cobre, Plata, Navy, Carbono, Grid IQ, Retro, Torre Elite,
Estrella Future, Corona Geometrica, Tres Estrellas, Laureles, Banner, Glint,
Scan y Edge Glow.

REVISAR (15): Bronce, Oro, Negro Mate, Cromo, Perla, Pizarra, Hex Mesh, Doble
Rayo, Alas, Rayos Laterales, Placa, Holo, Corona IQ, Escudo Interior y Orbita
IQ.

DESCARTAR (0): no se descarta ninguna propuesta sin revision humana.

## Evidencia Visual

- `artifacts/team-shield-cosmetics-qa/polish-overview-desktop-1440x900.png`
- `artifacts/team-shield-cosmetics-qa/contact-sheet-families-1440x900.png`
- `artifacts/team-shield-cosmetics-qa/contact-sheet-materials-1440x900.png`
- `artifacts/team-shield-cosmetics-qa/contact-sheet-symbols-1440x900.png`
- `artifacts/team-shield-cosmetics-qa/contact-sheet-effects-1440x900.png`
- `artifacts/team-shield-cosmetics-qa/contact-sheet-ornaments-1440x900.png`
- `artifacts/team-shield-cosmetics-qa/contact-sheet-lod-reduced-motion-1440x900.png`
- `artifacts/team-shield-cosmetics-qa/polish-full-lab-1440.png`
- `artifacts/team-shield-cosmetics-qa/polish-portrait-390x844.png`
- `artifacts/team-shield-cosmetics-qa/polish-landscape-844x390.png`

QA local: 1440x900, 390x844 y 844x390 sin overflow horizontal. La hoja incluye
familias, materiales, simbolos, efectos, ornamentos, LOD y reduced motion.
