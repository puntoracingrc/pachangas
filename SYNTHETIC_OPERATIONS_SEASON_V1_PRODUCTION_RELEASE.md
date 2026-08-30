# Synthetic Operations Season V1 Production Release

Estado: `RELEASED`

| Campo | Valor |
| --- | --- |
| fecha | `2026-08-30` |
| main inicial | `131b0005d9f13d19db23372ff357dca4b2d0cdb2` |
| PR funcional | `#230` / fusionado |
| commit funcional final | `56724896890c6b586576a2cdbb745c90eb109657` |
| main de release | `3ac642855e79eb283b2bd32e77256a09fe2329a0` |
| migraciones nuevas | 0 |
| ledger remoto | 212 local/remoto, 0 diferencias |
| deployment productivo | `dpl_HynEEjgPs69fd1X63rwsmFPaipPT` / READY |
| dominio | `https://pachangasiq.com` |
| canary con ROLLBACK | PASS |
| readback final a cero | PASS, 12/12 familias |
| Service Worker | PASS, activo y controlador |
| Stripe tocado | NO |
| Wave 8D | NO INICIADA |

## Entrega funcional

Wave 8C publica Demo World V3.2 como snapshot saneado GET-only de una temporada
sintetica determinista de 16 semanas: 6 Clubs, 32 Teams, 480 jugadores, 12
arbitros, 8 organizadores, 2 Ligas, 2 Torneos, 128 partidos y 9 checkpoints. La
conformidad usa las RPC productivas reales en PostgreSQL aislado; el mundo
publico no contiene Auth IDs, PII, secretos, Stripe ni escritura remota.

Hashes finales:

- input: `1640e475d3e079f07225abdbbf9ede1fa1128358b63f1a560fd67eac43b2a4c5`;
- autoridad: `763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1`;
- snapshot publico: `48b9bb09baa2e536708ec7c13109a716f81b128ba838a1ba29412d22b252358b`;
- manifest: `9b3b503869f77b66a00f0e721e884616a026cf6a27edbb5e74f78d2057be85e7`.

## Gates

| Gate | Resultado |
| --- | --- |
| `npm ci` | PASS; 525/526 paquetes |
| `npm test` | PASS; Node 20/20, TS/TSX 650/650, total 670/670 |
| fail/cancelled/skipped/todo | 0/0/0/0 |
| `npm run typecheck` | PASS |
| `npm run build` | PASS; Next.js 16.3.3, 62 paginas estaticas |
| build standalone | PASS |
| lint focalizado | PASS |
| lint global | 40 problemas preexistentes: 22 errores y 18 avisos |
| `git diff --check` | PASS |
| secret scan | PASS |
| `npm audit --omit=dev` | PASS; 0 vulnerabilidades runtime |
| audit completo | 18 hallazgos dev-only preexistentes |
| test focal sintetico | 20/20 PASS |
| matriz local/Preview | 128/128 PASS |

`W8C-025` permanece abierto como deuda preexistente no bloqueante: no afecta
rutas Wave 8C y corregirlo ampliaria el alcance. El resto de incidencias
W8C-001..W8C-103 esta cerrado como `fixed + regression_verified`.

## Staging y Realtime

El branch efimero ejecuto una temporada reducida con ledger 212, identidades
`.test` y cero datos clonados: 3 Clubs, 12 Teams, 120 jugadores, 6 arbitros, una
Liga y un Torneo. Produjo 50 CanonicalMatches activos, 30 decisiones de Liga, 12
partidos Group Stage, 8 Knockout, un predecessor retirado, un campeon y dos
completion snapshots. Las 14 capabilities Private Beta pasaron y no hubo
destinatarios no sinteticos, email, push ni Stripe.

Dos dispositivos autenticados convergieron a revision 14 mediante Realtime y
refetch canonico. La perdida parcial de una senal recreo ambos canales al volver
a `SUBSCRIBED`; una sola intencion produjo un winner y un stale, y el replay fue
idempotente. Ningun payload WAL se uso como estado autoritativo.

