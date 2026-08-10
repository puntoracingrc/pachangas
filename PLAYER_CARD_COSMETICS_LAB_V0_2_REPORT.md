# Player Card Cosmetics Lab V0.2

## Alcance

- Ruta: `/laboratorio-cosmeticos-ficha`.
- Metadatos: `noindex, nofollow`.
- 30 propuestas visuales.
- 14 piezas seleccionadas para catálogo real V1.
- 16 piezas exclusivamente experimentales.
- Renderer: `PlayerCardView` mediante la capa compartida de cosméticos.
- Datos deportivos fijos para comparar todas las variantes.

## Decisión artística

`MANTENER` significa conservar en V1 o como candidato fuerte. `REVISAR` permanece en laboratorio. `DESCARTAR` no debe entrar en recompensas con el diseño actual.

| Nombre | Slot | Colección | Material/variante | Rareza | Rendimiento | Decisión |
| --- | --- | --- | --- | --- | --- | --- |
| Barrio Acero | Marco | Fútbol de Barrio | Barrio / acero | Común | Estático | MANTENER |
| Marco Cobre | Marco | Fútbol de Barrio | Barrio / cobre | Poco común | Estático | MANTENER |
| Barrio Plata | Marco | Fútbol de Barrio | Barrio / plata | Raro | Estático | MANTENER |
| Future IQ Navy | Marco | Future IQ | Future / navy | Épico | Estático | MANTENER |
| Retro Cromo | Marco | Retro | Retro / cromo | Legendario | Estático | MANTENER |
| Asfalto Nocturno | Fondo | Noche de Partido | Negro mate | Común | Estático | MANTENER |
| Grid IQ | Fondo | Future IQ | Grid / navy | Poco común | Estático | MANTENER |
| Acento Cobre | Acento | Fútbol de Barrio | Cobre | Poco común | Estático | MANTENER |
| Acento Navy | Acento | Future IQ | Navy | Épico | Estático | MANTENER |
| Focos | Efecto | Noche de Partido | Barrido de luz | Raro | 120,6 FPS | MANTENER |
| IQ Scan | Efecto | Future IQ | Scan horizontal cian | Épico | 120,6 FPS | MANTENER |
| Glint Oro | Efecto | Noche de Partido | Reflejo diagonal | Legendario | 120,6 FPS | MANTENER |
| De toda la vida | Título | Fútbol de Barrio | Texto | Común | Estático | MANTENER |
| Motor del equipo | Título | Noche de Partido | Texto | Raro | Estático | MANTENER |
| Barrio Bronce | Marco | Fútbol de Barrio | Barrio / bronce | Poco común | Estático | REVISAR |
| Barrio Oro | Marco | Noche de Partido | Barrio / oro | Legendario | Estático | REVISAR |
| Future Carbono | Marco | Future IQ | Future / carbono | Épico | Estático | MANTENER |
| Barrio Negro Mate | Marco | Noche de Partido | Barrio / negro mate | Raro | Estático | MANTENER |
| Future Perla | Marco | Future IQ | Future / perla | Raro | Estático | REVISAR |
| Papel de Liga | Fondo | Retro | Papel impreso | Común | Estático | REVISAR |
| Pizarra de Míster | Fondo | Fútbol de Barrio | Pizarra | Raro | Estático | MANTENER |
| Noche de Focos | Fondo | Noche de Partido | Grada / luz | Épico | Estático | REVISAR |
| Acento Plata | Acento | Retro | Plata | Raro | Estático | MANTENER |
| Acento Cian | Acento | Future IQ | Cian IQ | Raro | Estático | MANTENER |
| Acento Oro | Acento | Noche de Partido | Oro | Legendario | Estático | DESCARTAR |
| Scan Diagonal | Efecto | Future IQ | Scan diagonal cian | Raro | 120,6 FPS | MANTENER |
| Holo Suave | Efecto | Future IQ | Holo contenido | Épico | 120,0 FPS | REVISAR |
| Barrido Cromo | Efecto | Retro | Glint frío | Épico | Equivalente a Glint | MANTENER |
| Capitán de barrio | Título | Fútbol de Barrio | Texto | Raro | Estático | REVISAR |
| Turno de noche | Título | Noche de Partido | Texto | Poco común | Estático | REVISAR |

