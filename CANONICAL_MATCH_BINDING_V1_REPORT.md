# Canonical Match Binding V1 Report

Estado: `AUDIT IN PROGRESS`

## Trazabilidad

Base auditada: `0ea46f1cfa797a253678b68a3ffb8d7456856c81`.

## Procedencias demostradas

| Source kind conceptual | Fuente actual | ID actual | Que representa | Decision R1 |
| --- | --- | --- | --- | --- |
| `GROUP_MATCH` | `pachanga_match_read_model` | `(group_id, match_id)` | Partido interno de un equipo/grupo | Una procedencia deportiva; requiere binding canonico |
| `OPEN_MATCH` | `pachanga_open_matches` | `id`, con `(source_group_id, source_match_id)` | Proyeccion publica del partido interno | Debe compartir el canonical ID de su `GROUP_MATCH`; nunca crea otro encuentro |
| `EXTERNAL_MATCH` | `pachanga_external_matches` | `id` | Partido compartido creado al aceptar un Reto | Una procedencia deportiva; requiere binding canonico |
| `TEAM_CHALLENGE` | `pachanga_team_challenges` | `id` | Intencion/procedencia que origina el partido externo | Provenance del mismo canonical ID que su `EXTERNAL_MATCH`, no un segundo partido |

Las invitaciones, accesos de invitado y snapshots son superficies de acceso o
lectura. No son encuentros deportivos independientes.

## Relaciones ya existentes

- `pachanga_open_matches` contiene la referencia exacta al partido de grupo de
  origen mediante `source_group_id` y `source_match_id`.
- `pachanga_external_matches.challenge_id` es unico y referencia el Reto que lo
  origino.
- No se ha localizado una relacion autoritativa que demuestre que un partido de
  grupo concreto y un partido externo concreto sean el mismo encuentro.

Por ello el backfill no los fusionara por fecha, equipos ni marcador. Los casos
sin relacion estructural demostrable permaneceran separados; una posible
coincidencia se registrara para revision.

## Invariantes del diseno

```text
una procedencia activa -> un canonicalMatchId
un CompetitionMatchContext -> un canonicalMatchId
un canonicalMatchId -> como maximo un encuentro deportivo real
```

El backfill sera idempotente, conservara los IDs existentes y no modificara
resultados, participantes, Rating ni ningun payload deportivo.

## Evidencia pendiente

- Esquema y restricciones definitivos.
- Matriz de backfill repetido.
- Caso ambiguo sin fusion.
- Vinculo de laboratorio con CompetitionMatchContext.
- Invariantes antes/despues y metricas de escala.

