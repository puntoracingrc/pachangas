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
26. **QA escritorio.** Shell local 1440x900 sin overflow; QA autenticada del contenido queda pendiente de staging.
27. **QA móvil vertical.** Shell local 390x844 sin overflow; QA autenticada del contenido queda pendiente de staging.
28. **QA móvil horizontal.** Rectángulos reales 844x390 sin overflow ni errores de consola; QA autenticada queda pendiente de staging.
29. **Preview.** Pendiente de publicar la rama y obtener el despliegue de Vercel.
30. **Commit.** Pendiente en el momento de crear este informe.
31. **PR.** Debe abrirse como borrador antes de staging.
32. **FUTURE.** Portero, MVP rival, triple hat-trick, goles 750/1000, rankings, temporadas, tienda, pase premium, tarjetas sociales y umbral por modalidad.
33. **Riesgos reales.** La victoria externa repetible sigue siendo la principal fuente de cajas; se mantiene porque la simulación anual no muestra crecimiento explosivo. El catálogo pequeño eleva duplicados con alta actividad.
34. **Sin retroactividad.** Las definiciones guardan `activation_server_sequence`; hechos anteriores actualizan estadísticas, pero no generan grants ni cajas V2.
35. **Fuera de alcance.** No se implementaron tienda, pase premium, rankings, MVP ni reconocimiento individual de portero.
36. **Producción.** No se ha tocado antes de Preview, staging y E2E; cualquier producción dependerá de que esas fases terminen verdes.

## Validación local

- `npm test`: verde, build incluido, 103 pruebas.
- `npm run typecheck`: verde.
- lint focalizado: verde.
- lint global: 43 incidencias preexistentes fuera del alcance, en `app/page.tsx` y `app/theme-toggle.tsx`.
- SQL catálogo V2, logros/escudos y cajas colectivas: verde sobre instalación limpia.
- concurrencia de logros/escudos: verde.
- `git diff --check`: verde.
