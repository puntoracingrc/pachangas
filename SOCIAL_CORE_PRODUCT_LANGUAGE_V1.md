# Social Core Product Language V1

## Objetivo

Este contrato fija el lenguaje visible del núcleo social de Pachangas IQ. La interfaz debe hablar de fútbol y acciones humanas; los nombres de arquitectura quedan reservados para código, logs e informes técnicos.

## Destinos principales

La navegación primaria contiene exactamente:

1. `Inicio`
2. `Partidos`
3. `Retos`
4. `Mercado`

`Equipo`, `Perfil`, `Avisos` y `Ajustes` son contextos o utilidades accesibles desde el selector, el avatar o la campana. No son una quinta pestaña.

## Nombres canónicos

| Concepto | Texto visible | Uso |
| --- | --- | --- |
| Sección de encuentros | Partidos | Navegación y títulos |
| Encuentro informal | pachanga | Copy cercano dentro de una frase |
| Equipo actual | Equipo | Selector y portada del equipo |
| Miembros | Plantilla | Lista completa del equipo |
| Centro de actividad | Avisos | Campana y pantalla de actividad |
| Identidad deportiva | Perfil | Datos personales y preferencias |
| Representación visual | Carta | Vista y personalización |

No se alternan `Partido` y `pachanga` dentro del mismo bloque para nombrar la misma entidad.

## Acciones

Usar verbos directos y específicos:

- `Crear partido`
- `Confirmar asistencia`
- `Ver partido`
- `Buscar una pachanga`
- `Solicitar plaza`
- `Buscar rival`
- `Enviar reto`
- `Aceptar`
- `Proponer cambios`
- `Invitar jugador`
- `Crear equipo`
- `Unirme`
- `Editar perfil`
- `Guardar`
- `Reintentar`
- `Volver`

Una pantalla muestra una acción principal y, como máximo, dos acciones secundarias visibles. Las acciones destructivas viven en el menú de más opciones y requieren confirmación.

## Estados

| Estado interno | Texto visible |
| --- | --- |
| `STALE` | La información ha cambiado. |
| `ACTIVE` normal | No se muestra. |
| `DISABLED` | Esta función no está disponible ahora. |
| `SERVER_CONFIRMED` | Guardado. |
| `CACHED` | Última copia disponible. |
| `OFFLINE` | Sin conexión. |
| carga | Cargando… o skeleton estable |
| sin resultados | No hay resultados con estos filtros. |
| error recuperable | No hemos podido cargarlo. Reintentar. |

Una escritura rechazada nunca se presenta como completada.

## Estados vacíos

| Superficie | Mensaje | Acción según rol |
| --- | --- | --- |
| Partidos | Aún no tienes ninguna pachanga próxima. | Crear partido / Buscar partido |
| Retos | Aún no tenéis ningún reto activo. | Buscar rival |
| Mercado | No hay resultados con estos filtros. | Cambiar filtros |
| Avisos | Todo al día. | Ninguna obligatoria |
| Equipo sin plantilla | Todavía no hay jugadores en la plantilla. | Invitar jugador |
| Equipo sin partido | El equipo no tiene ningún partido próximo. | Crear partido |
| Historial | Aún no hay partidos finalizados. | Volver a Próximos |
| Perfil sin carta | Tu perfil está listo. La carta es opcional. | Crear carta |
| Invitaciones | No hay invitaciones pendientes. | Invitar jugador |

No usar cifras ficticias ni expresiones como `0 registros`, `sin snapshot` o `servidor vacío`.

## Demo

La Demo se identifica siempre con `SIMULACIÓN`, `datos ficticios` y `sesión local`. Su revisión guiada usa `REVISIÓN RÁPIDA` y declara `LOCAL SESSION ONLY`.

No se presentan datos Demo como actividad productiva ni se usan claims como “miles de jugadores” sin evidencia real.

## Términos prohibidos en UI social

No mostrar:

- `CanonicalMatch`
- `RuleRevision`
- `operationId`
- `serverSequence`
- `read model`
- `RPC`
- `snapshot`
- `aggregate`
- `payload`
- `Supabase`
- `PostgREST`
- `RLS`
- `AUTH UUID`
- `revision N`
- nombres de Waves o versiones internas

Los errores técnicos se registran, pero la persona recibe una explicación humana y una salida clara.
