# R4B Large Schedule Execution - Release Reconciliation

Fecha de reconciliacion: 2026-09-04.

## 1. SHA base

- Repositorio: `puntoracingrc/pachangas`.
- Base real: `origin/main` en
  `39ed4af736b1174625de45e69c4aafd41b2d936e`.
- Rama continuada: `codex/r4b-interactive-schedule-limit-20`.
- La rama no se ha reescrito y el `main` remoto no ha avanzado.

## 2. Commit bloqueado

El commit `daa46c46c7f3c7fdf68208b2d641b20e45126c1f` conserva la auditoria que
clasifico correctamente la ejecucion anterior como
`BLOCKED_BY_RELEASE_STATE_OR_DATA_DIVERGENCE`. No se modifica ni se oculta esa
conclusion historica.

## 3. Comentario previo de #173

El comentario de bloqueo permanece en:

https://github.com/puntoracingrc/pachangas/issues/173#issuecomment-5541669888

El issue `#173` sigue abierto durante esta reconciliacion.

## 4. Cronologia

1. R4B se incorporo el 23 de agosto de 2026 mediante sus cuatro migraciones de
   scheduling y el PR historico `#172`.
2. El issue `#173` se abrio el 24 de agosto de 2026 para decidir el tratamiento
   de calendarios grandes y su generacion sincrona.
3. League Private Beta V1 se activo canonicamente el 25 de agosto de 2026 y
   habilito deliberadamente R4B con acceso privado, invite-only y por grant.
4. `#165` Rating V2 cerro el 3 de septiembre de 2026.
5. `#166` Google Places cerro el 4 de septiembre de 2026.
6. `#170` Ranking `CRON_SECRET` cerro el 4 de septiembre de 2026.
7. La primera auditoria de `#173` reprodujo el defecto, pero se detuvo porque su
   precondicion exigia seis flags R4B en `OFF`, incompatible con la Private Beta
   posterior.
8. Esta orden sustituye exclusivamente esa precondicion y autoriza conservar el
   vector privado vigente mientras se implementa Option A.

## 5. Por que la condicion OFF quedo superada

La condicion `R4B completamente OFF` describia un estado anterior a League
Private Beta V1. La activacion posterior fue realizada por la autoridad de
plataforma y registrada mediante el evento canonico
`league_scheduling_flags.set`, revision de settings 21 y secuencia 2614, con el
motivo `League Private Beta V1 production phase 5`. No fue deriva manual ni un
accidente de configuracion.

El criterio vigente es preservar exactamente ese vector. No se amplia ni se
reduce acceso durante `#173`.

## 6. Vector de flags productivo vigente

Readback directo de PostgreSQL productivo el 4 de septiembre de 2026:

| Flag | Estado autorizado |
| --- | --- |
| `league_scheduling_foundation_enabled` | `ON` |
| `league_schedule_generation_enabled` | `ON` |
| `league_schedule_editing_enabled` | `ON` |
| `league_schedule_publication_enabled` | `ON` |
| `league_public_calendar_enabled` | `OFF` |
| `league_canonical_fixture_creation_enabled` | `ON` |

El vector observado coincide exactamente con el autorizado. Esta tarea no lo
modificara.

## 7. Estado de League Private Beta

- `league_private_beta_enabled`: `ON`.
- `league_private_beta_creation_enabled`: `ON`.
- `league_private_beta_public_discovery_enabled`: `OFF`.
- Maximo de ediciones activas por organizador: 1.
- Creacion restringida a entitlement/grant valido.
- Exposicion invite-only y privada.
- Calendario y descubrimiento publicos permanecen desactivados.
- No se activan registro publico, standings publicos, incidencias publicas,
  Referee Assignments, disciplina, pagos ni torneos.

## 8. Capacidad ordinaria 4-12

La capa League Private Beta conserva su capacidad estandar de 4 a 12 equipos.
Esta regla pertenece al acceso comercial/operativo de la beta y no se copia en
la autoridad inferior R4B.

## 9. Override 13-20

League Private Beta conserva el override de plataforma ya existente para
autorizar capacidades de 13 a 20 equipos. El limite R4B de esta tarea admite
esas generaciones porque no superan el maximo interactivo absoluto.

## 10. Rechazo superior a 20 en la beta

La capa beta ya rechaza mas de 20 equipos mediante `BETA_CAPACITY_LIMIT`. Ese
rechazo no basta como defensa de profundidad porque la RPC R4B publica puede
invocarse fuera del wizard. La politica beta no se modifica.

