# Platform Infrastructure Health V1

## Contrato

Sistema es observabilidad de solo lectura. No incluye reiniciar DB, ejecutar SQL, borrar deployments, cambiar planes ni revelar env vars. Una integración sin token o una métrica no verificable produce `UNKNOWN`/`No disponible`, nunca verde ni porcentaje inventado.

## Supabase

### PostgreSQL local al proyecto

La RPC protegida devuelve:

- tamaño total de la base;
- conexiones totales y activas;
- consultas activas de más de 30 segundos, solo como conteo;
- usuarios Auth;
- top 10 tablas `public`/`private` por tamaño;
- número y última versión de migración si existe `supabase_migrations.schema_migrations`;
- buckets, archivos y bytes de Storage si existen las tablas.

No devuelve texto SQL, contenido Storage ni secretos.

### Management API

Con `SUPABASE_MANAGEMENT_ACCESS_TOKEN` y `PACHANGAS_SUPABASE_PROJECT_REF` consulta uso API y conteos de advisors de seguridad/rendimiento. El endpoint de advisors se etiqueta experimental/deprecated y solo se muestran conteos `ERROR/WARNING/INFO`.

Los límites del plan no se consideran disponibles en V1. Por ello no se calcula porcentaje ni semáforo de capacidad. Caché: 90 segundos.

## Vercel

Con `VERCEL_ADMIN_TOKEN`, `PACHANGAS_VERCEL_PROJECT_ID` y `PACHANGAS_VERCEL_TEAM_ID` consulta los últimos 10 deployments y costes/charges de 30 días cuando el endpoint responde.

Se muestran estado, target, URL, SHA, fecha y duración de build. Se identifica producción y el último fallo. No se declara un mismatch con `main` si no hay una fuente autoritativa de `main HEAD` disponible en runtime.

El coste no equivale a un límite. `usageLimitsAvailable=false`; no se calcula porcentaje. Caché: 60 segundos.

## Stripe agregado

Home/Sistema solo reciben estado, fuente, fecha y motivo seguro. Los pagos, customers y reconciliación completos se sirven únicamente en `/admin/billing` con `billing.read`. Caché: 60 segundos.

## Aplicación y PWA

Sistema muestra:

- `clientVersion` inmutable del build;
- `serviceWorkerVersion`;
- `minimumSupportedClientVersion`;
- SHA de build cuando Vercel/GitHub lo proporciona.

La telemetría de clientes incompatibles existente no se reinventa; el Control Center muestra el contrato de versión actual y el centro de errores nuevo.

## Error Center

El navegador envía exclusivamente ruta sin query, versión, fingerprint SHA-256, categoría, familia de navegador, plataforma y `operationId`. No envía mensaje, stack, nombre, email, texto de usuario, token ni body.

- Payload máximo declarado: 1.200 bytes.
- Rate limit por hash efímero de IP: 20/minuto por instancia.
- Deduplicación de operationId.
- Agregación por fingerprint/ruta/versión/categoría/browser/plataforma.
- Retención y receipts: 30 días, limpiados al escribir.
- Incidente manual: `new`, `investigating`, `resolved`, `ignored`.
- Usuarios/dispositivos aproximados: AUSENTE para no introducir tracking persistente en V1.

El rate limit en memoria es una defensa básica por instancia, no un límite global distribuido. Para volumen alto debe moverse a una infraestructura compartida antes de ampliar el payload.

## Estados

- `OK`: el conector respondió y no hay señal crítica conocida en los datos disponibles.
- `WARNING`: fallo reciente, pago/invoice abierta o advisor warning según la fuente.
- `CRITICAL`: deployment más reciente fallido o advisor error verificable.
- `UNKNOWN`: integración ausente, consulta fallida o información insuficiente.

Estos estados no certifican la salud completa de un proveedor; resumen únicamente las señales que V1 pudo consultar.

## Configuración staging

```text
PACHANGAS_ENVIRONMENT=staging
SUPABASE_MANAGEMENT_ACCESS_TOKEN=<server-only>
PACHANGAS_SUPABASE_PROJECT_REF=<staging-ref exacto>
VERCEL_ADMIN_TOKEN=<server-only, scope mínimo>
PACHANGAS_VERCEL_PROJECT_ID=<preview project>
PACHANGAS_VERCEL_TEAM_ID=<team exacto>
STRIPE_ADMIN_RESTRICTED_KEY=<rk_test read-only>
```

Si cualquiera falta, el resto del Control Center sigue funcionando. Ninguna variable administrativa usa `NEXT_PUBLIC_`.

## Resultado de Preview

El deployment de staging se validó sin credenciales administrativas de Stripe, Supabase Management o Vercel expuestas al runtime del navegador. Los conectores ausentes muestran `UNKNOWN` y el resto del panel continúa operativo. La salud PostgreSQL canónica, la versión de aplicación, el contrato PWA y el historial de migraciones sí se consultaron. La PWA real en app mode confirmó manifest, Service Worker activo/controlador y cero overflow o errores runtime.
