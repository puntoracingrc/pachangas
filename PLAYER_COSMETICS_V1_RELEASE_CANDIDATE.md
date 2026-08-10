# Player Cosmetics V1 - Release Candidate

Fecha de cierre técnico: 2026-08-10 (Europe/Madrid).

## Estado Git

- PR visual #122: fusionado en `main`.
- Merge SHA #122: `3b6f9f3f7e8bd222e494cdc5c997021c6dd2eaa9`.
- Corrección `noindex, nofollow` del laboratorio, PR #126: fusionada.
- `main` auditado: `c6eded866167fd2c56e95daeb42a1503a56806ac`.
- PR funcional: #125, rama `codex/player-cosmetics-v1`.
- SHA funcional previo a este informe: `0d48f6fab3a639224c352d3cede8b864f0fa73af`.
- Base real de #125: coincide exactamente con el `main` anterior.
- Diff normalizado: 58 rutas de Cosmetics V1/V0.2, evidencias y pruebas; no arrastra el diff histórico de #122.

## Alcance

Player Cosmetics V1 cambia exclusivamente la presentación de la ficha. Mantiene un único `PlayerCardView`; `PlayerCosmeticCard` solo compone fondo, marco, acento, un efecto, título y badge alrededor de la ficha deportiva. No existe un segundo cálculo de GRL, facetas o fiabilidad.

Team Cosmetics V1 no forma parte de este candidato. La arquitectura compartida queda preparada, manteniendo la separación:

- PLAYER: propiedad, visto y equipado pertenecen a `player_profile_id`.
- TEAM futuro: propiedad y equipado pertenecerán al grupo; visto será individual por admin.

## Catálogo

Los reward pools de staging contienen exactamente 14 cosméticos de jugador activos:

| Slot | Piezas V1 |
| --- | --- |
| Marco | Barrio Acero, Marco Cobre, Barrio Plata, Future IQ Navy, Retro Cromo |
| Fondo | Asfalto Nocturno, Grid IQ |
| Acento | Acento Cobre, Acento Navy |
| Efecto | Focos, IQ Scan, Glint Oro |
| Título | De toda la vida, Motor del equipo |

Las 16 piezas experimentales permanecen solo en cliente/laboratorio y no aparecen en reward pools:

Barrio Bronce, Barrio Oro, Future Carbono, Barrio Negro Mate, Future Perla, Papel de Liga, Pizarra de Míster, Noche de Focos, Acento Plata, Acento Cian, Acento Oro, Scan Diagonal, Holo Suave, Barrido Cromo, Capitán de barrio y Turno de noche.

Los materiales compartidos conservados para futuras capas son: `steel`, `bronze`, `copper`, `silver`, `gold`, `navy`, `carbon`, `black_matte`, `pearl` y `chrome`. V1 permite un solo efecto principal por carta.

## Staging Supabase

- Proyecto/rama: `pwa-bridge-staging`.
- Project ref: `iozcjirlfytryzrcmrnq`.
- Migración aplicada: `20260810040115_player_cosmetics_v1.sql`.
- Ledger confirmado: versión `20260810040115`, nombre `player_cosmetics_v1`.
- Flag: `player_cosmetics_enabled = true` desde `2026-08-10 08:05:32+00`.
- Reward items cosméticos activos: 14.
- Prototipos experimentales persistidos como rewards: 0.

La rama de staging se rebasó previamente sobre producción para incorporar las migraciones ya vigentes. La aplicación inicial generó una versión de ledger automática; se corrigió únicamente el historial de staging para que coincida con el nombre/versionado inmutable del repositorio. No se reescribió ninguna migración ya ejecutada en producción.

## Producción

Consulta estrictamente de lectura sobre `qonbngfrnrqgmxbdfbea`:

- migración `20260810040115`: ausente;
- `private.pachanga_player_cosmetic_settings`: ausente;
- `public.pachanga_player_cosmetic_loadouts`: ausente.

Producción no ha sido modificada ni se ha activado Cosmetics V1.

## E2E autenticado

La prueba `tests/player-cosmetics-v1-staging-e2e.mjs` usa tres sesiones GoTrue sintéticas reales, sin `service_role` en el cliente, y cubre:

- caja con Marco Cobre nuevo;
- una única fila de inventario y estado NEW persistente tras logout/otro dispositivo;
- notificación `player_reward_cosmetic_unlocked`;
- Realtime y refetch canónico al marcar visto;
- preview local sin confirmación optimista y guardado por RPC;
- `Equipar ahora` atómico: propiedad, visto y loadout confirmados juntos;
- `Ver mi colección`: deep link al slot/item correcto sin autoequipar;
- duplicado: una propiedad, +8 puntos, ninguna fila ni NEW artificial y ninguna notificación extra;
- badge realmente ganado equipable;
- badge ajeno/no ganado rechazado por el servidor;
- dos clientes desde la misma revisión: un ganador y un `PT409`;
- Usuario A sin lectura/escritura sobre inventario, loadout o puntos de B;
- carta pública de B legible solo mediante el read model seguro;
- outsider sin permiso para abrir la caja de A.

Resultado final canónico:

```json
{
  "badgeEarned": true,
  "badgeUnearnedRejected": true,
  "concurrency": { "conflict": true, "winnerCount": 1 },
  "duplicate": { "inventoryRows": 1, "newArtificial": false, "points": 8 },
  "equipNow": { "equipped": true, "owned": true, "seen": true },
  "multideviceNew": true,
  "notificationCount": 2,
  "publicCardsSafe": true,
  "ratingChecksumStable": true,
  "realtimeSeenConverged": true,
  "rlsAdversarial": true
}
```

