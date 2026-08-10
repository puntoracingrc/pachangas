# Player Cosmetics V1 - Production Release

Fecha de release: 2026-08-10 (Europe/Madrid).

## Resultado

Player Cosmetics V1 esta publicado y activo en `https://pachangasiq.com`.
El sistema deportivo permanece separado del sistema cosmetico y el checksum de
Rating V2 es identico antes y despues del release.

- Produccion modificada: SI.
- Cosmetics V1 activo: SI.
- Team Cosmetics desplegado: NO.
- Synthetic World desplegado: NO.

## Git y Vercel

- `main` inicial: `c6eded866167fd2c56e95daeb42a1503a56806ac`.
- PR funcional: #125, fusionado.
- Head revisado de #125: `21d91e537fbcea78762800a3135008d7c73e3aba`.
- Merge de #125: `c0884e7639a10c5cc805a56215ec9b276cb96d26`.
- Deployment funcional: `dpl_7bnUn3pKSo9twYXi4acA5WtPZkY5`, `READY`.
- Hotfix responsive: PR #127, fusionado.
- Commit del hotfix: `0ee749b73dc9205f7a63f3e9b2055281cc0c8ec6`.
- Merge del hotfix: `2f98e406780d38d3fbba779b303049da2322cab6`.
- Deployment final de aplicacion: `dpl_7FChmjX3ZVgK3iGWWUJNwQA13cTd`, `READY`.
- Dominio verificado: `https://pachangasiq.com` sirve el deployment final.

## Backup y PostgreSQL

Antes de la primera escritura se confirmo un backup fisico de Supabase con
estado `COMPLETED`, creado el 2026-08-10 a las 00:18:21 UTC. WAL-G esta activo.
PITR continuo no esta habilitado; la copia fisica diaria es la salvaguarda
recuperable disponible para esta migracion aditiva.

- Proyecto: Pachangas, region `eu-west-1`.
- PostgreSQL: `17.6`.
- Tamano de base al cierre: `28 MB`.
- El aviso historico sobre PostgreSQL 14 no aplica a este proyecto.
- No se combino ningun upgrade mayor de PostgreSQL con Cosmetics V1.

## Ledger y migracion

Antes del release, remoto y repositorio coincidian en 80 migraciones. La unica
migracion local pendiente era:

`20260810040115_player_cosmetics_v1.sql`

- SHA-256 del archivo: `89527cec240b5ee065e19bfccb707b6b53287771382001818f349154730d1002`.
- Migracion aplicada exclusivamente a produccion Pachangas.
- No se aplicaron baselines ni migraciones de Synthetic World.
- La API registro inicialmente una version horaria generada. Se normalizo solo
  esa fila nueva, con una comprobacion de unicidad, al versionado inmutable del
  repositorio.
- Ledger final: version `20260810040115`, nombre `player_cosmetics_v1`.

## Feature flag

La migracion creo `player_cosmetics_enabled = false`.

Secuencia operativa:

1. Flag OFF durante la verificacion de esquema, RLS y primer deploy.
2. Primera activacion a las `09:40:32 UTC`.
3. Flag OFF temporal a las `09:45:48 UTC` al detectar overflow movil.
4. Hotfix #127, build y QA responsive.
5. Activacion final a las `09:56:05 UTC`.

Estado final: `true`, revision fisica de fila `132275992`.

## Catalogo y economia

Produccion contiene exactamente 14 cosmeticos de jugador activos y 14 entradas
activas en los reward pools:

| Slot | Piezas activas |
| --- | --- |
| Marco | Barrio Acero, Marco Cobre, Barrio Plata, Future IQ Navy, Retro Cromo |
| Fondo | Asfalto Nocturno, Grid IQ |
| Acento | Acento Cobre, Acento Navy |
| Efecto | Focos, IQ Scan, Glint Oro |
| Titulo | De toda la vida, Motor del equipo |

- Filas player `prototype` persistidas: 0.
- Prototipos en reward pools: 0.
- Las otras 16 propuestas permanecen solo en codigo/laboratorio.
- No se recalibraron frecuencia de cajas, rareza global, puntos por duplicado
  ni logros que generan cajas fuera de lo revisado en #125.

## Autoridad, RLS y privacidad

- Inventario, loadout y recibos son autoritativos en PostgreSQL.
- Las mutaciones publicas resuelven el actor con `auth.uid()`.
- Cada escritura usa `operationId`, revision esperada, secuencia de servidor,
  transaccion y snapshot canonico.
- `anon` no tiene lectura de inventario, loadout ni public cards.
- `authenticated` no tiene grants directos de INSERT/UPDATE/DELETE sobre
  inventario, loadout o public cards.
- El inventario y el loadout privados tienen politicas SELECT owner-only.
- La prueba autenticada segura de produccion vio 0 filas ajenas.
- El read model publico no contiene inventario, NEW, puntos ni recibos.
- Las RPC mutables permanecen cerradas a `authenticated`, con `search_path`
  fijado y `lock_timeout = 750ms`.

La produccion solo tenia un perfil con ficha y ningun inventario cosmetico. No
se creo un segundo usuario ni se concedieron piezas sinteticas para forzar una
demostracion. La matriz A/B completa y adversaria queda respaldada por el E2E
autenticado de staging.

## Realtime y read models

Estas tres tablas estan en `supabase_realtime` con replica identity adecuada:

- `pachanga_player_reward_inventory`.
- `pachanga_player_cosmetic_loadouts`.
- `pachanga_player_cosmetic_public_cards`.

