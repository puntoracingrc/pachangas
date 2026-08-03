-- PostgREST and the Supabase gateway treat SQLSTATE 40xxx as transaction
-- failures. Keep stale revisions as application conflicts so clients receive a
-- prompt HTTP 409 and can reload the canonical snapshot.

create or replace function public.pachanga_translate_http_conflict_v2(conflict_message text)
returns jsonb
language plpgsql
set search_path = pg_catalog
as $$
begin
  if conflict_message = 'Player cards and ratings are server managed' then
    raise sqlstate 'PT422'
      using message = conflict_message,
            detail = 'Cards and ratings can only be changed by authoritative rating operations.';
  end if;

  raise sqlstate 'PT409'
    using message = conflict_message,
          detail = 'The client revision is stale; reload the canonical snapshot.';
end;
$$;

revoke all on function public.pachanga_translate_http_conflict_v2(text)
from public, anon, authenticated, service_role;

alter function public.create_pachanga_guest_identity_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
  rename to create_pachanga_guest_identity_authoritative_v2_impl;
revoke all on function public.create_pachanga_guest_identity_authoritative_v2_impl(uuid, text, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.create_pachanga_guest_identity_authoritative_v2(
  target_group_id uuid,
  display_name text,
  contact_hint text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.create_pachanga_guest_identity_authoritative_v2_impl(
    target_group_id, display_name, contact_hint, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.create_pachanga_guest_identity_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.create_pachanga_guest_identity_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.ensure_pachanga_external_team_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
  rename to ensure_pachanga_external_team_authoritative_v2_impl;
revoke all on function public.ensure_pachanga_external_team_authoritative_v2_impl(uuid, text, text, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.ensure_pachanga_external_team_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  display_name text,
  zone text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.ensure_pachanga_external_team_authoritative_v2_impl(
    target_group_id, target_match_id, display_name, zone, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.ensure_pachanga_external_team_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.ensure_pachanga_external_team_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.finalize_pachanga_match_authoritative_v2(uuid, text, integer, integer, jsonb, uuid, bigint, jsonb)
  rename to finalize_pachanga_match_authoritative_v2_impl;
revoke all on function public.finalize_pachanga_match_authoritative_v2_impl(uuid, text, integer, integer, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.finalize_pachanga_match_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_score_a integer,
  target_score_b integer,
  target_scorers jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.finalize_pachanga_match_authoritative_v2_impl(
    target_group_id, target_match_id, target_score_a, target_score_b,
    target_scorers, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.finalize_pachanga_match_authoritative_v2(uuid, text, integer, integer, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.finalize_pachanga_match_authoritative_v2(uuid, text, integer, integer, jsonb, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid)
  rename to finalize_pachanga_match_if_current_impl;
revoke all on function public.finalize_pachanga_match_if_current_impl(uuid, bigint, text, jsonb, uuid)
from public, anon, authenticated;

create function public.finalize_pachanga_match_if_current(
  target_group_id uuid,
  expected_revision bigint,
  target_match_id text,
  next_payload jsonb,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.finalize_pachanga_match_if_current_impl(
    target_group_id, expected_revision, target_match_id, next_payload, operation_key
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid)
to authenticated, service_role;

alter function public.issue_pachanga_guest_rating_token_authoritative_v2(uuid, text, uuid, uuid, bigint, integer, jsonb)
  rename to issue_pachanga_guest_rating_token_authoritative_v2_impl;
revoke all on function public.issue_pachanga_guest_rating_token_authoritative_v2_impl(uuid, text, uuid, uuid, bigint, integer, jsonb)
from public, anon, authenticated;

create function public.issue_pachanga_guest_rating_token_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_guest_id uuid,
  operation_id uuid,
  expected_revision bigint,
  expires_in_minutes integer default 1440,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.issue_pachanga_guest_rating_token_authoritative_v2_impl(
    target_group_id, target_match_id, target_guest_id, operation_id,
    expected_revision, expires_in_minutes, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.issue_pachanga_guest_rating_token_authoritative_v2(uuid, text, uuid, uuid, bigint, integer, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.issue_pachanga_guest_rating_token_authoritative_v2(uuid, text, uuid, uuid, bigint, integer, jsonb)
to authenticated, service_role;

alter function public.link_pachanga_guest_identity_authoritative_v2(uuid, uuid, uuid, text, uuid, bigint, jsonb)
  rename to link_pachanga_guest_identity_authoritative_v2_impl;
revoke all on function public.link_pachanga_guest_identity_authoritative_v2_impl(uuid, uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.link_pachanga_guest_identity_authoritative_v2(
  target_group_id uuid,
  target_guest_id uuid,
  target_user_id uuid,
  reason text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.link_pachanga_guest_identity_authoritative_v2_impl(
    target_group_id, target_guest_id, target_user_id, reason,
    operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.link_pachanga_guest_identity_authoritative_v2(uuid, uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.link_pachanga_guest_identity_authoritative_v2(uuid, uuid, uuid, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.link_pachanga_registered_opponent_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
  rename to link_pachanga_registered_opponent_authoritative_v2_impl;
revoke all on function public.link_pachanga_registered_opponent_authoritative_v2_impl(uuid, text, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.link_pachanga_registered_opponent_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  opponent_team_code text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.link_pachanga_registered_opponent_authoritative_v2_impl(
    target_group_id, target_match_id, opponent_team_code, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.link_pachanga_registered_opponent_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.link_pachanga_registered_opponent_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.moderate_pachanga_individual_rating_v2(uuid, uuid, text, uuid, bigint, jsonb)
  rename to moderate_pachanga_individual_rating_v2_impl;
revoke all on function public.moderate_pachanga_individual_rating_v2_impl(uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.moderate_pachanga_individual_rating_v2(
  target_group_id uuid,
  target_moderation_id uuid,
  reason text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.moderate_pachanga_individual_rating_v2_impl(
    target_group_id, target_moderation_id, reason, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.moderate_pachanga_individual_rating_v2(uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.moderate_pachanga_individual_rating_v2(uuid, uuid, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.patch_pachanga_match_lineup_authoritative_v2(uuid, text, boolean, text[], text[], text, uuid, bigint, jsonb)
  rename to patch_pachanga_match_lineup_authoritative_v2_impl;
revoke all on function public.patch_pachanga_match_lineup_authoritative_v2_impl(uuid, text, boolean, text[], text[], text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.patch_pachanga_match_lineup_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  next_lineup_closed boolean,
  target_team_a_ids text[],
  target_team_b_ids text[],
  target_payer_id text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.patch_pachanga_match_lineup_authoritative_v2_impl(
    target_group_id, target_match_id, next_lineup_closed, target_team_a_ids,
    target_team_b_ids, target_payer_id, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.patch_pachanga_match_lineup_authoritative_v2(uuid, text, boolean, text[], text[], text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.patch_pachanga_match_lineup_authoritative_v2(uuid, text, boolean, text[], text[], text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.patch_pachanga_match_player_paid_authoritative_v2(uuid, text, text, boolean, uuid, bigint, jsonb)
  rename to patch_pachanga_match_player_paid_authoritative_v2_impl;
revoke all on function public.patch_pachanga_match_player_paid_authoritative_v2_impl(uuid, text, text, boolean, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.patch_pachanga_match_player_paid_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_paid boolean,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.patch_pachanga_match_player_paid_authoritative_v2_impl(
    target_group_id, target_match_id, target_player_id, next_paid,
    operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.patch_pachanga_match_player_paid_authoritative_v2(uuid, text, text, boolean, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.patch_pachanga_match_player_paid_authoritative_v2(uuid, text, text, boolean, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.patch_pachanga_match_player_status_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
  rename to patch_pachanga_match_player_status_authoritative_v2_impl;
revoke all on function public.patch_pachanga_match_player_status_authoritative_v2_impl(uuid, text, text, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.patch_pachanga_match_player_status_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_status text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.patch_pachanga_match_player_status_authoritative_v2_impl(
    target_group_id, target_match_id, target_player_id, next_status,
    operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.patch_pachanga_match_player_status_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.patch_pachanga_match_player_status_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.patch_pachanga_match_scorers_authoritative_v2(uuid, text, integer, integer, jsonb, text[], text[], uuid, bigint, jsonb)
  rename to patch_pachanga_match_scorers_authoritative_v2_impl;
revoke all on function public.patch_pachanga_match_scorers_authoritative_v2_impl(uuid, text, integer, integer, jsonb, text[], text[], uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.patch_pachanga_match_scorers_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_score_a integer,
  target_score_b integer,
  next_scorers jsonb,
  target_team_a_ids text[],
  target_team_b_ids text[],
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.patch_pachanga_match_scorers_authoritative_v2_impl(
    target_group_id, target_match_id, target_score_a, target_score_b,
    next_scorers, target_team_a_ids, target_team_b_ids, operation_id,
    expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.patch_pachanga_match_scorers_authoritative_v2(uuid, text, integer, integer, jsonb, text[], text[], uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.patch_pachanga_match_scorers_authoritative_v2(uuid, text, integer, integer, jsonb, text[], text[], uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.patch_pachanga_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  rename to patch_pachanga_player_profile_authoritative_v2_impl;
revoke all on function public.patch_pachanga_player_profile_authoritative_v2_impl(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.patch_pachanga_player_profile_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.patch_pachanga_player_profile_authoritative_v2_impl(
    target_group_id, target_player_id, player_patch, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.patch_pachanga_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.patch_pachanga_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.persist_pachanga_player_assessment_authoritative_v2(uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb)
  rename to persist_pachanga_player_assessment_authoritative_v2_impl;
revoke all on function public.persist_pachanga_player_assessment_authoritative_v2_impl(uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.persist_pachanga_player_assessment_authoritative_v2(
  p_actor_user_id uuid,
  p_target_group_id uuid,
  p_target_player_id text,
  p_assessment_kind text,
  p_assessment_input jsonb,
  p_assessment_result jsonb,
  p_operation_id uuid,
  p_expected_revision bigint,
  p_client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.persist_pachanga_player_assessment_authoritative_v2_impl(
    p_actor_user_id, p_target_group_id, p_target_player_id, p_assessment_kind,
    p_assessment_input, p_assessment_result, p_operation_id, p_expected_revision, p_client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.persist_pachanga_player_assessment_authoritative_v2(uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.persist_pachanga_player_assessment_authoritative_v2(uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb)
to service_role;

alter function public.record_pachanga_global_rating_authoritative_v2(uuid, text, text, text, uuid, uuid, uuid, uuid, bigint, jsonb)
  rename to record_pachanga_global_rating_authoritative_v2_impl;
revoke all on function public.record_pachanga_global_rating_authoritative_v2_impl(uuid, text, text, text, uuid, uuid, uuid, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.record_pachanga_global_rating_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_kind text,
  comparison text,
  target_guest_id uuid,
  target_external_team_id uuid,
  rated_group_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.record_pachanga_global_rating_authoritative_v2_impl(
    target_group_id, target_match_id, target_kind, comparison, target_guest_id,
    target_external_team_id, rated_group_id, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.record_pachanga_global_rating_authoritative_v2(uuid, text, text, text, uuid, uuid, uuid, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.record_pachanga_global_rating_authoritative_v2(uuid, text, text, text, uuid, uuid, uuid, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.record_pachanga_guest_team_rating_token_v2(text, text, uuid, bigint, jsonb)
  rename to record_pachanga_guest_team_rating_token_v2_impl;
revoke all on function public.record_pachanga_guest_team_rating_token_v2_impl(text, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.record_pachanga_guest_team_rating_token_v2(
  claim_token text,
  comparison text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.record_pachanga_guest_team_rating_token_v2_impl(
    claim_token, comparison, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.record_pachanga_guest_team_rating_token_v2(text, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.record_pachanga_guest_team_rating_token_v2(text, text, uuid, bigint, jsonb)
to anon, authenticated, service_role;

alter function public.record_pachanga_individual_rating_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  rename to record_pachanga_individual_rating_authoritative_v2_impl;
revoke all on function public.record_pachanga_individual_rating_authoritative_v2_impl(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.record_pachanga_individual_rating_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  comparisons jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.record_pachanga_individual_rating_authoritative_v2_impl(
    target_group_id, target_player_id, comparisons, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.record_pachanga_individual_rating_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.record_pachanga_individual_rating_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.request_pachanga_open_match_authoritative_v2(uuid, uuid, bigint, jsonb)
  rename to request_pachanga_open_match_authoritative_v2_impl;
revoke all on function public.request_pachanga_open_match_authoritative_v2_impl(uuid, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.request_pachanga_open_match_authoritative_v2(
  target_open_match_id uuid,
  operation_id uuid,
  expected_match_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.request_pachanga_open_match_authoritative_v2_impl(
    target_open_match_id, operation_id, expected_match_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.request_pachanga_open_match_authoritative_v2(uuid, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.request_pachanga_open_match_authoritative_v2(uuid, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.reverse_pachanga_guest_link_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
  rename to reverse_pachanga_guest_link_authoritative_v2_impl;
revoke all on function public.reverse_pachanga_guest_link_authoritative_v2_impl(uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.reverse_pachanga_guest_link_authoritative_v2(
  target_group_id uuid,
  target_guest_id uuid,
  reason text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.reverse_pachanga_guest_link_authoritative_v2_impl(
    target_group_id, target_guest_id, reason, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.reverse_pachanga_guest_link_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.reverse_pachanga_guest_link_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.review_pachanga_open_match_request_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
  rename to review_pachanga_open_match_request_authoritative_v2_impl;
revoke all on function public.review_pachanga_open_match_request_authoritative_v2_impl(uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.review_pachanga_open_match_request_authoritative_v2(
  target_group_id uuid,
  target_request_id uuid,
  next_status text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.review_pachanga_open_match_request_authoritative_v2_impl(
    target_group_id, target_request_id, next_status, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.review_pachanga_open_match_request_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.review_pachanga_open_match_request_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.revoke_pachanga_guest_rating_token_authoritative_v2(uuid, uuid, uuid, bigint, jsonb)
  rename to revoke_pachanga_guest_rating_token_authoritative_v2_impl;
revoke all on function public.revoke_pachanga_guest_rating_token_authoritative_v2_impl(uuid, uuid, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.revoke_pachanga_guest_rating_token_authoritative_v2(
  target_group_id uuid,
  target_token_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.revoke_pachanga_guest_rating_token_authoritative_v2_impl(
    target_group_id, target_token_id, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.revoke_pachanga_guest_rating_token_authoritative_v2(uuid, uuid, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.revoke_pachanga_guest_rating_token_authoritative_v2(uuid, uuid, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.save_pachanga_payload_authoritative_v2(uuid, bigint, jsonb, uuid, jsonb)
  rename to save_pachanga_payload_authoritative_v2_impl;
revoke all on function public.save_pachanga_payload_authoritative_v2_impl(uuid, bigint, jsonb, uuid, jsonb)
from public, anon, authenticated;

create function public.save_pachanga_payload_authoritative_v2(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb,
  operation_id uuid,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.save_pachanga_payload_authoritative_v2_impl(
    target_group_id, expected_revision, next_payload, operation_id, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.save_pachanga_payload_authoritative_v2(uuid, bigint, jsonb, uuid, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.save_pachanga_payload_authoritative_v2(uuid, bigint, jsonb, uuid, jsonb)
to authenticated, service_role;

alter function public.save_pachanga_payload_if_current(uuid, bigint, jsonb)
  rename to save_pachanga_payload_if_current_impl;
revoke all on function public.save_pachanga_payload_if_current_impl(uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.save_pachanga_payload_if_current(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.save_pachanga_payload_if_current_impl(target_group_id, expected_revision, next_payload);
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.set_pachanga_group_ratings_enabled_authoritative_v2(uuid, boolean, uuid, bigint, jsonb)
  rename to set_pachanga_group_ratings_enabled_authoritative_v2_impl;
revoke all on function public.set_pachanga_group_ratings_enabled_authoritative_v2_impl(uuid, boolean, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.set_pachanga_group_ratings_enabled_authoritative_v2(
  target_group_id uuid,
  next_enabled boolean,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.set_pachanga_group_ratings_enabled_authoritative_v2_impl(
    target_group_id, next_enabled, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.set_pachanga_group_ratings_enabled_authoritative_v2(uuid, boolean, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.set_pachanga_group_ratings_enabled_authoritative_v2(uuid, boolean, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.sync_pachanga_market_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  rename to sync_pachanga_market_profile_authoritative_v2_impl;
revoke all on function public.sync_pachanga_market_profile_authoritative_v2_impl(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.sync_pachanga_market_profile_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  market_intent jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.sync_pachanga_market_profile_authoritative_v2_impl(
    target_group_id, target_player_id, market_intent, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.sync_pachanga_market_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.sync_pachanga_market_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.sync_pachanga_open_match_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  rename to sync_pachanga_open_match_authoritative_v2_impl;
revoke all on function public.sync_pachanga_open_match_authoritative_v2_impl(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.sync_pachanga_open_match_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  match_patch jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.sync_pachanga_open_match_authoritative_v2_impl(
    target_group_id, target_match_id, match_patch, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.sync_pachanga_open_match_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.sync_pachanga_open_match_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.upsert_pachanga_own_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  rename to upsert_pachanga_own_player_profile_authoritative_v2_impl;
revoke all on function public.upsert_pachanga_own_player_profile_authoritative_v2_impl(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.upsert_pachanga_own_player_profile_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.upsert_pachanga_own_player_profile_authoritative_v2_impl(
    target_group_id, target_player_id, player_patch, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.upsert_pachanga_own_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.upsert_pachanga_own_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
to authenticated, service_role;

alter function public.void_my_pachanga_individual_rating_v2(uuid, text, uuid, bigint, jsonb)
  rename to void_my_pachanga_individual_rating_v2_impl;
revoke all on function public.void_my_pachanga_individual_rating_v2_impl(uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated;

create function public.void_my_pachanga_individual_rating_v2(
  evidence_id uuid,
  reason text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  return public.void_my_pachanga_individual_rating_v2_impl(
    evidence_id, reason, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.void_my_pachanga_individual_rating_v2(uuid, text, uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.void_my_pachanga_individual_rating_v2(uuid, text, uuid, bigint, jsonb)
to authenticated, service_role;

-- PL/pgSQL allows parameters to be qualified with the function name. Renaming
-- the implementation does not rewrite those textual qualifiers, so preserve
-- them explicitly before any wrapper can invoke the implementation.
do $migration$
declare
  implementation record;
  definition text;
  rewritten text;
  inspected_count integer := 0;
begin
  for implementation in
    select procedures.oid, procedures.proname::text as implementation_name
    from pg_proc procedures
    join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
    where namespaces.nspname = 'public'
      and procedures.proname = any(array[
        'create_pachanga_guest_identity_authoritative_v2_impl',
        'ensure_pachanga_external_team_authoritative_v2_impl',
        'finalize_pachanga_match_authoritative_v2_impl',
        'finalize_pachanga_match_if_current_impl',
        'issue_pachanga_guest_rating_token_authoritative_v2_impl',
        'link_pachanga_guest_identity_authoritative_v2_impl',
        'link_pachanga_registered_opponent_authoritative_v2_impl',
        'moderate_pachanga_individual_rating_v2_impl',
        'patch_pachanga_match_lineup_authoritative_v2_impl',
        'patch_pachanga_match_player_paid_authoritative_v2_impl',
        'patch_pachanga_match_player_status_authoritative_v2_impl',
        'patch_pachanga_match_scorers_authoritative_v2_impl',
        'patch_pachanga_player_profile_authoritative_v2_impl',
        'persist_pachanga_player_assessment_authoritative_v2_impl',
        'record_pachanga_global_rating_authoritative_v2_impl',
        'record_pachanga_guest_team_rating_token_v2_impl',
        'record_pachanga_individual_rating_authoritative_v2_impl',
        'request_pachanga_open_match_authoritative_v2_impl',
        'reverse_pachanga_guest_link_authoritative_v2_impl',
        'review_pachanga_open_match_request_authoritative_v2_impl',
        'revoke_pachanga_guest_rating_token_authoritative_v2_impl',
        'save_pachanga_payload_authoritative_v2_impl',
        'save_pachanga_payload_if_current_impl',
        'set_pachanga_group_ratings_enabled_authoritative_v2_impl',
        'sync_pachanga_market_profile_authoritative_v2_impl',
        'sync_pachanga_open_match_authoritative_v2_impl',
        'upsert_pachanga_own_player_profile_authoritative_v2_impl',
        'void_my_pachanga_individual_rating_v2_impl'
      ]::name[])
  loop
    inspected_count := inspected_count + 1;
    definition := pg_get_functiondef(implementation.oid);
    rewritten := replace(
      definition,
      regexp_replace(implementation.implementation_name, '_impl$', '') || '.',
      implementation.implementation_name || '.'
    );
    if rewritten <> definition then
      execute rewritten;
    end if;
  end loop;

  if inspected_count <> 28 then
    raise exception 'Expected 28 Rating V2 implementations, found %', inspected_count;
  end if;
end;
$migration$;
