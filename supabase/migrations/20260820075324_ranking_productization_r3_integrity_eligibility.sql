-- Ranking Productization V1 / R3.
-- Private integrity review and certification holds. No score penalties and no automatic sanctions.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table if not exists private.pachanga_ranking_integrity_reviews (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  snapshot_id uuid not null unique references private.pachanga_season_score_snapshots(id) on delete restrict,
  state text not null default 'pending',
  risk_classification text not null,
  risk_score numeric not null,
  private_reason_codes text[] not null default '{}',
  private_evidence jsonb not null,
  resolution text,
  resolution_reason text,
  resolved_by uuid references auth.users(id) on delete restrict,
  resolved_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (state in ('pending', 'approved', 'excluded', 'superseded')),
  check (risk_classification in ('watch', 'suspicious', 'high_risk')),
  check (risk_score between 0 and 100),
  check (jsonb_typeof(private_evidence) = 'object'),
  check (resolution is null or resolution in ('evidence_valid', 'evidence_excluded', 'superseded')),
  check (revision >= 1),
  check (
    (state = 'pending' and resolution is null and resolved_by is null and resolved_at is null)
    or (state in ('approved', 'excluded') and resolution is not null
      and resolved_by is not null and resolved_at is not null)
    or (state = 'superseded' and resolution = 'superseded' and resolved_at is not null)
  )
);

create index if not exists pachanga_ranking_integrity_reviews_queue_idx
  on private.pachanga_ranking_integrity_reviews(state, risk_score desc, server_sequence, id)
  where state = 'pending';
create index if not exists pachanga_ranking_integrity_reviews_subject_idx
  on private.pachanga_ranking_integrity_reviews(season_id, player_profile_id, server_sequence desc, id desc);

create table if not exists private.pachanga_ranking_integrity_review_events (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references private.pachanga_ranking_integrity_reviews(id) on delete restrict,
  operation_id uuid not null unique,
  event_type text not null,
  from_state text,
  to_state text not null,
  actor_user_id uuid references auth.users(id) on delete restrict,
  actor_role text not null,
  reason text not null,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (event_type in ('review_opened', 'review_approved', 'review_excluded', 'review_superseded')),
  check (from_state is null or from_state in ('pending', 'approved', 'excluded', 'superseded')),
  check (to_state in ('pending', 'approved', 'excluded', 'superseded')),
  check (actor_role in ('ranking_engine', 'platform_owner', 'platform_admin')),
  check (char_length(reason) between 3 and 1200),
  check (jsonb_typeof(payload) = 'object')
);

create index if not exists pachanga_ranking_integrity_review_events_review_idx
  on private.pachanga_ranking_integrity_review_events(review_id, server_sequence, id);

revoke all on table private.pachanga_ranking_integrity_reviews from public, anon, authenticated;
revoke all on table private.pachanga_ranking_integrity_review_events from public, anon, authenticated;
grant all on table private.pachanga_ranking_integrity_reviews to service_role;
grant all on table private.pachanga_ranking_integrity_review_events to service_role;

create or replace function private.pachanga_open_ranking_integrity_review_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved_review_id uuid;
  saved_operation_id uuid;
begin
  if new.eligibility_state <> 'pending_integrity_review' then return new; end if;

  update private.pachanga_ranking_integrity_reviews reviews
  set state = 'superseded',
      resolution = 'superseded',
      resolution_reason = 'A newer authoritative score snapshot replaced this review.',
      resolved_by = reviews.resolved_by,
      resolved_at = clock_timestamp(),
      revision = reviews.revision + 1,
      updated_at = clock_timestamp()
  where reviews.season_id = new.season_id
    and reviews.player_profile_id = new.player_profile_id
    and reviews.state = 'pending';

  insert into private.pachanga_ranking_integrity_reviews(
    season_id, player_profile_id, snapshot_id, risk_classification, risk_score,
    private_reason_codes, private_evidence
  ) values (
    new.season_id, new.player_profile_id, new.id,
    case when new.integrity_classification = 'clean' then 'watch' else new.integrity_classification end,
    new.integrity_risk, new.reason_codes,
    jsonb_build_object(
      'integrityDetails', new.integrity_details,
      'evidenceRevision', new.evidence_revision,
      'graphBatchId', new.graph_batch_id,
      'snapshotChecksum', new.snapshot_checksum
    )
  ) returning id into saved_review_id;

  saved_operation_id := private.pachanga_ranking_stable_uuid_v1('integrity-review-open:' || new.id::text);
  insert into private.pachanga_ranking_integrity_review_events(
    review_id, operation_id, event_type, from_state, to_state,
    actor_role, reason, payload
  ) values (
    saved_review_id, saved_operation_id, 'review_opened', null, 'pending',
    'ranking_engine', 'Authoritative ranking integrity hold created.',
    jsonb_build_object('snapshotId', new.id, 'riskClassification', new.integrity_classification)
  );
  return new;
