# Team Operational Appeals V1 Report

Fecha: 2026-08-30 CEST

## Modelo

Estados canónicos:

`DRAFT -> SUBMITTED -> UNDER_REVIEW -> UPHELD | MODIFIED | OVERTURNED`

Salidas adicionales: `WITHDRAWN`, `INADMISSIBLE`.

La apelación conserva subject revision, requested outcome, mensajes, deadline
de servidor, actor, revisión, server sequence, receipt y evento. Nunca edita o
borra la restricción original.

## Permisos

- owner actual: crear, enviar y retirar;
- owner anterior: denegado tras transferencia;
- Team admin: sin autoridad implícita;
- support/moderator/admin: solo según capability exacta;
- resolución: humana y de plataforma;
- service worker/offline: sin escritura.

Enviar una apelación no suspende la medida. `MODIFIED` puede materializar una
nueva decisión allowlisted; `OVERTURNED` crea la transición correspondiente.

## Privacidad

Owner recibe mensajes `OWNER_SAFE`. Notas y mensajes `PLATFORM_PRIVATE`,
evidencia, reviewer y actor permanecen en autoridad privada. La proyección
pública no revela que exista una apelación ni permite reconstruir identidades.

## Validación

Staging probó:

1. Team limitado;
2. transferencia de owner;
3. owner A ya no puede apelar;
4. owner B crea y envía la apelación;
5. restricción permanece `LIMITED`;
6. proyección pública mantiene PII, Auth IDs y notas privadas en cero.

Concurrencia local cubre appeal create vs platform restore: un solo resultado
canónico, revisión monotónica y cleanup completo.