El cliente invalida el snapshot afectado y vuelve a leer el estado canonico.
No existe una cola offline de operaciones deportivas o cosmeticas confirmadas.

## Smoke de produccion

Con flag OFF y despues con flag ON se verificaron:

- `/`: 200.
- `/personalizar-carta`: 200.
- `/equipo/identidad`: 200.
- `/laboratorio-cosmeticos-ficha`: 200 y `noindex, nofollow`.
- `/admin/simulation-world`: 404 y `noindex`.

Un usuario sin inventario recibe:

- 0 piezas.
- revision 0.
- Original/Ninguno en todos los slots.
- ningun cosmetico bloqueado o regalado.
- Guardar deshabilitado mientras no exista un cambio confirmado.

Los selectores consumen exclusivamente el array `owned`; la previsualizacion
no persiste hasta que la RPC devuelve el snapshot confirmado.

## NEW, cajas, duplicados, badges y notificaciones

No se abrio ni altero una caja de un usuario real. El contrato productivo,
catalogo, triggers y RPC estan desplegados. La evidencia de aceptacion es el
E2E autenticado de staging, que cubrio:

- NEW persistente entre dispositivos y desaparicion jerarquica al marcar seen.
- notificacion `player_reward_cosmetic_unlocked`.
- selector owned-only.
- preview local distinta del loadout guardado.
- `Equipar ahora` atomico desde una caja.
- duplicado con una unica propiedad, +8 puntos y sin NEW/notificacion extra.
- badge ganado equipable y badge ajeno rechazado.
- dos clientes desde la misma revision: un ganador y un conflicto `PT409`.
- replay idempotente con un solo recibo.
- Realtime y refetch canonico sin recarga manual.

## Responsive, movimiento y rendimiento

QA real mediante Chrome Device Metrics sobre el dominio productivo:

| Vista | Documento/viewport | Overflow | Errores runtime |
| --- | --- | --- | --- |
| 1440x900 | 1440/1440 | 0 | 0 |
| 390x844 | 390/390 | 0 | 0 |
| 844x390 | 844/844 | 0 | 0 |

Se revisaron el editor personal, el editor de escudo y el laboratorio. El
hotfix #127 deja las seis categorias visibles en una rejilla estable de tres
columnas y mantiene accesibles Guardar/Restablecer.

Con `prefers-reduced-motion: reduce`, la media query estuvo activa en vertical
y apaisado. La referencia de staging conserva p95 de 10,1-10,2 ms para Focos,
IQ Scan y Glint Oro, sin regresion sostenida.

## PWA bridge

- `minimumSupportedClientVersion`: `2.0.0`.
- Cliente sin version: `v1-unversioned`, escritura bloqueada con
  `CLIENT_UPDATE_REQUIRED` y lecturas disponibles.
- Cliente `2.0.0+2f98e40`: escritura permitida.
- `/api/client-policy`: `private, no-store, max-age=0, must-revalidate`.
- Service Worker final: `2.0.0+sw.2f98e406780d`.
- `/sw.js`: `no-cache, no-store, must-revalidate`.

## Logs y advisors

- Vercel Runtime Errors, ventana posterior al deploy: ninguno.
- Vercel logs de error/warning del deployment final: ninguno.
- Supabase PostgreSQL desde la migracion: ninguna entrada de error/fatal.
- Realtime: sin incidencia asociada al release.

El advisor de seguridad marca como WARN las RPC `SECURITY DEFINER` que forman
la frontera autoritativa intencional y el uso del rol `authenticated` con Auth
anonimo habilitado. Grants, actor, ownership, RLS y busquedas seguras fueron
verificados; no se detecto un fallo critico de Cosmetics.

El advisor de rendimiento informa de FKs sin indice individual e indices nuevos
aun sin uso. Son avisos INFO sobre tablas 1:1 o recien creadas; no se anadieron
indices especulativos durante el release.

## Rating V2 y Synthetic World

Checksum agregado, sin PII, antes de la migracion:

`ba18d455796ebd2c33c7f12470e8a32e`

Checksum despues de migracion, activacion, hotfix y cierre:

`ba18d455796ebd2c33c7f12470e8a32e`

GRL, facetas, reliability y version de motor permanecen identicos.

Produccion no contiene schema ni tablas de simulacion. No se desplegaron los
640 agentes ni las 3.613 cajas de Synthetic World. La ruta alojada devuelve 404.

## Incidencias del release

1. Supabase genero una version horaria de ledger. Se corrigio solo la fila nueva
   tras verificar que la version canonica no existia.
2. La primera matriz visual detecto overflow en 390 px. Se apago la flag, se
   implemento #127, se repitieron build/typecheck/tests/QA y se reactivo.
3. No hubo perdida de datos, fallo RLS, cambio de Rating ni rollback destructivo.

## Checks

- PR #125: Vercel Preview verde y fusionado.
- PR #127: Vercel Preview verde y fusionado.
- Build del hotfix: correcto.
- Typecheck del hotfix: correcto.
- Tests focalizados Cosmetics: 6/6.
- Candidato completo previo: build y 202/202 pruebas.
- `git diff --check`: correcto.
- Deployment final y custom domain: `READY`.

## Cierre

Player Cosmetics V1 queda activo. Los usuarios pueden recibir cosmeticos desde
las cajas reales, ver el estado Nuevo, personalizar su ficha con sus propias
piezas y publicar una combinacion segura. Team Cosmetics y nuevas piezas quedan
fuera de este release.
