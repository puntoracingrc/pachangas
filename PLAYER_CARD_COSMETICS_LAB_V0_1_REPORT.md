# Player Card Cosmetics Lab V0.1

## Alcance

- Base auditada: `e4a09028d769149faa888205522015a0fb9d4074` (PR #121).
- Ruta: `/laboratorio-cosmeticos-ficha`.
- Naturaleza: laboratorio visual, sin catálogo definitivo, propiedad, inventario, equipamiento, economía ni persistencia.
- Slots representados: `card_frame`, `card_background`, `card_effect`, `player_title` y `featured_badge`.
- El badge usa exclusivamente previews de logros reales: Hat-trick, Primera conquista y Póker.

## Auditoría de la ficha existente

La ficha de producto activa estaba implementada dentro de `app/page.tsx` con la estructura `.fifa-player-card`. El laboratorio anterior de ficha de jugador contiene una representación simplificada propia y no se ha tomado como segunda fuente de verdad visual.

Se extrajo `PlayerCardView` como componente presentacional compartido. `app/page.tsx` conserva las decisiones existentes sobre GRL, tier, posición, facetas, tendencia, edad, permisos y arrastre de la foto; únicamente entrega esos valores al componente. El nuevo laboratorio reutiliza el mismo componente con datos deportivos fijos. No se ha importado, copiado ni alterado el motor de Rating V2.

## Datos fijos

- GRL: 78.
- Posición: MC.
- Facetas: 78 RIT, 72 TIR, 81 PAS, 79 REG, 64 DEF y 76 FÍS.
- Estadísticas: 14 goles, 28 partidos y 29 años.
- Nombres probados: Marc y Alejandro Martínez.
- Retrato único: `public/lab/player-card-preview.jpg`, generado con Imagegen para este laboratorio y reutilizado sin cambios en todas las variantes.

## Catálogo experimental

| Pieza | Colección | Slot | Recomendación | Motivo |
| --- | --- | --- | --- | --- |
| Barrio Acero | Fútbol de Barrio | card_frame | MANTENER | Material reconocible, contenido y compatible con la carta base. |
| Retro Cromo | Retro | card_frame | REVISAR | La silueta funciona, pero el cromo necesita una firma más propia antes de producción. |
| Future IQ | Future IQ | card_frame | MANTENER | Es el marco más distintivo y conserva bien la lectura. |
| Asfalto Nocturno | Noche de Partido | card_background | MANTENER | Buen contraste y carácter futbolero sin ocultar datos. |
| Papel de Liga | Retro | card_background | MANTENER | Diferencia claramente la colección y admite marcos ajenos. |
| Grid IQ | Future IQ | card_background | MANTENER | Da profundidad técnica sin competir con la foto. |
| Focos | Noche de Partido | card_effect | MANTENER | Movimiento sutil y barato, con fallback estático convincente. |
| IQ Scan | Future IQ | card_effect | REVISAR | Es fluido, pero conviene reforzar su presencia visual sin aumentar velocidad. |
| De toda la vida | Fútbol de Barrio | player_title | MANTENER | Corto, legible y con personalidad comunitaria. |
| Motor del equipo | Noche de Partido | player_title | REVISAR | Visualmente funciona; su concesión futura necesita una regla de mérito explícita. |

### Selección recomendada para producción

1. Barrio Acero.
2. Future IQ.
3. Asfalto Nocturno.
4. Grid IQ.
5. Focos.
6. De toda la vida.

## Composición

La mezcla deliberadamente extrema `Future IQ + Papel de Liga + Focos + Motor del equipo + Primera conquista` mantuvo contraste, jerarquía y dimensiones. No se recomienda bloquear combinaciones en esta fase. Un catálogo futuro debería destacar presets coherentes por colección y avisar de contraste insuficiente mediante tokens de tema, conservando la composición libre.

## Rendimiento y accesibilidad

Medición en Chromium a 1440x900, panel de 120 Hz, durante 2,4 segundos por efecto:

| Efecto | FPS observado | p95 de frame | Frames >34 ms |
| --- | ---: | ---: | ---: |
| Focos | 120,0 | 9,30 ms | 0 |
| IQ Scan | 120,0 | 9,20 ms | 0 |

Los efectos animan solo `transform` y `opacity`, están aislados con `contain` y usan `will-change`. Con `prefers-reduced-motion: reduce`, ambas animaciones quedan en `animation: none` y conservan una representación estática.

## QA responsive

| Vista | Resultado |
| --- | --- |
| 1440x900 | Sin overflow horizontal, diez muestras y seis selectores operativos. |
| 390x844 | Sin overflow horizontal; Alejandro Martínez y todos los datos caben en la carta. |
| 844x390 | Sin overflow horizontal; nombre largo completo y controles disponibles. |

La comparación original/cosmética conserva exactamente la misma información deportiva. La consola no registró errores ni avisos durante la navegación e interacción.

## Capturas

Las siete capturas se regeneraron desde la Preview de Vercel del PR #122, no desde el servidor de desarrollo.

- `artifacts/player-card-cosmetics-lab/original-1440x900.png`
- `artifacts/player-card-cosmetics-lab/barrio-1440x900.png`
- `artifacts/player-card-cosmetics-lab/noche-1440x900.png`
- `artifacts/player-card-cosmetics-lab/retro-1440x900.png`
- `artifacts/player-card-cosmetics-lab/future-iq-1440x900.png`
- `artifacts/player-card-cosmetics-lab/portrait-390x844.png`
- `artifacts/player-card-cosmetics-lab/landscape-844x390.png`

## Flujo futuro no implementado

`achievement -> box -> cosmetic reward -> inventory -> loadout -> player card`

El laboratorio solo demuestra la última capa visual. No define probabilidades, rarezas contractuales, costes, propiedad, desbloqueo, equipamiento ni reglas de logros.
