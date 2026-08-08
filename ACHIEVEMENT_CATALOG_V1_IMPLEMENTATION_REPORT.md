# Informe de implementación del catálogo V1

Fecha local: 2026-08-08. Rama: `codex/achievement-catalog-v1`.

1. **Estado inicial de main.** Base exacta `12452c72dde027058a5539de90f1f82097929dc1`, coincidente con el contrato recibido.
2. **Rama creada.** `codex/achievement-catalog-v1`, en worktree aislado.
3. **Catálogo encontrado.** 60 definiciones activas V1 antes de esta migración, con motor de grants, cajas, apertura, inventario, ledger, RLS e idempotencia ya desplegado.
4. **Clasificación.** 56 filas anteriores quedan `MIGRATE` y 4 `DEPRECATE`; todas se conservan inactivas para historial. El detalle por clave está en `ACHIEVEMENT_CATALOG_V1.md`.
5. **Catálogo final.** `achievement_catalog_v2`: 101 escalones activos en 22 familias.
6. **Logros individuales.** 45 escalones de partidos, victorias, goles, máximo goleador por partido, rachas y rivales distintos.
7. **Logros colectivos.** 56 escalones de partidos, victoria externa, goles por partido, portería a cero, goleada, mínima, rachas y rivales distintos.
8. **Familias repetibles.** Goles personales por partido, victoria externa normal, goles colectivos por partido, porterías a cero, goleadas y victorias por la mínima.
9. **Familias acumulativas.** Partidos, victorias, goles, mejores rachas y rivales distintos jugados o vencidos.
10. **Primeras veces.** Se guarda título de primera ocurrencia, contador, primera fecha, última fecha, partido y metadatos de presentación.
11. **Umbrales.** Todos figuran por fila en `ACHIEVEMENT_CATALOG_V1.md`; las 22 familias permanecen dentro del objetivo de 15-25.
12. **Rarezas.** `common`, `uncommon`, `rare`, `epic` y `legendary`, asignadas por dificultad y separadas del nivel deportivo.
13. **Logros con caja.** Todos y solo los logros colectivos activos; cada participante canónico recibe su caja personal.
14. **Logros sin caja.** Todos los individuales; tampoco generan puntos ni cosméticos directos.
15. **Media de cajas.** En doce meses: 1,77-2,76 por partido. Peor arranque simulado: 3,33.
16. **p50/p90.** En doce meses p50 2-3 y p90 3-4. Máximo p90 de todos los escenarios: 6.
17. **Simulación casual.** 13/26/52 partidos, tres tasas de victoria; resultados completos en `REWARD_ECONOMY_V1_SIMULATION.md`.
18. **Simulación activa.** 26/52/104 partidos, tres tasas de victoria; mismos pools y primera caja mejorada.
19. **Simulación muy activa.** 52/104/208 partidos. El escenario anual al 85% produce 516,8 cajas y 4.249,67 puntos.
20. **Inflación.** Un máximo de 10 solo aparece por coincidencia de primeras veces e hitos. Los hitos únicos se sellan por familia y umbral en la simulación y en PostgreSQL.
21. **Migración.** `20260808185802_achievement_catalog_v2.sql`, forward-only, con `lock_timeout` 5 s y `statement_timeout` 120 s.
22. **RPC modificada.** `get_pachanga_progression_snapshot_v1` conserva su nombre público y añade read models canónicos de catálogo, estadísticas y récords.
23. **Cambios de catálogo.** Metadatos versionados para familia, prioridad, icono, primera vez, caja, pool, animación, presentación, texto social, temporada futura y secuencia de activación.
24. **Tests.** 103 pruebas de aplicación verdes; tres suites SQL verdes, incluida una secuencia de 500 partidos.
25. **Rating V2.** Intacto por prueba de contrato y comparación SQL byte a byte de overall, facetas, fiabilidad y versión.
26. **QA escritorio.** Preview autenticada 1440x900 sin overflow horizontal; Logros, Estadísticas y Récords muestran el read model canónico y la consola no contiene errores.
27. **QA móvil vertical.** Preview autenticada 390x844 sin overflow horizontal; pestañas, tarjetas, estadísticas, récords y colección conservan una composición legible.
28. **QA móvil horizontal.** Preview autenticada 844x390 sin overflow horizontal; la progresión utiliza todo el ancho disponible y mantiene visibles sus controles.
29. **Preview.** Deployment aislado `dpl_94iuPWTFhdL2sMfjCNNb1QDYFTRi`, conectado exclusivamente a Supabase staging `iozcjirlfytryzrcmrnq`; el bundle no contiene la referencia de producción.
30. **Commit.** `ccf99b35a3fa8d35d978723aa6f2cb2196cfd38b` (`Add definitive achievement catalog V1`).
31. **PR.** Borrador [#111](https://github.com/puntoracingrc/pachangas/pull/111), abierto antes de modificar staging.
32. **FUTURE.** Portero, MVP rival, triple hat-trick, goles 750/1000, rankings, temporadas, tienda, pase premium, tarjetas sociales y umbral por modalidad.
33. **Riesgos reales.** La victoria externa repetible sigue siendo la principal fuente de cajas; se mantiene porque la simulación anual no muestra crecimiento explosivo. El catálogo pequeño eleva duplicados con alta actividad.
34. **Sin retroactividad.** Las definiciones guardan `activation_server_sequence`; hechos anteriores actualizan estadísticas, pero no generan grants ni cajas V2.
35. **Fuera de alcance.** No se implementaron tienda, pase premium, rankings, MVP ni reconocimiento individual de portero.
36. **Producción.** No se tocó antes de superar Preview, staging y E2E. Tras integrar el PR verde se aplicó exclusivamente `20260808185802_achievement_catalog_v2` y se desplegó `main` en producción.

## Validación local

- `npm test`: verde, build incluido, 103 pruebas.
- `npm run typecheck`: verde.
- lint focalizado: verde.
- lint global: 43 incidencias preexistentes fuera del alcance, en `app/page.tsx` y `app/theme-toggle.tsx`.
- SQL catálogo V2, logros/escudos y cajas colectivas: verde sobre instalación limpia.
- concurrencia de logros/escudos: verde.
- `git diff --check`: verde.

## Validación remota de staging

- Rama Supabase: `pwa-bridge-staging` (`iozcjirlfytryzrcmrnq`), hija del proyecto Pachangas y confirmada `ACTIVE_HEALTHY`.
- Historial remoto alineado con el repositorio hasta `20260808185802_achievement_catalog_v2`; no se reparó ni reescribió SQL aplicado.
- Catálogo remoto: 101 definiciones activas, 45 individuales, 56 colectivas y 22 familias.
- Escenarios canónicos: 5-0 con Pedro 3/Juan 2, 3-2 con segundo hat-trick y 1-0 para racha e hitos. El servidor generó 13 logros colectivos y 26 cajas para dos participantes.
- Jerarquía individual: una sola faceta goleadora máxima por jugador y partido; títulos `Primer hat-trick` y `Hat-trick`; cero recompensas individuales.
- Idempotencia: reevaluar el primer partido devolvió cero concesiones nuevas.
- Concurrencia: dos dispositivos abrieron la misma caja con dos `operationId`; quedaron dos recibos, una caja abierta, un evento y un único apunte económico.
- Realtime: tras la inicialización fría de la rama, entregó el `UPDATE` de revisión del usuario y el cliente recargó el snapshot confirmado.
- RLS: cada cuenta leyó solo sus 13 cajas; una escritura cruzada devolvió cero filas y un ledger falsificado fue rechazado.
- Corrección: anular el 3-2 revocó cuatro grants y seis cajas pendientes, recalculó a dos partidos/dos victorias y el replay de la corrección no alteró el resultado.
- Rating V2: overall, facetas, fiabilidad, versión y fechas de control permanecieron intactos.
- Limpieza: usuarios, grupos, perfiles, hechos, grants y notificaciones sintéticas quedaron todos a cero.

## Validación de producción

- PR [#111](https://github.com/puntoracingrc/pachangas/pull/111) fusionado mediante squash en `main` como `dee1fb7a64bfdc3c1806f98b52a13a07aa3c1932`.
- Historial Supabase alineado con el repositorio: `20260808185802_achievement_catalog_v2` es la única migración añadida por esta fase.
- Catálogo productivo: 101 definiciones activas, 45 individuales, 56 colectivas y 22 familias.
- Recompensas: las 45 definiciones individuales carecen de caja y las 56 colectivas tienen rareza, pool, animación y presentación configurados.
- Retroactividad: cero grants asociados al catálogo V2 inmediatamente después de instalarlo.
- Permisos: el snapshot canónico no es ejecutable por `anon` y sí por `authenticated`.
- Rating V2: staging y producción conservan 58 funciones de rating/assessment con el mismo hash `e1d702850b7433d4bc63ad323ecc614b`.
- Vercel: deployment productivo `dpl_ExYnppdbyFfUVAqTgkva4RZ2K7KQ`, estado `READY`, construido desde el SHA exacto de `main` y asignado a `pachangasiq.com` y `www.pachangasiq.com`.
- Smoke: `/` y `/equipo/identidad` responden HTTP 200; la demo productiva carga el equipo, partidos, alineación y ranking sin error visible.
- Observabilidad: Vercel no registró errores de runtime en la ventana posterior al despliegue.
- La QA autenticada destructiva se realizó íntegramente en staging; en producción solo se hicieron comprobaciones de lectura y no se crearon datos sintéticos.
