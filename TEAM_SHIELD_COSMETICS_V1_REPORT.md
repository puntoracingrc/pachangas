# Team Shield Cosmetics V1

Estado: RELEASE CANDIDATE. STAGING SUPERADO; PREVIEW PENDIENTE.

## Checkpoint

- Main de partida: `c92eb1c65bdd61b1124e7a2d836563350dad7bea`.
- Rama: `codex/team-shield-cosmetics-v1`.
- PR borrador: `#130`.
- Produccion modificada: NO.
- `player_cosmetics_enabled`: no se modifica.
- `team_cosmetics_enabled`: `false` por defecto.
- `team_cosmetic_rewards_enabled`: `false` por defecto.

## Decision De Producto

El renderer y editor de escudos anterior se consideran legacy descartable. V1
no conserva su apariencia, no traduce configuraciones antiguas y no concede
propiedad historica. Se conservan sin alteracion el equipo, su ID, owner,
admins, miembros y todos los datos deportivos.

La unica arquitectura visual nueva es:

`TeamShieldView + TeamShieldConfig + team loadout + Shared Cosmetics Editor`.

## Auditoria De Superficies

| Superficie | Estado V1 |
| --- | --- |
| `/equipo/identidad` | Renderer y editor anteriores sustituidos por `TeamShieldView` y el editor compartido. |
| Historial de identidad | Usa `TeamShieldView` sobre versiones inmutables. |
| `/laboratorio-cosmeticos-escudo` | Usa el mismo renderer y editor, sin adaptador legacy. |
| Retos | No dibuja escudo actualmente; no se introduce geometria duplicada. |
| Mercado | No dibuja escudo actualmente; queda preparado el read model publico. |
| Partidos | No dibuja escudo actualmente; fuera del refactor incremental. |
| Rankings/TOPS | No dibuja escudo actualmente; no se fuerza un cambio ajeno. |
| Invitaciones/notificaciones | Texto y deep links; no existe otro renderer visual. |

## Contrato Visual

`TeamShieldConfig` V1 controla exactamente:

- shape, background y pattern;
- primary/secondary symbol;
- border;
- top, side y bottom ornament;
- primary/secondary color;
- initials y foundation year;
- un unico effect;
- escala `0.8..1.2` y rotacion `-12..12` del simbolo principal.

La base gratuita contiene 28 valores: 8 formas originales, 6 colores, 3
fondos, 4 patrones, 5 simbolos y 2 bordes. El default `Base IQ` siempre es
valido y no depende de ningun premio.

## Autoridad De Servidor

Las migraciones forward-only, con las mismas versiones en repositorio y
staging, son:

- `20260810151241_team_shield_cosmetics_v1.sql`: modelo y RPCs V1.
- `20260810152852_team_shield_registered_user_hardening.sql`: cierre explicito
  de sesiones anonimas en RPCs y RLS.
- `20260810153058_team_shield_cosmetic_fk_indexes.sql`: indices inversos para
  las nuevas claves foraneas.

Modelo:

- `pachanga_team_cosmetic_inventory`: propiedad por `group_id`.
- `pachanga_team_shield_state`: revision monotona y secuencia del servidor.
- `pachanga_team_shield_loadouts`: configuracion canonica actual.
- `pachanga_team_shield_versions`: historial inmutable.
- `pachanga_team_shield_public`: read model publico sin inventario.
- `pachanga_team_cosmetic_admin_eligibility`: fecha efectiva por admin.
- `pachanga_team_cosmetic_seen`: estado NEW individual por admin.
- `pachanga_team_shield_events`: auditoria ordenada.
- `pachanga_team_shield_operation_receipts`: idempotencia.

RPCs:

- `get_pachanga_team_shield_snapshot_v1`.
- `get_pachanga_team_public_shield_v1`.
- `save_pachanga_team_shield_loadout_v1`.
- `mark_pachanga_team_cosmetics_seen_v1`.
- `grant_pachanga_team_cosmetic_v1`, solo `service_role`.

Guardar y marcar visto requieren usuario registrado, `operationId` y revision
esperada. Un conflicto devuelve `PT409`; repetir la misma operacion devuelve el
mismo recibo. Las escrituras legacy de draft/publicacion quedan revocadas para
clientes.

## Ownership Y NEW