## Catálogo V1 seleccionado

Las 14 piezas activas cubren los cinco slots sin saturar la primera economía. Mantienen una identidad de fútbol amateur y videojuego, combinan entre colecciones y no dependen de recursos pesados. Oro, carbono, perla, holo y variantes adicionales permanecen en laboratorio hasta tener reglas de mérito y contraste más maduras.

No se cambian pools ni probabilidades: las claves reales se integran en las entradas cosméticas ya existentes. Cada variante sigue siendo una pieza independiente aunque comparta `frameStyle`, material o motor de efecto.

## Materiales y efectos compartidos

El renderer separa estilo y material. `Barrio / cobre` y `Barrio / plata` comparten geometría; `Future / navy` y `Future / carbono` comparten estilo. Los tokens contienen base, acento y brillo para acero, bronce, cobre, plata, oro, navy, carbono, negro mate, perla, cromo y cian IQ.

V1 permite un solo `effect` principal. Fondo, marco y acento pueden acompañarlo. Esta limitación evita una estética de casino y mantiene legibles foto, nombre, GRL y facetas.

## Rendimiento

Medición en Chromium, 1440x900 y panel de 120 Hz, 1,6 segundos por estado:

| Estado | FPS | p95 frame | Frames >25 ms | Máximo |
| --- | ---: | ---: | ---: | ---: |
| Focos | 120,6 | 10,0 ms | 0 | 10,4 ms |
| Scan horizontal | 120,6 | 10,3 ms | 0 | 10,4 ms |
| Glint Oro | 120,6 | 10,1 ms | 0 | 10,3 ms |
| Holo Suave | 120,0 | 9,9 ms | 0 | 10,3 ms |
| Future IQ completo | 120,0 | 10,2 ms | 0 | 10,4 ms |

Los efectos usan CSS, `transform`, `opacity` y fondos. No existe canvas ni WebGL persistente. Con `prefers-reduced-motion: reduce`: `animation-name: none`, `transform: none`, `will-change: auto`, y opacidad estática 0,28.

## QA responsive

| Vista | Resultado |
| --- | --- |
| 1440x900 | Sin overflow horizontal; editor, preview y catálogo visibles. |
| 390x844 | Sin overflow horizontal; carta compacta, tabs desplazables y acciones accesibles. |
| 844x390 | Sin overflow horizontal; carta, selectores y acciones caben en primera vista. |

## Capturas

Generales:

- `artifacts/player-cosmetics-qa/lab-desktop-1440x900.png`
- `artifacts/player-cosmetics-qa/lab-desktop-night-1440x900.png`
- `artifacts/player-cosmetics-qa/lab-mobile-390x844.png`
- `artifacts/player-cosmetics-qa/lab-landscape-844x390.png`

Estados individuales:

- `lab-original-1440x900.png`
- `lab-barrio-acero-1440x900.png`
- `lab-marco-cobre-1440x900.png`
- `lab-barrio-bronce-1440x900.png`
- `lab-barrio-plata-1440x900.png`
- `lab-barrio-oro-1440x900.png`
- `lab-future-navy-1440x900.png`
- `lab-future-carbono-1440x900.png`
- `lab-negro-mate-1440x900.png`
- `lab-future-perla-1440x900.png`
- `lab-future-iq-1440x900.png`
- `lab-focos-1440x900.png`
- `lab-scan-horizontal-1440x900.png`
- `lab-scan-diagonal-1440x900.png`
- `lab-glint-oro-1440x900.png`
- `lab-holo-suave-1440x900.png`
- `lab-combinacion-compleja-1440x900.png`
- `lab-reduced-motion-1440x900.png`

Todos esos archivos están bajo `artifacts/player-cosmetics-qa/`.

## Conclusión

La dirección más propia de Pachangas IQ es una base sobria de barrio, materiales reconocibles y un único detalle animado. Carbono y negro mate merecen una segunda selección futura. Oro y holo deben seguir siendo raros y discretos. La capa compartida queda lista para reutilizar materiales y UX en el escudo, manteniendo inventarios y permisos separados.
