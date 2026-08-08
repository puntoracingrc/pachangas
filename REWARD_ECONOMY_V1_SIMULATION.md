# Simulación de economía de recompensas V1

## Alcance

La simulación usa el catálogo conservador V1 y una semilla fija. Modela cajas por goles colectivos, victoria, portería a cero, goleada, victoria ajustada y los principales hitos acumulativos. No modela compras, dinero real, transferencias, rachas ni todos los hitos de rivales, por lo que sirve para detectar inflación evidente, no para predecir el comportamiento real.

Los perfiles son:

- Casual: 1 partido por semana.
- Activo: 2 partidos por semana.
- Muy activo: 4 partidos por semana.

## Resultados

| Perfil | Periodo | Partidos | Cajas | Puntos | Comunes | Poco comunes | Raras | Épicas | Legendarias | Cosméticos únicos | Duplicados |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Casual | 3 meses | 13 | 30 | 210 | 17 | 9 | 4 | 0 | 0 | 4 | 3 |
| Casual | 6 meses | 26 | 56 | 487 | 24 | 18 | 6 | 8 | 0 | 7 | 9 |
| Casual | 12 meses | 52 | 94 | 1.053 | 44 | 24 | 8 | 17 | 1 | 10 | 30 |
| Activo | 3 meses | 26 | 56 | 460 | 34 | 10 | 6 | 6 | 0 | 7 | 12 |
| Activo | 6 meses | 52 | 103 | 953 | 49 | 29 | 9 | 15 | 1 | 11 | 26 |
| Activo | 12 meses | 104 | 203 | 1.869 | 109 | 53 | 16 | 23 | 2 | 12 | 54 |
| Muy activo | 3 meses | 52 | 111 | 1.251 | 56 | 30 | 11 | 6 | 8 | 9 | 28 |
| Muy activo | 6 meses | 104 | 223 | 2.585 | 106 | 56 | 12 | 43 | 6 | 11 | 57 |
| Muy activo | 12 meses | 208 | 347 | 3.181 | 196 | 87 | 38 | 23 | 3 | 12 | 95 |

No aparece un crecimiento explosivo: incluso el perfil muy activo queda en 347 cajas y 3.181 puntos al año. La adquisición del pequeño catálogo V1 se completa con actividad alta, tras lo cual aumenta la conversión de duplicados; será la señal principal que habrá que recalibrar con datos reales antes de fijar precios o ampliar pools.

## Umbrales V1

- Menos de 700 cajas por año para el perfil de 4 partidos semanales.
- Menos de 10.000 `player_points` anuales para ese mismo perfil.
- Como máximo los 12 cosméticos V1 distintos.
- Los duplicados siempre se convierten a puntos y nunca crean copias acumulables.

Estos umbrales son alarmas técnicas, no precios futuros. La tienda y el coste de los cosméticos quedan fuera de V1.

## Contrato operativo

- Los logros individuales son reconocimiento y no conceden cajas, puntos ni cosméticos.
- Los logros colectivos representan hechos del equipo. Cada ocurrencia válida crea una caja independiente para cada participante canónico del partido.
- La apertura es personal, autoritativa e idempotente. El cliente envía `boxId`, `operationId` y `expectedRevision`; PostgreSQL confirma el premio y devuelve el read model completo.
- `player_points` es una economía cosmética sin efecto sobre Rating V2, facetas, assessments o GRL.
- Realtime solo invalida el snapshot local. El cliente vuelve a solicitar `get_pachanga_progression_snapshot_v1` y nunca reconstruye saldo, inventario o cajas desde el evento.

Estados de una caja:

| Estado | Significado | Acción permitida |
| --- | --- | --- |
| `pending` | Contenido sellado y todavía no concedido | Abrir mediante `open_pachanga_reward_box_v2` |
| `opened` | Premio confirmado, con recibo y efectos persistidos | Lectura; una repetición devuelve la respuesta canónica |
| `revoked` | La evidencia deportiva dejó de ser válida antes de abrir | Ninguna concesión |

Una corrección nunca revierte destructivamente un premio abierto. Conserva ledger e inventario y añade `source_correction`; una caja pendiente pasa a `revoked` sin premio. El rollback operativo preferido es detener nuevas concesiones o hacer roll-forward. No se deben borrar cajas, recibos, ledger ni contenido sellado.

