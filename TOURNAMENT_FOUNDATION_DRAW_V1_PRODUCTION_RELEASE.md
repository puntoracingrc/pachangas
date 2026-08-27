# Tournament Foundation and Draw V1 Production Release

## Estado

`PRE-RELEASE / PRODUCTION NOT MODIFIED`

Este documento se completara con readbacks verificables tras staging, merge,
deployment y smoke. No presenta como PASS ningun gate remoto pendiente.

## Release coordinada

1. backup restaurable y baselines;
2. comprobar ledger remoto `158`;
3. aplicar las cinco migraciones exactas y confirmar defaults OFF;
4. ejecutar E2E autenticado y Preview en staging efimero;
5. revisar Security/Performance Advisors;
6. fusionar PR #204;
7. esperar deployment READY del SHA exacto;
8. smoke productivo con flags OFF;
9. activar por RPC Foundation, Private Beta, Creation, Draw, Automatic,
   Manual, Hybrid y Publish;
10. mantener Discovery, Match Generation, Bracket Progression y Payments OFF;
11. smoke efimero sin crear partidos y cleanup/rollback;
12. verificar Demo World V2.4 y Service Worker;
13. fusionar readbacks finales y retirar recursos temporales.

## Rollback

Antes de publicar un draw se puede cancelar el Tournament o el DrawPlan. Una
revision publicada es evidencia inmutable y no se borra. La operacion de
emergencia es kill switch/flags por RPC y roll-forward; no se reabren escrituras
directas ni se convierte un payload local en fuente de verdad.

## Readback pendiente

| Dato | Resultado |
| --- | --- |
| Main final | `PENDING` |
| Ledger remoto | `PENDING` |
| Deployment | `PENDING` |
| Flags finales | `PENDING` |
| Advisors | `PENDING` |
| Smoke productivo | `PENDING` |
| Tournament QA activo | `PENDING` |
| Tournament matches QA | `PENDING` |
| Worktree retirado | `PENDING` |
