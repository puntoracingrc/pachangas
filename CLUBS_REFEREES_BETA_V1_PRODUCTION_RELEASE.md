# Clubs & Referees Beta V1 - Production Release

Fecha de cierre: 2026-08-24 (Europe/Madrid)

## Alcance

Esta release productiza la base autoritativa de Clubs y Arbitros como beta publica, sin activar competiciones de Club ni asignaciones arbitrales. Supabase/PostgreSQL sigue siendo la unica fuente de verdad: el cliente envia intenciones idempotentes con revision esperada, recibe el snapshot canonico y usa Realtime solo para invalidar y volver a leer ese estado.

No se ha iniciado R4C. No se han modificado Rating V2, assessments, facetas, GRL, rewards, Conduct, Player Cosmetics, Team Cosmetics ni billing.

## Checkpoint Git

| Concepto | Valor |
| --- | --- |
| `main` inicial de Productization Wave 1 | `0627fe023a588ee91c0484ecf22bddbbaf4fe2aa` |
| PR funcional | [#175](https://github.com/puntoracingrc/pachangas/pull/175) |
| Merge funcional | `b5328a61fe3bc4e420c8acb3c712a7e46e503051` |
| Hotfix Realtime | [#176](https://github.com/puntoracingrc/pachangas/pull/176) |
| Merge final de aplicacion | `adac3371122bb31cb0ea05bb9a57ef42a77406b1` |
| Produccion funcional | [pachangasiq.com](https://pachangasiq.com) |
| Deployment funcional | `dpl_12Pnqwp3wKcMthxphF5Xuo3mZ7ad` |

## Migraciones

Aplicadas en produccion, en este orden:

1. `20260824101500_clubs_referees_beta_publication_consent_schema_v1.sql`
2. `20260824101501_clubs_referees_beta_authority_v1.sql`
3. `20260824101502_clubs_referees_beta_read_models_notifications_v1.sql`
4. `20260824101503_referee_restore_private_v1.sql`

El repositorio y `supabase_migrations.schema_migrations` contienen exactamente 127 versiones, sin versiones ausentes ni sobrantes. El comando local `supabase migration list --linked` no pudo leer el perfil del CLI (`Unsupported Config Type`); se contrasto la lista completa mediante la API enlazada de Supabase y lectura remota, con coincidencia exacta 127/127. No hubo reescritura de migraciones ejecutadas ni backfill canonico.

## Activacion

Estado confirmado tras la QA:

| Capacidad | Estado |
| --- | --- |
| Club foundation | ON |
| Club self-service creation | ON |
| Club-Team relationships | ON |
| Club public profiles/directory | ON |
| Club competition organizer | OFF |
| Referee foundation/self-service | ON |
| Referee public profiles/marketplace | ON |
| Club-Referee relationships | ON |
| Referee assignments | OFF |
| R1 Competition Foundation | OFF |
| R4A Participation/Rosters | OFF |
| R4B Scheduling/Fixtures | OFF |

Revisiones de flags: Club `4`, Arbitros `4`, R1/R4A/R4B `1`.

## Producto Entregado

- Creacion y edicion privada de Club, consentimiento explicito, envio a revision, aprobacion de plataforma y publicacion.
- Directorio publico de Clubs con filtros, paginacion y perfiles SEO de campos publicos seguros.
- Staff, invitaciones y relaciones Club-Team. Solo el owner del equipo puede aceptar; un admin de equipo recibe `TEAM_OWNER_REQUIRED`.
- Varios Clubs pueden relacionarse con un equipo sin convertir al Club en autoridad de competicion.
- Ficha arbitral propia con modalidades, zonas, disponibilidad, visibilidad, consentimiento y marketplace.
- Perfil publico de arbitro sin telefono, email, GRL, facetas, estrellas ni ranking. La disciplina permanece `NOT_AVAILABLE`.
- Relaciones Club-Arbitro idempotentes, moderacion/verificacion de plataforma y lectura canonica.
- CTA de Clubs y Arbitros dentro de Mercado, sin crear una navegacion primaria adicional.
- Texto beta exacto y acciones de publicacion protegidas por consentimiento.
- Asignaciones y organizacion competitiva permanecen ocultas/bloqueadas por flags.

## Autoridad, Privacidad y Realtime

- Todas las escrituras productivas pasan por RPC/API central con actor autenticado, `operationId`, revision esperada, fecha/secuencia del servidor y recibo canonico.
- Repetir la misma operacion devuelve el mismo `serverSequence`; una revision obsoleta devuelve `STALE_REVISION`.
- Los read models publicos solo exponen campos autorizados. Las tablas normalizadas no se conceden como segunda fuente de verdad al navegador.
- Realtime emite invalidaciones; escritorio y movil vuelven a leer el snapshot canonico. El hotfix #176 anade reconciliacion tras `SUBSCRIBED` y tras cada invalidacion para cerrar la carrera de suscripcion/reconexion.
- La QA inicial con la clave anon legacy no recibia ambos canales. La clave publica moderna usada por el producto confirmo invalidaciones de Club y arbitro en los dos dispositivos. No se cambio la autoridad ni se anadio estado optimista.
- Una PWA offline no confirma operaciones deportivas ni mantiene una cola de escrituras.

## Validacion

| Gate | Resultado |
| --- | --- |
| `npm test` | PASS, 408/408 |
| Typecheck | PASS |
| Build | PASS, 44/44 rutas |
| Lint focalizado | PASS |
| Lint global | Deuda heredada: 22 errores y 18 warnings, sin regresion Wave 1 |
| SQL/RLS | PASS |
| Idempotencia | PASS |
| Revision obsoleta | PASS |
| Concurrencia de dos clientes | PASS |
| Realtime + refetch canonico | PASS para Club y arbitro |
| `git diff --check` | PASS |

La QA autenticada de produccion cubrio: creacion, replay idempotente, dos clientes, Realtime, stale revision, consentimiento, revision/aprobacion, owner frente a admin, publicacion, busqueda de mercado, relacion Club-Team, relacion Club-Arbitro, privacidad publica y bloqueos de assignments/competition.

## QA Visual y PWA

- Desktop `1440x900`, portrait `390x844` y landscape `844x390`: sin overflow horizontal, controles cortados, imagenes rotas ni errores de consola.
- Rutas comprobadas: `/clubes`, Club publico, Arbitro publico, `/mercado?tab=arbitros`, `/clubes/gestionar` y `/perfil/arbitro`.
- En landscape, los filtros largos usan scroll interno sin romper el lienzo del modo juego.
- Manifest productivo: `display: fullscreen`, fallbacks `standalone/minimal-ui/browser`, cinco iconos validos y `scope: /`.
- `sw.js`: `200`, `no-store`, `Service-Worker-Allowed: /`, actualizacion con `SKIP_WAITING` y sin Background Sync deportivo.
- `/api/client-policy`: `no-store`; V1 sin version queda bloqueado para escritura y `2.0.0+metadata` queda autorizado.
- No se afirma QA fisica instalada en Android/iPhone: este cierre valida navegador responsive y contrato PWA productivo, no hardware real.

## Observabilidad

Vercel no registro errores `error/fatal` de esta release. Los unicos `5xx` observados son los `503` heredados de `/api/internal/rankings/refresh`, ajenos a Clubs/Arbitros y ya existentes antes de Wave 1.

Los avisos de Supabase Advisor son deuda conocida o advertencias heuristicas: tablas sin policies porque no tienen grants directos, y RPC `SECURITY DEFINER` publicas/autenticadas que validan permisos internamente. Las pruebas SQL/RLS intentan accesos directos y por actor. Referencia del linter: [Supabase Database Linter](https://supabase.com/docs/guides/database/database-linter).

## Limpieza

Los datos efimeros de QA quedaron retirados: `0` Clubs activos de prueba, `0` arbitros listados de prueba, `0` grupos QA y `0` relaciones activas. Las cuatro cuentas temporales fueron bloqueadas y el rol temporal de plataforma se revoco de forma auditable (`active=false`, revision `2`). Los flags conservaron sus revisiones y valores.

## Deuda y Rollback

- `Profile Reports` no existe aun como flujo de producto. No se fabrico dentro de esta release.
- El contacto legal de soporte permanece como `Pendiente de completar`; requiere una decision de negocio.
- La QA fisica instalada en Android/iPhone queda pendiente y no bloquea la publicacion web autorizada.
- Rollback preferente: poner primero los flags de Club/Arbitros en OFF y verificar lectura; despues revertir el deployment si fuera necesario. Las migraciones son aditivas y no deben deshacerse borrando evidencia.
- No reactivar escrituras antiguas, no convertir caches/payloads en fuente de verdad y no activar assignments, R1, R4A o R4B durante un rollback.

## Cierre

Clubs y Arbitros Beta V1 quedan disponibles en produccion bajo autoridad central, con superficies publicas seguras, consentimiento, moderacion, invalidacion Realtime y refetch canonico. R4C no se ha iniciado.
