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
| Hash SHA-256 | `cef767f201a00f9f36fdaad8b27a195e9c767147651153717dabf043b71d16d3` |
| Payload canonico | 567.068 bytes, sin contar el manifest |

`demoNow` sustituye a la hora del dispositivo al construir historias. El generador no usa `Date.now()` ni fechas variables.

## Distribucion fisica

| Recurso | Contenido | Bytes |
| --- | --- | ---: |
| `manifest.json` | version, seed, hash, conteos y URLs | 635 |
| `core.json` | equipos, campos, perspectivas, ranking e historias | 36.678 |
| `players.json` | 365 perfiles, Rating V2 y loadouts | 355.011 |
| `matches.json` | partidos, alineaciones, resultados, goleadores y Retos | 141.645 |
| `activity.json` | logros, cajas, avisos y mappings de equipo | 33.695 |

Los cuatro chunks de dominio se descargan en paralelo y se validan como una unidad antes de mostrar el mundo. V1 no hace carga diferida por pestana: el payload completo queda por debajo del presupuesto de 700 KB y esta decision evita esperas al cambiar de seccion. La separacion permite introducir carga lazy en V2 sin cambiar el contrato de las entidades.

Cada URL de chunk lleva `?h=cef767f201a00f9f`. El navegador puede conservarla con `force-cache` sin mezclar una version nueva del manifest con datos anteriores.

## Entidades publicas

| Entidad | Namespace | Campos funcionales principales |
| --- | --- | --- |
| Equipo | `demo_team_*` | identidad, territorio publico, plantilla, estadisticas, escudo y cosméticos desbloqueados |
| Jugador | `demo_player_*` | nombre ficticio, ano de nacimiento, posicion, Rating V2, estadisticas, mercado y carta |
| Partido | `demo_match_*` | revision, estado, modalidad, equipos, alineacion, reservas, marcador y goleadores |
| Reto | `demo_challenge_*` | equipos, propuesta, estado y partido canonico cuando procede |
| Logro | `demo_achievement_*` | sujeto, clave real, fecha y evidencia legible |
| Caja | `demo_reward_box_*` | propietario demo, logro de origen, estado y recompensa determinista |
| Aviso | `demo_notification_*` | categoria, obligatoriedad, destino y fecha |
| Historia | `demo_story_*` | titulo, cuerpo y referencias canonicas |

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
- avisos leidos en la sesion.

`Reiniciar demo` elimina esa clave y restaura el snapshot. No existe cola offline ni sincronizacion posterior.

## Contrato read-only

La carga publica solo permite `GET`, usa `credentials: "omit"` y no importa el cliente de Supabase. Se bloquean contractualmente:

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
- un Reto aceptado enlaza un partido programado;
- un Reto completado enlaza un partido finalizado;
- los demas estados de Reto no enlazan partido;
- logros, cajas, ranking e historias resuelven sujetos y referencias existentes;
- no aparece ningun campo prohibido.

## Rating y cosmeticos

Las cartas de campo se calculan mediante `calculateRatingCardLayers` y declaran `pachangas-rating-v2`. Los porteros conservan explicitamente `currentOverall: null` porque su dominio V2 sigue pendiente; no se inventa una formula alternativa.

La UI reutiliza `PlayerCosmeticCard` y `TeamShieldView` con los catalogos activos. No hay piezas prototype, Premium Ball ni propuestas del Premium Art Pack tratadas como posesiones.

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
