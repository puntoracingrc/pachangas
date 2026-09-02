# Social Core V3H Usability Audit

## Checkpoint auditado

- Fecha: 2026-09-02 (Europe/Madrid).
- Rama: `codex/official-ui-v3h-social-core-rc`.
- Commit base: `fd97b25b191391baf17a60499e34c38dbd0e11cc` (`origin/main`).
- Entorno: local, Node 24.16.0, npm 11.13.0, Next.js 16.3.3, Chromium automatizado.
- Datos: rutas publicas y Mundo Demo sintetico. No se usaron usuarios, equipos, partidos ni avisos reales.
- Supabase: solo codigo local; no se modifico ni consulto produccion.
- Stripe, push, email y SMS: no utilizados.
- Estado inicial: checkout funcional limpio; `AGENTS.md` y `CLAUDE.md` fueron generados sin seguimiento por `next dev` y quedan excluidos del producto.

## Baseline reconciliado

| Comprobacion | Resultado |
| --- | --- |
| Node tests | 20/20; 0 skipped, 0 todo, 0 cancelled |
| TS/TSX tests | 798/798; 0 skipped, 0 todo, 0 cancelled |
| Total | 818/818 |
| Typecheck | PASS |
| Build | PASS; 78 rutas generadas |
| Visual baseline | 42 capturas; 0 root overflow, 0 imagenes rotas, 0 errores o warnings de consola |
| Supabase diff | 0 |
| Migraciones nuevas | 0 |

## Metodo y leyenda

La auditoria combina inspeccion de rutas, codigo invocado, pruebas existentes y QA visual en `1440x900`, `390x844` y `844x390`. Los estados autenticados que dependen de una cuenta real se auditan mediante sus contratos y el Mundo Demo, sin escribir datos remotos.

- `D`: desktop.
- `P`: portrait.
- `L`: Mobile Game Landscape.
- `PWA`: shell standalone emulada.
- `0/1/2`: numero de navegaciones locales visibles, sin contar la navegacion primaria global.
- `No ejercido`: el estado existe en codigo, pero no fue provocado contra un backend real en esta auditoria inicial.

## Superficies: proposito, acciones y jerarquia

