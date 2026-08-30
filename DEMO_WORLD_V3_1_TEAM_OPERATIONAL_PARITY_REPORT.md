# Demo World V3.1 Team Operational Parity Report

Fecha: 2026-08-30 CEST

## Política

Demo World V3.1 procede exclusivamente de Simulation World con PostgreSQL
temporal, identidades sintéticas y RPC productivas reales. El snapshot público
es saneado, GET-only, sin Auth IDs, PII, escritura remota o indexación como
competición real. V2.1-V2.9 y V3.0 permanecen inmutables.

## Escenarios

| Escenario | Estado | Evidencia principal |
| --- | --- | --- |
| Team A | `ACTIVE + CLEAR` | Mercado, Retos e inscripción permitidos. |
| Team B | `UNDER_REVIEW` | Cero bloqueo automático y revisión no pública. |
| Team C | `LIMITED / SOCIAL_ONLY` | Mercado/Retos bloqueados; Liga vigente continúa. |
| Team D | `SUSPENDED / NEW_ACTIVITY_ONLY` | Nueva inscripción bloqueada; historia conservada. |
| Team E | `ARCHIVED` | Fuera de directorio, presente en historia. |
| Team F | owner transfer | Restricción preservada; owner nuevo apela. |
| Team G | Billing inactive | Team permanece `ACTIVE + CLEAR`. |

## Autoridad y hashes

- Seed: `pachangas-iq-demo-world-v3-1-2026-27`.
- Manifest hash lógico: `7d1de10a66147c7da53a062db4d96f59fa4b592b0dce6ef9c749044314dcd53c`.
- Team authority hash: `8813ba4f33eda8ba6e9a75de2572d31747c7fe613a3d71c4733c5625c3539a7c`.
- Continuity projection hash: `d4e7f2c6bef4e8c807335bc61037512496e8ae6013be0355f88cbcdca51da0db`.
- Ledger de Simulation World: 212 migraciones.
- Operaciones Team: 7 receipts.
- Owner transfer: 1 receipt.
- Secuencia de servidor: verificada.
- Remote writes: 0.

## Preservación

- Rating snapshots: intactos.
- Rewards: intactos.
- Player/Team Cosmetics: intactos.
- resultados oficiales: intactos por la restricción.
- standings reescritos por restricción: no.
- no-shows automáticos: 0.
- forfeits automáticos: 0.

Team C cambia de 7 a 10 puntos por un resultado oficial 3-1, no por su
limitación. Team D conserva su resultado histórico y no genera sanción
deportiva automática.

## Privacidad y transporte

Las comprobaciones `containsEmail`, `containsPhone`, `containsAuthUuid`,
`containsBillingId`, `containsPrivateMessage`, `containsPrivateEvidence` y
`containsReviewerIdentity` son todas `false`. El navegador usa únicamente
`GET`, read models congelados y caché derivada del Service Worker.

## Estado

El seed y la proyección semántica saneada de Simulation World son
deterministas y verificables. La segunda ejecución sin exportar confirmó el
mismo snapshot canónico (`snapshotIdentical: true`), sin escrituras remotas y
con destrucción completa de PostgreSQL temporal. Su publicación productiva y
smoke PWA se documentan en el informe de release.