## 11. Defecto restante en R4B

`public.command_pachanga_league_scheduling_v1` acepta actualmente planes con 21
a 32 entradas elegibles y llama al generador sincrono. El workbench expone solo
la capacidad tecnica 32 y la UI no representa el maximo interactivo. Una ruta
que omita o aplique mal la capa beta puede, por tanto, entrar en el camino
costoso.

## 12. Decision Option A

Se implementara `interactiveMaximumTeams = 20` por plan, edicion, fase,
categoria, division o grupo. `schedule.generate` y `schedule.regenerate`
rechazaran 21 a 32 equipos antes del algoritmo, sin revision, jornadas, items,
conflictos, quality, evento, invalidacion, notificacion ni receipt de exito.

No se crea arquitectura asincrona.

## 13. Motor tecnico 32

El motor determinista y el snapshot canonico de inputs conservaran su capacidad
tecnica `engineMaximumTeams = 32`. La prueba interna de 32 equipos debe seguir
produciendo 992 partidos con checksum determinista. La nueva politica limita
solo la operacion interactiva publica.

## 14. Estado productivo de planes y calendarios

Readback agregado actual:

- planes, revisiones, slots, jornadas, BYEs e items R4B: 0;
- validaciones, conflictos y quality snapshots: 0;
- planes o revisiones con mas de 20 equipos: 0;
- contextos y bindings `competition_generated`: 0;
- eventos y receipts de generacion/regeneracion: 0;
- wizards beta activos: 0;
- jobs o colas R4B: 0;
- canonical legacy backfill: `NOT_INITIALIZED`.

Ledger: 236 migraciones; ultima `20260903211715`. Los hashes de las cinco
funciones R4B criticas coinciden con la auditoria bloqueada.

## 15. Compatibilidad con la beta

La solucion sera una defensa inferior independiente:

- la beta mantiene grants, invite-only, cap estandar 12 y override 13-20;
- R4B mantiene actor, capability, revision, entradas canonicas y generacion;
- cualquier llamada user o platform R4B con mas de 20 se rechaza;
- ningun override permite 21-32;
- no cambian flags, grants, bundle ni exposicion publica;
- calendarios historicos mayores de 20, si aparecieran en el futuro por
  importacion o historia previa, seguirian siendo legibles e inmutables.

## 16. Secuencia de release

1. Ejecutar baseline global y focalizado antes de modificar codigo.
2. Crear una migracion forward-only con politica SQL unica, enforcement y read
   model.
3. Adaptar API y UI sin convertir TypeScript en autoridad.
4. Probar fresh bootstrap, upgrade exacto, SQL/RLS, idempotencia, concurrencia,
   historial y rendimiento.
5. Validar en staging Supabase desechable con flags solo del entorno QA.
6. Abrir PR y exigir checks verdes.
7. Fusionar y aplicar una unica migracion productiva sin tocar flags.
8. Desplegar el SHA exacto y hacer smoke de lectura y rechazo seguro.
9. Confirmar ledger, hashes, vector de flags y cero residuos QA.
10. Cerrar `#173` con evidencia.

## 17. Condiciones de rollback

- No se reescribe ni elimina una migracion aplicada.
- Si falla antes de produccion, se retira la rama o el deployment sin tocar
  flags.
- Si falla despues de aplicar SQL, se usa una migracion forward-only revisada
  para corregir funciones o deshabilitar temporalmente solo la accion afectada.
- No se reactiva una ruta interactiva de 32 mediante DML manual.
- No se borra calendario, revision, item, evento ni receipt historico.
- El vector de League Private Beta permanece inalterado durante rollback.

## 18. Criterios para cerrar #173

El issue solo se cerrara cuando se demuestre:

- una unica politica PostgreSQL con maximo interactivo 20;
- mismo recuento canonico en preflight, generacion y workbench;
- user y platform command sin bypass;
- 20 equipos bajo 15 segundos en todas las medidas post-warmup;
- 21 y 32 rechazados bajo 1 segundo y sin estado parcial;
- motor interno 32 intacto con 992 partidos;
- UI y API con error seguro y comprensible;
- fresh bootstrap, upgrade, staging, produccion y deployment exacto verificados;
- vector Private Beta exactamente `ON/ON/ON/ON/OFF/ON`;
- cero datos QA residuales y ninguna ampliacion de acceso.

RELEASE STATE RECONCILIATION: APPROVED

R4B PRIVATE BETA FLAG VECTOR MUST REMAIN UNCHANGED