| Superficie | Proposito | Usuario | Accion principal | Secundarias visibles | Navegacion / barras | Primer viewport y duplicaciones | Terminos tecnicos |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Landing publica | Explicar y abrir el producto | Visitante | Entrar con Google | Probar Demo; crear grupo | 0 | Hero entendible, pero Demo compite como bloque de capacidades y hay tres CTA equivalentes | No |
| Login | Autenticar y volver a la intencion | Visitante | Continuar con Google | Cancelar/seguir explorando | 0 | El destino se conserva en helpers; no hay formulario largo | No en UI |
| Inicio | Mostrar el siguiente paso | Miembro | Abrir o actuar sobre proximo partido | Avisos; recomendacion social | 0 | El Mundo Demo prioriza agenda; producto live depende del estado canonico | No |
| Partidos / Proximos | Encontrar el siguiente partido | Miembro | Ver partido | Crear partido si puede gestionar | 1 | Proximos e Historial bastan | No |
| Partidos / Historial | Consultar memoria deportiva | Miembro | Ver partido finalizado | Volver a Proximos | 1 | Resultado es protagonista; controles vivos se ocultan por contrato | No |
| Crear partido | Crear una pachanga | Owner/admin | Crear partido | Cancelar | 1 | Wizard contextual, no abierto en la lista | No |
| Detalle de partido | Resolver el estado del partido | Participante/admin | Accion segun estado | Compartir; Gestionar | 1 | La administracion queda contextual | No |
| Asistencia | Confirmar disponibilidad | Participante | Confirmar asistencia | Duda/no voy desde menu | 1 | Estado asociado al partido, no una ruta tecnica separada | No |
| Jugadores | Ver participantes | Participante/invitado aceptado | Ver jugador | Ver equipos | 1 | Lista compacta; permisos de edicion contextuales | No |
| Equipos | Ver alineacion | Participante/invitado aceptado | Ver alineacion | Ampliar campo | 1 | Diferencia visual legitima: el modo juego puede ser mas rico | No |
| Resultado | Consultar o cerrar marcador | Participante/admin | Ver/finalizar resultado | Goleadores; foto | 1 | Resultado final ocupa la jerarquia principal | No |
| Retos / Activos | Resolver propuestas | Equipo | Abrir reto pendiente | Crear reto | 2 | Activos/Historial mas Todos/Recibidos/Enviados parecen dos menus | No |
| Retos / Historial | Consultar retos cerrados | Equipo | Abrir reto | Volver a Activos | 1 | Lista sencilla | No |
| Crear reto | Proponer rival y momento | Owner/admin | Enviar reto | Cancelar | 1 | Wizard V3C preservado | No |
| Contrapropuesta | Ajustar una propuesta | Owner/admin | Enviar cambios | Cancelar | 1 | Formulario aparece solo en contexto | No |
| Mercado / Partidos | Buscar una pachanga | Visitante/jugador | Ver o solicitar plaza | Filtros | 1 | Ubicacion es el primer filtro; en portrait el boton de geolocalizacion ocupa una fila completa | No |
| Mercado / Jugadores | Buscar un jugador | Owner/admin | Ver/invitar jugador | Filtros | 1 | La carta completa vive en detalle | No |
| Mercado / Equipos | Buscar rival | Owner/admin | Ver/retar equipo | Filtros | 1 | Retar enlaza con V3C | No |
| Perfil | Ver identidad deportiva | Jugador | Editar perfil propio | Ver carta | 0 | El fallo de servicio local ocupa demasiado espacio, pero no filtra detalles tecnicos | No |
| Editar perfil | Mantener datos minimos | Jugador | Guardar | Cancelar | 0 | Foto, bio, carta y Mercado siguen opcionales | No |
| Carta | Ver identidad visual | Jugador/visitante permitido | Ver carta | Valorar cuando proceda | 0 | Diferencia legitima: superficie visual rica | No |
| Personalizar carta | Elegir cosmeticos | Jugador | Guardar personalizacion | Volver | 1 | Editor enmarcado y separado del perfil | No |
| Onboarding | Crear perfil minimo | Usuario nuevo | Completar paso actual | Volver cuando sea seguro | 1 | La intencion de origen se conserva por contrato | No |
| Crear equipo | Crear contexto social | Usuario registrado | Crear equipo | Cancelar | 1 | Transaccional y contextual | No |
| Unirse a equipo | Aceptar invitacion/codigo | Usuario registrado | Unirme | Cancelar | 1 | No concede rol admin por compartir enlace | No |
| Equipo | Abrir el hogar del equipo | Miembro | Ver proximo partido | Plantilla; invitar si gestiona | 1 | En Demo el H1 `Season Score V3` convierte un read model en protagonista | Si, en Demo |
| Plantilla | Consultar miembros | Miembro | Ver jugador | Invitar si gestiona | 1 | Cuadricula compacta y navegable | No |
| Invitaciones | Incorporar miembros | Owner/admin | Invitar jugador | Copiar/compartir | 1 | Vive dentro de Equipo, no como destino principal | No |
| Avisos / Pendientes | Resolver acciones | Usuario | Abrir accion | Marcar/archivar desde menu | 1 | H1 y contador claros | No |
| Avisos / Todos | Consultar actividad | Usuario | Abrir contexto | Filtros/menu | 1 | Actividad informativa separada de pendientes | No |
| Ajustes de notificaciones | Elegir preferencias | Usuario | Guardar preferencias | Volver | 1 | El audit visual apuntaba al redirect legado, no al Inbox real | No |
| Demo social | Probar el nucleo sin datos reales | Visitante | Empezar recorrido | Reiniciar; salir | 1 | Tres controles de igual peso, version interna visible y falta etiqueta persistente `SIMULACION` | Si, en cabecera |

## Superficies: estados y retorno

