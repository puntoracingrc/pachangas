# Wave 8C Synthetic Season Incidents

Registro permanente de incidencias encontradas durante Wave 8C. Ninguna
incidencia se corrige silenciosamente: debe registrarse y clasificarse antes de
la correccion, y solo puede cerrarse tras reproducir el escenario original y
verificar una regresion.

La validacion de esta fase es exclusivamente Demo-only: Simulation World
aislado, Demo World saneado y canary productivo sintetico con `ROLLBACK` o
cleanup completo. No se utilizan Clubs, Teams, jugadores, arbitros,
organizadores ni destinatarios reales.

Clasificaciones admitidas:

- `PRODUCT_BUG`;
- `SECURITY_ISSUE`;
- `PRIVACY_ISSUE`;
- `SIMULATION_BUG`;
- `TESTABILITY_GAP`;
- `ENVIRONMENT_ISSUE`;
- `PERFORMANCE_ISSUE`;
- `NEEDS_PRODUCT_DECISION`.

| ID | Clasificacion | Estado | Incidencia | Correccion | Regresion |
| --- | --- | --- | --- | --- | --- |

## Criterio de cierre

Cada incidencia debe terminar como `fixed + regression_verified`, o permanecer
abierta con causa, impacto y bloqueo explicitos. Un fallo abierto que afecte
autoridad, seguridad, privacidad, migraciones, coherencia deportiva o cleanup
bloquea la release.
