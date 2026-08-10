# Propuesta de producto: conducta, reportes y no-show

## Estado localizado

| Capacidad | Estado | Evidencia y límite |
| --- | --- | --- |
| Reportes generales de jugadores | NOT_IMPLEMENTED | No existe tabla, RPC, UI, RLS ni ciclo de revisión canónico. |
| Conducta general | PARTIALLY_IMPLEMENTED | Solo existe revisión administrativa de la retirada voluntaria de un invitado. |
| No-show real | NOT_IMPLEMENTED | Se guardan cambios de asistencia, pero no el hecho posterior `jugó/no apareció`. |
| Aviso `voy` | IMPLEMENTED | La transición a `voy` avisa y se deduplica. |
| Aviso `voy -> no` | IMPLEMENTED | Una baja posterior avisa; marcar directamente `no` no avisa ni implica mala conducta. |
| Lesión y recuperación | IMPLEMENTED | Se notifica indisponibilidad/disponibilidad sin exponer detalle médico. |
| Preferencias | IMPLEMENTED | In-app, push y email por categoría mediante RPC versionada. |
| Warning/sanction como aviso obligatorio | IMPLEMENTED | La infraestructura puede forzar visibilidad in-app. |
| Motor de warning/sanction | PARTIALLY_IMPLEMENTED | No existe decisión, historial, restricción temporal ni apelación canónicos. |
| Aislamiento de Rating V2 | PARTIALLY_IMPLEMENTED | La revisión de retirada existente declara `affectsSportRating=false`; falta un sistema general al que aplicar la garantía. |

## Demanda observada en la temporada sintética

- 424 bajas normales: 30 tempranas y 394 tardías. No se clasifican automáticamente como mala conducta.
- 37 confirmados finalmente no jugaron y no pueden distinguirse canónicamente de un no-show real.
- 8 agentes acumularon dos o más posibles no-shows.
- 79 escenarios de conducta necesitaron un sistema general inexistente.
- 30 retiradas de invitados sí recorrieron el flujo estrecho ya implementado.
- 1 campaña falsa coordinada, 1 ráfaga de cinco reportes desde un solo equipo, 1 caso con fuentes de dos equipos, 3 conflictos mutuos y 68 denuncias aisladas contra perfiles limpios quedaron solo como demanda sintética, sin sanciones.

## Propuesta para revisar con Alberto

### 1. Hecho de asistencia posterior

Crear una operación autoritativa de cierre de asistencia ligada a un partido finalizado. El servidor debe distinguir `played`, `excused_absence`, `late_cancellation` y `unexcused_no_show`; una transición previa `voy -> no` sigue siendo solo una cancelación. Debe decidirse quién confirma el hecho, durante qué ventana y qué evidencia o contradicción permite corregirlo.

### 2. Reporte canónico

Un reporte debe exigir actor autenticado, relación deportiva válida, partido/contexto, categoría cerrada, texto opcional, `operationId` y revisión esperada. El servidor resuelve identidades y pertenencias. No se permite auto-reporte, duplicado activo de la misma fuente/contexto ni acceso público a identidades.

### 3. Fuentes independientes y abuso

El riesgo no debe ser un contador bruto. Agrupar por equipo, partido y cluster relacional; diez miembros del mismo equipo constituyen como máximo una fuente correlacionada. Varias fuentes independientes pueden elevar prioridad de revisión, nunca imponer sanción automática. Detectar reciprocidad y campañas coordinadas sin revelar denunciantes.

### 4. Revisión, corrección y apelación

Estados sugeridos: `submitted -> triaged -> confirmed|dismissed -> warned|restricted -> appealed -> corrected|upheld`. Moderadores ordinarios operan con IDs opacos; la identidad real queda reservada a un rol interno de seguridad. Toda acción conserva historial y fecha efectiva original.

### 5. Restricciones sociales

Las medidas afectarían únicamente funciones sociales: mercado, retos, invitaciones o acceso a partidos públicos. Nunca deben modificar facetas, GRL, assessment, votos ni Season Score. Priorizar aviso y revisión humana; una sola denuncia no sanciona. Definir escalado, caducidad, rehabilitación y excepciones antes de construirlo.

### 6. Notificaciones

`security`, `warning` y `sanction` deben seguir siendo obligatorias in-app. Push/email pueden configurarse salvo los avisos operativos cuya recepción externa sea requisito explícito. Los payloads no deben incluir datos médicos, identidad del denunciante ni motivos sensibles en Realtime.

## Decisiones pendientes

1. Quién puede certificar que alguien jugó o no apareció.
2. Ventanas exactas para baja temprana, tardía y no-show.
3. Qué relación deportiva habilita un reporte.
4. Categorías permitidas y evidencia mínima.
5. Umbral de revisión y peso de fuentes independientes.
6. Qué rol interno puede revelar identidades.
7. Escalado y duración de restricciones sociales.
8. Procedimiento de apelación, corrección y borrado/retención.
9. Tratamiento de invitados no registrados.
10. Política contra denuncias falsas coordinadas.

Esta propuesta no crea producto, no impone sanciones y no cambia Rating V2.
