# Referee Profiles and Marketplace V1 Report

Estado: `READY FOR REVIEW`

## Identidad arbitral

`RefereeProfile` pertenece a un usuario universal, no a un grupo ni a una
`PlayerProfile`. La unicidad es una ficha por usuario. Las pruebas cubren:

- usuario solo arbitro;
- usuario con PlayerProfile y RefereeProfile simultaneas;
- rechazo de segunda ficha;
- otro usuario sin permiso de edicion;
- slug concurrente con un solo ganador;
- Rating, GRL y facetas ausentes de toda ficha arbitral.

La identidad publica toma un snapshot seguro de nombre y avatar al crear la
ficha. No almacena telefono, domicilio ni coordenadas residenciales.

## Lifecycle y verificacion

El lifecycle operativo es independiente de la verificacion:

| Eje | Estados |
| --- | --- |
| Perfil | `draft`, `active`, `suspended`, `archived` |
| Verificacion | `unverified`, `pending`, `verified`, `rejected`, `revoked` |
| Visibilidad | `private`, `unlisted`, `public` |
| Mercado | `not_listed`, `listed`, `paused` |
| Disponibilidad | `AVAILABLE`, `LIMITED`, `UNAVAILABLE` |

Activar exige identidad valida, bio, al menos una modalidad y una zona.
Publicar en Mercado exige perfil activo, visibilidad publica, disponibilidad
para propuestas y flags activos. Suspender o archivar lo retira de busqueda y
bloquea nuevas propuestas, conservando asignaciones y estadisticas historicas.

## Modalidades, zonas y disponibilidad

Modalidades R3: `FOOTBALL_11`, `FOOTBALL_7`, `FOOTBALL_5`, `FUTSAL` y `OTHER`.
Cada una admite año de experiencia y nota publica, pero no nivel ni voto.

Las zonas guardan pais, provincia, municipio, zona general y radio opcional.
No guardan domicilio ni geolocalizan por IP. El perfil admite multiples zonas.

La disponibilidad combina estado general, ventanas semanales con timezone IANA
y excepciones privadas. Solo las ventanas marcadas publicas salen en el read
model publico; el motivo y detalle de excepciones nunca salen.

## Perfil publico y privado

`RefereeProfileCard` es un componente propio. Comparte el lenguaje visual de
Pachangas IQ y muestra arbitro, partidos concluidos, modalidades, zonas, Clubs,
disponibilidad y verificacion. Nunca reutiliza una carta de jugador ni muestra
GRL, facetas, posicion, estrellas o Rating.

La ruta `/arbitros/[slug]` permanece gated, fuera de navegacion publica y
`noindex,nofollow` en R3. El read model publico incluye solo:

- nombre/avatar/slug/bio publicos;
- modalidades y zonas generales;
- experiencia declarada;
- Clubs con visibilidad aprobada por ambas partes;
- disponibilidad general y ventanas publicas;
- partidos concluidos y estado seguro de verificacion.

La ruta `/perfil/arbitro` entrega el snapshot privado exclusivamente al actor
autenticado mediante API `no-store`.

## Mercado integrado

R3 añade la pestana `Arbitros` al Mercado existente; no crea shell ni app
paralela. La busqueda y paginacion se ejecutan en servidor y solo devuelven
perfiles activos, publicos, listados y disponibles cuando el flag esta activo.

Filtros implementados:

- zona general, provincia y municipio;
- modalidad;
- dia y franja horaria;
- disponibilidad;
- Club vinculado visible;
- experiencia desde;
- verificacion.

El orden es estable por verificacion, disponibilidad, experiencia, nombre y
UUID estable. El cliente cachea el read model, no el resultado definitivo de
ninguna escritura.

## Seguridad

- `anon` solo puede leer el RPC publico minimizado cuando los flags lo permiten.
- `authenticated` no puede leer excepciones o campos privados de otro arbitro.
- Perfil privado y Mercado no aceptan un snapshot calculado por el navegador.
- Archivar, suspender o pausar invalida el resultado sin borrar historia.
- Realtime entrega invalidacion; la UI vuelve a consultar el servidor.
- APIs privadas responden `Cache-Control: private, no-store`.

## QA

El recorrido local y staging cubrio create, unicidad, Player + referee,
lifecycle, verificacion separada, modalidades, multi-zona, ventanas,
excepciones, listing/pausa, privacidad y filtros combinados. La carga de
Mercado con `10.000` perfiles, `50.000` modalidades y `50.000` zonas alcanzo
p95 `33.878 ms`; perfil publico p95 `0.177 ms` y privado p95 `4.360 ms`.

La matriz visual de perfil privado, publico y Mercado paso en los cinco
viewports obligatorios con `0` overflow, `0` controles recortados, `0` imagenes
rotas y `0` errores de consola.
