# Platform Billing Observability V1

## Fuentes de verdad

| Dato | Fuente | Autoridad |
| --- | --- | --- |
| Estado local, intervalo, trial usado, customer/subscription/price y period end | `pachanga_groups` | Read model local que usa el producto. |
| Estado de suscripción, price, periodo, PaymentIntents, invoices, refunds y disputes | Stripe API server-side | Stripe para su dominio. |
| Procesamiento de webhooks | `pachanga_stripe_webhook_events` | Ledger local idempotente. |

El panel nunca fusiona silenciosamente ambos estados. Muestra `Local`, `Stripe` y `SYNC OK`, `MISMATCH` o `UNKNOWN`.

## Permisos y credenciales

- Vista disponible para `platform_owner`, `platform_admin` y `finance`.
- Preferencia: `STRIPE_ADMIN_RESTRICTED_KEY` de test/staging con lectura mínima.
- Existe fallback visible a `STRIPE_SECRET_KEY` para compatibilidad, marcado `broad-key-fallback`; no es la configuración recomendada.
- Las claves son server-only y nunca usan prefijo `NEXT_PUBLIC_`.
- QA financiera usa Stripe test mode, nunca tarjetas/productos live.

## Consultas V1

- Hasta 100 subscriptions con `status=all`.
- Hasta 50 PaymentIntents.
- Hasta 50 invoices.
- Hasta 25 refunds.
- Hasta 25 disputes.
- Hasta 200 equipos locales con subscription ID para reconciliación.
- Caché en memoria del servidor: 60 segundos; refresh forzado limitado a uno cada 15 segundos.

Cada bloque expone `hasMore` cuando Stripe indica que la muestra está truncada. Una subscription local no encontrada no se declara mismatch si la muestra tiene más páginas: queda `UNKNOWN`.

## Métricas

| Métrica | Semántica | Estado |
| --- | --- | --- |
| Trial/active/past_due/canceled local | Conteo de `billing_status` local | IMPLEMENTADO |
| Distribución Stripe | Estado actual de la muestra de subscriptions | IMPLEMENTADO CON MUESTRA |
| Pagos correctos/fallidos | Estado de los PaymentIntents recientes | IMPLEMENTADO CON MUESTRA |
| Invoices pagadas/abiertas | Estado de invoices recientes | IMPLEMENTADO CON MUESTRA |
| Refunds/disputes | Conteo de muestra | IMPLEMENTADO CON MUESTRA |
| MRR estimado | Suma mensualizada de items active/trialing de la muestra | PARCIAL/ESTIMADO |
| ARR estimado | MRR estimado por 12 | PARCIAL/ESTIMADO |
| Cobrado hoy/mes/30d | Flujo de caja completo paginado | AUSENTE |
| Churn fiable | Cohortes y eventos completos | AUSENTE |

MRR anual divide `unit_amount` entre 12; mensual usa el importe mensual y multiplica por quantity. Otros intervalos aportan cero. Las monedas nunca se suman entre sí.

## Reconciliación

Se comparan:

- estado local frente a estado Stripe;
- primer price ID de Stripe frente a `stripe_price_id` local;
- fin de periodo con tolerancia de 60 segundos;
- existencia de la subscription.

V1 diagnostica, no corrige. No hay refund, cancel subscription, change price ni escritura Stripe desde el Control Center. Esas acciones permanecen en Stripe Dashboard.

## Webhooks y privacidad

Se muestran event ID, tipo, estado, fecha y error sanitizado. Nunca se expone el payload raw. El sanitizador elimina claves `sk_`, `rk_`, bearer, emails y secretos en query strings. Los errores desconocidos de Stripe o PostgreSQL se reemplazan por un mensaje genérico.

No se muestran PAN, CVC, payment method raw ni datos PCI. Customer/subscription IDs solo llegan a roles con `billing.read`.

## Contrato de QA Stripe test

Fixtures esperadas en Stripe test mode:

1. trial local;
2. checkout/active;
3. payment success;
4. payment failed/past_due;
5. cancel;
6. webhook duplicado;
7. local active + Stripe active = `SYNC OK`;
8. local active + Stripe canceled = `MISMATCH`;
9. webhook failed = alerta.

El Preview validado no tiene configurada una clave restringida de Stripe test. Por tanto, en esta fase se comprobó el comportamiento obligatorio `UNKNOWN`, la continuidad de Billing local, la redacción de webhooks y los permisos por rol, pero no se simularon llamadas externas de checkout/pago/cancelación. No se usó Stripe live ni producción.
