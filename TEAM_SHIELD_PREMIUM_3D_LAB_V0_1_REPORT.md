# Team Shield Premium 3D Lab V0.1

## Estado

| Campo | Valor |
| --- | --- |
| Fecha de cierre local | 2026-08-10 20:36 CEST |
| SHA inicial | `b3d013f21a987bac1025b3cdcc134bd472ec6619` |
| Rama | `codex/team-shield-premium-3d-lab-v0-1` |
| PR base | `#130` (`codex/team-shield-cosmetics-v1`) |
| SHA de implementación | `401c47e06f654318cca6824e56d0f513adde9b3a` |
| SHA final | Head del PR borrador; se entrega fuera del propio commit para evitar una referencia circular |
| Producción | No modificada |
| Supabase | No consultado ni modificado |
| Staging | No usado; Preview Vercel es suficiente para este laboratorio aislado |
| PR borrador | `#131` |
| Preview | `https://pachangas-git-codex-team-aca328-persianas-almar-web-s-projects.vercel.app/laboratorio-cosmeticos-escudo-3d` |

## Alcance

El laboratorio vive exclusivamente en `/laboratorio-cosmeticos-escudo-3d`, con `noindex` y `nofollow`. No altera `TeamShieldView`, `TeamShieldConfig`, catálogo, inventario, loadout, Realtime, RLS, PWA, ratings, Tops, Conduct ni Core Social.

No existe persistencia, RPC, API, `localStorage`, flag de producción ni asignación económica. Los controles solo modifican estado efímero del laboratorio.

## Blender

Se utilizó Blender `5.1.2` en modo batch mediante:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background \
  --python scripts/team-shield-premium-3d/generate-assets.py