El cambio posterior de A desde el grupo A al grupo B conservó exactamente los hashes de inventario, visto/loadout y datos deportivos. La prueba completa volvió a pasar después del cambio de equipo.

## Autoridad y seguridad

- Todas las escrituras usan actor autenticado, `operationId`, `expectedRevision`, transacción, secuencia de servidor y snapshot canónico.
- El navegador no puede confirmar operaciones offline ni escribir directamente inventario/loadout.
- Realtime invalida solo inventario/loadout del perfil y el cliente vuelve a leer el snapshot oficial.
- La carta pública no expone propiedad, NEW, puntos, recibos ni identidad privada.
- Los checksums de `rating`, `base/current/calibrated overall`, facetas, fiabilidad y versión del motor son idénticos antes y después.

El asesor de Supabase marca como `WARN` las RPC `SECURITY DEFINER` públicas. Son la frontera autoritativa intencional y están limitadas a `authenticated`, con actor resuelto en servidor, `search_path` cerrado y pruebas adversarias. También marca el helper booleano usado por la política RLS de la carta pública; revocarlo aisladamente rompería esa política, por lo que permanece accesible y no devuelve datos de ficha. Las advertencias de acceso anónimo proceden de tener Auth anónimo disponible para el rol `authenticated`; las rutas mutables exigen además perfil real y ownership. No se ha debilitado RLS para silenciar el asesor.

El asesor de rendimiento informa de claves foráneas sin índices individuales en loadout/public card y de índices nuevos aún no usados. Son tablas 1:1 o de staging recién creadas; no hay evidencia de regresión ni se añaden índices especulativos en este candidato.

## PWA Bridge

- Preview: política real responde `200` y `Cache-Control: private, no-store, max-age=0, must-revalidate`.
- `minimumSupportedClientVersion`: `2.0.0`.
- Cliente sin versión: escritura bloqueada con `CLIENT_UPDATE_REQUIRED`; las lecturas siguen disponibles.
- Service Worker: `2.0.0+sw.0d48f6fab3a6`.
- `/sw.js`: `no-cache, no-store, must-revalidate`, `Service-Worker-Allowed: /`.
- Supabase, APIs y rutas sensibles están fuera de la caché autoritativa.

## QA de navegador

Preview autenticada:

`https://pachangas-git-codex-playe-fbffe2-persianas-almar-web-s-projects.vercel.app`

El editor cargó el perfil sintético real, dos piezas y revisión 8. Un guardado desde la interfaz incrementó la revisión a 9 y confirmó `Ficha confirmada por el servidor`; la restauración del fondo se confirmó en revisión 10. El deep link de colección mantuvo perfil, revisión y pieza correcta. Consola: 0 errores.

| Vista | Scroll width/client width | Resultado |
| --- | ---: | --- |
| 1440x900 | 1440/1440 | Sin overflow horizontal; editor y carta visibles |
| 390x844 | 390/390 | Sin overflow horizontal; tabs desplazables y acciones accesibles |
| 844x390 | 844/844 | Sin overflow horizontal; modo apaisado compacto |

## Rendimiento y movimiento reducido

Medición real en Chrome sobre la preview de staging, 1440x900, 120 frames por efecto:

| Efecto | FPS | p95 | Máximo observado |
| --- | ---: | ---: | ---: |
| Focos | 120,8 | 10,2 ms | 10,3 ms |
| IQ Scan | 109,8 | 10,1 ms | 91,9 ms, un único outlier de arranque |
| Glint Oro | 120,6 | 10,2 ms | 10,4 ms |

El p95 de los tres permanece alineado con el laboratorio; no existe una regresión sostenida. La misma sesión confirmó `noindex, nofollow` y overflow horizontal 0 en el laboratorio.

Con emulación real de `prefers-reduced-motion: reduce`:

- media query activa: sí;
- `animation-name`: `none`;
- `transform`: `none`;
- `will-change`: `auto`;
- opacidad estática: `0.28`.

## Synthetic World

La regresión canónica conserva:

- 640 jugadores;
- 3.613 cajas;
- 738 concesiones únicas;
- 101 duplicados;
- 262 loadouts;
- 254 combinaciones diferentes;
- máximo loadout repetido: 1,5 %;
- invariantes deportivas/cosméticas fallidas: 0.

No se recalibraron pools, puntos, Rating V2 ni distribución del mundo.

## Checks

- `npm test`: build y 202/202 pruebas, correcto tras el rebase.
- `npm run typecheck`: correcto.
- `npm run test:player-cosmetics`: 6/6, incluido Synthetic World.
- SQL/RLS local: correcto con rollback transaccional.
- Concurrencia local: revisión 4, un ganador, un conflicto, replay idempotente y un recibo.
- E2E staging autenticado: correcto.
- Lint focalizado de Cosmetics y del E2E: correcto.
- Lint global: mantiene la deuda histórica de `app/page.tsx`; no está causada por Cosmetics V1.
- `git diff --check`: correcto.

## Decisión

PR #125 queda técnicamente preparado como `READY FOR RELEASE`, sujeto a la autorización expresa para la secuencia de producción: migración, flag controlado, frontend y smoke autenticado. En esta fase no se fusiona #125, no se despliega su frontend a producción y no se aplica su migración en producción.
