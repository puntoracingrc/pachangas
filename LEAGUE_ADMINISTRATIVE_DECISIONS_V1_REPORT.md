# League Administrative Decisions V1 Report

## Autoridad

`CompetitionAdministrativeDecision` es append-only y conserva competicion,
tipo, objetivo, authority assignment, RuleRevision, motivo, evidencia privada,
decision anterior, revision, operationId, secuencia y fecha de servidor.

Solo el organizador o un actor con capability contextual, incluido
`competition_operations_manager`, puede publicar una decision de su
competicion. El nuevo rol no puede editar reglas, Billing, Rating ni sanciones.

## Efectos tipados

R4D admite exclusivamente:

- `RESCHEDULE_MATCH`;
- `CHANGE_VENUE`;
- `CANCEL_MATCH`;
- `RESUME_FROM_MINUTE`;
- `ORDER_REPLAY`;
- `SET_OFFICIAL_RESULT`;
- `ANNUL_OFFICIAL_RESULT`.

El cliente envia una intencion semantica; PostgreSQL deriva el efecto y sus
valores. No se acepta SQL, pesos, snapshots ni resultados calculados por el
navegador.

Permanecen fail-closed y fuera de R4D:

- `DEDUCT_POINTS`;
- `CREATE_SANCTION`;
- `REVERSE_SANCTION_SERVICE`;
- `CREATE_COMPETITION_CHARGE`;
- `CREATE_COMPETITION_CREDIT`.

## Integracion con R4C

Cuando una decision cambia un resultado oficial:

1. crea una nueva `CompetitionOfficialResultDecision`;
2. supersede la anterior sin editarla;
3. reconstruye standings;
4. actualiza el estado de jornada;
5. crea receipt y evento;
6. emite invalidaciones acotadas.

Todo ocurre en una transaccion. La anulacion conserva lineage y el rebuild
incremental coincide con el full rebuild.

## Seguridad y privacidad

- INSERT/UPDATE/DELETE directos estan revocados a `anon` y `authenticated`;
- las funciones usan `SECURITY DEFINER`, `search_path=pg_catalog`, `auth.uid()`
  y tablas cualificadas;
- metadata de cliente queda allowlisted;
- evidencia, razon privada y actor interno no salen en lecturas publicas;
- Platform Admin no sustituye la capability deportiva contextual;
- R5, Billing y disciplina no tienen adaptador activo y fallan cerrado.

## Evidencia

Staging autentico verifico:

- publicacion, supersession y anulacion;
- resultado oficial por no-show;
- resolucion administrativa de una suspension;
- decision vs result correction concurrentes;
- dos decisiones simultaneas;
- un ganador y un `STALE_REVISION` en cada carrera;
- 5.000 decisiones en rollback;
- administrative decision desk a 4.003 ms;
- decision completa a 10.768 ms;
- rebuild de standings a 20.232 ms.

Negativos confirmados: actor ajeno, RuleRevision incorrecta, resultado
administrativo enviado por cliente, deduccion de puntos, sancion, multa y
escritura directa.

## Invariantes

No se modifica Rating V2, rewards, cosmetics, Conduct, disciplina, Billing,
Ranking, Clubs/Referees ni Referee Assignments. R5 no se ha iniciado.

## Resultado

`PASS / PENDIENTE DE RELEASE PRODUCTIVA INACTIVA`
