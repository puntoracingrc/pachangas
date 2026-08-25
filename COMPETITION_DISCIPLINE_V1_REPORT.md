# Competition Discipline V1 Report

## Estado

`R5 ACTIVE / PRIVATE BETA / PUBLIC DISCIPLINE OFF`

R5 extiende la autoridad canonica R1-R4D sin crear una segunda identidad de
partido. Los hechos disciplinarios se enlazan con `CanonicalMatch`,
`CompetitionMatchContext`, `RuleRevision`, Entry, roster y ciclos de la Edition.

## Trazabilidad

| Dato | Valor |
| --- | --- |
| Inicio | `2026-08-25` |
| Cierre local | `2026-08-25T20:47:59+02:00` |
| Base inicial | `30ac19ef3091c9668d52c182082cd5263955301d` |
| Rama | `codex/competition-discipline-v1` |
| Rama hotfix V2.1 | `codex/product-demo-parity-wave-3-release` |
| Node | `v24.16.0` |
| npm | `11.13.0` |
| Supabase CLI | `2.107.0` |
| Ledger base | `141` |
| Ledger R5 inicial | `145` (`141 + 4`) |
| Ledger con hotfix V2.1 | `146` (`141 + 5`) |
| Ledger final | `147` (`141 + 6`) |
| Main productivo R5 final | `0401a127ebd910ccad799b466ad3327782067b37` |

## Migraciones forward-only

1. `20260825165834_competition_discipline_schema_v1.sql`
2. `20260825165838_competition_discipline_commands_v1.sql`
3. `20260825165843_competition_discipline_access_v1.sql`
4. `20260825165849_competition_discipline_hardening_v1.sql`
5. `20260825203500_competition_discipline_appeal_service_accounting_v1.sql`
6. `20260825211825_competition_discipline_private_policy_revoke_v1.sql`

Las siete flags nacen en `false`; instalar las migraciones no activa R5 ni crea
datos deportivos. `competition_public_discipline_enabled` permanece separado y
debe continuar OFF durante la beta privada.

## Autoridad canonica

| Dominio | Autoridad | Regla |
| --- | --- | --- |
| Partido | `CanonicalMatch` + `CompetitionMatchContext` | una identidad deportiva |
| Reglamento | catalogo ligado a `RuleRevision` | nunca enviado por navegador |
| Hecho | event + revision inmutable | corregir o anular crea historia |
| Acumulacion | counter materializado reconstruible | incremental = full rebuild |
| Sancion | sanction + revisions + proposal privada | servidor deriva o comite decide |
| Cumplimiento | `SanctionServiceEvent` inmutable | correccion crea reverso |
| Apelacion | appeal + revisions | plazo y efecto desde RuleRevision |
| Elegibilidad | player state + validador R4C | PostgreSQL bloquea squad locked |
| Cliente | intencion semantica | `operationId` + revision esperada |

La RPC `command_pachanga_competition_discipline_v1` resuelve actor, permiso,
Competition, partido, jugador, regla, ciclo, fecha, secuencia, counters,
sanciones, elegibilidad y revision global de disciplina en una transaccion.
Una repeticion valida devuelve el mismo receipt; una intencion concurrente con
revision anterior recibe conflicto.

El hotfix aditivo de V2.1 conserva las unidades ya cumplidas cuando una
apelacion reduce el total. La fila canonica se alinea por trigger con su
revision inmutable vigente; una reduccion de 2 a 1 despues de cumplir 1 termina
en `served / 0`, nunca en una unidad pendiente nueva.

## Catalogo V1

| Tipo | Regla por defecto | Resultado |
| --- | --- | --- |
| Amarilla | `points=1`, threshold `3` por Edition | 1 partido por threshold |
| Segunda amarilla | threshold `2` en el mismo partido | 1 partido |
| Roja directa | rango `1..3`, provisional `1` | decision obligatoria de comite |
| Azul | expulsion temporal `5 min`, termina con gol rival, sin sustitucion | sin sancion acumulada |

Formula de acumulacion:

```text
points = carried_points + sum(active_event.accumulationPoints)
threshold_hits = floor(points / threshold)
```

El ciclo por defecto es la Edition con `RESET`. Los partidos aplazados,
cancelados o bye no consumen sancion. Una apelacion usa el plazo de la
RuleRevision (72 horas en el catalogo inicial) y no suspende automaticamente.

## Entidades

