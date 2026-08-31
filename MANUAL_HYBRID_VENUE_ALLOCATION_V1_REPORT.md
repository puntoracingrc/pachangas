# Manual And Hybrid Venue Allocation V1 Report

Estado: `RELEASE CANDIDATE / STAGING CERTIFIED`

Fecha: 2026-08-31 CEST

## Modos

- `AUTOMATIC`: completa todos los Match posibles dentro de hard constraints.
- `MANUAL_ASSISTED`: el organizador asigna, mueve, intercambia o retira drafts;
  PostgreSQL valida cada intencion.
- `HYBRID`: conserva locks manuales y completa los huecos automaticamente.

No hay IA generativa como autoridad y ningun modo puede cambiar fecha u hora.

## Operaciones y locks

El cliente envia solo accion semantica, `operationId` y expected revision. Las
operaciones admiten asignar, mover, intercambiar, retirar, bloquear,
desbloquear, regenerar, validar y publicar. Cada respuesta sustituye cualquier
preview local por el snapshot confirmado.

Locks V1:

- `MATCH_TO_VENUE`;
- `MATCH_TO_PITCH`;
- `MATCH_TO_RECURRING_OCCURRENCE`;
- `MATCH_KEEP_EXISTING_BINDING`;
- `ROUND_TO_VENUE`;
- `FINAL_TO_PITCH`.

Cada lock conserva actor, motivo, revision, secuencia y fecha de servidor. Un
lock contradictorio bloquea la generacion con explicacion. La regeneracion no
mueve un lock sin una operacion explicita.

## Planner adaptable

Rutas productivas:

- `/competiciones/[competition]/gestion/campos`;
- `/competiciones/[competition]/gestion/campos/plan`;
- `/competiciones/[competition]/gestion/campos/revisiones`.

Desktop separa jornadas/partidos, tablero y campos/conflictos. Portrait usa
vistas compactas de Partidos, Campos, Asignacion, Conflictos y Resumen. Mobile
Game Landscape usa rail de jornadas, asignaciones y panel de campo sin doble
navegacion ni formulario vertical girado.

La UI muestra horarios fijos, fuente de slot, locks, conflictos, calidad,
capacidad, reservas existentes, revision y proxima accion. Realtime solo
invalida; el cliente relee el read model canonico.

## Seguridad y PWA

- sin actor, quality, disponibilidad, conflictos, estados ni secuencias
  aportados como autoridad por el navegador;
- todas las escrituras quedan bloqueadas offline y nunca se encolan;
- planner publicado y Demo V3.5 pueden cachearse como read models derivados;
- notas, contactos, coordenadas y APIs privadas no entran en Service Worker.

## Evidencia

- asignacion manual concurrente: un ganador y un stale explicito;
- lock + regeneracion: lock preservado;
- automatico e hibrido: deterministas y comparables por diff;
- Preview exacta `0f5d25f`: ocho viewports y ocho capas de planner sin overflow,
  controles cortados, imagenes rotas ni errores de consola;
- physical Android, iPhone e installed PWA: `PENDING`, no presentados como PASS.

Produccion permanece pendiente del release coordinado de Wave 9B.