## Diagnóstico y reconciliación

Consultas mínimas, siempre con identificadores controlados y en el entorno correcto:

```sql
select box_id, status, revision, match_fact_id, achievement_grant_id,
       reward_granted_at, source_correction, revoked_reason
from public.pachanga_reward_recipients
where user_id = '<test-user-id>'::uuid
order by snapshot_at, box_id;

select operation_id, box_id, expected_revision, result_revision,
       server_sequence, response->>'alreadyOpened' as already_opened
from public.pachanga_reward_open_receipts
where operation_id = '<operation-id>'::uuid;

select source_box_id, delta, balance_after, idempotency_key, server_sequence
from public.pachanga_player_points_ledger
where source_box_id = '<box-id>'::uuid;

select reward_key, source_box_id, state, acquired_at
from public.pachanga_player_reward_inventory
where player_profile_id = '<profile-id>'::uuid;
```

Para comprobar duplicados, debe existir una sola fila de inventario por cosmético. La segunda caja conserva su recibo, suma `duplicateConversionPoints` al ledger y devuelve `duplicateConverted=true`. Dos aperturas concurrentes con `operationId` distintos dejan dos recibos de intento auditables, pero un único evento y un único efecto económico canónico. Repetir el mismo `operationId` devuelve exactamente el mismo recibo.

Si un snapshot parece atrasado:

1. comprobar la revisión y `server_sequence` de `pachanga_progression_user_state`;
2. verificar el recibo por `operationId`;
3. recargar `get_pachanga_progression_snapshot_v1`;
4. comparar caja, ledger e inventario por `boxId`;
5. no reparar el estado escribiendo JSON local ni actualizando tablas públicas desde cliente.

## QA remota de staging del PR #110

Ejecutada el 8 de agosto de 2026 en la rama Supabase `pwa-bridge-staging` (`iozcjirlfytryzrcmrnq`), sin usar producción.

- Resultado canónico 5-0 confirmado mediante RPC con diez participantes, Pedro 3 y Juan 2: cuatro logros colectivos y 40 cajas exactas; el no participante recibió cero.
- Pedro obtuvo `Primer hat-trick` y Juan `Primer doblete`, ambos sin recompensa individual. El segundo hat-trick de Pedro se mostró como `Hat-trick`, contador 2; cinco goles exactos produjeron solo `Repóker` dentro de la familia goleadora.
- Las distribuciones 3+2, 5+0 y 1+1+1+1+1 produjeron la misma ocurrencia colectiva de cinco goles.
- Apertura parcial, cierre, reautenticación y continuación conservaron el orden y las revisiones confirmadas.
- Concurrencia remota: una concesión, un evento y un efecto económico; dos recibos auditables para dos `operationId` distintos, uno de ellos con `alreadyOpened=true`.
- RLS remota impidió leer o abrir cajas ajenas y escribir rareza, contenido sellado, ledger, saldo, inventario o recibos.
- Realtime entregó el `UPDATE` del estado de usuario; la UI recargó después el snapshot oficial.
- La anulación canónica revocó cajas pendientes y conservó cajas abiertas, saldo e inventario con `source_correction`.
- Un cosmético repetido produjo una sola fila de inventario y convirtió la segunda copia en 16 puntos.
- Los perfiles Rating V2 de control conservaron exactamente overall, facetas, fiabilidad, versión y `updated_at`.
- QA visual autenticada en 1440x900, 390x844 y 844x390: canvas 3D visible, sin overflow horizontal, secuencia siguiente/cerrar/reabrir funcional y consola sin errores.

### Preflight de producción pendiente

La cadena histórica del repositorio no puede considerarse sincronizada todavía: el remoto registra las migraciones de notificaciones como `20260804144819` y `20260804145109`, mientras el repositorio conserva `20260804141213` y `20260804144912`. Además, las tres migraciones del PR se aplicaron a staging mediante la API de ramas con versiones remotas `20260808175351`, `20260808175352` y `20260808175354`.

Antes de cualquier `db push`, merge de la rama Supabase o despliegue de producción se debe reconciliar el historial de forma revisable, sin reescribir migraciones ya ejecutadas ni volver a aplicar su SQL. Hasta entonces rige: **NO producción**. Un deployment frontend verde no elimina este bloqueo de base de datos.