- OWNED y EQUIPPED pertenecen al equipo.
- SEEN pertenece a cada administrador.
- Owner/admin pueden editar; miembro normal solo recibe el escudo publico.
- Un admin nuevo inicia elegibilidad en su fecha efectiva: piezas anteriores no
  aparecen como NEW; piezas posteriores si.
- Cambiar owner, retirar un admin o renombrar el equipo no mueve inventario ni
  loadout.
- Un grant duplicado devuelve already-owned, no crea moneda ni otra fila.

## Seguridad Y Sincronizacion

- RLS impide al miembro normal leer inventario, seen, recibos o fuentes de
  unlock.
- Las sesiones anonimas de Supabase quedan rechazadas aunque usen internamente
  el rol PostgreSQL `authenticated`.
- El read model publico solo contiene la configuracion equipada y revision.
- Realtime invalida state, loadout, public, inventory y seen; el cliente hace
  refetch canonico.
- Preview y borrador son locales; guardar offline nunca aparece confirmado y no
  existe cola offline autoritativa.
- Las dos nuevas escrituras estan clasificadas por el PWA bridge.
- El cache local contiene un snapshot derivado y nunca compite con PostgreSQL.

## Evidencia Local

- Bootstrap vacio: baseline + 84 migraciones, estado `BOOTSTRAP_COMPLETE`.
- SQL/RLS adversarial: PASS sobre base reconstruida.
- Concurrencia: un ganador, un `PT409`, revision 1 y un unico recibo.
- Synthetic World: 50 equipos, 50 duplicados, 50 conflictos stale, 50 admins
  tardios sin NEW historico, 0 cambio de Rating.
- Typecheck: PASS.
- Build Next.js, 30 rutas: PASS.
- Lint focalizado: PASS.
- Lint global: 43 incidencias preexistentes (23 errores y 20 avisos) fuera del
  alcance de escudos, concentradas en `app/page.tsx`, `app/legal-data.tsx`,
  `app/mercado/page.tsx` y `app/theme-toggle.tsx`.
- Regresion cruzada: 107/107 PASS (Rating V2, Player Cosmetics, logros, PWA,
  notificaciones, Core Social, TOPS y conducta).
- Browser QA: 1440x900, 390x844 y 844x390 sin overflow de documento.
- Reduced motion: `animation: none`, transform none, estado estatico visible.
- Consola del laboratorio: 0 warnings y 0 errores.

El bootstrap vacio se arranca en modo database-only. El `config.toml` expone el
esquema de laboratorio `simulation`, que deliberadamente no existe en una base
de producto limpia y haria fallar la salud de PostgREST antes del baseline.

## Evidencia Staging

- Rama Supabase: `pwa-bridge-staging` (`iozcjirlfytryzrcmrnq`).
- Historial remoto alineado con las tres versiones anteriores.
- Feature flags: `team_cosmetics_enabled=true` y
  `team_cosmetic_rewards_enabled=false`, exclusivamente en staging.
- Seis identidades QA: owner, dos admins, admin tardio, miembro y outsider.
- E2E Auth/RPC/RLS/Realtime: PASS.
- NEW individual, promocion tardia, retirada de admin y transferencia de owner:
  PASS.
- Carrera owner/admin: un ganador, un conflicto `PT409` y snapshot canonico
  convergente: PASS.
- El primer intento Realtime encontro el arranque en frio ya observado en esta
  rama; la escritura quedo confirmada y las dos repeticiones completas
  posteriores recibieron el evento y convergieron.
- Payload deportivo antes/despues: identico; Rating V2 no modificado.
- Advisors: cero claves foraneas nuevas sin indice. Los diez indices nuevos
  figuran como `INFO unused_index`, normal con el volumen minimo del fixture.
- Los avisos `SECURITY DEFINER` son intencionados para las RPC autoritativas.
  La heuristica de anonymous-auth persiste por el rol, pero SQL/RLS verifica el
  rechazo real mediante `is_registered_pachanga_user()`.

## Invariantes Deportivas

La migracion no escribe perfiles, Rating V2, facetas, Season Score, TOPS,
partidos, retos, logros ni evidencias deportivas. Synthetic World y la bateria
cruzada confirman `ratingChanges: 0`.

## Pendiente Remoto

- Publicar y verificar una Vercel Preview exacta del commit final.
- Mantener ambos feature flags desactivados por defecto fuera de staging.

No se autoriza merge ni despliegue a produccion en esta fase.
