# Platform Admin RBAC V1

## Principio

El rol de plataforma es una autoridad privada distinta de cualquier rol de equipo. Los registros están en `private.pachanga_platform_admin_roles`; el usuario no puede escribirlos, no se guardan en `user_metadata` y no se hardcodea ningún email.

Toda página llama a `requirePlatformPage(capability)`. Toda API llama a `requirePlatformRequest(request, capability)`. Cada RPC vuelve a exigir la capability con `private.pachanga_platform_require_v1`; ocultar enlaces no forma parte de la barrera de seguridad.

## Matriz

| Capacidad | Owner | Platform admin | Moderator | Support | Finance | Ops |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Resumen y búsqueda | Sí | Sí | Sí | Sí | Sí | Resumen |
| Usuarios/equipos | Sí | Sí | Sí, sin PII | Sí, con PII | Sí, con PII | No |
| Suspender/banear | Sí | Sí | No | No | No | No |
| Gestionar roles globales | Sí | No | No | No | No | No |
| Partidos/Retos | Sí | Sí | Sí | Sí | No | No |
| Moderación lectura/escritura | Sí/Sí | Sí/Sí | Sí/Sí | No/No | No/No | No/No |
| Rankings/Rewards | Sí | Sí | No | No | No | No |
| Notificaciones lectura/envío | Sí/Sí | Sí/Sí | No/No | Sí/No | No/No | No/No |
| Billing/Stripe | Sí | Sí | No | No | Sí | No |
| Sistema/errores | Sí | Sí | No | No | No | Sí |
| Flags lectura/escritura | Sí/Sí | Sí/Sí | No/No | No/No | No/No | Sí/No |
| Auditoría | Sí | Sí | Sí | No | Sí | Sí |
| Synthetic World | Sí, si entorno habilitado | No | No | No | No | No |

Un `team owner` o `team admin` sin fila global activa obtiene 404 en páginas y 403 en APIs/RPC.

## PII y secretos

- Email, proveedores Auth y fecha de nacimiento requieren `users.pii.read`.
- IDs Stripe y datos de periodo requieren `billing.read`.
- Moderador puede buscar por nombre seguro o UUID, pero no por email ni Stripe.
- Support puede diagnosticar por email, pero no buscar Stripe ni leer billing.
- Finance puede relacionar owner/equipo con Stripe, pero no moderar.
- Passwords, JWT, refresh/access tokens, raw Auth, CVC, PAN, claves y payload Stripe raw nunca se devuelven.

## Bootstrap del primer owner

Solo local/staging, nunca producción en V1:

```bash
PACHANGAS_ENVIRONMENT=staging \
NEXT_PUBLIC_SUPABASE_URL='https://<staging-ref>.supabase.co' \
SUPABASE_SERVICE_ROLE_KEY='<staging-service-role>' \
npm run platform-admin:bootstrap-owner -- \
  --user-id '<uuid-auth-staging>' \
  --reason 'Bootstrap inicial del Control Center en staging'
```

El script genera un `operationId` si no se aporta. La RPC exige `service_role`, bloquea la tabla, comprueba que el usuario exista, rechaza un segundo bootstrap y escribe exactamente un evento de auditoría. Ningún UUID personal vive en la migración.

Para producción se diseñará un procedimiento independiente después de aprobar staging; el script actual falla antes de leer credenciales cuando detecta producción.

## Mutaciones

| Acción | Capability | Protecciones |
| --- | --- | --- |
| Rol global | `roles.manage` | Motivo, revisión, operationId, lock por usuario, último owner protegido. |
| Estado global | `users.suspend` | Motivo, revisión, operationId, no auto-suspensión, sincronización Auth. |
| Flag | `flags.write` | Preview, motivo, revisión, operationId, confirmación y allowlist. |
| Anuncio | `notifications.send` | Draft, audiencia limitada, preview, recuento, confirmación y operationId. |
| Incidente | `system.read` más rol owner/admin/ops | Estado, nota, motivo, revisión, operationId y lock. |

Los componentes retienen el mismo `operationId` durante un retry del mismo intento y lo descartan al cambiar la intención.

## Suspensión y ban

`active`, `suspended` y `banned` conservan historial. La fila privada corta el acceso al Control Center al siguiente request. La API sincroniza `ban_duration` con Supabase Auth y registra `pending`, `confirmed` o `error` sin guardar el error raw.

- `suspended`: requiere fecha futura.
- `banned`: estado reversible y ban Auth de larga duración; no borra datos.
- `active`: usa `ban_duration: none`.
- Ninguna señal de Conducta ejecuta un ban global automáticamente.
- Un JWT existente puede sobrevivir hasta expirar; debe tenerse en cuenta en incidentes urgentes.

## Auditoría

El ledger privado registra `actor_user_id`, rol, acción, objetivo, motivo, before/after, respuesta canónica, `operation_id`, `server_sequence` y fecha. Las repeticiones de la misma operación convergen y una operación no puede reutilizarse para otra acción/objetivo.

Las pruebas SQL cubren visitor, usuario normal, admin de equipo, moderator, support, finance, ops, platform_admin y platform_owner, además de accesos adversariales y último owner.
