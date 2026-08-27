# Tournament Foundation and Draw V1 Production Release

## Estado

`PRODUCTION ACTIVE / PRIVATE BETA / CLEAN READBACK`

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

## Readback de staging

| Dato | Resultado |
| --- | --- |
| Supabase branch | `zmjmzgdwovluvakfjggs / ACTIVE_HEALTHY` |
| Ledger pre-R6A | `158 / 20260826123500 / ff75c105ff5fa08802cc004390e29693` |
| Ledger post-R6A | `163 / 20260826195040 / 53b5456c21933e614752179568576d18` |
| Migraciones | `5/5 exactas` |
| Flags | `11/11 OFF despues del E2E` |
| E2E autenticado | `PASS` |
| Realtime | `postgres_changes listo, evento recibido, refetch canonico PASS` |
| Concurrencia | `1 winner / 1 stale PASS` |
| Advisors | `sin ERROR; indices FK R6A cubiertos` |
| Logs | `0 5xx; negativos 4xx esperados` |
| Preview Git | `dpl_CcoXgisaJH6jQ68vpRcgcU3SaGNR / READY / exact SHA` |
| Bundle Preview | `staging ref presente; production/unrelated/service_role ausentes` |
| Responsive Preview | `1440x900, 390x844 y 844x390 PASS` |
| PWA instalada fisica | `PENDING / no bloqueante` |
| Tournament match contexts | `0` |
| Produccion | `ACTIVA / PRIVATE BETA` |

## Readback productivo

| Dato | Resultado |
| --- | --- |
| PR funcional | `#204 MERGED` |
| Main funcional | `68dc360acf5dcce6cd7ffb6be4fa4b4d14d20cd7` |
| Ledger remoto | `163 / 20260826195040 / 53b5456c21933e614752179568576d18` |
| Migraciones | `5/5 exactas; historial remoto sincronizado` |
| Backup | `272 tablas / 1536 filas / 0 diferencias al restaurar` |
| Deployment | `dpl_2CHjktZiXEmimN5AXGeKrdrUFZh7 / READY / SHA exacto` |
| Flags ON por RPC | `Foundation, Private Beta, Creation, Draw, Automatic, Manual, Hybrid, Publish` |
| Flags OFF | `Public Discovery, Match Generation, Bracket Progression` |
| Idempotencia de activacion | `1 evento + 1 receipt; revision 11 sin doble aplicacion` |
| Canary | `R6A-PROD-4784A46F4233 / PASS / ROLLBACK` |
| QA persistente | `0 Tournaments, plans, placements, grants y match contexts` |
| Advisors | `0 errores; 0 warnings R6A de rendimiento` |
| Logs | `0 errores runtime Vercel; 0 5xx R6A` |
| Smoke productivo | `4 rutas x 3 viewports PASS` |
| Realtime | `invalidacion + refetch canonico; controlador SW activo` |
| PWA instalada fisica | `PENDING / no bloqueante` |
| Staging efimero | `ELIMINADO` |
| Variables Preview R6A | `3/3 ELIMINADAS` |
| Temporales sensibles | `ELIMINADOS` |
| Worktree | `RETIRAR TRAS MERGE DE ESTE INFORME` |

## Migraciones productivas

| Version | Archivo | SHA-256 |
| --- | --- | --- |
| `20260826195034` | `tournament_foundation_participant_freeze_v1.sql` | `2335bf3edd0aa2c84152977a17f5bca84059058220267e7bbcb90bf15c50191a` |
| `20260826195036` | `tournament_draw_schema_revisions_v1.sql` | `9810ca5ab4b92b172df7cb01f225e2ac80d9db7833d1a5734f55551cef17931c` |
| `20260826195037` | `tournament_draw_commands_engine_v1.sql` | `e286eb53a26db2f95621f1427d414436f3dddd5f0b0b1a71f103e97e527afa51` |
| `20260826195039` | `tournament_draw_access_read_models_v1.sql` | `0091c1d254527ea2c425065d67e58097343da9d8b50ad55e2ece28ffa5d92bb8` |
| `20260826195040` | `tournament_draw_hardening_indexes_flags_v1.sql` | `4a17e0011884346f9b131f52da33ce0d3b7d0bfad97a1a30c594e705c91ad7d9` |

## Limites conservados

No se inicio R6B. No existen partidos, progresion de bracket, resultados,
standings, pagos ni discovery publico de Tournament. Rating V2, rewards,
Conduct, Player Cosmetics, Team Cosmetics y billing permanecen intactos.