El branch `wave8c-synthetic-season-final8-f393244` fue eliminado. El inventario
posterior conserva solo el branch principal y el project ref efimero devuelve
`Project not found`.

## Preview y PWA

La matriz de alto valor se ejecuto sobre el deployment Preview exacto
`dpl_CDWyT3UoSACJqn8Sc9ceHUGtREZ2`: 16 superficies por 8 viewports, 128/128
PASS. La PWA standalone 390x844 cargo manifest, Service Worker, manifest V3.2,
season y checkpoint 8, con 23 recursos V3.2 y recarga offline de Postemporada y
Cuadros.

La Preview exacta final del commit funcional fue
`dpl_6v1uqTbF1oQu3rxPtWaRXG3MigKE`, `READY`, y su smoke focal devolvio PASS para
Demo, manifest, checkpoint, webmanifest y Service Worker.

Tras el gate se retiraron:

- los seis deployments Preview exclusivos de la rama;
- los dos overrides Preview `NEXT_PUBLIC_SUPABASE_URL` y
  `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`;
- las cookies HttpOnly temporales de bypass;
- `.env.local`, `.vercel` y `supabase/.temp` locales.

Production no recibio esas variables y nunca existio una clave service role en
la Preview o el bundle.

## Produccion

Vercel desplego el SHA exacto de `main`
`3ac642855e79eb283b2bd32e77256a09fe2329a0` en
`dpl_HynEEjgPs69fd1X63rwsmFPaipPT`. El deployment esta `READY`, target
`production`, y `pachangasiq.com` conserva ese alias.

QA productiva en `/demo?tab=temporada&perspective=admin`:

- desktop 1440x900: PASS;
- portrait 390x844: PASS;
- landscape 844x390: PASS;
- checkpoint 8 y Cuadros: PASS;
- overflow, controles cortados e imagenes rotas: 0;
- errores y avisos de consola: 0;
- PII, secretos y texto invalido: 0;
- Service Worker: soportado, activo, controlador y script `/sw.js`;
- Cache Storage: 23 recursos V3.2.

Android fisico, iPhone fisico y PWA instalada en dispositivo fisico permanecen
`PENDING`; no se presentan como PASS.

## Canary y readback

El canary productivo uso una subtransaccion con rollback forzado. Valido:

- Team `ACTIVE`, revision 1;
- Team `LIMITED`, revision 2;
- Mercado bloqueado para actividad nueva;
- continuidad permitida para una operacion de competicion existente;
- CanonicalMatch revision 2;
- una invalidacion canonica;
- read model `TeamOperationalState` revision 2;
- destinatarios externos 0;
- Stripe events 0;
- rollback confirmado;
- readback a cero en users, Clubs, slugs, Teams, grants, CanonicalMatches,
  resultados, sesiones, estados Team, competiciones, Stripe y notificaciones.

El readback independiente posterior confirma los ocho flags Team Operational en
ON, revision 9. `supabase migration list --linked` devuelve 212 pares exactos,
desde `20260728051437` hasta `20260829221312`, sin drift ni migraciones nuevas.

## Logs e incidencias

Ventana final agregada, sin PII:

- API: 100 entradas, 98 HTTP 200, 2 upgrades 101 y 0 respuestas 5xx;
- PostgreSQL: 99 LOG y un ERROR esperado del primer canary W8C-099, revertido;
- Realtime: 76 entradas y 0 errores.

El canary corregido reprodujo el escenario, paso en staging y produccion y dejo
las doce familias a cero. No quedan incidencias abiertas de autoridad,
seguridad, privacidad, migraciones, coherencia deportiva o cleanup.

## Cierre

Rating V2, Rewards, Conduct, Billing y las autoridades de Liga/Torneo no fueron
reescritas. No se iniciaron Wave 8D, pagos reales, notificaciones reales ni
entidades deportivas reales.

El SQL temporal del canary, cookies, variables Preview, deployments Preview y
branch Supabase fueron retirados. El worktree se conserva solo hasta fusionar
este informe documental; su retirada posterior al merge se confirma en el
mensaje de cierre conforme a `AGENTS.md`.
