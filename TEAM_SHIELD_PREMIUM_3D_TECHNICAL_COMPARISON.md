# Team Shield Premium 3D Technical Comparison

## Resumen ejecutivo

| Pipeline | Resultado | Peso visual | JS adicional | Movimiento | Uso recomendado | Decisión |
| --- | ---: | ---: | ---: | --- | --- | --- |
| A. Blender prerender | 1 WebP completo | 37,112 B (Oro) | Sin motor 3D | Parallax del conjunto | 48/64, listas destacadas, fallback | MANTENER / PRODUCCIÓN |
| B. Ocho vistas | Base + corona + frame | 41,094 B inicial; 79,676 B con 8 vistas | Ligero | Cambio de vista + parallax | 64/medio, balón premium | MANTENER / PRODUCCIÓN |
| C. Three.js + GLB | Geometría real | GLB 214,536 B | 595,860 B raw / 149,391 B gzip diferidos | Inclinación continua | Editor, perfil, modal grande | REVISAR / LAB CONTROLADO |

## Medición exacta

### Assets

| Asset/familia | Bytes |
| --- | ---: |
| Render completo Oro | 37,112 |
| Base Oro sin balón/corona | 30,248 |
| Corona Oro overlay | 5,282 |
| Corona Cromo overlay | 5,116 |
| Primera vista de balón | 5,564 |
| Ocho vistas de balón | 44,146 |
| Pipeline B, carga inicial Oro | 41,094 |
| Pipeline B, todas las vistas visitadas | 79,676 |
| GLB completo | 214,536 |
| Todos los assets públicos del laboratorio | 624,958 |

Los 624,958 B no se descargan de una vez en un uso real: el navegador solicita el material y la vista activos. El laboratorio de comparación sí termina mostrando más variantes al recorrer la página.

### JavaScript y CSS de build

| Chunk | Raw | Gzip | Observación |
| --- | ---: | ---: | --- |
| UI inicial del laboratorio | 59,225 B | 16,646 B | A/B, controles y composición; sin canvas C |
| Wrapper dinámico de C | 4,297 B | 2,013 B | Visor, materiales y ciclo de vida |
| Three.js + GLTFLoader | 591,563 B | 147,378 B | Motor compartido por la carga dinámica de C |
| Total JS diferido de C | 595,860 B | 149,391 B | Se solicita únicamente al elegir `C GLB` |
| CSS asociado a la ruta | 93,388 B | 16,021 B | Incluye estilos importados del renderer canónico |

Three.js ya existe como dependencia del producto por la demo de recompensas, pero el build genera un chunk específico para esta ruta. Por ello no debe asumirse que su coste es cero.

## Pipeline A: prerender transparente

### Ventajas

- payload mínimo;
- resultado idéntico entre navegadores;
- no requiere WebGL;
- perfecto para caché larga;
- apto para listas y varias instancias;
- fallback robusto si falla C.

### Límites

- el volumen no cambia realmente con el ángulo;
- cada combinación de material/corona necesita asset o composición;
- el parallax del conjunto no equivale a iluminación 3D.

### Clasificación

MANTENER. VIABLE PARA PRODUCCIÓN.

## Pipeline B: multi-vista pseudo-3D

### Ventajas

- el balón cambia perceptualmente sin WebGL;
- cada vista pesa aproximadamente 5-6 KB;
- permite descargar solo el frame activo;
- funcionamiento determinista y compatible con caché;
- coste bajo incluso después de visitar las ocho vistas;
- muy buen equilibrio para móvil.

### Límites

- ocho escalones, no rotación continua;
- el marco conserva iluminación prerenderizada;
- necesita precarga selectiva para evitar un primer cambio tardío en redes lentas.

### Clasificación

MANTENER. VIABLE PARA PRODUCCIÓN en superficies destacadas. Es el pipeline recomendado por defecto para el balón premium.

## Pipeline C: 3D real

### Implementación

- `three` y `GLTFLoader` sin React Three Fiber;
- GLB de 215 KB;
- materiales del marco/corona reemplazables por nombre de objeto;
- `ResizeObserver` y pixel ratio máximo 1.5 en táctil, 2 en PC;
- `preserveDrawingBuffer` solo para diagnóstico del laboratorio;
- carga dinámica, no incluida en A/B;
- fallback visual disponible mediante A/B.

### Ventajas

- profundidad, reflejos y oclusión reales;
- inclinación continua;
- una geometría admite varios materiales;
- mayor sensación premium en vista grande.

### Límites

- 147 KB gzip adicionales de JavaScript más 215 KB de modelo;
- coste GPU continuo cuando está activo;
- no es razonable repetirlo en listas;
- más superficie de mantenimiento y compatibilidad;
- requiere prueba física en iOS/Android antes de producción.

### Rendimiento observado

- canvas no vacío y fase `ready` en 1440 x 900 y 844 x 390;
- aproximadamente 121 iteraciones de render en un segundo en el equipo local;
- 0 iteraciones adicionales durante 700 ms en reduced motion;
- sin overflow horizontal en los tres viewports probados;
- controles secundarios con scroll interno en 844 x 390.

### Clasificación

REVISAR. VIABLE SOLO COMO LAB/EDITOR CONTROLADO en V0.1. No compensa para listas, retos, miniaturas, tablas ni Tops.

## Sensor y privacidad

No se solicita permiso al cargar. El usuario pulsa `Activar sensor`; después:

1. si existe `requestPermission`, se solicita y se respeta su resultado;
2. si el navegador ofrece `DeviceOrientation` sin permiso explícito, se conecta después del gesto;
3. si no existe o se deniega, el escudo sigue estático;
4. no se persisten ángulos ni datos del dispositivo;
5. reduced motion bloquea sensor y puntero.

La fórmula de inclinación limita beta/gamma a +/-6 grados. No existe rotación autónoma ni acumulativa.

## Fallos encontrados durante QA

| Hallazgo | Causa | Corrección | Regresión |
| --- | --- | --- | --- |
| GLB visto de canto | Conversión de ejes Blender Z-up a glTF Y-up | Rotación base de 90 grados antes del encuadre | Captura frontal + canvas no vacío |
| Primera hoja multi-vista recortada | Varias instancias no formaban celdas independientes fiables | Ocho WebP individuales generados por Blender | Captura móvil con balón circular |
| Hydration mismatch en sensor | Estado inicial dependía de `window` | Estado SSR determinista; detección tras gesto | Consola recargada sin error de hidratación |
| Corona Cromo casi invisible | Rugosidad demasiado baja | Cromo más rugoso y menos especular | Render y panel de materiales |

## Recomendación técnica

Adoptar una arquitectura híbrida si el concepto se aprueba:

- A como read model visual y fallback universal;
- B como interacción premium habitual;
- C como mejora progresiva bajo demanda en una sola instancia grande;
- caché larga para WebP/GLB versionados;
- ningún cambio al contrato productivo hasta validar sensor físico y segunda corona;
- nunca múltiples canvases C en listados.

Esta arquitectura conserva la autoridad del servidor para inventario/loadout cuando llegue la integración. Los assets locales son representación; nunca una fuente de verdad sobre propiedad o equipamiento.
