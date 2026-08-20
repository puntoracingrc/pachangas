# Ranking Productization V1 Report

Estado: DRAFT

## Punto de partida

- `origin/main`: `cce6d5e68a34b10c3ae6cb2f8bbdb1d567465aeb`
- Rama: `codex/ranking-productization-v1`
- Alcance: R1 contrato y persistencia, R2 refresh y read model, R3 integridad/elegibilidad y R4 producto provincial.
- Fuera de alcance: premios provinciales, ranking autonomico productivo y ranking nacional productivo.

## Invariantes

- PostgreSQL sera la unica autoridad del ranking.
- Rating V2 sera una entrada de solo lectura y no se modificara.
- Conducta, rewards, cosmetics y billing no modificaran Season Score.
- No se concederan premios, cajas, puntos ni cosmeticos desde esta release.
- La UI leera read models canónicos ya calculados.

## Estado de implementacion

Pendiente de completar durante el PR.