- catalogos y ciclos disciplinarios;
- eventos y revisiones append-only;
- counters con checksum;
- sanciones, revisiones y propuestas de comite;
- eventos de cumplimiento y reversos;
- apelaciones y revisiones;
- estado materializado del jugador;
- evidencia privada;
- revision monotona de disciplina por Competition.

La revision global evita que dos acciones sobre agregados distintos de la
misma Competition se acepten silenciosamente desde el mismo snapshot.

## Seguridad y privacidad

- RLS activada en todas las tablas publicas R5.
- `anon` y `authenticated` tienen 0 `INSERT`, 0 `UPDATE` y 0 `DELETE` directos.
- El helper privado de politica no concede `EXECUTE` a `PUBLIC`, `anon` ni
  `authenticated`; los clientes tampoco tienen `USAGE` del esquema privado.
- evidencia, notas privadas, identidad de comite y documentos quedan cerrados.
- actor exclusivamente desde `auth.uid()`.
- APIs `no-store`, same-origin, payloads por lista blanca y sin service role.
- el read model publico se construye por allowlist y no devuelve proposals,
  appeals, evidencia, motivos privados, deliberacion ni capacidad de apelar.
- `canAppeal` y `canWithdraw` se calculan en PostgreSQL para el usuario real.

## RBAC

R5 incorpora capacidades acotadas:

- `competition_discipline_manage`;
- `competition_discipline_review`;
- `competition_appeals_manage`.

El bundle `LEAGUE_PRIVATE_BETA_V1` nuevo incluye las tres. Los bundles activos
anteriores requieren la RPC explicita e idempotente de upgrade antes de activar
R5; la activacion falla cerrada si el upgrade no se ha realizado.

## Producto

Superficies nuevas:

- `/competiciones/[competition]/gestion/disciplina`;
- `/competiciones/[competition]/partidos/[match]/disciplina`;
- `/competiciones/[competition]/jugadores/[player]/disciplina`;
- `/competiciones/[competition]/disciplina` (publica y flag-gated).

El Match Hub R4C incorpora `Disciplina`. La UI permite registrar, corregir y
anular hechos; resolver propuestas; registrar/revertir cumplimiento; apelar,
admitir, inadmitir, revisar, confirmar, modificar, revocar o retirar; consultar
counters, health y elegibilidad. El perfil muestra `No disponible por sancion`
sin mezclarlo con la carta universal.

## Realtime, cache y PWA

Realtime transporta invalidaciones acotadas. Al entrar en `SUBSCRIBED`, al
reconectar y tras cada mutacion se relee el snapshot canonico; el WAL nunca es
autoridad. `localStorage` conserva solo read models con TTL.

Offline permite leer la ultima copia confirmada. Nunca confirma tarjeta,
correccion, sancion, apelacion o cumplimiento, y no existe cola deportiva.

## Notificaciones

Las notificaciones usan claves de deduplicacion por operacion y destinatario:

- evento registrado/corregido/anulado;
- sancion provisional o confirmada;
- unidad de sancion pendiente;
- sancion cumplida o cumplimiento corregido;
- apelacion recibida por organizacion;
- apelacion actualizada o resuelta para el jugador.

Repetir la misma operacion no crea un segundo evento ni una segunda
notificacion.

## Validacion local

| Gate | Resultado |
| --- | --- |
| R5 focal | `15/15 PASS` |
| Bateria completa | `508/508 PASS` (`20 Node + 488 TSX`) |
| SQL/RLS/adversarial | `PASS` |
| Fresh install reproducible | `141 + 6 / PASS` en PostgreSQL temporal |
| Flags y datos al instalar | `OFF / 0 filas de producto` |
| Idempotencia | mismo receipt, secuencia y efectos |
| Concurrencia | 7 carreras deterministas |
| Escala | `10.000` eventos, `2.000` sanciones, `5.000` servicios, `1.000` apelaciones |
| Rollback de escala | `PASS` |
| Typecheck | `PASS` |
| Build | `PASS` |
| Lint focalizado | `PASS` |
| Lint global | deuda previa: `22 errores / 18 warnings` |
| `git diff --check` | `PASS` |

Resultados de concurrencia:

