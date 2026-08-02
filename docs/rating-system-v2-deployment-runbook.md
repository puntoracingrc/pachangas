# Rating System V2 - Runbook de staging y producción

## 1. Objetivo y regla de seguridad

Este runbook coordina PostgreSQL/Supabase y el frontend de Pachangas IQ sin dejar una versión incompatible en servicio.

Advertencias obligatorias:

- Las migraciones V2 crean las RPC nuevas, pero la activación final revoca las RPC antiguas.
- El frontend V1 puede dejar de funcionar si se revocan las RPC antiguas antes de desplegar el frontend V2.
- El frontend V2 puede fallar si se despliega antes de instalar las RPC V2.
- Nunca ejecutar un `supabase db push` improvisado contra producción.
- Supabase aplica las migraciones pendientes por orden de timestamp. La guía oficial está en [Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations).

La entrega queda separada físicamente:

- `supabase/migrations/`: 23 migraciones aditivas y compatibles con V1.
- `supabase/deferred-migrations/20260802144700_rating_v2_legacy_write_closure.sql`: unidad 24, destructiva para clientes V1 y deliberadamente excluida de `db push`.

No se debe mover la unidad 24 a `supabase/migrations/` hasta la fase 5 y debe hacerse en un PR de activación independiente.

## 2. Responsables y entornos

Antes de actuar, registrar:

| Dato | Valor requerido |
| --- | --- |
| Responsable de base de datos | Nombre y hora de inicio |
| Responsable de frontend | Nombre y despliegue exacto |
| Proyecto Supabase de staging | Ref comprobada visualmente |
| Proyecto Vercel de staging | Proyecto y dominio comprobados |
| Proyecto Supabase de producción | Ref comprobada visualmente |
| Proyecto Vercel de producción | Proyecto y dominio comprobados |
| Commit V2 | SHA exacto aprobado |
| Copia de seguridad | Identificador y hora |

Hay otros proyectos en Supabase y Vercel: no continuar si la referencia, organización o dominio no coinciden exactamente con Pachangas IQ.

## 3. Preflight

1. Congelar otros cambios de esquema y elegir una ventana con un único operador de base de datos.
2. Confirmar que el commit contiene 23 archivos en `supabase/migrations/` y una activación en `supabase/deferred-migrations/`.
3. Confirmar que la activación diferida no aparece en la salida de `supabase db push --dry-run`.
4. Ejecutar y guardar:

```bash
git rev-parse HEAD
git status --short
supabase --version
supabase migration list --linked
supabase db push --linked --dry-run
```

5. Crear o verificar una copia recuperable de la base antes de tocar producción.
6. Registrar métricas base: errores RPC, latencia, CPU, locks, conexiones y eventos Realtime.
7. Definir criterio de parada: cualquier error de autorización, revisión, RLS, duplicado o divergencia entre dispositivos detiene la fase.

## 4. Fase 1: infraestructura y RPC V2 aditivas

### Staging

1. Enlazar exclusivamente el proyecto de staging.
2. Revisar el `--dry-run`: debe listar las 23 migraciones aditivas y nunca la activación diferida.
3. Aplicar las 23 migraciones.
4. Verificar que las RPC V2 existen y que las RPC V1 siguen ejecutables para `authenticated`.
5. Ejecutar pruebas SQL/RLS y concurrencia contra staging con datos sintéticos.
6. Confirmar que el frontend V1 de staging todavía puede leer y escribir.

### Producción

Solo después de aprobar staging, repetir el `--dry-run` con la referencia de producción verificada. Aplicar únicamente las 23 migraciones aditivas. El frontend V1 debe seguir funcionando durante esta fase.

## 5. Fase 2: frontend V2 en staging

1. Desplegar el commit V2 en un deployment de staging/preview conectado solo al Supabase de staging.
2. Confirmar que no contiene claves `service_role` ni apunta a producción.
3. Verificar que el navegador envía solo intención, `operationId` y `expectedRevision`.
4. Confirmar que la respuesta reemplaza la previsualización con `confirmedRevision`, `serverSequence` y snapshot canónico.
5. Mantener V1 disponible; todavía no ejecutar la unidad 24.

## 6. Fase 3: QA autenticada y Realtime

Usar al menos dos usuarios y dos sesiones independientes. Deben pasar:

