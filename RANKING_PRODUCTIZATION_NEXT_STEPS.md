# Ranking Productization Next Steps

Estado: propuesta de siguiente fase. No activa Season Score, rankings ni premios y no modifica formulas.

## Situacion actual

Season Score V3, diversidad de red, integridad y Territory Award Readiness estan validados como motores de laboratorio. El piloto provincial puede representar rankings y simular cierres, pero no existe una autoridad PostgreSQL productiva que publique una clasificacion oficial reproducible.

Clasificacion actual:

```text
Season Score V3        NEEDS_PRODUCTIZATION
Ranking provincial     NEEDS_PRODUCTIZATION
Premios provinciales   BLOCKED
```

## Hueco entre LAB y PRODUCT

| Pieza | Existe en LAB | Falta para PRODUCT |
| --- | ---: | --- |
| Formula Season Score congelada | Si | Registro versionado de formula activa y checksum |
| Evidencia deportiva | Si | Selector SQL canónico, revisionado y auditable |
| Persistencia de score | No | Snapshot por jugador/temporada/territorio |
| Read model | No | Ranking ordenado con revision y `server_sequence` |
| Refresh/rebuild | No | Job idempotente, incremental y reconstruccion verificable |
| Ciclo de temporada | Parcial | Borrador, abierta, congelada, cerrada, archivada |
| Territorio | Sintetico | Fuente canónica, historial de cambios y reglas de residencia/actividad |
| Eligibility | Motor | Evidencia persistida y reason codes publicables |
| Integrity/confidence | Motor | Casos, revisiones, caducidad y resultado canónico |
| API | No | RPC privada/admin y lectura publica minimizada |
| UI productiva | No | Ranking, ficha, explicaciones y estados pendientes |
| Awards | Simulacion | Ledger idempotente posterior a cierre certificado |
| Rollback | N/A | Despublicar sin borrar snapshots ni grants emitidos |

## Fase R1: contrato y persistencia

1. Congelar `season_score_v3` con `formula_version`, configuracion y checksum inmutables.
2. Definir temporadas y territorios canónicos con revisiones monotónicas.
3. Crear snapshots de score derivados de evidencia confirmada, nunca del navegador.
4. Guardar inputs resumidos, reason codes, confidence, eligibility e integrity separados del score.
5. Hacer que un snapshot apunte a la revision exacta de evidencia que lo produjo.
6. Prohibir que goles, posiciones, Rating V2, conducta o restricciones alteren la formula salvo contrato futuro explicito.

Gate de salida: el mismo dataset y version producen el mismo checksum y read model tras rebuild completo.

## Fase R2: refresh y read model

1. Implementar recalculo por eventos canónicos: partido externo confirmado/corregido, elegibilidad o integridad.
2. Mantener una cola duradera e idempotente con `operationId`, revision esperada y secuencia del servidor.
3. Crear ranking por territorio/temporada con desempate estable; nunca solo `ORDER BY created_at`.
4. Servir snapshots ya calculados; no recalcular al leer.
5. Cachear por revision y usar Realtime solo para invalidar la entidad cambiada.
6. Ofrecer rebuild administrativo que compare antes/despues y no publique hasta validar.

Gate de salida: incremental y rebuild convergen al mismo snapshot canónico bajo concurrencia.

## Fase R3: integridad y elegibilidad productivas

1. Persistir estados `eligible`, `pending_integrity_review`, `excluded` y sus reason codes.
2. Separar madurez territorial de confiabilidad individual.
3. Mantener campañas coordinadas, redes cerradas y evidencia insuficiente como revisiones explicables, no manipulaciones silenciosas del score.
4. Crear cola humana para casos pendientes antes de cierre.
5. Versionar toda correccion y conservar lineage.

Gate de salida: ataques de laboratorio, redes pequenas y falsos positivos quedan reproducidos en SQL y QA con datos no-PII.

## Fase R4: producto provincial

1. Añadir RPC admin de apertura/congelacion/cierre de temporada.
2. Añadir API publica minimizada con score, posicion, estado y explicacion segura.
3. Construir UI responsive y accesible en web/PWA, separada del laboratorio.
4. Añadir Control Center para salud del refresh, revision, backlog e incidencias.
5. Lanzar ranking sin premios primero mediante flag productivo real.

Gate de salida: una temporada piloto completa puede abrirse, actualizarse, congelarse y archivarse sin grants.

## Fase R5: premios provinciales

Solo despues de ranking productivo estable:

1. Definir `award_readiness` por territorio y temporada.
2. Exigir temporada cerrada, ranking congelado, elegibilidad e integridad resueltas.
3. Crear ledger de premio idempotente y no retroactivo.
4. Separar premio pendiente de investigacion de premio certificado.
5. Probar correccion, anulacion y restauracion sin doble grant.
6. Activar `provincial_awards_enabled` en una release independiente.

## Flags futuros sugeridos

Los nombres son propuesta, no contrato implementado:

```text
season_score_product_enabled
provincial_rankings_product_enabled
provincial_awards_enabled
```

Cada cambio deberia pasar por la RPC administrativa con revision, `operationId`, motivo y ledger. El flag de premios debe fallar cerrado si ranking, temporada o readiness no cumplen.

## Criterios no negociables

- PostgreSQL es la unica fuente de verdad.
- El cliente no calcula ni persiste scores definitivos.
- Rating V2, facetas, conducta, sanciones y cosmetics permanecen aislados.
- No hay awards desde snapshots LAB ni datos Synthetic World.
- No hay backfill/grants al encender un flag.
- Toda correccion conserva historial y es reconstruible.
- Los cinco Team Cosmetic Reward mappings actuales no se reutilizan ni cambian en esta fase.
- Premium Ball y Premium Art permanecen fuera del catalogo de rewards hasta decisiones separadas.
