# Team Platform Restrictions V1 Report

Fecha: 2026-08-30 CEST

## Autoridad

Las restricciones Team son decisiones humanas, explícitas, versionadas y
separadas de Billing, Conduct, Triage, owner y actividad deportiva. Solo una
capability de plataforma puede aplicar, modificar, levantar o suspender.

El owner puede archivar su lifecycle o apelar, pero no retirar enforcement,
cambiar notas privadas, falsificar scopes ni enviar estado efectivo.

## Scopes canónicos

1. `PUBLIC_DISCOVERY`
2. `MARKETPLACE`
3. `SOCIAL_CHALLENGES`
4. `NEW_MATCH_CREATION`
5. `COMPETITION_REGISTRATION`
6. `COMPETITION_ORGANIZER`
7. `EXISTING_COMPETITION_OPERATIONS`
8. `TEAM_MEMBERSHIP_ADMINISTRATION`
9. `PUBLIC_PROFILE`

Los presets se materializan como filas versionadas:

| Preset | Scopes |
| --- | --- |
| `SOCIAL_ONLY` | Mercado y Retos. |
| `NEW_ACTIVITY_ONLY` | partidos nuevos, inscripción y organización. |
| `COMPETITION_ONLY` | inscripción y organización. |
| `FULL_PLATFORM_SUSPENSION` | los nueve scopes. |
| `CUSTOM` | combinación allowlisted explícita. |

## Guards transversales

Los triggers y helpers serializan contra la autoridad Team antes de permitir:

- publicar o renovar Mercado;
- crear/aceptar Retos;
- crear partidos nuevos;
- modificar membresía/roles;
- enviar o aceptar Registration Requests;
- crear `CompetitionEntry`;
- crear/revisar Organizer Access Application y grants;
- crear contextos u operaciones de competición.

Las RPC antiguas atraviesan los mismos límites de tabla y no pueden saltarse
la restricción. El cliente recibe `TEAM_OPERATIONALLY_RESTRICTED`, nunca un
éxito optimista.

## Aplicación y restauración

Una medida exige `operationId`, revisión esperada, confirmación, reason code,
mensaje público seguro, continuity policy, scopes, fechas de servidor y
expiración opcional. Las notas/evidencias privadas no salen del Control Center.

Levantar o modificar crea una revisión nueva; no edita la decisión histórica.
Restaurar no republica Mercado, perfiles ni solicitudes previas. El worker de
expiración usa lotes limitados, `SKIP LOCKED`, server time e idempotencia.

## Independencias demostradas

- owner suspendido y Team: independientes;
- Billing `past_due` y Team: `ACTIVE + CLEAR`;
- señal Conduct y Team: sin transición;
- Triage: sin autoridad;
- Club relacionado: sin capability de suspensión Team;
- sanción R5: sin enforcement universal;
- inactividad: sin transición.

## Privacidad, notificaciones y health

La proyección pública solo expone disponibilidad segura. Nunca incluye actor,
denuncia, evidencia, reviewer, Billing, mensajes privados ni Auth IDs.

Las notificaciones son idempotentes por operación y se limitan a owner/admins
autorizados, reviewer y organizador afectado. No se difunden a toda la
plantilla. `TeamOperationalHealth` detecta estados ausentes, expiraciones,
grants incompatibles, Entries afectadas, Mercado/Retos incompatibles, owner
ausente y revisiones inconsistentes; no repara silenciosamente.

## Evidencia

- Mercado y Retos bloqueados por `SOCIAL_ONLY`.
- Organizer Application y Competition Registration bloqueados por scope.
- owner anterior pierde autoridad después de transferir.
- escritura directa autenticada: denegada.
- invalidación pública: RLS activa; autoridades privadas: sin acceso cliente.
- 21 FKs detectadas por Advisor recibieron índice; staging no conserva ningún
  `unindexed_foreign_keys` Wave 8B.
