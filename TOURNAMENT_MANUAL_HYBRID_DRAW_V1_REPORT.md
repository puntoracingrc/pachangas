# Tournament Manual and Hybrid Draw V1 Report

## Estado

`STAGING AUTHENTICATED CERTIFIED / PRODUCTION PENDING`

## Acciones manuales

- colocar una entry en grupo/slot/seed;
- mover una entry;
- intercambiar dos entries;
- retirar una entry de la revision de trabajo;
- crear o soltar locks de grupo, slot, separacion, mitad o pot.

Cada accion exige permiso de Draw, `operationId`, revision esperada y motivo.
La accion crea una DrawRevision; nunca reescribe placements previos.

## HYBRID

HYBRID conserva locks validos y completa las posiciones restantes con el motor
determinista. Los placements distinguen `LOCKED`, `HYBRID_FILL`, `MANUAL` y
`ENGINE`. El checksum de locks entra en el input canonico y cualquier cambio
marca la revision previa como stale.

Locks contradictorios, dos equipos en una posicion o una entry que ya no forma
parte del freeze producen conflicto/unsatisfiable. El motor no resuelve una
contradiccion ignorando silenciosamente una orden manual.

## UX

Draw Desk muestra participantes, board, pots, constraints, locks, quality y
audit sin convertir el navegador en autoridad. Drag/drop envia intencion y
solo renderiza la respuesta confirmada. Offline conserva lectura local, bloquea
escrituras y no presenta fake success.

Viewports locales revisados:

- `1440x900`, `1920x1080`;
- `390x844`, `360x800`;
- `667x375`, `740x360`, `844x390`, `932x430`;
- PWA emulada.

Resultado: cero overflow raiz, controles cortados, imagenes rotas, errores de
consola o warnings de hidratacion. La PWA instalada real queda para Preview.

## Evidencia

- manual swap y lineage: `PASS`;
- dos locks + completion HYBRID: `PASS`;
- conflicto de locks: `PASS`;
- duplicate position: `PASS`;
- input freshness: `PASS`;
- validation/publication: `PASS`;
- revision actual seleccionada por ID/secuencia estable, no solo timestamp.

El E2E remoto completo intercambio dos participantes desbloqueados dentro de
un plan HYBRID, conservo dos locks, rechazo la edicion del plan automatico y
publicado, y convergio por Realtime al snapshot canonico. Ninguna accion manual
creo partidos ni reescribio revisiones anteriores.
