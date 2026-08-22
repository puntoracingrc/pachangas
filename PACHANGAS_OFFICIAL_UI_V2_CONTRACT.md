# Pachangas Official UI V2 Contract

## Estado

- Versión visual: `2.0.0-preview`.
- Referencia: Demo World V1.
- Alcance: presentación y navegación del producto oficial autenticado.
- Autoridad de datos: sin cambios; PostgreSQL/Supabase y las RPC/API existentes continúan siendo la única fuente de verdad.

## Principio

Official UI V2 combina:

```text
funciones y permisos  -> producto oficial
composición visual    -> Demo World
datos y revisiones    -> read models productivos
navegación            -> OfficialProductShellV2
```

No se permite importar fixtures Demo, convertir JSON local en autoridad, duplicar read models canónicos ni mostrar una mutación como confirmada antes de la respuesta del servidor.

## Tokens Semánticos

Los valores se extraen de `app/demo-world/demo-world.module.css` y se formalizan en `app/_design-v2/official-ui-v2-contract.ts`.

| Rol | Valor |
| --- | --- |
| `background` | `#07110f` |
| `surface-primary` | `rgba(18, 29, 26, 0.88)` |
| `surface-elevated` | `rgba(18, 29, 26, 0.94)` |
| `surface-interactive` | `rgba(32, 48, 42, 0.78)` |
| `border` | `rgba(217, 234, 225, 0.16)` |
| `text-primary` | `#f1f6f2` |
| `text-muted` | `#a9bbb2` |
| `accent` | `#c8ef5d` |
| `accent-cool` | `#51cfdf` |
| `info` | `#4d82d8` |
| `danger` | `#d6535c` |
| `warning` | `#efbd64` |

### Geometría

- Espaciado: `4, 8, 12, 16, 24, 32px`.
- Radios: `5px` pequeño, `6px` control, `8px` panel.
- Ancho máximo de contenido: `1440px`; lectura: `720px`.
- Navegación: desktop `64px`, portrait `68px`, rail landscape `88px`.
- Movimiento: `140ms` rápido, `220ms` normal.
- Z-index: navegación `80`, overlay `140`, toast `180`.
- Letter spacing: `0`.

## Tres Composiciones

### `MOBILE_PORTRAIT`

- Se activa hasta `760px`, o en ventanas táctiles menores de `1024px` que no entren en landscape.
- Mantiene una única navegación inferior con 4–5 destinos.
- Permite scroll vertical completo y añade espacio para safe area y barra inferior.
- No fuerza el giro para ninguna función esencial.

### `MOBILE_GAME_LANDSCAPE`

- Teléfono horizontal: ancho `568–932px` y alto máximo `600px`.
- Tablet/iPad táctil horizontal: ancho `768–1368px` y alto máximo `1024px`.
- Se consideran `visualViewport`, orientación, ancho, alto y capacidad táctil; no se usa `userAgent`.
- Rail lateral compacto, context bar, contenido principal y acciones contextualizadas.
- No muestra shell ni footer de escritorio.
- Usa `100dvh`, `visualViewport` y las cuatro `env(safe-area-inset-*)`.
- No depende de Fullscreen API.

### `DESKTOP`

- Cabecera horizontal, navegación de sección, Ranking, Avisos y estado.
- Contenido limitado a `1440px`, con densidad de aplicación operativa.
- Zoom de navegador 125 % y 150 % permanece en desktop con puntero fino.
- No es la base reducida del modo juego.

## Persistencia Al Girar

- `OfficialProductShellV2` monta `children` una sola vez.
- El cambio de modo modifica atributos y CSS; no cambia la key, ruta ni árbol funcional.
- Se escucha `resize`, `orientationchange` y `visualViewport.resize`.
- No se recarga la página, no se reconstruye el formulario y no se dispara una navegación.
- Cualquier estado de alineación, filtro, modal o selección sigue perteneciendo a la ruta oficial.

## Shell

`OfficialProductShellV2` contiene:

- cabecera desktop;
- rail de modo juego;
- context bar;
- viewport de contenido;
- `MobileAppNav` portrait;
- links configurables para conservar la navegación existente;
- `adminViewPreview` solo como vista, sin alterar autorización;
- variante `PRODUCT`.

Control Center conserva su shell y declara `data-shell-variant="PLATFORM_ADMIN"`.

## Componentes Compartidos

- `GamePageHeader`
- `StatusChip`
- `MetricTile`
- `SectionHeader`
- `PrimaryActionCard`
- `SecondaryActionCard`
- `GameTabs`
- `CompactList`
- `ActivityFeed`
- `ResponsiveActionBar`

Se conservan `ProductState` y `ProductFeedback` como autoridades existentes de estados, en vez de duplicarlos.

## Jerarquía De Pantalla

Cada superficie debe ordenar:

1. contexto;
2. estado principal;
3. próxima acción;
4. información secundaria;
5. historial o detalle.

Los controles frecuentes usan botones claros; modos y categorías usan tabs; opciones binarias siguen usando toggles/checkboxes donde ya existen; los iconos mantienen label o tooltip accesible.

