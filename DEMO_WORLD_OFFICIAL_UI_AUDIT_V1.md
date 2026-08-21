# Demo World / Official UI Audit V1

## Checkpoint

- Fecha: 2026-08-22 (CEST).
- Rama: `codex/official-ui-v2-demo-convergence`.
- Base auditada: `da6dace3a1a5d20de9fdba0d34174f916a2b2c61` (`origin/main`).
- PR de trabajo: [#158](https://github.com/puntoracingrc/pachangas/pull/158).
- Fuentes: código local, capturas locales de Demo World y lectura visual de la oficial ya desplegada. No se escribió en Supabase ni en producción.
- Referencia visual primaria: `app/demo-world/demo-world.module.css` y las composiciones de `/demo`.

## Conclusión

Demo World ya contenía un lenguaje de producto más coherente que la oficial: jerarquía clara, densidad útil, navegación compacta y un modo apaisado con sensación de juego. La oficial conserva mucha más capacidad real, permisos y estados. La convergencia correcta es, por tanto, compartir composición y lenguaje visual sin adoptar fixtures, estado local ni contratos de Demo World.

La mayor diferencia no era el color. Era la estructura: la oficial daba peso parecido a demasiados bloques, mientras Demo World distingue contexto, estado, siguiente acción y detalle.

## Matriz Por Superficie

| Superficie | Demo World hace mejor | Debe conservarse de la oficial | Migración | No copiar | Riesgo | Decisión |
| --- | --- | --- | --- | --- | --- | --- |
| Inicio autenticado | Dashboard compacto, próxima acción y actividad | Equipo real, próximos partidos, historial, permisos y logros | Shell, métricas y jerarquía | Comunidad ficticia y métricas sintéticas | Medio | `MIGRATE_NOW` |
| Partido | Contexto persistente y navegación unificada | Máquina de estados, revisión, RPC, Realtime y permisos | Context bar y experiencia común | Estado de sesión Demo | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Próximo | Asistencia y convocatoria visibles a la vez | Estados voy/duda/no, pago, reservas y mercado | Dos paneles con acción primaria | Participantes de fixture | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Alineación | Campo protagonista y banquillo lateral | Drag, pizarra, snapshots y autoridad de alineación | Composición horizontal | Posiciones o niveles Demo | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Resultado | Marcador y goleadores sin ruido | Finalización, evidencias, revisión e idempotencia | Jerarquía y densidad | Resultado ficticio | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Admin partido | Operaciones agrupadas | RBAC owner/admin y acciones reales | Variante administrativa dentro de Partido | Permisos simulados | Alto | `ADMIN_VARIANT` |
| Mercado | Filtros cortos y tarjetas escaneables | Jugadores, partidos, equipos, Retos y operaciones RPC | Cabecera, filtros y rail/listado | Perfiles Demo | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Ranking | Posición propia y tabla legibles | Season Score V3, elegibilidad y backend | Cabecera territorial y tabla compacta | Puntuaciones sintéticas | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Avisos | Categorías y prioridad visibles | Preferencias, obligatoriedad, lectura y Realtime | Centro de avisos compacto | Eventos Demo | Medio | `MIGRATE_NOW` |
| Identidad de equipo | Escudo tratado como objeto de juego | `TeamShieldView`, inventario, revisión y guardado RPC | Escenario + controles laterales | Escudo ficticio o inventario Demo | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Personalizar carta | Carta protagonista y selector lateral | `PlayerCardView`, loadout, NEW y guardado RPC | Escenario + colección compacta | Carta o GRL Demo | Alto | `KEEP_FUNCTIONAL_RESTYLE` |
| Landing | Marca y materiales | Función comercial, SEO y acceso | Solo afinidad visual | Shell autenticado | Bajo | `PUBLIC_VARIANT` |
| Control Center | Tokens compartibles | Tablas, filtros, diagnóstico y `PLATFORM_ADMIN` | Identificador de variante | HUD de videojuego literal | Alto | `ADMIN_VARIANT` |
| Demo World | Referencia navegable y explicativa | Aislamiento público y solo datos ficticios | Mantener funcional | Convertirla en segunda oficial | Alto | `DO_NOT_COPY` |

## Diferencias Estructurales

| Dimensión | Oficial anterior | Demo World | Official UI V2 |
| --- | --- | --- | --- |
| Shell | Variaba por ruta | Único y estable | Compartido por rutas oficiales |
| Jerarquía | Bloques con peso parecido | Contexto, acción y detalle | Misma jerarquía con datos reales |
| Desktop | Navegación dispersa | Cabecera compacta | Cabecera de producto común |
| Portrait | Barra móvil existente | Navegación compacta | Conserva una única barra |
| Landscape | Parches históricos por ruta | HUD lateral | Composición explícita `MOBILE_GAME_LANDSCAPE` |
| Objetos | Formularios dominantes | Carta/escudo protagonistas | Objeto + controles |
| Estados | Correctos pero visualmente heterogéneos | Claros, aunque ideales | V2 para loading, empty, error, permiso, offline y stale |
| Datos | Productivos y autoritativos | Fixtures locales | Productivos, sin adaptador sintético global |

## Responsive Y PWA

- `MOBILE_PORTRAIT`: aplicación móvil completa, navegación inferior existente y contenido desplazable.
- `MOBILE_GAME_LANDSCAPE`: HUD lateral, contexto compacto, panel principal y acciones visibles; no usa cabecera ni footer de escritorio.
- `DESKTOP`: cabecera horizontal y contenido denso, sin reducirla para imitar móvil.
- El giro no debe cambiar ruta ni remontar el árbol funcional. El shell renderiza `children` una sola vez y solo cambia la composición CSS.
- El manifest mantiene `fullscreen` con fallback `standalone`, orientación libre, iconos maskable y shortcuts.
- La instalación física Android/iPhone no estuvo disponible: `PHYSICAL_QA_PENDING`.

## Estados Y Roles

| Estado | Evidencia | Resultado |
| --- | --- | --- |
| Visitante | Landing local sin sesión | Conserva variante pública |
| Autenticado con equipo / owner | Capturas Before de la oficial y revisión de guards | Funciones conservadas bajo shell V2 |
| Jugador / admin | Guards y controles existentes no modificados | Presentación depende del permiso real |
| Sin equipo / sin actividad | Ramas oficiales y estado vacío del laboratorio | Acción disponible permanece clara |
| Sin notificaciones | Contrato existente de `ProductState` | No se inventan eventos |
| Sin permisos | Estado explícito del laboratorio y guards productivos | Acceso restringido, sin control falso |
| Offline / stale | PWA bridge y estados de producto | Lectura posible; ninguna escritura aparece confirmada |
| Platform owner | Control Center conserva `PLATFORM_ADMIN` | No recibe shell de juego |

## Evidencia Visual

- `docs/official-ui-v2/captures/before`: 10 pantallas oficiales reales.
- `docs/official-ui-v2/captures/demo`: 9 equivalentes reales de Demo World; no existe un Admin de partido equivalente directo.
- `docs/official-ui-v2/captures/after`: 50 capturas del laboratorio V2.
- `docs/official-ui-v2/OFFICIAL_UI_V2_BEFORE_DEMO_AFTER_CONTACT_SHEET.png`.
- `docs/official-ui-v2/OFFICIAL_UI_V2_CONTACT_SHEET.png`.
- `docs/official-ui-v2/OFFICIAL_UI_V2_MOBILE_GAME_LANDSCAPE_CONTACT_SHEET.png`.

## Límites

- No se hizo QA autenticada destructiva ni se enviaron intenciones deportivas.
- No se creó un usuario artificial para cubrir cada rol; permisos y estados se verificaron por rutas existentes, tests y capturas de lectura.
- Demo World continúa siendo una referencia y showcase aislado, no una fuente de datos ni permisos.
