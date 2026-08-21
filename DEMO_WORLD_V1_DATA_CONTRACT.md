# Demo World V1 Data Contract

## Proposito

Demo World V1 es un read model publico, ficticio y congelado de Pachangas IQ. Explica el producto sin crear identidades Auth, filas deportivas, avisos o recompensas en Supabase. No comparte datos ni autoridad con Synthetic World o con un grupo real.

## Identidad del snapshot

| Campo | Valor V1 |
| --- | --- |
| Version | `1` |
| Temporada | `2026/27` |
| Modo | `demo-world-read-only` |
| Seed | `pachangas-iq-demo-world-v1-2026-27` |
| `demoNow` | `2027-03-18T18:00:00.000Z` |
| Hash SHA-256 | `34158b4f56a3011c9010b0952f74043435e9f896f0b7ea5fd90e0dfacdfac3ae` |
| Payload canonico | 603.252 bytes, sin contar el manifest |

`demoNow` sustituye a la hora del dispositivo al construir historias. El generador no usa `Date.now()` ni fechas variables.

## Distribucion fisica

| Recurso | Contenido | Bytes |
| --- | --- | ---: |
| `manifest.json` | version, seed, hash, conteos y URLs | 635 |
| `core.json` | preview inicial, equipos, campos, perspectivas, Ranking Provincial e historias | 76.158 |
| `players.json` | 331 perfiles, Rating V2 y loadouts | 323.156 |
| `matches.json` | partidos, asistencia, alineaciones, resultados, goleadores y Retos | 169.906 |
| `activity.json` | logros, cajas, avisos y mappings de equipo | 34.032 |

Inicio descarga y valida solo `core.json`. La primera navegacion a Partido, Mercado, Equipo o Perfil solicita una unica vez `activity.json`, `matches.json` y `players.json`, valida el hash comun y reutiliza desde entonces el snapshot completo. La carga secundaria no bloquea Inicio ni ejecuta escrituras.

Cada URL de chunk lleva `?h=34158b4f56a3011c`. El navegador puede conservarla con cache larga sin mezclar una version nueva del manifest con datos anteriores. El Service Worker conserva `/demo`, el manifest y los chunks inmutables por hash; nunca encola acciones deportivas offline.

## Entidades publicas

| Entidad | Namespace | Campos funcionales principales |
| --- | --- | --- |
| Equipo | `demo_team_*` | identidad, territorio publico, plantilla, estadisticas, escudo y cosméticos desbloqueados |
| Jugador | `demo_player_*` | nombre ficticio, ano de nacimiento, posicion, Rating V2, estadisticas, mercado y carta |
| Partido | `demo_match_*` | revision, estado, modalidad, equipos, alineacion, reservas, marcador y goleadores |
| Asistencia | `demo_attendance_*` | partido, jugador, estado publico y fecha estable del registro |
| Reto | `demo_challenge_*` | equipos, propuesta, estado y partido canonico cuando procede |
| Logro | `demo_achievement_*` | sujeto, clave real, fecha y evidencia legible |
| Caja | `demo_reward_box_*` | propietario demo, logro de origen, estado y recompensa determinista |
| Aviso | `demo_notification_*` | categoria, obligatoriedad, destino y fecha |
| Historia | `demo_story_*` | titulo, cuerpo y referencias canonicas |
| Ranking provincial | `demo_ranking_entry_*` | read model Season Score V3, revision publicada y estado de elegibilidad |

No existen paginas indexables por jugador o equipo. `/demo` y `/demo/contact-sheet` heredan `noindex,nofollow`.

## Perspectivas

| ID | Rol visual | Equipo | Autoridad real |
| --- | --- | --- | --- |
| `player` | jugador de plantilla | Cobalto Raval | ninguna |
| `admin` | administrador de equipo | Cobalto Raval | ninguna |
| `free-agent` | jugador sin equipo | sin equipo | ninguna |

Cambiar de perspectiva solo modifica estado local. Nunca crea ni suplanta una sesion Auth.

## Estado efimero

La unica persistencia de interaccion usa `sessionStorage` bajo `pachangas-demo-world-v1-session`:

- perspectiva activa;
- asistencia simulada por partido;
- cajas abiertas en la sesion;
- piezas cosmeticas guardadas en el inventario;
- piezas marcadas como nuevas;
- piezas equipadas en la sesion;
- avisos leidos en la sesion.

`Reiniciar demo` elimina esa clave y restaura el snapshot. No existe cola offline ni sincronizacion posterior.

## Contrato read-only

La carga publica solo permite `GET`, usa `credentials: "same-origin"` para que los snapshots funcionen tambien en Previews protegidas de Vercel y no importa el cliente de Supabase. Las URLs de chunks son relativas al propio despliegue; nunca se envian credenciales a otro origen. Se bloquean contractualmente:

