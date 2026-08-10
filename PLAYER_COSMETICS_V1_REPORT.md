# Player Cosmetics V1

## Estado

- Main de partida: `43026daeef131583f7685faf32f22df467d9d496`.
- PR #122 normalizado: `codex/player-card-cosmetics-lab-v0-1` sobre `main`, commit `3e28c98541037bb14e9a33c58d6214bd1164821c`, con solo sus 15 rutas propias.
- Rama de esta fase: `codex/player-cosmetics-v1`.
- Migración nueva: `20260810040115_player_cosmetics_v1.sql`.
- Feature flag: `player_cosmetics_enabled`, `false` por defecto.
- Producción: no modificada.

## Contrato

Cosmetics V1 solo cambia la presentación de la ficha. No escribe Rating V2, GRL, facetas, `ratingReliability`, Season Score, TOPS, ranking ni matchmaking. El renderer conserva los valores deportivos recibidos y superpone un loadout visual.

El flujo canónico es:

`achievement -> box sellada -> open_pachanga_reward_v1 -> inventario -> NEW -> seen -> loadout -> read model público`

La economía de cajas existente sigue decidiendo el premio y los duplicados. No se ha creado una segunda economía ni se han cambiado probabilidades, frecuencia de cajas o puntos por rareza.

## Modelo de datos

| Entidad | Alcance | Autoridad | Contenido |
| --- | --- | --- | --- |
| `pachanga_cosmetic_catalog` | Compartido | Servidor | Slot, colección, rareza, material y contrato de render |
| `pachanga_player_reward_inventory` | Privado del jugador | Servidor | Propiedad, `acquired_at`, `seen_at`, revisión y secuencia |
| `pachanga_player_cosmetic_loadouts` | Privado editable | Servidor | Una selección por slot y revisión monotónica |
| `pachanga_player_cosmetic_public_cards` | Público restringido | Servidor | Solo loadout equipado y badge público seguro |
| `private.pachanga_player_cosmetic_operation_receipts` | Privado | Servidor | Idempotencia, actor, operación y respuesta canónica |

Los cosméticos se asocian a `pachanga_player_profiles.id`, la identidad universal. Cambiar de grupo no mueve ni elimina inventario, estado visto o loadout.

## Slots

- `frame`: marco.
- `background`: fondo interior.
- `accent`: líneas y pequeños detalles.
- `effect`: un único efecto principal.
- `title`: título textual.
- `featuredBadgeGrantId`: logro real concedido, no un cosmético inventado.

Todos los slots permiten `Original` o `Ninguno`. El servidor rechaza una pieza no poseída, un badge no concedido y un slot incompatible.

## RPC

| RPC | Tipo | Garantía principal |
| --- | --- | --- |
| `get_pachanga_player_cosmetics_snapshot_v1` | Lectura propia | Inventario, unseen, badges reales, loadout y revisión |
| `get_pachanga_public_player_card_cosmetics_v1` | Lectura pública | Solo piezas equipadas y badge público permitido |
| `mark_pachanga_player_cosmetics_seen_v1` | Escritura | `operationId`, `expectedRevision`, ownership y cambio atómico |
| `save_pachanga_player_cosmetic_loadout_v1` | Escritura | Una mutación para todo el borrador, ownership y revisión |
| `equip_pachanga_player_cosmetic_from_box_v1` | Escritura | Marcar visto y equipar en la misma transacción |

Las respuestas de escritura contienen `expectedRevision`, `confirmedRevision`, `serverSequence`, `confirmedAt` y el snapshot canónico. Dos dispositivos con la misma revisión no pueden ganar ambos.

## NEW jerárquico

`acquired_at` y `seen_at` son independientes del loadout. Cargar la página no marca nada visto. Abrir una categoría renderizada marca sus piezas visibles mediante RPC. El indicador accesible se propaga item -> categoría -> Mi ficha y usa texto/`aria-label`, no solo color.

Un duplicado mantiene la economía actual: se convierte en puntos y no crea otra fila. Si la primera pieza seguía sin verse, el duplicado no cambia su `seen_at`.

## Cliente y caché

`/personalizar-carta` carga primero una caché derivada por usuario y después sustituye el estado con la RPC canónica. La selección es una previsualización local; `Guardar ficha` realiza una sola escritura. Sin conexión, la previsualización permanece como borrador y nunca aparece como confirmada.

Realtime escucha únicamente el loadout y el inventario del perfil. Cada evento invalida la entidad y provoca refetch canónico. La QA autenticada comprobó una concesión en servidor que apareció en el editor sin recargar: 5 -> 6 piezas y revisión 8 -> 9.

Las tres escrituras nuevas están clasificadas por el PWA bridge. Un cliente incompatible no puede interpretar un rechazo como éxito.

## Seguridad

- Inventario, `seen_at`, `acquired_at`, puntos y recibos no son públicos.
- RLS permite al jugador leer únicamente su inventario y loadout privado.
- La carta pública se obtiene por read model y función segura; no consulta inventario ajeno.
- El badge destacado se resuelve desde una concesión real y expone solo título, clave, rareza y fecha públicas.
- Las funciones `SECURITY DEFINER` privadas tienen `search_path` cerrado y `EXECUTE` revocado.
- No existe `service_role` en código cliente.
- Tablas privadas sin escritura directa para `authenticated`; toda mutación pasa por RPC.

## Caja, duplicados y notificación

El catálogo de recompensas existente se amplía con `player_cosmetic`. Al abrir una caja:

