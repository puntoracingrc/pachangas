# Season Ranking Lab V1

Laboratorio reproducible y exclusivamente sintético para Season Score, rankings territoriales y señales de integridad. No contiene migraciones, llamadas a Supabase, escrituras de usuarios reales ni cambios en Rating V2.

## Ejecutar

```bash
npm run test:season-ranking-lab
npm run test:season-ranking-elite
npm run lab:season-ranking
npm run lab:season-ranking:elite
npm run lab:season-ranking:v3
```

La semilla, población, fórmulas, elegibilidad, decaimiento por rival, volumen, actividad e integridad viven en `season_score_config.json`. El comando genera de nuevo `results/` y el informe `docs/season-ranking-lab-v1-report.md`.

La validación de élite continúa el mismo laboratorio con métricas provinciales/autonómicas/nacionales, tres ground truths, corte out-of-sample 70/30, bootstrap #10/#11, leave-one-out, 20 seeds de 10.000 jugadores y ataque específico al corte. Genera `results/elite/` y `docs/season-ranking-elite-validation.md`.

V3 mantiene la fórmula finalista y añade, solo en laboratorio, rival lógico, independencia, confianza competitiva, estrategias A/B/C y certificación de trofeo. Ejecuta 30 seeds de 10.000 jugadores, ataques mixtos, colusión, participación fantasma, falsos positivos, corte #15→#9 y readiness separado por ámbito. Genera `results/v3/` y `docs/season-ranking-v3-validation.md`.

## Límites

- Solo `challenge` con estado `confirmed` o `auto_confirmed` aporta Season Score.
- Goles y posición se conservan como datos sintéticos, pero no entran en la fórmula.
- Rating V2 es una entrada de solo lectura y no se recalcula.
- Ceuta y Melilla son territorios base y nacionales; no se inventa una comunidad autónoma para ellas.
- `ranking_integrity_risk` es diagnóstico, no sanción, acusación ni auto-ban.
- Los resultados no son una especificación de producción: sirven para comparar y volver a atacar candidatos.