```

El script genera de forma reproducible:

- geometría extruida del escudo y su borde tubular;
- balón IQ facetado con tres costuras;
- corona extruida;
- materiales Cobre, Plata, Oro, Cromo y Carbono;
- renders WebP RGBA de 768 x 768;
- ocho vistas WebP del balón de 256 x 256;
- GLB con objetos nombrados para cambiar materiales en Three.js;
- fuente `.blend` de 121 KB.

## Piezas estudiadas

### Balón 3D

Es la pieza con mayor ganancia visual. Tiene volumen claro, lectura inmediata y responde bien tanto al cambio entre ocho vistas como a la inclinación real del GLB. En 24/32 px pierde detalles, por lo que allí se conserva el símbolo 2D canónico.

**Decisión:** MANTENER.

**Viabilidad:** PRODUCCIÓN mediante pipeline B en tamaños medios y grandes. Pipeline C solo en editor, perfil o modal grande.

### Marco premium

Cobre, Plata y Oro se leen bien y aportan volumen sin alterar la silueta. Cromo funciona en grande, pero sus reflejos pierden consistencia en fondos claros. Carbono es elegante pero demasiado discreto a 48 px.

**Decisión:** MANTENER Cobre/Plata/Oro; REVISAR Cromo/Carbono.

**Viabilidad:** PRODUCCIÓN con prerender en 48/64/medio. GLB solo en superficies grandes.

### Corona premium

Oro comunica premio y mantiene buena lectura en grande. La geometría actual es intencionadamente simple, pero todavía parece un prototipo en 24/32 px. Cromo ya es visible después de reducir su especularidad, aunque sigue necesitando una silueta más propia.

**Decisión:** REVISAR.

**Viabilidad:** SOLO LAB hasta una segunda pasada de modelado. En tamaños pequeños debe omitirse o volver a la corona 2D.

## Movimiento

### Móvil y tablet

- El sensor solo se activa tras una acción explícita del usuario.
- En iOS se usa `DeviceOrientationEvent.requestPermission()` cuando existe.
- En otros navegadores se registra `deviceorientation` después del botón de activación.
- La inclinación se limita a +/-6 grados.
- Permiso denegado, sensor ausente o error: fallback estático.
- El laboratorio incluye controles de simulación para QA sin hardware.

La ruta se comprobó a 390 x 844 y 844 x 390 sin overflow horizontal. En horizontal bajo, las herramientas secundarias usan scroll interno y el escenario permanece visible.

No se completó una prueba física de giroscopio en iPhone/Android durante esta fase local; debe formar parte de la revisión de Preview en dispositivo real.

### PC

La experiencia arranca estática y usa micro-parallax de puntero, limitado a 5/6 grados. Al salir del área vuelve al eje neutro. No existe giro autónomo.

### Reduced motion

`prefers-reduced-motion: reduce` tiene prioridad sobre el control del laboratorio. También existe un modo reducido manual. En ambos casos:

- inclinación a cero;
- sensor y sliders desactivados;
- no se inicia el bucle `requestAnimationFrame` del GLB;
- render premium estático.

La comprobación automática observó `0` frames adicionales durante 700 ms en modo reducido.

## LOD propuesto

| Tamaño/superficie | Representación | Movimiento |
| --- | --- | --- |
| 24 px | `TeamShieldView` 2D canónico | No |
| 32 px | `TeamShieldView` 2D canónico | No |
| 48 px | WebP premium-lite prerenderizado | No |
| 64 px | WebP o vista B seleccionada | Opcional y solo una instancia destacada |
| Tamaño medio | Pipeline B, ocho vistas bajo demanda | Sensor/parallax sutil |
| Editor/perfil/modal grande | Pipeline C cargado bajo demanda; A como fallback | Sí, salvo reduced motion |
| Listas, retos, tablas y Tops | 2D o WebP estático | No |

## QA visual y rendimiento

Entorno: Next.js `16.2.6`, Node `24.16.0`, navegador Chromium integrado, servidor local, Mac del entorno de desarrollo.

Resultados:

- build de producción: correcto;
- typecheck: correcto;
- lint focalizado: correcto;
- pruebas focalizadas: 5/5;
- batería completa: 20/20 pruebas Node y 215/215 pruebas TypeScript;
- lint global: conserva 43 incidencias preexistentes (23 errores y 20 avisos) fuera de los archivos del laboratorio;
- carga inicial: pipeline A sin canvas ni chunk Three.js;
- canvas GLB: `data-canvas-nonblank=true`;
- fase GLB: `ready`;
- escritorio 1440 x 900: sin overflow horizontal;
- móvil 390 x 844: sin overflow horizontal;
- horizontal 844 x 390: sin overflow horizontal;
- tasa local aproximada del bucle: 121 frames en 1 segundo en una pantalla de alta frecuencia;
- reduced motion: 0 frames adicionales en 700 ms;
- carga limpia en servidor reiniciado: sin errores, mismatch de hidratación, avisos LCP ni assets 404 después de priorizar las capas visibles y mantener lazy las variantes no repetidas.

La QA se repitió en la Preview de Vercel del PR #131: pipeline A inició con cero canvases, pipeline C creó exactamente un canvas no vacío y los viewports 390 x 844 y 844 x 390 permanecieron sin overflow. Con movimiento reducido activo, el contador de frames no avanzó durante 800 ms.

La cifra de frames no sustituye una medición física en Android/iPhone. Sirve para demostrar que el modelo no satura el equipo de desarrollo y que el bucle se detiene realmente en reduced motion.

## Capturas

- `artifacts/team-shield-premium-3d-qa/desktop-editor-glb-frontal.png`
- `artifacts/team-shield-premium-3d-qa/desktop-editor-glb-tilted.png`
- `artifacts/team-shield-premium-3d-qa/desktop-editor-reduced.png`
- `artifacts/team-shield-premium-3d-qa/mobile-portrait-multiview.png`
- `artifacts/team-shield-premium-3d-qa/mobile-landscape-editor-glb.png`
- `artifacts/team-shield-premium-3d-qa/pipeline-comparison.png`
- `artifacts/team-shield-premium-3d-qa/materials-crowns-lod.png`

## Conclusión

Sí merece la pena una capa premium 3D, pero no un renderer 3D universal.

La combinación recomendada es:

1. Pipeline A para miniaturas y fallback.
2. Pipeline B para el balón premium interactivo en 64 px, tamaño medio y superficies destacadas.
3. Pipeline C únicamente en editor, perfil de equipo o modal grande, con carga bajo demanda.
4. `TeamShieldView` intacto en 24/32 px y en listados densos.

El siguiente paso realista es revisar la silueta de la corona, probar el sensor en un iPhone y un Android físicos desde Preview y, solo después, definir un contrato premium/fallback sin asignarle todavía economía ni rareza.
