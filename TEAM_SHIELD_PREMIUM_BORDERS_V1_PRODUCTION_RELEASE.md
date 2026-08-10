# Team Shield Premium Borders V1 - Production Release

Fecha de cierre: 2026-08-11 (Europe/Madrid).

## Resultado

Se extrajo de la investigacion Premium 3D un subset estatico y seguro para
produccion:

- Borde Cobre Premium: PUBLICADO.
- Borde Plata Premium: PUBLICADO.
- Borde Oro Premium: PUBLICADO.
- Balon Premium interactivo: NO ACTIVO.

La release no incorpora sensores, `DeviceOrientation`, Three.js, GLB, Cromo
3D, Carbono 3D, Corona 3D ni Holo.

## Git, PR y deployment

- Base: merge de Team Shield V1
  `cbbdbd0616925f5e755d4cbbfd536715124a3e8a`.
- Rama: `codex/team-shield-premium-borders-v1`.
- Commit: `031abb52a276a3a99980390eca8b8af4d42d2ccb`.
- PR: [#133](https://github.com/puntoracingrc/pachangas/pull/133), no draft y
  fusionado.
- Merge: `740d1f9116709674d39e0fcec733b3907bff2819`.
- Deployment: `dpl_8PPEqaGvkwhbru2T2XQNbwv8bJAZ`, `READY`.
- Dominio: `https://pachangasiq.com`.

El diff contiene exactamente 12 rutas, 158 lineas anadidas y 7 eliminadas.

## Migracion especifica

Se creo y aplico una migracion forward-only exclusiva para los tres bordes:

`20260810221436_team_shield_premium_borders_v1.sql`

- MD5 local/remoto: `0d358cb7a32c807f4caf84d7df609983`.
- No activa feature flags.
- No concede inventario.
- No crea reward mappings.
- No modifica datos deportivos.
- No contiene Ball, sensores ni runtime 3D.

Estado de catalogo final:

| Key | Version | Contrato | Asset |
| --- | ---: | --- | --- |
| `team.shield.border.copper` | 2 | `prerender-material-v1` | `border-copper.9b756acb.webp` |
| `team.shield.border.silver` | 2 | `prerender-material-v1` | `border-silver.dde0edf8.webp` |
| `team.shield.border.gold` | 2 | `prerender-material-v1` | `border-gold.96413f0c.webp` |

## Renderer y rendimiento

El renderer solo usa una textura premium cuando se cumplen simultaneamente:

1. El contrato es `prerender-material-v1`.
2. El material pertenece a la allowlist interna Cobre/Plata/Oro.
3. El tamano no es 24 ni 32 px.

Los tamanos 24 y 32 conservan el fallback CSS ligero. Las texturas son WebP
con nombre content-hashed:

- Cobre: 37.060 bytes.
- Plata: 35.682 bytes.
- Oro: 37.112 bytes.

En produccion, los tres assets responden 200, `image/webp` y
`Cache-Control: public, max-age=31536000, immutable`.

## Economia y aislamiento

- `team_cosmetics_enabled = true`.
- `team_cosmetic_rewards_enabled = false`.
- Inventarios Team Shield creados por el release: 0.
- Inventarios premium creados por el release: 0.
- Reward mappings nuevos: 0.
- Contratos o assets del Balon Premium interactivo anadidos por esta release: 0.
- Los simbolos estaticos preexistentes `symbol.ball` y
  `team.shield.symbol.ball_iq` permanecen en el catalogo; no son el Balon
  Premium, no usan sensores y no forman parte de este subset.

Cobre, Plata y Oro existen como cosmeticos visuales catalogados. No aumentan
Rating, Season Score ni TOPS y no se conceden automaticamente.

## Validacion

- Tests focalizados Team Shield + Premium: 13/13.
- `npm test`: build correcto y 215/215 pruebas.
- Typecheck: correcto.
- Lint focalizado: correcto.
- SQL transaccional: Cobre/Plata/Oro v2, ningun contrato Premium interactivo
  nuevo, rewards OFF y rollback correcto.
- `git diff --check`: correcto.
- PR #133: Vercel Preview verde.

QA visual en preview y produccion:

| Vista | Premium visibles | Overflow | Imagenes rotas | Errores runtime |
| --- | ---: | ---: | ---: | ---: |
| 1440x900 | 20 ejemplos | 0 | 0 | 0 |
| 390x844 | 20 ejemplos | 0 | 0 | 0 |
| 844x390 | 20 ejemplos | 0 | 0 | 0 |

Tambien se verificaron `/equipo/identidad` y Player Cosmetics en vertical y
apaisado. La aplicacion no introduce el bundle de Three.js/GLB en listas,
Retos, Mercado, TOPS, rankings ni mini escudos.

## Pendiente deliberado

- PR #131 permanece abierto/draft como evidencia del laboratorio.
- PR #132 permanece abierto/draft para continuar el Balon Premium.
- Estado del Balon: `READY_PENDING_PHYSICAL_QA`.
- iPhone fisico: PENDING.
- Android fisico: PENDING.

Hasta completar esas dos pruebas fisicas no se publicara el comportamiento
interactivo ni se crearan grants o reward mappings asociados al Balon.

## Cierre

El subset productivo queda limitado a tres materiales prerenderizados, con LOD
ligero, cache inmutable y sin efectos sobre la economia o el sistema deportivo.