| Carrera | Resultado |
| --- | --- |
| dos tarjetas | `1 winner / 1 stale` |
| tarjeta vs correccion | `1 winner / 1 stale` |
| rebuild vs evento | `1 winner / 1 stale` |
| dos decisiones | `1 winner / 1 stale` |
| apelacion vs servicio | `1 winner / 1 stale` |
| servicio vs correccion | `1 winner / 1 stale` |
| lineup vs activacion | `1 winner / 1 conflict` |

Escala local:

| Medida | Resultado |
| --- | ---: |
| Duracion total | `1.918 s` |
| Indices R5 | `7,348,224 bytes` |
| Lookup de evento | `1.099 ms` |

## Historias cubiertas

- amarilla simple y acumulacion por debajo del threshold;
- threshold y sancion de un partido;
- bloqueo de la siguiente alineacion;
- cumplimiento, reverso y nuevo cumplimiento inmutables;
- roja provisional y decision de comite;
- correccion que reconcilia la sancion;
- apelacion confirmada;
- apelacion que modifica unidades;
- retirada de apelacion;
- azul temporal desde RuleRevision;
- plazo vencido, actor ajeno, permiso insuficiente, partido inexistente,
  tipo/minuto invalido, payload autoritativo falsificado y direct write.

## Incidencias permanentes

| ID | Clasificacion | Hallazgo | Correccion | Estado |
| --- | --- | --- | --- | --- |
| R5-001 | PRODUCT_BUG | Revisiones por entidad permitian dos ganadores sobre una Competition | `discipline_revision` global y stale obligatorio | fixed + regression_verified |
| R5-002 | PRODUCT_BUG | Activar sancion podia competir con bloquear una alineacion | guard transaccional sobre squads futuros locked | fixed + regression_verified |
| R5-003 | PRODUCT_BUG | El indice de servicio impedia volver a cumplir tras un reverso auditado | unicidad solo del reverso; servicio conserva historia | fixed + regression_verified |
| R5-004 | PRODUCT_BUG | Segunda amarilla podia derivar de eventos posteriores, no del threshold exacto | comparacion por igualdad del threshold | fixed + regression_verified |
| R5-005 | PRODUCT_BUG | El validador de squad podia omitir una plantilla sin MatchSheet | validacion directa del squad en todo cierre | fixed + regression_verified |
| R5-006 | PRODUCT_BUG | Upgrade beta exigia una capability inexistente y tenia `bundle_id` ambiguo | capabilities canonicas y conflicto PL/pgSQL explicito | fixed + regression_verified |
| R5-007 | SECURITY_BUG | Reutilizar el snapshot privado podia exponer proposal/deliberacion publica | proyeccion publica por allowlist ejecutada como `anon` | fixed + regression_verified |
| R5-008 | SECURITY_BUG | La UI no tenia prueba de propiedad individual para apelar/retirar | flags por usuario calculadas en servidor | fixed + regression_verified |
| R5-009 | TESTABILITY_GAP | Solo se cubria apelacion confirmada | regresiones `modified`, `withdrawn` e inadmissible en UI | fixed + regression_verified |
| R5-010 | SIMULATION_BUG | El rol `anon` no podia guardar el resultado en la tabla temporal del test | grant temporal exclusivo al arnes y revocacion inmediata | fixed + regression_verified |
| R5-011 | PRODUCT_BUG | El formulario sincronizaba selects con setState dentro de effects | inicializacion por montaje y fallback derivado | fixed + regression_verified |
| R5-012 | PRODUCT_BUG | Reducir por apelacion una sancion parcialmente cumplida podia volver a exigir una unidad ya servida | preservar servicio neto en la revision y alinear la fila canonica | fixed + regression_verified |

## Invariantes

Los digests antes/despues son identicos para:

- Rating V2 y assessments;
- rewards;
- Player Cosmetics;
- Team Cosmetics;
- Conduct;
- Billing;
- Ranking / Season Score.

R5 no modifica standings por tarjetas, no activa puntos disciplinarios, no
crea Referee Assignments, no activa pagos y no implementa Tournament Engine.

## Gate de publicacion

Las seis migraciones R5 estan publicadas y el ledger remoto contiene `147`
versiones. La beta privada sigue activa con disciplina publica OFF. Los dos
hotfixes forward-only descubiertos durante Demo World V2.1 y el readback final
fueron aplicados con backup previo, privilegios verificados, regresiones reales
y smoke transaccional con rollback; la evidencia exacta se registra en
`COMPETITION_DISCIPLINE_V1_PRODUCTION_RELEASE.md`.
