# Social Core Visual Contract V1

## Propósito

El núcleo social debe sentirse como un único producto tranquilo, deportivo y previsible. La riqueza de videojuego se reserva para Partido, Alineación, Resultado, Carta, Escudo, recompensas y landscape; formularios, Mercado, Avisos y Ajustes priorizan claridad.

## Estructura

- Navegación primaria: exactamente cuatro destinos.
- Cabecera social: identidad/equipo, campana y avatar como máximo.
- Navegación local: una por pantalla.
- Jerarquía: un H1 y una acción principal.
- Contenido: máximo dos columnas funcionales en desktop y una en portrait.
- Formularios: cerrados hasta que la acción los solicite; nunca dentro de otra tarjeta decorativa.

## Escala

| Token conceptual | Valor recomendado |
| --- | --- |
| Espacio mínimo | 4 px |
| Espacio compacto | 8 px |
| Separación de controles | 10–12 px |
| Separación de bloques | 16–24 px |
| Margen de página portrait | 14–18 px |
| Ancho de lectura | 680–760 px |
| Ancho social amplio | hasta 1180 px |
| Radio de control/tarjeta | 4–8 px |
| Touch target preferente | 44 × 44 px |
| Touch target mínimo | 40 × 40 px |

No se escala tipografía con el ancho del viewport. El texto debe envolver antes de desbordar.

## Tipografía

- H1: identifica la pantalla, no un estado técnico.
- Título de bloque: pequeño y ajustado al contenido.
- Texto secundario: contraste legible, sin competir con la acción.
- Números deportivos: pueden ganar peso en marcador, carta o clasificación.
- Letter spacing: 0.

## Superficies

- Fondos tranquilos y continuidad cromática al cambiar de destino.
- Una tonalidad de acento para la acción principal.
- Bordes solo cuando separan función o selección.
- Sombra contenida; no sustituye la jerarquía.
- Tarjetas grandes: próximo partido, resultado, carta y equipo protagonista.
- Filas compactas: jugadores, invitaciones, avisos, historial, plantilla y resultados de búsqueda.
- No tarjeta dentro de tarjeta salvo una herramienta realmente enmarcada.

## Botones y controles

- Primario: sólido, uno por pantalla.
- Secundario: borde o fondo neutro.
- Terciario: texto o icono accesible.
- Filtros: chips, select o sheet según volumen; no una segunda navegación.
- Menú de más opciones: acciones secundarias o destructivas.
- Iconos: genéricos, con nombre accesible mediante texto, `aria-label` o `title`.

## Estados

`LOADING`, `EMPTY`, `READY`, `SAVING`, `SUCCESS`, `ERROR`, `OFFLINE`, `UNAVAILABLE` y `ACTION_REQUIRED` mantienen dimensiones estables. Ningún cambio de estado mueve la navegación o tapa el CTA.

- Loading: skeleton estable.
- Error: mensaje humano, reintento y alternativa si existe.
- Offline: lectura de última copia y escritura bloqueada.
- Empty: explicación, una acción válida y cero datos inventados.

## Responsive

### Desktop

- Ancho de lectura coherente.
- Listado + detalle solo cuando reduce navegación.
- Sin tres railes ni composición de dashboard administrativo.

### Portrait

- Primer viewport: título, contexto, contenido protagonista y CTA.
- Barra inferior con cuatro destinos y safe area.
- Sheets/formularios con scroll interno; teclado no tapa Guardar.
- Sin doble navegación.

### Mobile Game Landscape

- Rail compacto + contenido protagonista + detalle o acción.
- Sin footer, scroll horizontal raíz ni navegación inferior sobre el campo.
- Mercado, Retos, Equipo y Avisos conservan fondo, transparencia y densidad del shell.
- Los controles no se eliminan por falta de espacio: se compactan o pasan a menús contextuales.

## Temas y movimiento

- Dark y light conservan jerarquía, contraste y significado.
- El tema predeterminado no cambia en V3H.
- `prefers-reduced-motion: reduce` elimina transiciones ornamentales sin romper foco, dialogs o navegación.
- La interfaz funciona también con alto contraste/forced colors cuando el navegador lo aplica.

## Accesibilidad

- Landmarks y un H1 por pantalla.
- `aria-current` para destino y tab activos.
- `aria-expanded` en menús/sheets.
- Focus visible y orden lógico.
- Dialogs con focus trap, Escape y retorno del foco.
- `aria-live` solo para cambios que necesitan anuncio.
- Cero controles sin nombre accesible.

## Rendimiento

- Demo avanzada no se carga en la experiencia social.
- Editores ricos se cargan al abrirlos.
- Cambiar tab/equipo no crea suscripciones duplicadas.
- Realtime invalida la entidad afectada; el payload local es una copia derivada.
- Ninguna ruta debe crecer más de 10 % sin justificación documentada.