| Superficie | Empty | Loading | Error / unavailable | Offline | Back / return |
| --- | --- | --- | --- | --- | --- |
| Landing publica | Demo honesta, sin cifras reales | Estable | Entrada sigue disponible | Recursos cacheables | CTA explicitos |
| Login | N/A | Estado del proveedor | Cancelacion debe ser humana | Escritura bloqueada | `returnTo` validado |
| Inicio | Siguiente accion | Skeleton/estado estable | Mensaje humano | Lectura de ultima copia | Contexto de equipo |
| Partidos / Proximos | Crear o buscar partido segun rol | Carga estable | Reintentar | Lectura; sin fake success | Conserva Proximos |
| Partidos / Historial | Historial vacio | Carga estable | Reintentar | Cache larga | Conserva Historial |
| Crear partido | N/A | Saving | Mantiene borrador | No confirma | Cancela al origen |
| Detalle de partido | N/A | Carga canonica | Reintentar | Snapshot de lectura | Respeta `returnTo` |
| Asistencia | Estado actual | Saving | Revierte preview | No confirma | Permanece en partido |
| Jugadores | Sin participantes | Carga estable | Reintentar | Snapshot | Vuelve al partido |
| Equipos | Huecos honestos | Carga estable | Reintentar | Snapshot | Vuelve al partido |
| Resultado | Pendiente si no jugado | Saving | Revierte preview | No finaliza | Vuelve al partido |
| Retos / Activos | Existe, pero live concatena ademas un aviso de servicio y tres CTA | Carga estable | Duplicado con empty cuando no hay backend/sesion | Lectura; no muta | Conserva filtro |
| Retos / Historial | Sin retos cerrados | Carga estable | Reintentar | Cache | Conserva vista |
| Crear reto | N/A | Saving | Mantiene propuesta | No envia | Vuelve al rival |
| Contrapropuesta | N/A | Saving | Mantiene propuesta | No envia | Vuelve al detalle |
| Mercado / Partidos | Honesto, sin datos Demo | Carga estable | Unavailable humano | Cache de catalogo | Conserva filtros/scroll |
| Mercado / Jugadores | Honesto | Carga estable | Unavailable humano | Cache | Conserva filtros/scroll |
| Mercado / Equipos | Honesto | Carga estable | Unavailable humano | Cache | Conserva filtros/scroll |
| Perfil | Perfil minimo | Carga estable | Error humano, pero sobredimensionado localmente | Ultima copia | Avatar/origen |
| Editar perfil | Campos opcionales | Saving | Mantiene edicion | No guarda | Cancelar |
| Carta | Sin personalizacion usa base | Carga estable | Alternativa base | Ultima copia | Volver |
| Personalizar carta | Catalogo vacio posible | Carga estable | Reintentar | No guarda | Volver a Carta |
| Onboarding | N/A | Saving | Mantiene paso | No confirma | Intencion original |
| Crear equipo | N/A | Saving | Mantiene formulario | No crea | Origen |
| Unirse a equipo | Invitacion invalida/ausente | Saving | Explicacion humana | No acepta | Origen |
| Equipo | Equipo sin partido/jugadores | Carga estable | Reintentar | Snapshot | Selector/avatar |
| Plantilla | Invitar/buscar segun rol | Carga estable | Reintentar | Snapshot | Equipo |
| Invitaciones | Invitar como accion | Saving | Mantiene datos | No envia | Equipo |
| Avisos / Pendientes | `Todo al dia` | Carga estable | Reintentar | Ultima copia | Deep link vuelve a Avisos |
| Avisos / Todos | Sin actividad | Carga estable | Reintentar | Ultima copia | Conserva filtro |
| Ajustes de notificaciones | Preferencias por defecto | Carga estable | No finge guardado | No guarda | Avatar/Avisos |
| Demo social | Dataset sintetico determinista | Carga local | Reinicio local | Sigue en local | Salir explicito |

## Superficies: responsive y PWA

| Superficie | Desktop | Portrait | Landscape | PWA |
| --- | --- | --- | --- | --- |
| Landing publica | Correcta pero cargada | Correcta pero larga | Sin overflow | Shell disponible |
| Login | Dialogo centrado | CTA visible | Compacto | Retorno conservado |
| Inicio | Shell horizontal | Bottom nav | Game shell | Standalone compatible |
| Partidos / Proximos | Lista amplia | Tarjetas apiladas | Compacto | Safe areas |
| Partidos / Historial | Carril/lista | Scroll correcto | Compacto | Cacheable |
| Crear partido | Wizard centrado | Una columna | Compacto | Teclado a verificar final |
| Detalle de partido | Dos columnas si procede | Una columna | Submenu lateral | Safe areas |
| Asistencia | Controles legibles | Menu compacto | Compacto | Touch |
| Jugadores | Lista/cuadricula | Lista | Bloques laterales | Scroll contenido |
| Equipos | Campo amplio | Campo adaptado | Campo protagonista | Fullscreen progresivo |
| Resultado | Marcador y detalle | Una columna | Dos zonas | Safe areas |
| Retos / Activos | Correcto | Dos barras locales | Dos barras locales | Shell correcto |
| Retos / Historial | Correcto | Lista | Lista compacta | Shell correcto |
| Crear reto | Dialogo/wizard | Una columna | Compacto | Teclado a verificar final |
| Contrapropuesta | Dialogo | Una columna | Compacto | Teclado a verificar final |
| Mercado / Partidos | Correcto | Geolocalizacion ocupa otra fila | Claro pero varios targets menores de 44px | Shell correcto |
| Mercado / Jugadores | Correcto | Igual | Igual | Shell correcto |
| Mercado / Equipos | Correcto | Igual | Igual | Shell correcto |
| Perfil | Correcto | Error card alta | Compacto | Shell correcto |
| Editar perfil | Dos columnas si caben | Una columna | Scroll interno | Teclado a verificar final |
| Carta | Escenario amplio | Carta adaptada | Rica | Standalone compatible |
| Personalizar carta | Panel/editor | Apilado | Compacto | Safe areas |
| Onboarding | Centrado | CTA visible | Compacto | Teclado a verificar final |
| Crear equipo | Centrado | Una columna | Compacto | Teclado a verificar final |
| Unirse a equipo | Centrado | Una columna | Compacto | Deep link compatible |
| Equipo | Dos zonas | Apilado | Game shell; titulo tecnico actual | Shell correcto |
| Plantilla | Cuadricula | Lista/cuadricula | Cuadricula compacta | Touch |
| Invitaciones | Panel contextual | Sheet | Compacto | Compartir compatible |
| Avisos / Pendientes | Lista | Lista | Compacto | Badge y deep links |
| Avisos / Todos | Lista | Lista | Compacto | Cacheable |
| Ajustes de notificaciones | Panel | Una columna | Compacto | Shell correcto |
| Demo social | Correcta | Banner ocupa altura util | Mercado cambia a claro en game landscape | Local session |