- primera valoración inmediata y sustitución tras tres partidos compartidos;
- anonimato, lectura del propio voto y moderación mediante identificador opaco;
- resumen social oculto con 0, 1 y 2 evaluadores, visible con 3;
- assessment inicial y avanzado de una sola ejecución;
- asistencia, alineación, pago, goleadores y finalización concurrentes;
- rechazo de una revisión obsoleta y recarga del snapshot oficial;
- reconexión y Realtime con convergencia de ambos clientes;
- restauración A->B sin voto, peso ni fecha de opinión nuevos;
- selección idéntica del último snapshot cuando varios comparten `created_at`;
- invitado, enlace reversible y valoración global;
- intento directo de RPC V1 y V2 fuera de permisos.

Guardar evidencias sin PII: SHA, operación, revisiones, secuencias, resultado y capturas de staging.

## 7. Fase 4: activación controlada de V2

1. Aplicar primero las 23 migraciones aditivas en producción y comprobar V1.
2. Desplegar/promover el frontend V2 exacto.
3. Hacer smoke autenticado inmediato con un grupo sintético o controlado.
4. Observar durante la ventana acordada errores RPC, revisiones obsoletas, CPU, locks y Realtime.
5. Si falla V2 antes de la revocación, revertir el frontend a V1. No hay que revertir el esquema aditivo.

No avanzar mientras exista tráfico V1 conocido o una versión cliente antigua que todavía necesite escribir.

## 8. Fase 5: revocación final de escrituras V1

La activación se publica en un PR independiente:

1. Mover `supabase/deferred-migrations/20260802144700_rating_v2_legacy_write_closure.sql` a `supabase/migrations/` con un timestamp nuevo generado por `supabase migration new`.
2. Revisar que el nuevo archivo contiene únicamente las revocaciones aprobadas.
3. Ejecutar `supabase db push --linked --dry-run`; debe aparecer solo la migración de cierre.
4. Aplicarla primero en staging y repetir los intentos directos contra V1.
5. Aplicarla en producción únicamente tras confirmar que el frontend V2 está estable.
6. Verificar que V1 devuelve error de permisos y V2 continúa operativo.

## 9. Fase 6: verificación

Comprobar y registrar:

- SHA del frontend servido y dominio de producción;
- versión de migración aplicada;
- RPC V1 sin `EXECUTE` para `authenticated`;
- tabla `pachanga_groups` sin `UPDATE` directo para `authenticated`;
- RPC V2 operativas con RLS y actor autenticado;
- un solo evento y recibo por `operationId`;
- secuencias monotónicas y revisiones convergentes;
- Realtime provoca recarga del estado oficial;
- CPU, locks, errores y latencia dentro del umbral acordado.

## 10. Reversión

### Antes de la fase 5

Revertir únicamente el frontend a V1. Las 23 migraciones son aditivas y se conservan para evitar pérdida de historial.

### Después de la fase 5

Antes de volver a desplegar V1, restaurar temporalmente sus permisos mediante una migración de emergencia revisada:

```sql
grant execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) to authenticated;
grant execute on function public.patch_pachanga_match_player_status(uuid, text, text, text, uuid) to authenticated;
grant execute on function public.patch_pachanga_match_lineup_state(uuid, text, boolean, text[], text[], text, uuid) to authenticated;
grant execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean, uuid) to authenticated;
grant execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[], uuid) to authenticated;
grant execute on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid) to authenticated;
grant execute on function public.sync_pachanga_market_profile(uuid, text, jsonb) to authenticated;
grant execute on function public.sync_pachanga_open_match(uuid, text, jsonb, uuid) to authenticated;
grant execute on function public.review_pachanga_open_match_request(uuid, text, uuid) to authenticated;
grant execute on function public.request_pachanga_open_match(uuid, uuid) to authenticated;
grant update on table public.pachanga_groups to authenticated;
```

Después:

1. confirmar permisos V1 con un usuario controlado;
2. revertir el frontend;
3. mantener intactas evidencias, snapshots, recibos y eventos V2;
4. abrir incidente y no reintentar la activación hasta identificar la causa.

No borrar tablas V2 ni reescribir historial durante una reversión.

## 11. Criterio de cierre

La activación solo se considera cerrada cuando frontend, PostgreSQL, Realtime y dos clientes convergen; los permisos V1 están revocados; no hay errores de autorización inesperados; y existe una ruta de recuperación comprobada. Un deployment `READY` por sí solo no basta.