- `POST`, `PUT`, `PATCH` y `DELETE`;
- RPC;
- `insert`, `update` y `delete` de Supabase;
- cualquier operacion clasificada como mutacion o escritura.

Las acciones Voy/Duda/No, Invitar, herramientas Admin, leer avisos y abrir cajas son simulaciones locales. Los Retos existentes se consultan y sus partidos canonicos se pueden abrir, pero V1 no simula la creacion de uno nuevo. Ninguna accion puede crear usuarios, equipos, partidos, Retos, puntos, notificaciones, logros o rewards reales.

## Sanitizacion

La validacion recursiva rechaza claves relacionadas con:

- email, telefono o movil;
- IDs Auth, propietario real o `service_role`;
- direccion privada;
- informacion medica o de lesiones;
- conducta, moderacion o reportes;
- recibos de operacion y tokens.

Las ubicaciones son nombres ficticios o zonas publicas generalizadas. La demo no consulta Google Places.

## Integridad referencial

Antes de servir el mundo se comprueba que:

- jugadores y equipos usan namespaces demo;
- cada jugador pertenece a un equipo existente o es agente libre;
- el contador de plantilla coincide con sus jugadores;
- cada participante, reserva y goleador existe;
- cada goleador participo y la suma coincide con el marcador;
- cada asistencia referencia un jugador y partido existentes y usa uno de los cuatro estados publicos permitidos;
- un Reto aceptado enlaza un partido programado;
- un Reto completado enlaza un partido finalizado;
- los demas estados de Reto no enlazan partido;
- logros, cajas, ranking e historias resuelven sujetos y referencias existentes;
- el Ranking Provincial conserva la formula 55/30/15, los umbrales de elegibilidad, la revision publicada y premios desactivados;
- no aparece ningun campo prohibido.

## Rating y cosmeticos

Las cartas de campo se calculan mediante `calculateRatingCardLayers` y declaran `pachangas-rating-v2`. Los porteros conservan explicitamente `currentOverall: null` porque su dominio V2 sigue pendiente; no se inventa una formula alternativa.

La UI reutiliza `PlayerCosmeticCard` y `TeamShieldView` con los catalogos activos. No hay piezas prototype, Premium Ball ni propuestas del Premium Art Pack tratadas como posesiones.

La caja destacada nace de un hat-trick canonico, desbloquea `player.frame.barrio.copper` y reproduce localmente el ciclo abrir, guardar, NEW y equipar. Este inventario es efimero y `Reiniciar demo` lo elimina por completo.

## Ranking Provincial

El snapshot reutiliza el mismo contrato y componente publico que `/ranking`. Su read model esta congelado y no recalcula Season Score en el navegador:

- formula V3: calidad 55 %, competicion 30 % y oposicion 15 %;
- minimo de 15 Retos validos, 6 rivales logicos y fiabilidad 0,45;
- Top 10 paginado sobre 32 entradas ficticias;
- ficha propia en posicion 27;
- casos no elegible, provisional y pendiente de verificacion;
- `awardsEnabled: false`, sin conceder trofeos ni recompensas.

## Asistencia

Hay 168 evidencias publicas ficticias: 126 `played`, 14 `excused_absence`, 14 `late_cancellation` y 14 `unexcused_no_show`. Son historial descriptivo de asistencia, no reportes ni sanciones. Una baja justificada o tardia no se convierte automaticamente en mala conducta.

Los cinco mappings de equipo son exactamente:

| Hito | Achievement | Recompensa | Primera ocurrencia |
| --- | --- | --- | ---: |
| Primera victoria | `team.external.wins.001` | `team.shield.border.copper` | si |
| 10 Retos | `team.external.matches.010` | `team.shield.ornament.banner` | no |
| 25 partidos | `team.matches.025` | `team.shield.ornament.laurels` | no |
| 50 partidos | `team.matches.050` | `team.shield.border.silver` | no |
| Primera porteria a cero | `team.external.clean_sheets.001` | `team.shield.effect.edge_glow` | si |

## Generacion y congelacion

`npm run demo-world:generate` ejecuta el generador determinista. El test compara su resultado completo con los JSON versionados y recalcula el hash. Regenerar V1 con cualquier diferencia hace fallar la bateria; una evolucion intencional debe crear otra version/seed y otro manifest.

## Adaptacion de entrada

Los enlaces heredados `?demo=1` redirigen a `/demo`, conservando pestana y perspectiva cuando son validas. El centro global conectado a Supabase y el footer real no se montan dentro de Demo World. Un usuario autenticado que abra la URL recibe el mismo mundo ficticio aislado.
