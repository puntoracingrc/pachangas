# Ranking CRON_SECRET Production Verification Plan

Fecha de auditoría: 2026-09-04 (Europe/Madrid)

## 1. SHA base real

- Repositorio: `puntoracingrc/pachangas`.
- Rama de trabajo aislada: `codex/ranking-cron-secret-production-verification`.
- Base auditada: `origin/main` en `3fa6fe778fe00b7b2218b3ee1fbee108b2a060d6`.
- El checkout compartido conserva cambios locales ajenos y no se utilizará para editar.

## 2. Estado del issue #170

- `OPEN` al iniciar la verificación.
- Objetivo: cerrar la evidencia productiva de `CRON_SECRET` sin leer, imprimir, rotar ni sustituir su valor.
- Los issues de QA física `#167`, `#168` y `#169` permanecen abiertos.
- Los issues `#165` y `#166` permanecen cerrados y congelados.

## 3. Fuentes revisadas

- Issue `#170` y estado de `#165` a `#169`.
- `RANKING_PRODUCTIZATION_V1_REPORT.md`.
- `RANKING_PRODUCTIZATION_V1_PRODUCTION_RELEASE.md`.
- `RANKING_PRODUCTIZATION_NEXT_STEPS.md`.
- Rutas internas de Ranking, Billing y Team Operational.
- `vercel.json`, `.env.example`, `package.json` y suites Ranking existentes.
- Migraciones R1-R8, funciones SQL de cola, salud, publicación, eventos y recibos.
- Metadatos de Vercel del proyecto, variables, cron jobs, deployments, logs y métricas.
- Read models productivos de Supabase mediante consultas exclusivamente de lectura.
- Documentación oficial de Vercel para Cron Jobs, variables sensibles, variables por entorno y runtime logs; changelog oficial de Supabase.

## 4. Estado de Ranking Productization

- R1-R8 están presentes en el repositorio y el producto Ranking está desplegado.
- La cola autoritativa se procesa mediante PostgreSQL; el endpoint no calcula rankings en el cliente.
- La publicación provincial y su salud se leen desde el estado canónico, no desde cachés locales.

## 5. Estado de flags

- `season_score_v3_enabled = true`.
- `provincial_ranking_enabled = true`.
- `territory_awards_enabled = false`.
- Revisión de settings observada: `3`.

## 6. Piloto Barcelona

- Temporada activa: `barcelona-pilot-2026`.
- Provincia piloto: `08`.
- Estado: `open`.
- Revisión Ranking y revisión publicada observadas: `2`.

## 7. Call graph del cron

`Vercel Cron (GET, UTC)` -> `/api/internal/rankings/refresh` -> validación exacta de `Authorization: Bearer <CRON_SECRET>` -> `platformServiceClient()` -> RPC `process_pachanga_ranking_refresh_queue_v1(maximum_operations => 25)` -> snapshot JSON no cacheable.

La RPC solo se alcanza después de una autorización válida. La ausencia de variable termina en `503`; una credencial ausente o incorrecta termina en `403`.

## 8. Rutas que comparten el secreto

1. `/api/internal/rankings/refresh`.
2. `/api/internal/billing/reconcile`.
3. `/api/internal/team-operational/expire`.

No se rotará ni dividirá el secreto y no se invocarán manualmente Billing o Stripe.

## 9. Configuración en vercel.json

- Ranking: `*/5 * * * *`.
- Billing: `17 * * * *`.
- Team Operational: `*/10 * * * *`.
- La semántica de Vercel Cron es UTC.

## 10. Cron jobs registrados en Vercel

- Cron jobs habilitados: sí.
- Definiciones activas: exactamente las tres del repositorio.
- Ranking duplicado o ruta alternativa: no observado.
- Cambios sin desplegar: ninguno.
- Deployment propietario al iniciar: deployment productivo `READY` del SHA base.

## 11. Metadatos de CRON_SECRET

- Existe una única entrada con nombre `CRON_SECRET` en el proyecto `pachangas`.
- El valor no se ha leído, descifrado, impreso ni convertido en fingerprint.
- Fecha de creación y última modificación observada: `2026-08-28T16:23:08.034Z`.

## 12. Targets de entorno

- Production: presente.
- Preview: ausente.
- Development: ausente.
- Custom environments: ninguno.
- Overrides de rama: ninguno observado.

## 13. Tipo de variable

- Tipo Vercel: `sensitive`.
- Visibilidad: secreta/no legible después de su creación.
- No está almacenada como variable pública.

## 14. Scope project/shared

- Variable de proyecto, no shared: figura directamente en el proyecto `pachangas` y no tiene `configurationId` de variable compartida.
- No se ha consultado ni afectado ningún otro proyecto de Vercel.

## 15. Deployments que la reciben

- La variable se limita a Production.
- El primer redeploy posterior a la configuración quedó `READY` el 2026-08-28.
- El deployment productivo actual fue construido varios días después de esa configuración y recibe el scope Production.