1. El servidor sella/resuelve la pieza.
2. Una pieza nueva entra una sola vez en inventario.
3. El trigger aumenta la revisión cosmética.
4. Se crea una notificación idempotente con enlace a `/personalizar-carta?slot=...&item=...`.
5. El reveal ofrece `Equipar ahora` y `Ver mi colección`.

`Equipar ahora` valida que la caja, pieza, jugador y revisión coinciden; marca visto y equipa atómicamente. `Ver mi colección` abre y resalta la pieza sin equiparla.

## SHARED_COSMETICS_EDITOR_ARCHITECTURE

El núcleo compartido vive en `app/_components/cosmetics-editor.tsx`:

- `CosmeticEditorShell`
- `CosmeticCategoryTabs`
- `OwnedCosmeticSelector`
- `MaterialSwatch`
- `NewBadge`
- `EditorActions`
- `UnsavedChanges`

La ficha real y el laboratorio comparten el mismo shell, selectores, acciones y renderer. `PlayerCosmeticCard` es una capa compositiva que siempre delega la ficha deportiva en el único `PlayerCardView`; no replica su estructura ni sus cálculos.

El editor de escudo ya reutiliza `EditorActions` y `UnsavedChanges`, además del mismo lenguaje preview -> borrador -> guardado -> publicación. Sus formas, símbolos y reglas de administración siguen siendo específicas del equipo. La siguiente fase puede trasladar tabs, swatches y NEW jerárquico al inventario de equipo sin mezclar propiedad:

- jugador -> `player_profile_id`;
- escudo/equipo -> `group_id`;
- un admin edita para el grupo, pero nunca recibe personalmente sus piezas.

## Synthetic World

Soak persistente: semilla `202608106`, mundo `9a5f39c1-e9e0-4e4c-a284-9f17ef793383`, 2026-09-01 a 2027-06-30.

| Métrica | Resultado |
| --- | ---: |
| Jugadores registrados | 640 |
| Equipos | 50 |
| Partidos | 1.196 |
| Cajas | 3.613 |
| Concesiones cosméticas únicas | 738 |
| Duplicados convertidos | 101 |
| Loadouts | 262 |
| Piezas no vistas al cierre | 105 |
| Eventos de inventario, incluidos duplicados | 839 |
| Eventos mark seen | 515 |
| Eventos equip from box | 375 |
| Eventos save loadout | 30 |
| Loadouts visualmente distintos | 254 |
| Combinación más repetida | 1,5 % |

Evolución por perfil sintético:

| Corte | Actividad | Jugadores | Piezas | No vistas | Duplicados | Puntos duplicado | Loadouts |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 meses | Casual | 131 | 89 | 8 | 16 | 197 | 35 |
| 3 meses | Normal | 260 | 163 | 26 | 28 | 196 | 51 |
| 3 meses | Activo | 219 | 157 | 20 | 11 | 76 | 59 |
| 3 meses | Muy activo | 30 | 16 | 3 | 0 | 0 | 8 |
| 6 meses | Casual | 131 | 103 | 10 | 18 | 205 | 41 |
| 6 meses | Normal | 260 | 208 | 32 | 30 | 216 | 70 |
| 6 meses | Activo | 219 | 203 | 26 | 22 | 144 | 76 |
| 6 meses | Muy activo | 30 | 24 | 5 | 0 | 0 | 10 |
| Fin de temporada | Casual | 131 | 129 | 13 | 19 | 209 | 53 |
| Fin de temporada | Normal | 260 | 243 | 35 | 33 | 244 | 82 |
| Fin de temporada | Activo | 219 | 242 | 32 | 25 | 160 | 92 |
| Fin de temporada | Muy activo | 30 | 30 | 7 | 0 | 0 | 12 |

La temporada canónica dura diez meses; no se inventa un corte de doce meses fuera de su calendario. Invariantes diarias/semanales: 0 fallos. El checksum canónico de Rating V2, facetas y fiabilidad de los 670 agentes, incluidos invitados, permanece idéntico; ningún payload de evento cosmético contiene campos deportivos.

## QA y pruebas

- `npm test`: build y 202 pruebas, 202 pasan.
- `npm run typecheck`: pasa.
- Lint focalizado de archivos nuevos/modificados: pasa.
- Lint global: deuda previa, 43 hallazgos (23 errores y 20 avisos); no se modifica.
- SQL/RLS: pasa con rollback transaccional.
- Concurrencia real con dos conexiones: revisión 4, un ganador, un conflicto, replay idempotente y un solo recibo.
- Bootstrap limpio local: 81 migraciones aplicadas.
- Browser autenticado: seen, preview local, offline, reconexión, guardado, notificación y Realtime pasan.
- Consola del editor tras recarga: sin excepciones.
- 1440x900, 390x844 y 844x390: sin overflow horizontal; carta y acciones visibles.
- Feature flag OFF degrada a la ficha original.

Capturas:

- `artifacts/player-cosmetics-qa/editor-desktop-1440x900.png`
- `artifacts/player-cosmetics-qa/editor-mobile-390x844.png`
- `artifacts/player-cosmetics-qa/editor-landscape-844x390.png`

## Preparación futura

Demo World deberá consumir `PlayerCardView` y los mismos contratos de loadout con snapshots ficticios. La distribución recomendada es original para recién llegados, 1-2 piezas para actividad normal y combinaciones más elaboradas para veteranos. Las afinidades visuales por equipo pueden modelarse como presets, nunca como propiedad compartida. Tutorial, tienda, monetización, TOPS cosméticos y economía de escudo permanecen fuera de V1.
