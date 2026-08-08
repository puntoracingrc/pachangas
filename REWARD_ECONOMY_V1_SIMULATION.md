# Simulación de economía de recompensas V1

## Alcance del catálogo definitivo

Simulación determinista de 160 temporadas por escenario. Incluye victoria normal repetible, goles colectivos, portería a cero, goleada, victoria por la mínima, hitos de partidos y victorias, rachas y rivales distintos. También estima por separado los reconocimientos individuales de un participante representativo. Esos reconocimientos nunca se suman a cajas, puntos ni cosméticos.

| Perfil | Meses | Victorias | Partidos | Logros individuales | Logros colectivos / cajas | Cajas por partido | p50 | p90 | Máximo | Puntos | Cosméticos | Duplicados |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Casual | 3 | 50% | 13 | 13.88 | 31.18 | 2.4 | 2 | 4 | 9 | 274.35 | 6.36 | 4.26 |
| Casual | 3 | 70% | 13 | 16.18 | 38.09 | 2.93 | 3 | 5 | 9 | 334.66 | 7.08 | 6.08 |
| Casual | 3 | 85% | 13 | 17.75 | 43.33 | 3.33 | 3 | 6 | 10 | 384.98 | 7.43 | 7.19 |
| Casual | 6 | 50% | 26 | 20.31 | 56.44 | 2.17 | 2 | 4 | 10 | 500.03 | 8.09 | 11.46 |
| Casual | 6 | 70% | 26 | 21.91 | 66.83 | 2.57 | 3 | 4 | 9 | 577.17 | 8.46 | 14.29 |
| Casual | 6 | 85% | 26 | 23.84 | 76.61 | 2.95 | 3 | 5 | 10 | 673.2 | 9.15 | 17.22 |
| Casual | 12 | 50% | 52 | 29.73 | 104.28 | 2.01 | 2 | 4 | 8 | 930.63 | 9.88 | 25.34 |
| Casual | 12 | 70% | 52 | 31.59 | 124.31 | 2.39 | 2 | 4 | 10 | 1086.66 | 10.13 | 31.64 |
| Casual | 12 | 85% | 52 | 34.69 | 143.48 | 2.76 | 3 | 4 | 10 | 1267.76 | 10.56 | 37.29 |
| Activo | 3 | 50% | 26 | 20.44 | 56.49 | 2.17 | 2 | 4 | 9 | 496.38 | 8.13 | 11.14 |
| Activo | 3 | 70% | 26 | 21.98 | 67.9 | 2.61 | 3 | 4 | 10 | 585.75 | 8.68 | 14.13 |
| Activo | 3 | 85% | 26 | 24.29 | 77.27 | 2.97 | 3 | 5 | 10 | 688.49 | 8.91 | 16.54 |
| Activo | 6 | 50% | 52 | 30.17 | 104.96 | 2.02 | 2 | 4 | 10 | 943.43 | 10.03 | 25.83 |
| Activo | 6 | 70% | 52 | 32.38 | 126.4 | 2.43 | 2 | 4 | 10 | 1104.02 | 10.38 | 32.66 |
| Activo | 6 | 85% | 52 | 34.53 | 142.21 | 2.73 | 3 | 4 | 10 | 1247.16 | 10.65 | 37.11 |
| Activo | 12 | 50% | 104 | 43.89 | 194.29 | 1.87 | 2 | 3 | 9 | 1747.14 | 11.21 | 53.64 |
| Activo | 12 | 70% | 104 | 47.28 | 236.54 | 2.27 | 2 | 4 | 10 | 2051.84 | 11.43 | 67.07 |
| Activo | 12 | 85% | 104 | 50.19 | 270.29 | 2.6 | 3 | 4 | 10 | 2328.06 | 11.43 | 78.18 |
| Muy activo | 3 | 50% | 52 | 30.19 | 103.56 | 1.99 | 2 | 4 | 9 | 924.05 | 9.81 | 25.64 |
| Muy activo | 3 | 70% | 52 | 32.29 | 126.09 | 2.42 | 2 | 4 | 10 | 1090.97 | 10.33 | 31.2 |
| Muy activo | 3 | 85% | 52 | 34.08 | 143.21 | 2.75 | 3 | 4 | 10 | 1244.78 | 10.67 | 37.18 |
| Muy activo | 6 | 50% | 104 | 44.21 | 195.79 | 1.88 | 2 | 3 | 9 | 1757.75 | 11.13 | 54.73 |
| Muy activo | 6 | 70% | 104 | 47.14 | 237.26 | 2.28 | 2 | 4 | 10 | 2051.89 | 11.28 | 66.99 |
| Muy activo | 6 | 85% | 104 | 49.85 | 269.23 | 2.59 | 3 | 4 | 10 | 2306.24 | 11.47 | 76.43 |
| Muy activo | 12 | 50% | 208 | 65.18 | 368.14 | 1.77 | 2 | 3 | 10 | 3218.41 | 11.69 | 110.44 |
| Muy activo | 12 | 70% | 208 | 68.76 | 453.48 | 2.18 | 2 | 3 | 10 | 3820.23 | 11.71 | 136.57 |
| Muy activo | 12 | 85% | 208 | 72.16 | 516.8 | 2.48 | 3 | 4 | 10 | 4249.67 | 11.79 | 156.85 |

## Lectura de inflación

- El arranque concentra primeras veces e hitos tempranos: la media máxima es 3.33 cajas por partido y el p90 máximo es 6.
- A doce meses la media queda entre 1.77 y 2.76; el p90 queda entre 3 y 4.
- El máximo simulado de 10 corresponde a coincidencias legítimas de primeras veces, resultado, defensa, gol colectivo, racha e hitos. No es el comportamiento rutinario.
- El equipo muy activo y fuerte termina el año con 516.8 cajas y 4249.67 puntos, dentro de los límites técnicos.
- Mantener una caja por victoria aumenta la recompensa gradualmente: entre 50% y 85% de victorias, el volumen anual no se multiplica por 1,7.

## Umbrales técnicos

- En cualquier horizonte: media <= 3,4; p90 <= 6; máximo <= 10.
- En doce meses: media < 2,8 y p90 <= 4.
- Muy activo/fuerte anual: < 800 cajas, < 12.000 puntos y como máximo 12 cosméticos V1.

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

### Preflight de producción

El historial del repositorio se alineó con las versiones ya registradas por Supabase sin cambiar el SQL ni volver a ejecutar migraciones: notificaciones usan `20260804144819` y `20260804145109`; las tres migraciones de este PR usan `20260808175351`, `20260808175352` y `20260808175354`, iguales a staging.

Producción termina en `20260804145109`, por lo que sus únicas migraciones pendientes son las tres de este PR, en ese orden. Antes de aplicarlas se debe volver a comparar el historial remoto, confirmar el SHA verde de `main` y conservar el rollback no destructivo descrito arriba.
