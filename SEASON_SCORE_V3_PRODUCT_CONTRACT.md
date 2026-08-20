# Season Score V3 Product Contract

Estado: DRAFT

## Formula congelada

- Formula key: `season_score_v3`.
- Ventana: `recent_30`.
- Calidad: 55%.
- Competicion: 30%.
- Oposicion: 15%.
- Rating V2: entrada canónica de solo lectura.

## Elegibilidad de ranking

- 15 Retos validos.
- 6 rivales logicos.
- Fiabilidad Rating >= 0.45.
- Actividad <= 12 semanas.

## Readiness futuro de trofeo

- 25 Retos validos.
- 10 rivales logicos.
- Match confidence >= 0.72.
- Network diversity >= 0.68.
- Fiabilidad Rating >= 0.55.
- Actividad <= 12 semanas.

`award_readiness` no concede premios en esta release.

## Integridad

- Estrategia B+C: exclusion de evidencia no fiable y retencion de certificacion.
- No existe penalizacion secreta del score.
- No se crean sanciones, warnings ni casos de Conduct.
- Un participante pendiente conserva su posicion; no se promueve automaticamente al siguiente.

## Desempate

1. Raw Season Score.
2. Competitive confidence.
3. Rivales logicos.
4. Fiabilidad Rating.
5. Retos validos.
6. Fecha mas temprana al alcanzar el score.
7. Identificador estable.

## Ciclo de temporada

`draft -> open -> frozen -> closed -> archived`

Las transiciones son administrativas, server-authoritative, versionadas e idempotentes.