## Auditoria por tareas

| Tarea | Pantallas y pulsaciones principales | Retorno / contexto | Hallazgo inicial |
| --- | --- | --- | --- |
| A. Visitante | Landing -> Probar Demo -> Mercado -> Partido | Demo permite salir; Mercado conserva ruta | Landing exige leer demasiado antes de elegir; Demo no dice `SIMULACION` de forma persistente |
| B. Usuario nuevo | Entrar -> perfil minimo -> Buscar pachanga -> Mercado -> solicitar plaza | Helpers conservan destino y filtros; escritura requiere servidor | No ejercido contra Auth real; contratos y tests existentes preservan la intencion |
| C. Owner nuevo | Entrar -> perfil -> crear equipo -> compartir -> equipo -> primer partido | Acciones viven en Equipo y shell | No ejercido remotamente; Demo debe convertirlo en recorrido humano directo |
| D. Jugador de equipo | Inicio -> asistencia -> jugadores -> equipos -> resultado | Contexto del partido permanece | Flujo Demo existe; falta entrada de revision que lo explique sin arquitectura |
| E. Buscar jugadores | Partido -> Mercado -> jugador -> invitar -> volver | `returnTo` y query del partido existen | Mercado portrait desperdicia ancho y eleva el contenido |
| F. Retar equipo | Mercado -> equipo -> Retar -> wizard -> contrapropuesta -> aceptar -> partido | V3C conserva rival y partido | Retos presenta filtro como segunda navegacion; Demo social expone texto/versiones internas en Equipo |
| G. Avisos | Campana -> Pendientes -> accion -> dominio -> volver | Deep links y contador comparten proyeccion | Script visual auditaba Ajustes bajo el nombre Avisos; cobertura visual engañosa |
| H. Varios equipos | Selector -> Inicio -> Partidos -> Retos -> Mercado -> Equipo | Shell conserva contexto canonico | En Demo Perfil aparecen perspectivas avanzadas que no pertenecen al nucleo social |

## Hallazgos consolidados