## Contrato Por Ruta

| Ruta | Navegación activa | Autoridad conservada |
| --- | --- | --- |
| `/` autenticada | Inicio / Partido / Equipo / Perfil | payload/read models, RPC, Realtime, permisos |
| `/mercado` | Mercado | consultas, filtros y mutaciones del mercado |
| `/ranking` | Equipo | snapshot territorial canónico |
| `/perfil/avisos` | Perfil | preferencias y eventos canónicos |
| `/equipo/identidad` | Equipo | Team Cosmetics, inventario y revisión |
| `/personalizar-carta` | Perfil | Player Cosmetics, inventario y revisión |
| `/admin/*` | `PLATFORM_ADMIN` | RBAC y APIs server-side |
| `/demo` | shell Demo propio | fixtures públicos read-only |
| `/laboratorio-official-ui-v2` | fixtures visuales | ninguna conexión a Supabase |

## Estados

- `loading`: estructura estable, sin salto de layout.
- `empty`: explica ausencia y muestra la siguiente acción permitida.
- `error`: mensaje de producto, nunca error técnico crudo.
- `permission denied`: no renderiza controles operables falsos.
- `offline`: lectura derivada disponible; escritura bloqueada y no confirmada.
- `stale`: muestra estado y solicita/refresca snapshot canónico.
- `success`: solo después de confirmación servidor.
- `disabled` / `coming soon`: visualmente distintos de una acción disponible.

## Tema Y Movimiento

- Oscuro: reproducción más fiel de Demo World.
- Claro: fondo `#eef2ef`, texto `#10201a`, superficies blancas y campos legibles.
- La preferencia existente `data-theme` sigue siendo la autoridad del usuario.
- `prefers-reduced-motion: reduce` reduce transiciones y animaciones a `0.01ms`.
- No se añade movimiento decorativo continuo.

## Accesibilidad

- Foco visible y orden DOM estable.
- Contraste comprobable en ambos temas.
- Controles táctiles principales de al menos `40–44px` cuando el espacio lo permite.
- Labels y `aria-current` en navegación.
- Texto puede ajustar línea; no usa escalado tipográfico por ancho de viewport.
- Scroll horizontal solo en colecciones intencionales, no en el documento.

## PWA

- Manifest: `display: fullscreen`, fallback `standalone`, `minimal-ui`, `browser`.
- Orientación: `any`.
- Service Worker: `Cache-Control: no-cache, no-store, must-revalidate`, versión explícita y actualización controlada.
- Las escrituras incompatibles o sin red nunca se muestran como exitosas.
- Una única navegación se muestra en cada composición.
- El diseño funciona con barras del navegador; fullscreen es una mejora, no un requisito.

## Límites De Autoridad

Esta capa no puede modificar fórmulas, tablas, RPC, migraciones ni contratos de:

- Rating V2 y assessments;
- partidos, asistencia, alineación y resultados;
- conducta y no-show;
- logros, cajas y recompensas;
- Player Cosmetics y Team Cosmetics;
- Season Score / ranking;
- billing;
- Clubs y Competiciones.

## Criterio De Aceptación

- `0` overflow horizontal documental.
- `0` controles cortados fuera de un scroller intencional.
- `0` imágenes rotas.
- `0` navegación duplicada.
- `0` errores de consola en rutas revisadas.
- El giro conserva el estado.
- Demo World y el laboratorio no escriben en producción.
- `MOBILE_GAME_LANDSCAPE` parece un HUD de fútbol, no desktop reducido.

## Extensión Referee Platform R3

Referee Platform usa el mismo shell y tokens, pero conserva una identidad de
producto propia:

- `RefereeProfileCard` es el único protagonista arbitral; nunca se sustituye
  por una carta de jugador sin GRL.
- La ficha arbitral no muestra GRL, facetas, estrellas ni ranking arbitral.
- Mercado → Árbitros solo existe si el flag canónico está activo; con el flag
  OFF no monta el panel ni lanza su lectura.
- Proponer un árbitro continúa limitado por la autoridad owner que resuelve R3.
- Mobile Game Landscape usa filtros, lista y detalle/acción como paneles
  independientes; portrait y desktop cambian composición, no lógica.
- El giro preserva filtros, selección, borradores y paneles abiertos sin
  repetir requests o comandos.
- `MATCH_SCHEDULE_CHANGED` y conflictos horarios se traducen a feedback de
  producto sin alterar el resultado canónico.
- Las estadísticas disciplinarias permanecen `NOT_AVAILABLE` hasta que exista
  la autoridad futura correspondiente.
- `/admin/referees` utiliza `PLATFORM_ADMIN`, no el HUD del usuario.
- `/laboratorio-referee-platform` es noindex,nofollow, visual-only y no puede
  abrir Auth, Supabase, Realtime ni escrituras.

Official UI V2 presenta snapshots R3 confirmados; PostgreSQL/RPC sigue siendo
la única autoridad sobre perfil, relaciones, asignaciones y estadísticas.
