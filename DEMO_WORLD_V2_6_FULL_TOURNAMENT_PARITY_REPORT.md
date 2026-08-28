# Demo World V2.6 Full Tournament Parity

## Snapshot

- Nombre: `Demo World V2.6 - Full Tournament Parity`.
- Torneo: `COPA BARRIOS IQ 2027`.
- Seed: `pachangas-iq-demo-world-v2-6-2026-27`.
- Manifest hash: `3b770ddde8a3d3599581e963f836b28e00d9ce8496d9127facdaa091f3aa68d9`.
- Authority hash: `da9aac991d30eb0dcfe3b7934122385bddbdcffa10fc316cc25c1a044addf8f9`.
- Ledger de simulación: 176.
- Remote writes: 0.

V2.1, V2.2, V2.3, V2.4 y V2.5 permanecen inmutables en directorios
versionados. V2.6 actualiza únicamente `public/demo-world/v2` y su proof.

## Historia canónica

La simulación PostgreSQL ejecuta motores reales y publica un snapshot reducido:

- 4 cuartos;
- 2 semifinales;
- 1 final;
- 1 tercer puesto;
- 1 resultado normal;
- 1 prórroga;
- 1 tanda de penaltis;
- 1 no-show administrativo;
- 1 reemplazo arbitral en semifinal;
- 1 sanción R5 aplicada sin tocar Rating;
- 1 árbitro confirmado en final;
- 1 corrección de cuarto antes de la semifinal;
- 1 match semifinal retirado y replacement vigente;
- campeón, subcampeón y tercer puesto.

Prueba de lineage: 8 matches activos, 9 históricos y 1 predecesor retirado.
Los contadores R3 y los 24 partidos de grupos V2.5 permanecen separados de la
nueva evidencia knockout.

## Integridad

- 8 clasificados correctos.
- 8 nodes eliminatorios actuales, sin duplicados.
- Penaltis separados de GF y goleadores.
- R4D, R5 y Referee Assignments enlazados.
- Estadísticas de árbitros convergentes tras reemplazo.
- Rating, Rewards, Conduct y Billing intactos.
- Reward grants: 0.
- Datos públicos sin PII, service role, evidencia privada ni rutas de escritura.

## UI

Demo añade la pestaña `Cuadro` como vista predeterminada del Torneo:

- cuadro completo por rondas;
- ET, penaltis y no-show visibles;
- campeón y subcampeón;
- selector de Team Journey;
- podio, árbitros, disciplina e integridad;
- corrección visible como estado saneado, con proof histórico separado.

QA visual confirmada en 1440x900, 1920x1080, 390x844, 360x800, 667x375,
740x360, 844x390 y 932x430: 0 overflow raíz, 0 imágenes rotas, 0 navegación
solapada, active tab visible y 0 errores de consola/hidratación.

Se corrigieron dos regresiones descubiertas durante QA: active tab cortada tras
rotación y solapamiento del primer intento sticky. Ambas están registradas y
regression_verified en `R6C_TOURNAMENT_KNOCKOUT_INCIDENTS.md`.

## PWA

- Manifest presente.
- `/sw.js` controla el build productivo `41c8280b55bd`.
- Cache versionada `pachangas-iq-pwa-2.0.0-sw.41c8280b55bd`.
- Chunk de torneo lazy cacheado tras primera visita.
- Reload offline conserva `COPA BARRIOS IQ 2027` y `Cuadro`.
- Reconexión conserva el snapshot y no genera errores.
- Ninguna operación deportiva offline se presenta como confirmada.

## Tests

- `demo-world:v2:simulate`: PASS.
- `demo-world:v2:verify`: `snapshotIdentical = true`.
- `test:demo-world:v2`: 15/15 PASS.
- Proof y snapshot usan el mismo authority hash.
- La batería global completa pasa 572/572.

## Paridad remota en staging

- El fixture canónico se ejecutó sobre un full-clone privado con ledger 175;
  después se regeneró de forma determinista y se publicó con provenance 176.
- Resultado: 8 nodes vigentes, 8 matches activos, 9 históricos, 1 retirado,
  campeón único y tercer puesto resuelto.
- Dos clientes autenticados recibieron el evento de invalidación y recargaron
  el mismo read model canónico; la escritura directa del cliente fue denegada.
- Rating, Rewards, Conduct y Billing mantuvieron sus digests y se concedieron
  cero rewards.
- Tras la verificación se restauraron flags y grants, y se retiraron usuario,
  membresía, probe y sesiones temporales.

## Estado remoto

- `pachangasiq.com`: LIVE sobre merge `41c8280b55bdabd201da4169fbf524561bc9ee24`.
- Responsive productivo 1440x900, 390x844 y 844x390: 0 overflow raíz/cuerpo,
  0 imágenes rotas y 0 errores o warnings de consola.
- Service Worker: activo, `no-store`, install/activate/fetch, `skipWaiting` y
  `clients.claim`; Demo completa disponible offline y convergente tras reconexión.
- Campeón, ocho partidos y evidencia de corrección visibles en los tres
  viewports.
- Android físico, iPhone físico y PWA instalada física permanecen PENDING y no
  se presentan como PASS.