| ID | Clasificacion | Evidencia | Impacto | Decision V3H |
| --- | --- | --- | --- | --- |
| V3H-001 | CLUTTER | Landing muestra Google, Demo y crear grupo con peso similar, mas una lista extensa de capacidades | El visitante tarda en identificar la accion principal | Simplificar al mensaje, dos CTA y tres pasos del contrato |
| V3H-002 | COPY | Demo banner muestra `Mundo Demo V3.5` y temporada | Expone fase/version interna | Sustituir por etiqueta persistente `SIMULACION` y lenguaje humano |
| V3H-003 | CLUTTER | Demo banner ofrece Empezar, Reiniciar y Salir con igual peso | No hay protagonista | Hacer `Revision rapida` principal y relegar reinicio/salida |
| V3H-004 | COPY | Equipo Demo usa H1 `Season Score V3` y `read model` | El usuario percibe arquitectura | Titular el equipo/ranking en lenguaje de producto |
| V3H-005 | INCONSISTENT | Perfil Demo social permite perspectivas de organizador/Club/plataforma | Modulos avanzados se filtran al nucleo social | Limitar selectores internos al conjunto social ya filtrado |
| V3H-006 | INCONSISTENT | Mercado Demo pasa a una superficie clara dentro del shell game oscuro | Cambio brusco al navegar | Aplicar el mismo contrato de tema al Mercado Demo en landscape |
| V3H-007 | CLUTTER | Retos muestra Activos/Historial y otra barra Todos/Recibidos/Enviados | Dos navegaciones locales | Mantener tabs y convertir el segundo control en filtro compacto |
| V3H-008 | CONFUSING | Sin sesion/backend, Retos concatena `sin equipo`, tres CTA y `servicio no disponible` | Dos causas y cuatro decisiones compiten | Derivar un solo estado con maximo dos acciones |
| V3H-009 | RESPONSIVE | `Usar mi ubicacion` ocupa una fila completa en 390px | Empuja filtros/resultados fuera del primer viewport | Convertirlo en accion iconica compacta y accesible |
| V3H-010 | ACCESSIBILITY | Mercado registra 19-28 targets menores de 44px segun viewport | Toque impreciso | Elevar targets interactivos prioritarios sin perder densidad landscape |
| V3H-011 | INCONSISTENT | `visual-audit-v1` llama Avisos a `/perfil/avisos`, que redirige a Ajustes | La evidencia no cubre el Inbox real | Auditar `/avisos` y Ajustes como superficies separadas |
| V3H-012 | BLOCKING | No existe la entrada `Revision rapida` con siete recorridos exigidos | No puede completarse la revision humana V3H | Reutilizar historias locales existentes y agregar navegador de recorridos sin nueva autoridad |
| V3H-013 | LEGITIMATE DIFFERENCE | Carta, escudo, alineacion y resultado son mas visuales que Ajustes/Mercado | Identidad deportiva intencional | Conservar; no homogeneizar estas superficies |
| V3H-014 | LEGITIMATE DIFFERENCE | Mobile Game Landscape usa rail lateral y mayor densidad | Modo videojuego solicitado | Conservar, corrigiendo solo contraste, overflow y jerarquia |

## Componentes compartidos y contratos existentes

- `OfficialProductShellV2` ya centraliza los cuatro destinos, selector de contexto, campana, avatar y separacion de administracion.
- `product-navigation-contract.ts` ya fija Inicio, Partidos, Retos y Mercado como unicos destinos primarios.
- Los helpers de autenticacion y `returnTo` ya preservan destinos permitidos y rechazan retornos abiertos.
- Mercado, Retos y Avisos ya consumen contratos server-authoritative; V3H no cambia autoridad ni persistencia.
- El Mundo Demo ya opera en memoria/local session; la revision rapida debe reutilizarlo y no introducir escrituras remotas.

## Alcance de correccion aprobado por esta auditoria

1. Simplificar landing y lenguaje.
2. Normalizar Demo social, ocultar perspectivas avanzadas y anadir Revision rapida local.
3. Unificar estados de Retos y su filtro secundario.
4. Compactar ubicacion de Mercado y asegurar targets prioritarios.
5. Corregir la matriz visual para cubrir Avisos y Ajustes por separado.
6. Crear pruebas y evidencia visual de los recorridos, estados y contratos V3H.

No se modificaran SQL, Supabase, migraciones, RPC, RLS, Stripe, Rating, rewards, motores deportivos ni Wave 9C.

## Cierre del RC

- Resultado final: Node 20/20 + TS/TSX 805/805 = 825/825.
- Omitidos, `todo` y cancelados: 0/0/0.
- Typecheck, build 78/78, lint focalizado, lint global y `git diff --check`: PASS.
- Responsive: 152 combinaciones en los ocho viewports exigidos; 0 overflow raiz, errores de navegacion, errores/warnings de consola, peticiones fallidas o imagenes rotas.
- Tema y movimiento: 25 combinaciones light/dark/reduced motion; PASS.
- Retos light/dark: superficies tematicas verificadas y evidencia desktop/portrait/landscape regenerada tras V3H-032.
- PWA productiva local: 8/8 superficies `standalone`, controladas por Service Worker y sin targets pequenos.
- Offline: Demo y pruebas de cero escritura disponibles desde cache; una ruta API no cacheable no finge exito y se recupera al reconectar.
- Supabase, migraciones, RPC, RLS, flags, Stripe y datos productivos: sin cambios.
- Android fisico, iPhone fisico y PWA instalada fisicamente: PENDING.
