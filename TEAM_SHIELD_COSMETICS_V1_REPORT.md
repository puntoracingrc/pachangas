# Team Shield Cosmetics V1

Estado: EN DESARROLLO - NO APTO PARA PRODUCCION.

## Checkpoint

- Main de partida: `c92eb1c65bdd61b1124e7a2d836563350dad7bea`.
- Rama: `codex/team-shield-cosmetics-v1`.
- Produccion modificada: NO.
- `player_cosmetics_enabled`: fuera del alcance; no se modifica.
- `team_cosmetics_enabled`: se creara desactivado por defecto.
- `team_cosmetic_rewards_enabled`: se creara desactivado por defecto.

## Auditoria Inicial

Pachangas IQ ya dispone de un MVP autoritativo de identidad de equipo. No se
creara un segundo sistema paralelo. La fase V1 evoluciona estas piezas:

- `pachanga_team_crest_drafts`: borrador privado del equipo.
- `pachanga_team_crest_versions`: versiones publicadas e inmutables.
- `pachanga_team_crest_state`: revision monotona y secuencia de servidor.
- `pachanga_team_crest_events`: historial auditable.
- `pachanga_team_crest_operation_receipts`: idempotencia.
- `pachanga_team_cosmetic_inventory`: propiedad ligada al `group_id`.
- `get/save/publish_pachanga_team_crest_*_v1`: lectura y mutaciones RPC.
- Realtime sobre `pachanga_team_crest_state`.
- Cache local derivada con refetch canonico.

El editor actual vive en `app/equipo/identidad/page.tsx` y su renderer esta
embebido como `CrestPreview`. Player Cosmetics ya aporta shell, acciones,
estado sin guardar, materiales, efectos y semantica NEW reutilizables.

## Riesgos Localizados

1. El renderer del escudo esta duplicable porque permanece dentro de la pagina.
2. El contrato legacy solo admite un adorno y un simbolo.
3. La RLS legacy permite a miembros normales leer inventario de equipo.
4. El snapshot legacy expone el catalogo completo y su estado `unlocked`.
5. La vista normal mezcla editor, coleccion y progresion en una pagina extensa.
6. No existe seen-per-admin ni semantica de alta posterior de administrador.
7. No existen flags independientes de editor y recompensas de equipo.

## Superficies De Escudo

| Superficie | Estado inicial | Accion V1 |
| --- | --- | --- |
| Identidad del equipo | Renderer `CrestPreview` embebido | Migrar a `TeamShieldView` |
| Historial de escudos | Mismo renderer embebido | Migrar a `TeamShieldView` |
| Retos | No renderiza escudo hoy | No inventar una segunda geometria |
| Mercado | No renderiza escudo hoy | Consumira el read model cuando se incorpore |
| Partidos | No renderiza escudo hoy | Fuera del refactor incremental |
| Rankings/TOPS | No renderiza escudo hoy | Contrato preparado, sin cambio visual forzado |
| Invitaciones/notificaciones | Texto y enlaces | Sin geometria duplicada |

## Invariantes De Compatibilidad

- Un equipo sin loadout cosmetico conserva exactamente su diseno legacy.
- Todas las formas, colores y piezas base actuales siguen siendo gratuitas.
- Ningun cosmetico pertenece al owner o admin; pertenece al `group_id`.
- Cambiar owner/admin no mueve ni elimina inventario o loadout.
- Un miembro normal solo ve el escudo publicado, nunca inventario ni seen state.
- Guardar requiere actor autenticado, `operationId` y revision esperada.
- Un conflicto devuelve `PT409`; nunca hay last-write-wins silencioso.
- Offline permite borrador local, pero nunca confirmacion ni cola de escritura.
- Team Cosmetics no altera Rating, Season Score, TOPS, retos ni facetas.

## Evidencia Pendiente

Este informe se completara con migracion, RPCs, RLS, Realtime, PWA, fixtures,
pruebas, staging, Preview, QA responsive, rendimiento y checks finales.

