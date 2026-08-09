# Season Ranking Lab V1

Laboratorio reproducible y exclusivamente sintético para Season Score, rankings territoriales y señales de integridad. No contiene migraciones, llamadas a Supabase, escrituras de usuarios reales ni cambios en Rating V2.

## Ejecutar

```bash
npm run test:season-ranking-lab
npm run lab:season-ranking
```

La semilla, población, fórmulas, elegibilidad, decaimiento por rival, volumen, actividad e integridad viven en `season_score_config.json`. El comando genera de nuevo `results/` y el informe `docs/season-ranking-lab-v1-report.md`.

## Límites

- Solo `challenge` con estado `confirmed` o `auto_confirmed` aporta Season Score.
- Goles y posición se conservan como datos sintéticos, pero no entran en la fórmula.
- Rating V2 es una entrada de solo lectura y no se recalcula.
- Ceuta y Melilla son territorios base y nacionales; no se inventa una comunidad autónoma para ellas.
- `ranking_integrity_risk` es diagnóstico, no sanción, acusación ni auto-ban.
- Los resultados no son una especificación de producción: sirven para comparar y volver a atacar candidatos.
