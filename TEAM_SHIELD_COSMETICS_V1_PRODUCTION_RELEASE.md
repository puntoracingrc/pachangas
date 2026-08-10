# Team Shield Cosmetics V1 - Production Release

Fecha de cierre: 2026-08-11 (Europe/Madrid).

## Resultado

Team Shield Cosmetics V1 esta publicado y activo en `https://pachangasiq.com`.
El nuevo editor y `TeamShieldView` sustituyen a la configuracion visual legacy
como autoridad activa. Los equipos sin loadout nuevo reciben la configuracion
Base IQ, sin conservar ni reinterpretar la apariencia antigua.

- Nuevo editor de escudos: ACTIVO.
- `TeamShieldView`: ACTIVO.
- Base gratuita: ACTIVA.
- Inventario, loadout y NEW por admin: PREPARADOS.
- Rewards automaticos de equipo: OFF.
- Synthetic World: AUSENTE.

## Git y Vercel

- `main` inicial: `c92eb1c65bdd61b1124e7a2d836563350dad7bea`.
- PR funcional: [#130](https://github.com/puntoracingrc/pachangas/pull/130), fusionado.
- Head revisado de #130: `b3d013f21a987bac1025b3cdcc134bd472ec6619`.
- Merge de #130: `cbbdbd0616925f5e755d4cbbfd536715124a3e8a`.
- Deployment de #130: `dpl_9ZXmSvZsrT9S3WqfA4F2AkBBZCa3`, `READY`.
- Main funcional final tras los bordes: `740d1f9116709674d39e0fcec733b3907bff2819`.
- Deployment funcional final: `dpl_8PPEqaGvkwhbru2T2XQNbwv8bJAZ`, `READY`.
- Dominio verificado: `https://pachangasiq.com` sirve el deployment final.

## Backup y ledger

Antes de la primera escritura se comprobo en Supabase produccion un backup
fisico recuperable con fecha `2026-08-10 00:18:21 UTC`. PostgreSQL es `17.6`.

- Ledger inicial: 81 migraciones.
- No existia ninguna migracion Team Shield.
- No existia el schema `simulation`.
- Ledger final: 85 migraciones.
- Los hashes de los archivos y los statements registrados se verificaron antes
  del cierre.

Migraciones aplicadas, en este orden:

1. `20260810151241_team_shield_cosmetics_v1`.
2. `20260810152852_team_shield_registered_user_hardening`.
3. `20260810153058_team_shield_cosmetic_fk_indexes`.

Despues se aplico separadamente la migracion premium documentada en
`TEAM_SHIELD_PREMIUM_BORDERS_V1_PRODUCTION_RELEASE.md`.

No se aplicaron baselines, migraciones de Synthetic World ni migraciones de los
laboratorios Premium 3D.

## Activacion

La infraestructura se migro inicialmente con ambas flags desactivadas. Tras la
verificacion de DB, RLS, aplicacion, PWA y smoke se activo solo:

- `team_cosmetics_enabled = true`.
- `team_cosmetic_rewards_enabled = false`.

El editor, el renderer y el read model estan activos. No se fabricaron grants,
inventarios ni loadouts para usuarios reales durante el release.

## Autoridad y seguridad

- Las escrituras pasan por RPC autoritativas con actor autenticado,
  `operationId`, revision esperada, secuencia de servidor y recibo idempotente.
- `authenticated` no tiene escritura directa sobre las tablas Team Shield.
- Las RPC legacy `save_pachanga_team_crest_draft_v1` y
  `publish_pachanga_team_crest_v1` no son ejecutables por clientes autenticados.
- Las ocho tablas nuevas tienen RLS habilitado.
- `anon` no puede leer inventario, seen ni guardar escudos.
- Un miembro ordinario solo recibe el escudo publico de su equipo.
- Un admin puede gestionar exclusivamente su equipo; owner y admin pueden
  guardar.
- Las politicas exigen usuario registrado y comprueban membership, rol, actor y
  ownership. El Auth anonimo de Supabase no satisface el predicado de usuario
  registrado.

Las pruebas adversarias confirmaron `permission denied` para anon, rechazo para
no miembros y rechazo de escritura para miembros sin rol administrativo. El
replay de una operacion admin devolvio la misma revision y no duplico efectos.

## Realtime y PWA

Realtime publica las entidades canonicas de inventario, seen, escudo publico y
estado. El cliente invalida el snapshot afectado y vuelve a leer del servidor;
no existe una segunda autoridad en localStorage.

- `/api/client-policy`: `Cache-Control: private, no-store`.
- `minimumSupportedClientVersion`: `2.0.0`.
- Cliente sin version: clasificado `v1-unversioned`, escritura bloqueada con
  `CLIENT_UPDATE_REQUIRED` y lecturas disponibles.
- Cliente `2.0.0+release.test`: escritura permitida.
- `/sw.js`: no-store y version `2.0.0+sw.cbbdbd061692` en el release base.
- El Service Worker incluye actualizacion controlada y `SKIP_WAITING`.

## Verificacion funcional y visual

Validacion del head final de #130:

- `npm test`: 20 pruebas Node y 210 TypeScript, correctas.
- Typecheck: correcto.
- Build: correcto.
- Lint focalizado: correcto.
- `git diff --check`: correcto.

QA en preview y produccion:

| Vista | Overflow horizontal | Imagenes rotas | Errores de consola |
| --- | ---: | ---: | ---: |
| 1440x900 | 0 | 0 | 0 |
| 390x844 | 0 | 0 | 0 |
| 844x390 | 0 | 0 | 0 |

Se revisaron `/equipo/identidad`, `/laboratorio-cosmeticos-escudo`, escudo
publico y Player Cosmetics. La sesion autenticada final mostro el grupo
correcto, `Revisión confirmada 0`, el boton `Guardar escudo`, cero overflow,
cero imagenes rotas y cero errores de consola.

El LOD de `TeamShieldView` se comprobo visualmente a 24, 32, 48 y 64 px. Los
tamanos 24 y 32 conservan el renderer ligero; las superficies mayores pueden
usar materiales prerenderizados aprobados.

## Integridad deportiva

La misma consulta agregada y sin PII se ejecuto antes y despues del release:

| Evidencia | Antes | Despues |
| --- | --- | --- |
| Perfiles | 1 | 1 |
| Grupos | 4 | 4 |
| Rating V2, facetas, reliability y motor | `c86fa53118f7e0b978144b246ae6be6c` | `c86fa53118f7e0b978144b246ae6be6c` |
| Payload de grupos | `292d2806300164b9e6cc8ce3e9842b47` | `292d2806300164b9e6cc8ce3e9842b47` |

Rating V2, Season Score, TOPS, Player Cosmetics y Core Social no fueron
modificados por las migraciones ni por la activacion.

## Logs y advisors

- Vercel Runtime Errors desde el release: ninguno.
- Supabase API despues del deployment: 14 peticiones, cero errores; las dos
  lecturas Team Shield observadas respondieron 200.
- PostgreSQL despues del deployment: cuatro entradas, cero errores.
- Realtime: sin errores posteriores al release.

El advisor de seguridad conserva avisos sobre tres RPC `SECURITY DEFINER`
autenticadas y sobre Auth anonimo. Son la frontera autoritativa intencional y
quedaron respaldadas por grants minimos, validacion de `auth.uid()`, usuario
registrado, membership y RLS adversarial. Referencia:
https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

El advisor de rendimiento solo marca como no usados indices de tablas nuevas y
vacias. No se eliminaron indices de FK necesarios por una muestra sin trafico.
Referencia:
https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Fuera del release

- PR #131: abierto y draft; laboratorio Premium 3D.
- PR #132: abierto y draft; RC del Balon Premium.
- Balon Premium interactivo: NO ACTIVO.
- QA fisica iPhone: PENDING.
- QA fisica Android: PENDING.
- Cromo 3D, Carbono 3D, Corona 3D, Holo y Three.js/GLB productivo: FUERA.
- `/admin/simulation-world` y su API: 404.
- Schema `simulation`: AUSENTE.

## Cierre

Team Shield Cosmetics V1 queda operativo como unica autoridad visual de los
escudos. La identidad gratuita es util sin premios, los contratos de
inventario/loadout/NEW estan listos y los rewards automaticos permanecen
deliberadamente desactivados.
