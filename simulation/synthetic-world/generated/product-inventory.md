# Synthetic World product inventory

Generated from product SQL and client code at `93361fe0f22cafb8bd31fbde65fa055774ac0ca4+core-social-flows-closure-v1`. This file distinguishes definitions from active client or server-side activation paths; it is not proof that a remote environment has applied a migration.

## Counts

- RPC definitions: 287
- RPC called by the web client: 82
- Product tables: 100
- Mutable table targets in the web client: 3
- Achievement keys found: 84
- Notification/status literals found: 63
- Time-dependent SQL lines: 456

## Capability matrix

| Area | Flow | Classification | Located contracts | Active route or trigger |
| --- | --- | --- | --- | --- |
| teams | Crear equipo | implemented | pachanga_groups | pachanga_groups |
| teams | Invitar y aceptar miembro | implemented | join_pachanga_team | join_pachanga_team |
| teams | Invitar y aceptar admin | implemented | create_pachanga_admin_invite, accept_pachanga_admin_invite_authoritative_v1 | create_pachanga_admin_invite, accept_pachanga_admin_invite_authoritative_v1 |
| teams | Abandonar grupo | implemented | leave_pachanga_group_authoritative_v1 | leave_pachanga_group_authoritative_v1 |
| teams | Eliminar miembro | implemented | remove_pachanga_group_member_authoritative_v1 | remove_pachanga_group_member_authoritative_v1 |
| teams | Transferir propiedad | implemented | transfer_pachanga_group_ownership_authoritative_v1 | transfer_pachanga_group_ownership_authoritative_v1 |
| challenges | Crear reto | implemented | create_pachanga_team_challenge_authoritative | create_pachanga_team_challenge_authoritative |
| challenges | Aceptar, rechazar o contrapropuesta | implemented | respond_pachanga_team_challenge_authoritative | respond_pachanga_team_challenge_authoritative |
| challenges | Caducar reto | implemented | reconcile_pachanga_team_challenge_expiry_v1 | reconcile_pachanga_team_challenge_expiry_v1 (server-side) |
| market | Partido publico completo | implemented | sync_pachanga_open_match_authoritative_v2, request_pachanga_open_match_authoritative_v2, review_pachanga_open_match_request_authoritative_v2 | sync_pachanga_open_match_authoritative_v2, request_pachanga_open_match_authoritative_v2, review_pachanga_open_match_request_authoritative_v2 |
| market | Abandonar plaza invitada | implemented | leave_pachanga_guest_match_v1 | leave_pachanga_guest_match_v1 |
| market | Jugador busca equipo | implemented | sync_pachanga_market_profile_authoritative_v2 | sync_pachanga_market_profile_authoritative_v2 |
| matches | Confirmar asistencia | implemented | patch_pachanga_match_player_status_authoritative_v2 | patch_pachanga_match_player_status_authoritative_v2 |
| matches | Modificar alineacion | implemented | patch_pachanga_match_lineup_authoritative_v2 | patch_pachanga_match_lineup_authoritative_v2 |
| matches | Finalizar partido interno | implemented | finalize_pachanga_match_authoritative_v2 | finalize_pachanga_match_authoritative_v2 |
| results | Publicar resultado externo | implemented | publish_pachanga_external_result_v1 | publish_pachanga_external_result_v1 |
| results | Confirmar, rechazar o corregir resultado | implemented | confirm_pachanga_external_result_v1, reject_pachanga_external_result_change_v1, propose_pachanga_external_result_change_v1 | confirm_pachanga_external_result_v1, reject_pachanga_external_result_change_v1, propose_pachanga_external_result_change_v1 |
| results | Auto-confirmar por plazo | partially_implemented | run_pachanga_external_result_expiry_v1 | - |
| rating | Assessment inicial y avanzado | implemented | persist_pachanga_player_assessment_authoritative_v2 | persist_pachanga_player_assessment_authoritative_v2 |
| rating | Valoracion entre jugadores | implemented | record_pachanga_individual_rating_authoritative_v2 | record_pachanga_individual_rating_authoritative_v2 |
| progression | Evaluar logros | implemented | get_pachanga_progression_snapshot_v1 | get_pachanga_progression_snapshot_v1 |
| progression | Abrir caja | implemented | open_pachanga_reward_box_v2 | open_pachanga_reward_box_v2 |
| notifications | Leer y marcar notificaciones | implemented | get_pachanga_notification_center_v1, mark_pachanga_notification_read_v1 | get_pachanga_notification_center_v1, mark_pachanga_notification_read_v1 |
| integrity | Season Score V3 | implemented_lab | - | - |

## Interpretation

- `implemented`: a product contract exists and has an active client or server-side activation path.
- `partially_implemented`: at least one contract exists, but part of the requested flow lacks an active route.
- `not_implemented`: no matching product contract was located.
- `implemented_lab`: implemented only by the isolated Season Score laboratory and never presented as production behaviour.

The machine-readable inventory is `product-inventory.json`.