## 16. Resultados recientes del cron

- El deployment actual presenta ejecuciones Ranking `200` en la cadencia de cinco minutos.
- No se observan `500`, `503` ni timeouts actuales.
- Se observarán y registrarán al menos seis slots consecutivos del scheduler.

## 17. Distribución histórica de status

- La ventana móvil de siete días muestra una amplia mayoría de `200` y una cohorte antigua de `503`.
- Los totales exactos se volverán a capturar al cerrar para evitar presentar como simultáneas cifras obtenidas en instantes diferentes de una ventana móvil.
- Los `403` generados de forma controlada por esta auditoría se separarán del tráfico del scheduler.

## 18. Ventana de los 503

- Los `503` se concentran el 2026-08-28 antes de la propagación del deployment posterior a la configuración de la variable.
- Las tres revisiones históricas afectadas contienen el mismo contrato de ruta que el SHA actual.
- El último `503` observado pertenece al deployment anterior durante la transición de alias; el nuevo deployment empezó a responder `200` inmediatamente después.
- No hay `503` en la ventana reciente del deployment actual.

## 19. Clasificación provisional

`ALREADY_CONFIGURED_AND_VERIFIED`.

La clasificación se confirmará únicamente tras completar las pruebas negativas, el caso aislado sin variable, los seis slots, el readback posterior y los scans de secretos.

## 20. Pruebas negativas previstas

- Dos peticiones independientes sin `Authorization`.
- Bearer falso.
- Esquema con capitalización incorrecta.
- Header vacío, solo espacios, texto sin esquema, Basic falso y valor falso largo.
- Esperado: `403`, `RANKING_REFRESH_FORBIDDEN`, `Cache-Control: no-store, max-age=0`, sin stack ni metadatos privados.
- Comparación canónica antes/después para demostrar cero efectos laterales.

## 21. Verificación autorizada prevista

- Preferencia: observar ejecuciones reales del scheduler, que ya aporta el header gestionado por Vercel.
- No se obtendrá el secreto para fabricar una petición manual.
- Se confirmarán seis slots consecutivos `200`, duración, deployment y ausencia de errores.

## 22. Readback Ranking

Antes y después se compararán:

- cola, intentos y operaciones fallidas;
- eventos y recibos;
- temporada, fórmula, settings y flags;
- health y reason codes;
- publicación, revisión, checksum y conteos;
- contadores protegidos de Rating, Conduct, Rewards, Billing, Stripe y Team Cosmetics.

## 23. Riesgos

- Exposición accidental del secreto: mitigada usando solo metadatos y salidas redactadas.
- Confundir `403` manuales con fallos del scheduler: se separan por timestamp y cadencia.
- Activar Billing o Stripe: no se invocarán manualmente esas rutas.
- Ventana histórica móvil: se registrará timestamp y se explicará su variación.
- Mutación productiva: todas las consultas Supabase serán `SELECT`; las pruebas rechazadas terminan antes de la RPC.

## 24. Rollback

- No se prevé cambio de runtime, cron, variable ni base de datos; por tanto no hay rollback operativo.
- Si aparece un defecto real, se detendrá el caso A y se reclasificará antes de modificar nada.
- La documentación puede revertirse con Git sin alterar producción.

## 25. Archivos previstos

1. `RANKING_CRON_SECRET_PRODUCTION_VERIFICATION_PLAN.md`.
2. `RANKING_CRON_SECRET_PRODUCTION_VERIFICATION_REPORT.md`.

No se prevén cambios en código, tests, `package.json`, `package-lock.json`, SQL ni configuración.

## 26. Configuración externa prevista

- Ninguna modificación.
- No se creará, copiará, rotará ni eliminará ninguna variable.
- No se cambiarán cron jobs, dominios, deployments, flags ni Supabase.

## 27. Criterio de cierre

El issue `#170` solo se cerrará cuando estén fusionados el plan y el informe y se haya demostrado: scope Production correcto, tipo sensitive, cron único `*/5`, seis slots autorizados `200`, pruebas sin header y con Bearer falso `403`, caso aislado sin variable `503`, cero efectos laterales, health/publicación correctos, ausencia de `503` actuales, histórico reconciliado y secret scans limpios.

## Referencias oficiales

- [Vercel Cron Jobs](https://vercel.com/docs/cron-jobs)
- [Managing Cron Jobs](https://vercel.com/docs/cron-jobs/manage-cron-jobs)
- [Securing Cron Jobs](https://vercel.com/docs/cron-jobs/manage-cron-jobs#securing-cron-jobs)
- [Sensitive environment variables](https://vercel.com/docs/environment-variables/sensitive-environment-variables)
- [Environment variables by environment](https://vercel.com/docs/environment-variables/manage-across-environments)
- [Runtime logs](https://vercel.com/docs/logs/runtime)
- [Supabase changelog](https://supabase.com/changelog)