end;
$$;

revoke all on function private.pachanga_open_ranking_integrity_review_v1()
  from public, anon, authenticated;
drop trigger if exists open_ranking_integrity_review_v1
  on private.pachanga_season_score_snapshots;
create trigger open_ranking_integrity_review_v1
after insert on private.pachanga_season_score_snapshots
for each row execute function private.pachanga_open_ranking_integrity_review_v1();

create or replace function private.pachanga_resolve_ranking_integrity_review_v1(
  target_review_id uuid,
  target_resolution text,
  expected_revision bigint,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_actor_role text,
  target_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected private.pachanga_ranking_integrity_reviews%rowtype;
  replay private.pachanga_ranking_operation_receipts%rowtype;
  next_state text;
  response jsonb;
begin
  if target_review_id is null or target_resolution not in ('evidence_valid', 'evidence_excluded')
    or expected_revision is null or target_operation_id is null
    or target_actor_user_id is null
    or target_actor_role not in ('platform_owner', 'platform_admin')
    or char_length(trim(coalesce(target_reason, ''))) < 3 then
    raise exception 'Invalid ranking integrity decision';
  end if;
  perform private.pachanga_lock_ranking_operation_v1(target_operation_id);
  perform pg_advisory_xact_lock(hashtextextended('ranking-integrity-review:' || target_review_id::text, 0));

  select * into replay
  from private.pachanga_ranking_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if found then
    if replay.action <> 'ranking.integrity.resolve' or replay.target_id <> target_review_id::text then
      raise exception 'operationId already belongs to a different ranking action';
    end if;
    return replay.response;
  end if;

  select * into selected
  from private.pachanga_ranking_integrity_reviews reviews
  where reviews.id = target_review_id
  for update;
  if not found then raise exception 'Ranking integrity review not found'; end if;
  if selected.revision <> expected_revision then
    raise exception 'Ranking integrity review revision mismatch' using errcode = '40001';
  end if;
  if selected.state <> 'pending' then raise exception 'Ranking integrity review already resolved'; end if;

  next_state := case target_resolution when 'evidence_valid' then 'approved' else 'excluded' end;
  update private.pachanga_ranking_integrity_reviews reviews
  set state = next_state,
      resolution = target_resolution,
      resolution_reason = trim(target_reason),
      resolved_by = target_actor_user_id,
      resolved_at = clock_timestamp(),
      revision = reviews.revision + 1,
      updated_at = clock_timestamp()
  where reviews.id = target_review_id;

  response := jsonb_build_object(
    'reviewId', target_review_id,
    'opaqueReference', selected.opaque_reference,
    'state', next_state,
    'revision', selected.revision + 1,
    'serverTime', clock_timestamp()
  );
  insert into private.pachanga_ranking_integrity_review_events(
    review_id, operation_id, event_type, from_state, to_state,
    actor_user_id, actor_role, reason, payload
  ) values (
    target_review_id, target_operation_id,
    case next_state when 'approved' then 'review_approved' else 'review_excluded' end,
    selected.state, next_state, target_actor_user_id, target_actor_role,
    trim(target_reason), response
  );
  insert into private.pachanga_ranking_operation_receipts(
    operation_id, action, target_type, target_id, actor_user_id,
    expected_revision, result_revision, response
  ) values (
    target_operation_id, 'ranking.integrity.resolve', 'ranking_integrity_review',
    target_review_id::text, target_actor_user_id, expected_revision,
    selected.revision + 1, response
  );
  insert into private.pachanga_ranking_events(
    operation_id, event_type, season_id, player_profile_id, payload
  ) values (
    target_operation_id, 'ranking_integrity_resolved', selected.season_id,
    selected.player_profile_id, response
  );
  return response;
end;
$$;

revoke all on function private.pachanga_resolve_ranking_integrity_review_v1(
  uuid, text, bigint, uuid, uuid, text, text
) from public, anon, authenticated;

comment on table private.pachanga_ranking_integrity_reviews is
  'Private human-review queue. Decisions never alter Rating V2, conduct state, rewards or the frozen score formula.';

reset lock_timeout;
reset statement_timeout;
