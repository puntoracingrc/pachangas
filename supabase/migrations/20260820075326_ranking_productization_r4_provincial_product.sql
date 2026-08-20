-- Ranking Productization V1 / R4.
-- Provincial product read model, minimized APIs, lifecycle and Control Center authority.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table if not exists public.pachanga_provincial_ranking_publications (
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  province_code text not null references private.pachanga_ranking_territories(province_code) on delete restrict,
  published_revision bigint not null,
  rebuild_id uuid not null references private.pachanga_ranking_rebuilds(id) on delete restrict,
  publication_checksum text not null,
  entry_count integer not null,
  ranked_count integer not null,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  published_at timestamptz not null default clock_timestamp(),
  primary key (season_id, province_code),
  check (published_revision >= 1),
  check (publication_checksum ~ '^[0-9a-f]{64}$'),
  check (entry_count >= 0 and ranked_count >= 0 and ranked_count <= entry_count)
);

create table if not exists public.pachanga_provincial_ranking_entries (
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  province_code text not null references private.pachanga_ranking_territories(province_code) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  display_name text not null,
  position integer,
  visible_score integer not null,
  quality_component numeric not null,
  competition_component numeric not null,
  opposition_component numeric not null,
  eligibility_state text not null,
  safe_reason_codes text[] not null default '{}',
  valid_challenges integer not null,
  logical_opponents integer not null,
  rating_reliability numeric not null,
  competitive_confidence numeric not null,
  network_diversity numeric not null,
  trophy_readiness boolean not null default false,
  snapshot_checksum text not null,
  publication_revision bigint not null,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (season_id, province_code, player_profile_id),
  check (position is null or position >= 1),
  check (visible_score between 0 and 1000),
  check (quality_component between 0 and 550),
  check (competition_component between 0 and 300),
  check (opposition_component between 0 and 150),
  check (eligibility_state in ('eligible', 'provisional', 'pending_integrity_review', 'not_eligible')),
  check (valid_challenges >= 0 and logical_opponents >= 0),
  check (rating_reliability between 0 and 1),
  check (competitive_confidence between 0 and 1),
  check (network_diversity between 0 and 1),
  check (snapshot_checksum ~ '^[0-9a-f]{64}$'),
  check (publication_revision >= 1)
);

create unique index if not exists pachanga_provincial_ranking_position_idx
  on public.pachanga_provincial_ranking_entries(season_id, province_code, position)
  where position is not null;
create index if not exists pachanga_provincial_ranking_player_idx
  on public.pachanga_provincial_ranking_entries(player_profile_id, updated_at desc, season_id);
create unique index if not exists pachanga_provincial_ranking_sequence_idx
  on public.pachanga_provincial_ranking_entries(server_sequence);

alter table public.pachanga_provincial_ranking_publications enable row level security;
alter table public.pachanga_provincial_ranking_entries enable row level security;
revoke all on table public.pachanga_provincial_ranking_publications from public, anon, authenticated;
revoke all on table public.pachanga_provincial_ranking_entries from public, anon, authenticated;
grant select on table public.pachanga_provincial_ranking_publications to authenticated;
grant all on table public.pachanga_provincial_ranking_publications to service_role;
grant all on table public.pachanga_provincial_ranking_entries to service_role;

create or replace function public.pachanga_can_read_provincial_rankings_v1(target_province_code text)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select public.is_registered_pachanga_user()
    and exists (
      select 1 from private.pachanga_ranking_settings settings
      where settings.singleton
        and settings.season_score_product_enabled
        and settings.provincial_rankings_product_enabled
        and target_province_code = any(settings.pilot_province_codes)
    );
$$;

revoke all on function public.pachanga_can_read_provincial_rankings_v1(text)
  from public, anon, authenticated;
grant execute on function public.pachanga_can_read_provincial_rankings_v1(text)
  to authenticated;

drop policy if exists "Authenticated users observe active ranking revisions"
  on public.pachanga_provincial_ranking_publications;
create policy "Authenticated users observe active ranking revisions"
on public.pachanga_provincial_ranking_publications
for select to authenticated
using (
  public.pachanga_can_read_provincial_rankings_v1(province_code)
);

drop policy if exists "Authenticated users observe safe provincial ranking rows"
  on public.pachanga_provincial_ranking_entries;
create policy "Authenticated users observe safe provincial ranking rows"
on public.pachanga_provincial_ranking_entries
for select to authenticated
using (
  public.pachanga_can_read_provincial_rankings_v1(province_code)
);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'pachanga_provincial_ranking_publications'
    ) then
    alter publication supabase_realtime add table public.pachanga_provincial_ranking_publications;
  end if;
end;
$$;

create or replace function private.pachanga_publish_provincial_ranking_v1(
  target_rebuild_id uuid,
  expected_season_revision bigint,
  expected_candidate_checksum text,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_rebuild private.pachanga_ranking_rebuilds%rowtype;
  selected_season private.pachanga_ranking_seasons%rowtype;
  replay private.pachanga_ranking_operation_receipts%rowtype;
  changed_rows integer := 0;
  removed_rows integer := 0;
  publication_checksum text;
  response jsonb;
begin
  if target_rebuild_id is null or expected_season_revision is null
    or expected_candidate_checksum !~ '^[0-9a-f]{64}$'
    or target_operation_id is null or char_length(trim(coalesce(target_reason, ''))) < 3 then
    raise exception 'rebuildId, expectedRevision, checksum, operationId and reason required';
  end if;
  perform private.pachanga_lock_ranking_operation_v1(target_operation_id);

  select * into replay
  from private.pachanga_ranking_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if found then
    if replay.action <> 'ranking.publish' or replay.target_id <> target_rebuild_id::text then
      raise exception 'operationId already belongs to a different ranking action';
    end if;
    return replay.response;
  end if;

  select * into selected_rebuild
  from private.pachanga_ranking_rebuilds rebuilds
  where rebuilds.id = target_rebuild_id
  for update;
  if not found then raise exception 'Ranking rebuild not found'; end if;
  if selected_rebuild.state <> 'candidate_ready' then raise exception 'Ranking candidate is not ready'; end if;
  if selected_rebuild.candidate_checksum <> expected_candidate_checksum then
    raise exception 'Ranking candidate checksum mismatch' using errcode = '40001';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ranking-season:' || selected_rebuild.season_id::text, 0));
  select * into selected_season
  from private.pachanga_ranking_seasons seasons
  where seasons.id = selected_rebuild.season_id
  for update;
  if selected_season.revision <> expected_season_revision then
    raise exception 'Ranking season revision mismatch' using errcode = '40001';
  end if;
  if selected_season.ranking_revision <> selected_rebuild.rebuild_revision then
    raise exception 'A newer ranking candidate exists' using errcode = '40001';
  end if;

  with effective as (
    select candidates.*,
      snapshots.raw_score,
      snapshots.match_competitive_confidence,
      snapshots.logical_opponents,
      snapshots.rating_reliability,
      snapshots.valid_challenges,
      snapshots.lineage,
      snapshots.snapshot_checksum,
      snapshots.eligibility_state as source_eligibility_state,
      reviews.state as review_state,
      case
        when snapshots.eligibility_state = 'eligible' then true
        when snapshots.eligibility_state = 'pending_integrity_review'
          and reviews.state = 'approved' then true
        else false
      end as effectively_eligible
    from private.pachanga_ranking_candidates candidates
    join private.pachanga_season_score_snapshots snapshots on snapshots.id = candidates.snapshot_id
    left join lateral (
      select reviews.state
      from private.pachanga_ranking_integrity_reviews reviews
      where reviews.snapshot_id = snapshots.id
      order by reviews.server_sequence desc, reviews.id desc
      limit 1
    ) reviews on true
    where candidates.rebuild_id = target_rebuild_id
  ),
  positioned as (
    select effective.*,
      case when effectively_eligible and province_code <> '00' then row_number() over (
        partition by province_code, effectively_eligible
        order by raw_score desc,
          match_competitive_confidence desc,
          logical_opponents desc,
          rating_reliability desc,
          valid_challenges desc,
          (lineage ->> 'scoreReachedAt')::timestamptz asc,
          player_profile_id asc
      )::integer end as effective_position,
      case
        when source_eligibility_state = 'pending_integrity_review' and review_state = 'approved'
          then 'eligible'
        when source_eligibility_state = 'pending_integrity_review' and review_state = 'excluded'
          then 'not_eligible'
        else source_eligibility_state
      end as effective_eligibility_state
    from effective
  )
  select count(*)::integer into changed_rows
  from positioned
  left join public.pachanga_provincial_ranking_entries current_rows
    on current_rows.season_id = positioned.season_id
   and current_rows.province_code = positioned.province_code
   and current_rows.player_profile_id = positioned.player_profile_id
  where current_rows.player_profile_id is null
     or current_rows.snapshot_checksum <> positioned.snapshot_checksum
     or current_rows.position is distinct from positioned.effective_position
     or current_rows.eligibility_state <> positioned.effective_eligibility_state;

  select count(*)::integer into removed_rows
  from public.pachanga_provincial_ranking_entries current_rows
  where current_rows.season_id = selected_rebuild.season_id
    and not exists (
      select 1
      from private.pachanga_ranking_candidates candidates
      where candidates.rebuild_id = target_rebuild_id
        and candidates.player_profile_id = current_rows.player_profile_id
        and candidates.province_code = current_rows.province_code
    );
  changed_rows := changed_rows + removed_rows;
  delete from public.pachanga_provincial_ranking_entries current_rows
  where current_rows.season_id = selected_rebuild.season_id;

  with effective as (
    select candidates.rebuild_id,
      candidates.season_id,
      candidates.province_code,
      candidates.player_profile_id,
      candidates.snapshot_id,
      snapshots.raw_score,
      snapshots.visible_score,
      snapshots.quality_component,
      snapshots.competition_component,
      snapshots.opposition_component,
      snapshots.match_competitive_confidence,
      snapshots.logical_opponents,
      snapshots.rating_reliability,
      snapshots.valid_challenges,
      snapshots.network_diversity,
      snapshots.trophy_readiness,
      snapshots.safe_reason_codes,
      snapshots.lineage,
      snapshots.snapshot_checksum,
      snapshots.eligibility_state,
      reviews.state as review_state,
      case
        when snapshots.eligibility_state = 'eligible' then true
        when snapshots.eligibility_state = 'pending_integrity_review'
          and reviews.state = 'approved' then true
        else false
      end as effectively_eligible
    from private.pachanga_ranking_candidates candidates
    join private.pachanga_season_score_snapshots snapshots on snapshots.id = candidates.snapshot_id
    left join lateral (
      select reviews.state
      from private.pachanga_ranking_integrity_reviews reviews
      where reviews.snapshot_id = snapshots.id
      order by reviews.server_sequence desc, reviews.id desc
      limit 1
    ) reviews on true
    where candidates.rebuild_id = target_rebuild_id
  ),
  positioned as (
    select effective.*,
      case when effectively_eligible and province_code <> '00' then row_number() over (
        partition by province_code, effectively_eligible
        order by raw_score desc,
          match_competitive_confidence desc,
          logical_opponents desc,
          rating_reliability desc,
          valid_challenges desc,
          (lineage ->> 'scoreReachedAt')::timestamptz asc,
          player_profile_id asc
      )::integer end as effective_position,
      case
        when eligibility_state = 'pending_integrity_review' and review_state = 'approved'
          then 'eligible'
        when eligibility_state = 'pending_integrity_review' and review_state = 'excluded'
          then 'not_eligible'
        else eligibility_state
      end as effective_eligibility_state
    from effective
  )
  insert into public.pachanga_provincial_ranking_entries(
    season_id, province_code, player_profile_id, display_name, position, visible_score,
    quality_component, competition_component, opposition_component,
    eligibility_state, safe_reason_codes, valid_challenges, logical_opponents,
    rating_reliability, competitive_confidence, network_diversity,
    trophy_readiness, snapshot_checksum, publication_revision, server_sequence, updated_at
  )
  select positioned.season_id,
    positioned.province_code,
    positioned.player_profile_id,
    profiles.display_name,
    positioned.effective_position,
    positioned.visible_score,
    positioned.quality_component,
    positioned.competition_component,
    positioned.opposition_component,
    positioned.effective_eligibility_state,
    case when positioned.effective_eligibility_state = 'eligible'
      then '{}'::text[] else positioned.safe_reason_codes end,
    positioned.valid_challenges,
    positioned.logical_opponents,
    positioned.rating_reliability,
    positioned.match_competitive_confidence,
    positioned.network_diversity,
    positioned.trophy_readiness and positioned.effective_eligibility_state = 'eligible',
    positioned.snapshot_checksum,
    selected_rebuild.rebuild_revision,
    nextval('private.pachanga_ranking_sequence'),
    clock_timestamp()
  from positioned
  join public.pachanga_player_profiles profiles on profiles.id = positioned.player_profile_id
  on conflict (season_id, province_code, player_profile_id) do update set
    display_name = excluded.display_name,
    position = excluded.position,
    visible_score = excluded.visible_score,
    quality_component = excluded.quality_component,
    competition_component = excluded.competition_component,
    opposition_component = excluded.opposition_component,
    eligibility_state = excluded.eligibility_state,
    safe_reason_codes = excluded.safe_reason_codes,
    valid_challenges = excluded.valid_challenges,
    logical_opponents = excluded.logical_opponents,
    rating_reliability = excluded.rating_reliability,
    competitive_confidence = excluded.competitive_confidence,
    network_diversity = excluded.network_diversity,
    trophy_readiness = excluded.trophy_readiness,
    snapshot_checksum = excluded.snapshot_checksum,
    publication_revision = excluded.publication_revision,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at;

  delete from public.pachanga_provincial_ranking_publications publications
  where publications.season_id = selected_rebuild.season_id;
  insert into public.pachanga_provincial_ranking_publications(
    season_id, province_code, published_revision, rebuild_id,
    publication_checksum, entry_count, ranked_count
  )
  select entries.season_id,
    entries.province_code,
    selected_rebuild.rebuild_revision,
    target_rebuild_id,
    private.pachanga_ranking_json_checksum_v1(jsonb_agg(jsonb_build_object(
      'playerProfileId', entries.player_profile_id,
      'position', entries.position,
      'snapshotChecksum', entries.snapshot_checksum,
      'eligibilityState', entries.eligibility_state
    ) order by entries.position nulls last, entries.player_profile_id)),
    count(*)::integer,
    count(*) filter (where entries.position is not null)::integer
  from public.pachanga_provincial_ranking_entries entries
  where entries.season_id = selected_rebuild.season_id
  group by entries.season_id, entries.province_code;

  select private.pachanga_ranking_json_checksum_v1(coalesce(jsonb_agg(jsonb_build_object(
    'provinceCode', publications.province_code,
    'checksum', publications.publication_checksum,
    'entryCount', publications.entry_count,
    'rankedCount', publications.ranked_count
  ) order by publications.province_code), '[]'::jsonb))
  into publication_checksum
  from public.pachanga_provincial_ranking_publications publications
  where publications.season_id = selected_rebuild.season_id;

  update private.pachanga_ranking_rebuilds rebuilds
  set state = 'published',
      published_checksum = publication_checksum,
      changed_count = changed_rows,
      completed_at = clock_timestamp()
  where rebuilds.id = target_rebuild_id;
  update private.pachanga_ranking_seasons seasons
  set published_revision = selected_rebuild.rebuild_revision,
      updated_at = clock_timestamp()
  where seasons.id = selected_rebuild.season_id;

  response := jsonb_build_object(
    'rebuildId', target_rebuild_id,
    'seasonId', selected_rebuild.season_id,
    'publishedRevision', selected_rebuild.rebuild_revision,
    'candidateChecksum', selected_rebuild.candidate_checksum,
    'publicationChecksum', publication_checksum,
    'changedCount', changed_rows,
    'awardsGranted', 0,
    'rewardsGranted', 0,
    'notificationsSent', 0
  );
  insert into private.pachanga_ranking_operation_receipts(
    operation_id, action, target_type, target_id, actor_user_id,
    expected_revision, result_revision, response
  ) values (
    target_operation_id, 'ranking.publish', 'ranking_rebuild', target_rebuild_id::text,
    target_actor_user_id, expected_season_revision, selected_rebuild.rebuild_revision, response
  );
  insert into private.pachanga_ranking_events(
    operation_id, event_type, season_id, payload
  ) values (
    target_operation_id, 'provincial_ranking_published', selected_rebuild.season_id, response
  );
  return response;
end;
$$;

revoke all on function private.pachanga_publish_provincial_ranking_v1(
  uuid, bigint, text, uuid, uuid, text
) from public, anon, authenticated;

create or replace function public.get_pachanga_provincial_ranking_v1(
  target_province_code text default '08',
  page_offset integer default 0,
  page_size integer default 10
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  selected_settings private.pachanga_ranking_settings%rowtype;
  selected_publication public.pachanga_provincial_ranking_publications%rowtype;
  selected_season private.pachanga_ranking_seasons%rowtype;
  selected_territory private.pachanga_ranking_territories%rowtype;
  items jsonb;
  total_count integer;
begin
  page_offset := greatest(0, coalesce(page_offset, 0));
  page_size := greatest(1, least(coalesce(page_size, 10), 100));
  select * into selected_settings
  from private.pachanga_ranking_settings settings
  where settings.singleton;
  if not found or not selected_settings.season_score_product_enabled
    or not selected_settings.provincial_rankings_product_enabled
    or target_province_code <> all(selected_settings.pilot_province_codes) then
    return jsonb_build_object(
      'available', false,
      'reason', 'RANKING_NOT_ACTIVE',
      'revision', coalesce(selected_settings.revision, 0),
      'items', '[]'::jsonb
    );
  end if;

  select * into selected_territory
  from private.pachanga_ranking_territories territories
  where territories.province_code = target_province_code
    and territories.product_allowed;
  if not found then
    return jsonb_build_object('available', false, 'reason', 'TERRITORY_NOT_AVAILABLE', 'items', '[]'::jsonb);
  end if;

  select publications.* into selected_publication
  from public.pachanga_provincial_ranking_publications publications
  join private.pachanga_ranking_seasons seasons on seasons.id = publications.season_id
  join private.pachanga_ranking_season_territories season_territories
    on season_territories.season_id = seasons.id
   and season_territories.province_code = publications.province_code
   and season_territories.product_enabled
  where publications.province_code = target_province_code
    and seasons.status in ('open', 'frozen', 'closed')
  order by publications.published_at desc,
    publications.published_revision desc,
    publications.rebuild_id desc
  limit 1;
  if not found then
    return jsonb_build_object('available', false, 'reason', 'READ_MODEL_UNAVAILABLE', 'items', '[]'::jsonb);
  end if;
  select * into selected_season
  from private.pachanga_ranking_seasons seasons
  where seasons.id = selected_publication.season_id;

  select count(*)::integer into total_count
  from public.pachanga_provincial_ranking_entries entries
  where entries.season_id = selected_publication.season_id
    and entries.province_code = target_province_code
    and entries.position is not null;
  select coalesce(jsonb_agg(jsonb_build_object(
    'entryKey', encode(extensions.digest(
      selected_publication.season_id::text || ':' || ranked.player_profile_id::text,
      'sha256'
    ), 'hex'),
    'displayName', ranked.display_name,
    'position', ranked.position,
    'score', ranked.visible_score,
    'components', jsonb_build_object(
      'quality', round(ranked.quality_component / 5.5, 1),
      'competition', round(ranked.competition_component / 3, 1),
      'opposition', round(ranked.opposition_component / 1.5, 1)
    ),
    'validChallenges', ranked.valid_challenges,
    'logicalOpponents', ranked.logical_opponents
  ) order by ranked.position), '[]'::jsonb)
  into items
  from (
    select entries.*
    from public.pachanga_provincial_ranking_entries entries
    where entries.season_id = selected_publication.season_id
      and entries.province_code = target_province_code
      and entries.position is not null
    order by entries.position
    offset page_offset limit page_size
  ) ranked;

  return jsonb_build_object(
    'available', true,
    'season', jsonb_build_object(
      'id', selected_season.id,
      'key', selected_season.season_key,
      'label', selected_season.label,
      'status', selected_season.status,
      'startsAt', selected_season.starts_at,
      'endsAt', selected_season.ends_at,
      'formulaKey', selected_season.formula_key,
      'formulaVersion', selected_season.formula_version
    ),
    'territory', jsonb_build_object(
      'provinceCode', selected_territory.province_code,
      'provinceName', selected_territory.province_name
    ),
    'publication', jsonb_build_object(
      'revision', selected_publication.published_revision,
      'checksum', selected_publication.publication_checksum,
      'publishedAt', selected_publication.published_at
    ),
    'pagination', jsonb_build_object(
      'offset', page_offset,
      'pageSize', page_size,
      'total', total_count
    ),
    'items', items
  );
end;
$$;

revoke all on function public.get_pachanga_provincial_ranking_v1(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_provincial_ranking_v1(text, integer, integer)
  to anon, authenticated;

create or replace function public.get_my_pachanga_provincial_rank_v1(
  target_season_id uuid default null
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_profile_id uuid;
  selected public.pachanga_provincial_ranking_entries%rowtype;
begin
  if current_user_id is null or not public.is_registered_pachanga_user() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select profiles.id into current_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = current_user_id;
  if current_profile_id is null then
    return jsonb_build_object('available', false, 'reason', 'PLAYER_PROFILE_REQUIRED');
  end if;
  select entries.* into selected
  from public.pachanga_provincial_ranking_entries entries
  join public.pachanga_provincial_ranking_publications publications
    on publications.season_id = entries.season_id
   and publications.province_code = entries.province_code
  where entries.player_profile_id = current_profile_id
    and (target_season_id is null or entries.season_id = target_season_id)
    and public.pachanga_can_read_provincial_rankings_v1(entries.province_code)
  order by publications.published_at desc,
    publications.published_revision desc,
    publications.rebuild_id desc
  limit 1;
  if not found then return jsonb_build_object('available', false, 'reason', 'NO_PUBLISHED_POSITION'); end if;
  return jsonb_build_object(
    'available', true,
    'seasonId', selected.season_id,
    'provinceCode', selected.province_code,
    'displayName', selected.display_name,
    'position', selected.position,
    'score', selected.visible_score,
    'eligibilityState', selected.eligibility_state,
    'reasonCodes', to_jsonb(selected.safe_reason_codes),
    'validChallenges', selected.valid_challenges,
    'logicalOpponents', selected.logical_opponents,
    'publicationRevision', selected.publication_revision
  );
end;
$$;

revoke all on function public.get_my_pachanga_provincial_rank_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.get_my_pachanga_provincial_rank_v1(uuid)
  to authenticated;

create or replace function private.pachanga_platform_capabilities_v1(target_role text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case target_role
    when 'platform_owner' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend', 'roles.manage',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'billing.read', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read'
    )
    else '[]'::jsonb
  end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_ranking_operational_health_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  settings private.pachanga_ranking_settings%rowtype;
  active_season private.pachanga_ranking_seasons%rowtype;
  reason_codes text[] := '{}'::text[];
  classification text;
  queued_count integer := 0;
  stuck_count integer := 0;
  failed_count integer := 0;
  dead_letter_count integer := 0;
  integrity_count integer := 0;
  failed_rebuild_count integer := 0;
  pending_diff_count integer := 0;
  pilot_publication_count integer := 0;
begin
  select * into settings
  from private.pachanga_ranking_settings ranking_settings
  where ranking_settings.singleton;

  select * into active_season
  from private.pachanga_ranking_seasons seasons
  where seasons.status in ('open', 'frozen')
  order by seasons.starts_at desc, seasons.server_sequence desc, seasons.id desc
  limit 1;

  select count(*) filter (where queue.state = 'queued'),
    count(*) filter (
      where queue.state = 'processing'
        and queue.updated_at < current_timestamp - interval '10 minutes'
    ),
    count(*) filter (where queue.state = 'failed'),
    count(*) filter (where queue.state = 'dead_letter')
  into queued_count, stuck_count, failed_count, dead_letter_count
  from private.pachanga_ranking_refresh_queue queue;

  select count(*) into integrity_count
  from private.pachanga_ranking_integrity_reviews reviews
  where reviews.state = 'pending';

  select count(*) filter (where rebuilds.state = 'failed'),
    count(*) filter (
      where rebuilds.state = 'candidate_ready'
        and coalesce(rebuilds.changed_count, 0) > 0
    )
  into failed_rebuild_count, pending_diff_count
  from private.pachanga_ranking_rebuilds rebuilds
  where active_season.id is not null and rebuilds.season_id = active_season.id;

  select count(*) into pilot_publication_count
  from public.pachanga_provincial_ranking_publications publications
  where active_season.id is not null
    and publications.season_id = active_season.id
    and publications.province_code = any(settings.pilot_province_codes)
    and publications.published_revision = active_season.published_revision;

  reason_codes := array_remove(array[
    case when active_season.id is null then 'NO_ACTIVE_SEASON' end,
    case when active_season.id is not null and active_season.starts_at >= active_season.ends_at
      then 'SEASON_INTERVAL_INVALID' end,
    case when active_season.id is not null and not exists (
      select 1
      from private.pachanga_season_score_formula_registry formulas
      where formulas.formula_key = active_season.formula_key
        and formulas.formula_version = active_season.formula_version
        and formulas.configuration_checksum = active_season.formula_checksum
    ) then 'FORMULA_CHECKSUM_MISMATCH' end,
    case when active_season.id is not null and active_season.status = 'open'
      and (
        active_season.last_refresh_at is null
        or active_season.last_refresh_at < current_timestamp - interval '15 minutes'
      ) then 'RANKING_REFRESH_STALE' end,
    case when queued_count > 100 then 'RANKING_QUEUE_GROWING' end,
    case when stuck_count > 0 then 'RANKING_REFRESH_STUCK' end,
    case when failed_count > 0 then 'RANKING_QUEUE_FAILED' end,
    case when dead_letter_count > 0 then 'RANKING_QUEUE_DEAD_LETTER' end,
    case when failed_rebuild_count > 0 then 'RANKING_REBUILD_FAILED' end,
    case when pending_diff_count > 0 then 'RANKING_REBUILD_DIFF_PENDING' end,
    case when integrity_count > 0 then 'RANKING_INTEGRITY_BACKLOG' end,
    case when settings.provincial_rankings_product_enabled
      and pilot_publication_count < cardinality(settings.pilot_province_codes)
      then 'PILOT_PUBLICATION_MISSING' end
  ]::text[], null);

  classification := case
    when active_season.id is null
      and not settings.season_score_product_enabled
      and not settings.provincial_rankings_product_enabled then 'UNKNOWN'
    when reason_codes && array[
      'NO_ACTIVE_SEASON', 'SEASON_INTERVAL_INVALID', 'FORMULA_CHECKSUM_MISMATCH',
      'RANKING_QUEUE_DEAD_LETTER', 'RANKING_REBUILD_FAILED', 'PILOT_PUBLICATION_MISSING'
    ]::text[] then 'CRITICAL'
    when cardinality(reason_codes) > 0 then 'WARNING'
    else 'OK'
  end;

  return jsonb_build_object(
    'status', classification,
    'reasonCodes', to_jsonb(reason_codes),
    'checkedAt', current_timestamp,
    'metrics', jsonb_build_object(
      'queued', queued_count,
      'stuck', stuck_count,
      'failed', failed_count,
      'deadLetter', dead_letter_count,
      'integrityPending', integrity_count,
      'failedRebuilds', failed_rebuild_count,
      'pendingRebuildDiffs', pending_diff_count,
      'pilotPublications', pilot_publication_count
    )
  );
end;
$$;

revoke all on function private.pachanga_ranking_operational_health_v1()
  from public, anon, authenticated;

create or replace function public.get_pachanga_ranking_admin_overview_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('rankings.read');
  select jsonb_build_object(
    'health', private.pachanga_ranking_operational_health_v1(),
    'settings', jsonb_build_object(
      'seasonScoreEnabled', settings.season_score_product_enabled,
      'provincialRankingsEnabled', settings.provincial_rankings_product_enabled,
      'provincialAwardsEnabled', settings.provincial_awards_enabled,
      'pilotProvinceCodes', to_jsonb(settings.pilot_province_codes),
      'revision', settings.revision,
      'serverSequence', settings.server_sequence,
      'updatedAt', settings.updated_at
    ),
    'formula', (
      select jsonb_build_object(
        'key', formulas.formula_key,
        'version', formulas.formula_version,
        'checksum', formulas.configuration_checksum,
        'configuration', formulas.configuration
      )
      from private.pachanga_season_score_formula_registry formulas
      where formulas.active_until is null
      order by formulas.active_from desc, formulas.formula_key, formulas.formula_version desc
      limit 1
    ),
    'seasons', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', seasons.id,
        'key', seasons.season_key,
        'label', seasons.label,
        'status', seasons.status,
        'startsAt', seasons.starts_at,
        'endsAt', seasons.ends_at,
        'revision', seasons.revision,
        'rankingRevision', seasons.ranking_revision,
        'publishedRevision', seasons.published_revision,
        'formulaChecksum', seasons.formula_checksum,
        'lastRefreshAt', seasons.last_refresh_at,
        'lastErrorCode', seasons.last_error_code,
        'candidateCount', coalesce(latest_rebuild.candidate_count, 0),
        'candidateChecksum', latest_rebuild.candidate_checksum,
        'rebuildId', latest_rebuild.id,
        'rebuildState', latest_rebuild.state,
        'eligiblePlayers', coalesce(candidate_counts.eligible_players, 0),
        'notEligiblePlayers', coalesce(candidate_counts.not_eligible_players, 0),
        'pendingIntegrityPlayers', coalesce(candidate_counts.pending_integrity_players, 0)
      ) order by seasons.starts_at desc, seasons.id desc)
      from private.pachanga_ranking_seasons seasons
      left join lateral (
        select rebuilds.id,
          rebuilds.state,
          rebuilds.candidate_count,
          rebuilds.candidate_checksum
        from private.pachanga_ranking_rebuilds rebuilds
        where rebuilds.season_id = seasons.id
        order by rebuilds.rebuild_revision desc, rebuilds.server_sequence desc, rebuilds.id desc
        limit 1
      ) latest_rebuild on true
      left join lateral (
        select count(*) filter (where snapshots.eligibility_state = 'eligible')::integer as eligible_players,
          count(*) filter (where snapshots.eligibility_state = 'not_eligible')::integer as not_eligible_players,
          count(*) filter (where snapshots.eligibility_state = 'pending_integrity_review')::integer as pending_integrity_players
        from private.pachanga_ranking_candidates candidates
        join private.pachanga_season_score_snapshots snapshots on snapshots.id = candidates.snapshot_id
        where candidates.rebuild_id = latest_rebuild.id
      ) candidate_counts on true
    ), '[]'::jsonb),
    'territories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'provinceCode', territories.province_code,
        'provinceName', territories.province_name,
        'productAllowed', territories.product_allowed,
        'revision', territories.revision
      ) order by territories.province_code)
      from private.pachanga_ranking_territories territories
    ), '[]'::jsonb),
    'queue', jsonb_build_object(
      'queued', (select count(*) from private.pachanga_ranking_refresh_queue where state = 'queued'),
      'processing', (select count(*) from private.pachanga_ranking_refresh_queue where state = 'processing'),
      'failed', (select count(*) from private.pachanga_ranking_refresh_queue where state = 'failed'),
      'deadLetter', (select count(*) from private.pachanga_ranking_refresh_queue where state = 'dead_letter')
    ),
    'integrity', jsonb_build_object(
      'pending', (select count(*) from private.pachanga_ranking_integrity_reviews where state = 'pending'),
      'approved', (select count(*) from private.pachanga_ranking_integrity_reviews where state = 'approved'),
      'excluded', (select count(*) from private.pachanga_ranking_integrity_reviews where state = 'excluded')
    ),
    'integrityReviews', coalesce((
      select jsonb_agg(review_payload order by risk_score desc, server_sequence, review_id)
      from (
        select jsonb_build_object(
          'id', reviews.id,
          'reference', reviews.opaque_reference,
          'seasonId', reviews.season_id,
          'seasonLabel', seasons.label,
          'playerName', profiles.display_name,
          'provinceCode', snapshots.province_code,
          'riskClassification', reviews.risk_classification,
          'riskScore', reviews.risk_score,
          'reasonCodes', to_jsonb(reviews.private_reason_codes),
          'evidenceSummary', jsonb_build_object(
            'evidenceRevision', snapshots.evidence_revision,
            'validChallenges', snapshots.valid_challenges,
            'logicalOpponents', snapshots.logical_opponents,
            'competitiveConfidence', snapshots.match_competitive_confidence,
            'networkDiversity', snapshots.network_diversity,
            'snapshotChecksum', snapshots.snapshot_checksum
          ),
          'revision', reviews.revision,
          'state', reviews.state,
          'createdAt', reviews.created_at
        ) as review_payload,
        reviews.risk_score,
        reviews.server_sequence,
        reviews.id as review_id
        from private.pachanga_ranking_integrity_reviews reviews
        join private.pachanga_ranking_seasons seasons on seasons.id = reviews.season_id
        join private.pachanga_season_score_snapshots snapshots on snapshots.id = reviews.snapshot_id
        join public.pachanga_player_profiles profiles on profiles.id = reviews.player_profile_id
        where reviews.state = 'pending'
        order by reviews.risk_score desc, reviews.server_sequence, reviews.id
        limit 100
      ) pending_reviews
    ), '[]'::jsonb),
    'queueItems', coalesce((
      select jsonb_agg(queue_payload order by server_sequence, queue_id)
      from (
        select jsonb_build_object(
          'id', queue.id,
          'seasonId', queue.season_id,
          'seasonLabel', seasons.label,
          'scope', queue.refresh_scope,
          'state', queue.state,
          'reason', queue.reason,
          'sourceType', queue.source_type,
          'attempts', queue.attempts,
          'errorCode', queue.error_code,
          'availableAt', queue.available_at,
          'updatedAt', queue.updated_at
        ) as queue_payload,
        queue.server_sequence,
        queue.id as queue_id
        from private.pachanga_ranking_refresh_queue queue
        join private.pachanga_ranking_seasons seasons on seasons.id = queue.season_id
        where queue.state in ('queued', 'processing', 'failed', 'dead_letter')
        order by queue.server_sequence, queue.id
        limit 100
      ) active_queue
    ), '[]'::jsonb),
    'venueMappings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'placeId', mappings.place_id,
        'provinceCode', mappings.province_code,
        'confidence', mappings.confidence,
        'revision', mappings.revision,
        'source', mappings.evidence_source,
        'effectiveFrom', mappings.effective_from
      ) order by mappings.effective_from desc, mappings.server_sequence desc, mappings.id desc)
      from private.pachanga_ranking_venue_territories mappings
      where mappings.effective_until is null
    ), '[]'::jsonb),
    'rebuilds', coalesce((
      select jsonb_agg(row_payload order by rebuild_revision desc, server_sequence desc, rebuild_id desc)
      from (
        select jsonb_build_object(
          'id', rebuilds.id,
          'seasonId', rebuilds.season_id,
          'revision', rebuilds.rebuild_revision,
          'state', rebuilds.state,
          'candidateChecksum', rebuilds.candidate_checksum,
          'publishedChecksum', rebuilds.published_checksum,
          'candidateCount', rebuilds.candidate_count,
          'changedCount', rebuilds.changed_count,
          'errorCode', rebuilds.error_code,
          'startedAt', rebuilds.started_at,
          'completedAt', rebuilds.completed_at
        ) as row_payload,
        rebuilds.rebuild_revision,
        rebuilds.server_sequence,
        rebuilds.id as rebuild_id
        from private.pachanga_ranking_rebuilds rebuilds
        order by rebuilds.server_sequence desc, rebuilds.id desc
        limit 25
      ) recent
    ), '[]'::jsonb),
    'invariants', jsonb_build_object(
      'ratingV2ReadOnly', true,
      'conductAffectsScore', false,
      'rewardsAffectScore', false,
      'awardsEnabled', false
    )
  ) into result
  from private.pachanga_ranking_settings settings
  where settings.singleton;
  return result;
end;
$$;

revoke all on function public.get_pachanga_ranking_admin_overview_v1()
  from public, anon, authenticated;
grant execute on function public.get_pachanga_ranking_admin_overview_v1()
  to authenticated;

create or replace function private.pachanga_record_ranking_admin_action_v1(
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_actor_role text,
  target_action text,
  target_type text,
  target_id text,
  target_reason text,
  target_before jsonb,
  target_after jsonb,
  target_response jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response
  ) values (
    target_operation_id, target_actor_user_id, target_actor_role,
    target_action, target_type, target_id, trim(target_reason),
    coalesce(target_before, '{}'::jsonb), coalesce(target_after, '{}'::jsonb),
    coalesce(target_response, '{}'::jsonb)
  );
end;
$$;

revoke all on function private.pachanga_record_ranking_admin_action_v1(
  uuid, uuid, text, text, text, text, text, jsonb, jsonb, jsonb
) from public, anon, authenticated;

create or replace function public.create_pachanga_ranking_season_v1(
  season_key text,
  season_label text,
  starts_at timestamptz,
  ends_at timestamptz,
  province_codes text[],
  requested_operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  selected_formula private.pachanga_season_score_formula_registry%rowtype;
  saved_season_id uuid;
  response jsonb;
  replay private.pachanga_ranking_operation_receipts%rowtype;
begin
  actor_role := private.pachanga_platform_require_v1('rankings.write');
  if requested_operation_id is null or season_key !~ '^[a-z0-9_-]{3,80}$'
    or char_length(trim(coalesce(season_label, ''))) < 3
    or starts_at is null or ends_at <= starts_at
    or cardinality(province_codes) < 1
    or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'Invalid ranking season request';
  end if;
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  select * into replay
  from private.pachanga_ranking_operation_receipts receipts
  where receipts.operation_id = requested_operation_id;
  if found then
    if replay.action <> 'ranking.season.create' or replay.target_id <> season_key then
      raise exception 'operationId already belongs to a different ranking action';
    end if;
    return replay.response;
  end if;
  if exists (
    select 1 from unnest(province_codes) province_code
    where not exists (
      select 1 from private.pachanga_ranking_territories territories
      where territories.province_code = province_code and territories.product_allowed
    )
  ) then raise exception 'Ranking territory is not product-allowed'; end if;

  select * into selected_formula
  from private.pachanga_season_score_formula_registry formulas
  where formulas.formula_key = 'season_score_v3'
    and formulas.active_until is null
  order by formulas.formula_version desc
  limit 1;
  if not found then raise exception 'Active Season Score V3 formula unavailable'; end if;

  insert into private.pachanga_ranking_seasons(
    season_key, label, formula_key, formula_version, formula_checksum,
    starts_at, ends_at, created_by, updated_by
  ) values (
    season_key, trim(season_label), selected_formula.formula_key,
    selected_formula.formula_version, selected_formula.configuration_checksum,
    starts_at, ends_at, actor_user_id, actor_user_id
  ) returning id into saved_season_id;
  insert into private.pachanga_ranking_season_territories(
    season_id, province_code, product_enabled
  )
  select saved_season_id, distinct_provinces.province_code, true
  from (select distinct unnest(province_codes) as province_code) distinct_provinces;

  response := jsonb_build_object(
    'seasonId', saved_season_id,
    'seasonKey', season_key,
    'status', 'draft',
    'revision', 1,
    'formulaKey', selected_formula.formula_key,
    'formulaVersion', selected_formula.formula_version,
    'formulaChecksum', selected_formula.configuration_checksum,
    'provinceCodes', to_jsonb(province_codes)
  );
  insert into private.pachanga_ranking_operation_receipts(
    operation_id, action, target_type, target_id, actor_user_id,
    result_revision, response
  ) values (
    requested_operation_id, 'ranking.season.create', 'ranking_season', season_key,
    actor_user_id, 1, response
  );
  perform private.pachanga_record_ranking_admin_action_v1(
    requested_operation_id, actor_user_id, actor_role, 'ranking.season.create',
    'ranking_season', saved_season_id::text, reason, '{}'::jsonb, response, response
  );
  return response;
end;
$$;

revoke all on function public.create_pachanga_ranking_season_v1(
  text, text, timestamptz, timestamptz, text[], uuid, text
) from public, anon, authenticated;
grant execute on function public.create_pachanga_ranking_season_v1(
  text, text, timestamptz, timestamptz, text[], uuid, text
) to authenticated;

create or replace function public.transition_pachanga_ranking_season_v1(
  target_season_id uuid,
  next_status text,
  expected_revision bigint,
  requested_operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  selected private.pachanga_ranking_seasons%rowtype;
  response jsonb;
  replay private.pachanga_ranking_operation_receipts%rowtype;
begin
  actor_role := private.pachanga_platform_require_v1('rankings.write');
  if target_season_id is null or expected_revision is null or requested_operation_id is null
    or char_length(trim(coalesce(reason, ''))) < 3 then raise exception 'Invalid season transition'; end if;
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  select * into replay
  from private.pachanga_ranking_operation_receipts receipts
  where receipts.operation_id = requested_operation_id;
  if found then
    if replay.action <> 'ranking.season.transition' or replay.target_id <> target_season_id::text then
      raise exception 'operationId already belongs to a different ranking action';
    end if;
    return replay.response;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('ranking-season:' || target_season_id::text, 0));
  select * into selected
  from private.pachanga_ranking_seasons seasons
  where seasons.id = target_season_id
  for update;
  if not found then raise exception 'Ranking season not found'; end if;
  if selected.revision <> expected_revision then
    raise exception 'Ranking season revision mismatch' using errcode = '40001';
  end if;
  if not ((selected.status = 'draft' and next_status = 'open')
    or (selected.status = 'open' and next_status = 'frozen')
    or (selected.status = 'frozen' and next_status = 'closed')
    or (selected.status = 'closed' and next_status = 'archived')) then
    raise exception 'Invalid ranking season lifecycle transition';
  end if;
  if selected.status = 'draft' and not exists (
    select 1 from private.pachanga_ranking_season_territories territories
    where territories.season_id = target_season_id and territories.product_enabled
  ) then raise exception 'Season needs at least one enabled territory'; end if;
  if selected.status = 'frozen' and selected.published_revision = 0 then
    raise exception 'Season cannot close without a published ranking';
  end if;

  update private.pachanga_ranking_seasons seasons
  set status = next_status,
      revision = seasons.revision + 1,
      updated_by = actor_user_id,
      updated_at = clock_timestamp()
  where seasons.id = target_season_id;
  response := jsonb_build_object(
    'seasonId', target_season_id,
    'status', next_status,
    'revision', selected.revision + 1,
    'rankingRevision', selected.ranking_revision,
    'publishedRevision', selected.published_revision
  );
  insert into private.pachanga_ranking_operation_receipts(
    operation_id, action, target_type, target_id, actor_user_id,
    expected_revision, result_revision, response
  ) values (
    requested_operation_id, 'ranking.season.transition', 'ranking_season', target_season_id::text,
    actor_user_id, expected_revision, selected.revision + 1, response
  );
  perform private.pachanga_record_ranking_admin_action_v1(
    requested_operation_id, actor_user_id, actor_role, 'ranking.season.transition',
    'ranking_season', target_season_id::text, reason,
    jsonb_build_object('status', selected.status, 'revision', selected.revision), response, response
  );
  return response;
end;
$$;

revoke all on function public.transition_pachanga_ranking_season_v1(uuid, text, bigint, uuid, text)
  from public, anon, authenticated;
grant execute on function public.transition_pachanga_ranking_season_v1(uuid, text, bigint, uuid, text)
  to authenticated;

create or replace function public.map_pachanga_ranking_venue_v1(
  target_place_id text,
  target_province_code text,
  confidence numeric,
  expected_mapping_revision bigint,
  requested_operation_id uuid,
  reason text,
  evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  selected private.pachanga_ranking_venue_territories%rowtype;
  next_revision bigint;
  response jsonb;
  replay private.pachanga_ranking_operation_receipts%rowtype;
begin
  actor_role := private.pachanga_platform_require_v1('rankings.write');
  if char_length(trim(coalesce(target_place_id, ''))) < 3
    or target_province_code !~ '^[0-9]{2}$' or target_province_code = '00'
    or confidence not between 0.50 and 1 or expected_mapping_revision is null
    or requested_operation_id is null or char_length(trim(coalesce(reason, ''))) < 3
    or jsonb_typeof(coalesce(evidence, '{}'::jsonb)) <> 'object' then
    raise exception 'Invalid ranking venue mapping';
  end if;
  if not exists (
    select 1 from private.pachanga_ranking_territories territories
    where territories.province_code = target_province_code and territories.product_allowed
  ) then raise exception 'Ranking territory is not product-allowed'; end if;
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  select * into replay from private.pachanga_ranking_operation_receipts receipts
  where receipts.operation_id = requested_operation_id;
  if found then
    if replay.action <> 'ranking.venue.map' or replay.target_id <> target_place_id then
      raise exception 'operationId already belongs to a different ranking action';
    end if;
    return replay.response;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('ranking-venue:' || target_place_id, 0));
  select * into selected
  from private.pachanga_ranking_venue_territories mappings
  where mappings.place_id = target_place_id and mappings.effective_until is null
  for update;
  if found and selected.revision <> expected_mapping_revision then
    raise exception 'Ranking venue revision mismatch' using errcode = '40001';
  end if;
  if not found and expected_mapping_revision <> 0 then
    raise exception 'Ranking venue revision mismatch' using errcode = '40001';
  end if;
  next_revision := coalesce(selected.revision, 0) + 1;
  update private.pachanga_ranking_venue_territories mappings
  set effective_until = clock_timestamp()
  where mappings.id = selected.id;
  insert into private.pachanga_ranking_venue_territories(
    place_id, province_code, confidence, evidence_source, evidence,
    revision, operation_id, actor_user_id, reason
  ) values (
    trim(target_place_id), target_province_code, confidence,
    'platform_admin_verified', coalesce(evidence, '{}'::jsonb), next_revision,
    requested_operation_id, actor_user_id, trim(reason)
  );
  response := jsonb_build_object(
    'placeId', target_place_id,
    'provinceCode', target_province_code,
    'confidence', confidence,
    'revision', next_revision,
    'serverTime', clock_timestamp()
  );
  insert into private.pachanga_ranking_operation_receipts(
    operation_id, action, target_type, target_id, actor_user_id,
    expected_revision, result_revision, response
  ) values (
    requested_operation_id, 'ranking.venue.map', 'ranking_venue', target_place_id,
    actor_user_id, expected_mapping_revision, next_revision, response
  );
  perform private.pachanga_record_ranking_admin_action_v1(
    requested_operation_id, actor_user_id, actor_role, 'ranking.venue.map',
    'ranking_venue', target_place_id, reason,
    case when selected.id is null then '{}'::jsonb else jsonb_build_object(
      'provinceCode', selected.province_code,
      'confidence', selected.confidence,
      'revision', selected.revision
    ) end,
    response, response
  );
  return response;
end;
$$;

revoke all on function public.map_pachanga_ranking_venue_v1(
  text, text, numeric, bigint, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.map_pachanga_ranking_venue_v1(
  text, text, numeric, bigint, uuid, text, jsonb
) to authenticated;

create or replace function public.rebuild_pachanga_provincial_ranking_v1(
  target_season_id uuid,
  expected_season_revision bigint,
  requested_operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  saved_rebuild_id uuid;
  response jsonb;
  platform_replay jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('rankings.write');
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  platform_replay := private.pachanga_platform_admin_replay_v1(
    requested_operation_id, 'ranking.rebuild_candidate', 'ranking_season', target_season_id::text
  );
  if platform_replay is not null then return platform_replay; end if;
  saved_rebuild_id := private.pachanga_build_season_ranking_candidate_v1(
    target_season_id, expected_season_revision, requested_operation_id,
    actor_user_id, reason
  );
  select jsonb_build_object(
    'rebuildId', rebuilds.id,
    'seasonId', rebuilds.season_id,
    'state', rebuilds.state,
    'revision', rebuilds.rebuild_revision,
    'candidateChecksum', rebuilds.candidate_checksum,
    'candidateCount', rebuilds.candidate_count,
    'awardsGranted', 0,
    'rewardsGranted', 0
  ) into response
  from private.pachanga_ranking_rebuilds rebuilds
  where rebuilds.id = saved_rebuild_id;
  perform private.pachanga_record_ranking_admin_action_v1(
    requested_operation_id, actor_user_id, actor_role, 'ranking.rebuild_candidate',
    'ranking_season', target_season_id::text, reason,
    jsonb_build_object('expectedRevision', expected_season_revision), response, response
  );
  return response;
end;
$$;

revoke all on function public.rebuild_pachanga_provincial_ranking_v1(uuid, bigint, uuid, text)
  from public, anon, authenticated;
grant execute on function public.rebuild_pachanga_provincial_ranking_v1(uuid, bigint, uuid, text)
  to authenticated;

create or replace function public.publish_pachanga_provincial_ranking_v1(
  target_rebuild_id uuid,
  expected_season_revision bigint,
  expected_candidate_checksum text,
  requested_operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  response jsonb;
  platform_replay jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('rankings.write');
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  platform_replay := private.pachanga_platform_admin_replay_v1(
    requested_operation_id, 'ranking.publish', 'ranking_rebuild', target_rebuild_id::text
  );
  if platform_replay is not null then return platform_replay; end if;
  response := private.pachanga_publish_provincial_ranking_v1(
    target_rebuild_id, expected_season_revision, expected_candidate_checksum,
    requested_operation_id, actor_user_id, reason
  );
  perform private.pachanga_record_ranking_admin_action_v1(
    requested_operation_id, actor_user_id, actor_role, 'ranking.publish',
    'ranking_rebuild', target_rebuild_id::text, reason,
    jsonb_build_object('candidateChecksum', expected_candidate_checksum), response, response
  );
  return response;
end;
$$;

revoke all on function public.publish_pachanga_provincial_ranking_v1(uuid, bigint, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.publish_pachanga_provincial_ranking_v1(uuid, bigint, text, uuid, text)
  to authenticated;

create or replace function public.resolve_pachanga_ranking_integrity_v1(
  target_review_id uuid,
  target_resolution text,
  expected_revision bigint,
  requested_operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  response jsonb;
  platform_replay jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('rankings.write');
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  platform_replay := private.pachanga_platform_admin_replay_v1(
    requested_operation_id, 'ranking.integrity.resolve', 'ranking_integrity_review', target_review_id::text
  );
  if platform_replay is not null then return platform_replay; end if;
  response := private.pachanga_resolve_ranking_integrity_review_v1(
    target_review_id, target_resolution, expected_revision,
    requested_operation_id, actor_user_id, actor_role, reason
  );
  perform private.pachanga_record_ranking_admin_action_v1(
    requested_operation_id, actor_user_id, actor_role, 'ranking.integrity.resolve',
    'ranking_integrity_review', target_review_id::text, reason,
    jsonb_build_object('expectedRevision', expected_revision), response, response
  );
  return response;
end;
$$;

revoke all on function public.resolve_pachanga_ranking_integrity_v1(uuid, text, bigint, uuid, text)
  from public, anon, authenticated;
grant execute on function public.resolve_pachanga_ranking_integrity_v1(uuid, text, bigint, uuid, text)
  to authenticated;

create or replace function public.process_pachanga_ranking_refresh_queue_admin_v1(
  maximum_operations integer,
  expected_settings_revision bigint,
  requested_operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  settings_revision bigint;
  response jsonb;
  platform_replay jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('rankings.write');
  if requested_operation_id is null or expected_settings_revision is null
    or maximum_operations not between 1 and 50
    or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'Invalid ranking queue processing request';
  end if;
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  platform_replay := private.pachanga_platform_admin_replay_v1(
    requested_operation_id, 'ranking.refresh_queue.process', 'ranking_queue', 'global'
  );
  if platform_replay is not null then return platform_replay; end if;

  select settings.revision into settings_revision
  from private.pachanga_ranking_settings settings
  where settings.singleton
  for update;
  if settings_revision <> expected_settings_revision then
    raise exception 'Ranking settings revision mismatch' using errcode = '40001';
  end if;

  response := public.process_pachanga_ranking_refresh_queue_v1(maximum_operations)
    || jsonb_build_object(
      'settingsRevision', settings_revision,
      'operationId', requested_operation_id
    );
  perform private.pachanga_record_ranking_admin_action_v1(
    requested_operation_id, actor_user_id, actor_role, 'ranking.refresh_queue.process',
    'ranking_queue', 'global', reason,
    jsonb_build_object('expectedSettingsRevision', expected_settings_revision),
    response, response
  );
  return response;
end;
$$;

revoke all on function public.process_pachanga_ranking_refresh_queue_admin_v1(
  integer, bigint, uuid, text
) from public, anon, authenticated;
grant execute on function public.process_pachanga_ranking_refresh_queue_admin_v1(
  integer, bigint, uuid, text
) to authenticated;

alter function public.get_pachanga_platform_flags_v1()
  rename to get_pachanga_platform_flags_pre_ranking_v1;
alter function public.set_pachanga_platform_flag_v1(text, boolean, bigint, uuid, text)
  rename to set_pachanga_platform_flag_pre_ranking_v1;

create or replace function public.get_pachanga_platform_flags_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  legacy_flags jsonb;
  settings private.pachanga_ranking_settings%rowtype;
  ranking_health boolean;
begin
  legacy_flags := public.get_pachanga_platform_flags_pre_ranking_v1();
  select * into settings from private.pachanga_ranking_settings where singleton;
  select exists (
    select 1
    from private.pachanga_ranking_seasons seasons
    join public.pachanga_provincial_ranking_publications publications
      on publications.season_id = seasons.id
     and publications.published_revision = seasons.published_revision
    where seasons.status in ('open', 'frozen', 'closed')
      and seasons.published_revision > 0
      and seasons.last_error_code is null
      and publications.province_code = any(settings.pilot_province_codes)
  ) and not exists (
    select 1 from private.pachanga_ranking_refresh_queue
    where state = 'dead_letter'
  ) into ranking_health;
  return coalesce((
    select jsonb_agg(item order by ordinal)
    from jsonb_array_elements(coalesce(legacy_flags, '[]'::jsonb)) with ordinality rows(item, ordinal)
    where item ->> 'key' not in ('season_score_v3', 'provincial_rankings', 'provincial_awards')
  ), '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'key', 'season_score_v3', 'label', 'Season Score V3',
      'enabled', settings.season_score_product_enabled,
      'state', case when settings.season_score_product_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when ranking_health then 'READY_FOR_ACTIVATION' else 'NEEDS_PRODUCTIZATION' end,
      'readiness', case when ranking_health then 'READY' else 'DEPENDENCY' end,
      'readinessReason', case when ranking_health
        then 'Fórmula congelada, temporada, territorio y read model verificados.'
        else 'Falta una publicación sana y canónica para la provincia piloto.' end,
      'dependency', 'Season Score V3 + Rating V2 de solo lectura.',
      'mutable', true, 'sensitive', true, 'revision', settings.revision,
      'source', 'pachanga_season_score_snapshots'
    ),
    jsonb_build_object(
      'key', 'provincial_rankings', 'label', 'Rankings provinciales',
      'enabled', settings.provincial_rankings_product_enabled,
      'state', case when settings.provincial_rankings_product_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when ranking_health then 'READY_FOR_ACTIVATION' else 'NEEDS_PRODUCTIZATION' end,
      'readiness', case when ranking_health then 'READY' else 'DEPENDENCY' end,
      'readinessReason', case when ranking_health
        then 'Top público y posición propia servidos desde read model autoritativo.'
        else 'Read model o salud operativa no disponibles.' end,
      'dependency', 'Season Score productivo y provincia piloto publicada.',
      'mutable', true, 'sensitive', true, 'revision', settings.revision,
      'source', 'pachanga_provincial_ranking_entries'
    ),
    jsonb_build_object(
      'key', 'provincial_awards', 'label', 'Premios provinciales',
      'enabled', false, 'state', 'OFF', 'classification', 'BLOCKED',
      'readiness', 'BLOCKED',
      'readinessReason', 'Esta release calcula readiness, pero no concede premios.',
      'dependency', 'Decisión y release futura de awards.',
      'mutable', false, 'sensitive', true, 'revision', settings.revision,
      'source', 'ranking_trophy_readiness'
    )
  );
end;
$$;

revoke all on function public.get_pachanga_platform_flags_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_flags_v1()
  to authenticated;

create or replace function public.set_pachanga_platform_flag_v1(
  flag_key text,
  next_enabled boolean,
  expected_revision bigint,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_user_id uuid := (select auth.uid());
  actor_role text;
  requested_operation_id uuid := operation_id;
  settings private.pachanga_ranking_settings%rowtype;
  current_enabled boolean;
  next_revision bigint;
  sequence_value bigint;
  response jsonb;
  replay jsonb;
  ranking_health boolean;
begin
  if flag_key not in ('season_score_v3', 'provincial_rankings', 'provincial_awards') then
    return public.set_pachanga_platform_flag_pre_ranking_v1(
      flag_key, next_enabled, expected_revision, requested_operation_id, reason
    );
  end if;
  actor_role := private.pachanga_platform_require_v1('flags.write');
  if requested_operation_id is null or expected_revision is null
    or char_length(trim(coalesce(reason, ''))) < 3 then raise exception 'Invalid ranking flag request'; end if;
  if flag_key = 'provincial_awards' and next_enabled then
    raise exception 'Provincial awards remain disabled in Ranking Productization V1';
  end if;
  perform private.pachanga_lock_ranking_operation_v1(requested_operation_id);
  replay := private.pachanga_platform_admin_replay_v1(
    requested_operation_id, 'platform_flag.set', 'feature_flag', flag_key
  );
  if replay is not null then return replay; end if;

  select * into settings
  from private.pachanga_ranking_settings ranking_settings
  where ranking_settings.singleton
  for update;
  if settings.revision <> expected_revision then
    raise exception 'Feature flag changed before saving' using errcode = '40001';
  end if;
  current_enabled := case flag_key
    when 'season_score_v3' then settings.season_score_product_enabled
    when 'provincial_rankings' then settings.provincial_rankings_product_enabled
    else false
  end;

  select exists (
    select 1
    from private.pachanga_ranking_seasons seasons
    join public.pachanga_provincial_ranking_publications publications
      on publications.season_id = seasons.id
     and publications.published_revision = seasons.published_revision
    join private.pachanga_ranking_season_territories territories
      on territories.season_id = seasons.id
     and territories.province_code = publications.province_code
     and territories.product_enabled
    where seasons.status in ('open', 'frozen', 'closed')
      and seasons.published_revision > 0
      and seasons.last_error_code is null
      and publications.province_code = any(settings.pilot_province_codes)
      and publications.publication_checksum ~ '^[0-9a-f]{64}$'
  ) and not exists (
    select 1 from private.pachanga_ranking_refresh_queue where state = 'dead_letter'
  ) into ranking_health;
  if next_enabled and not ranking_health then
    raise exception 'Ranking product health gate failed';
  end if;
  if flag_key = 'provincial_rankings' and next_enabled
    and not settings.season_score_product_enabled then
    raise exception 'Season Score must be enabled before provincial rankings';
  end if;
  if flag_key = 'season_score_v3' and not next_enabled
    and settings.provincial_rankings_product_enabled then
    raise exception 'Disable provincial rankings before Season Score';
  end if;

  next_revision := settings.revision + 1;
  sequence_value := nextval('private.pachanga_ranking_sequence');
  update private.pachanga_ranking_settings ranking_settings
  set season_score_product_enabled = case flag_key
        when 'season_score_v3' then next_enabled else ranking_settings.season_score_product_enabled end,
      provincial_rankings_product_enabled = case flag_key
        when 'provincial_rankings' then next_enabled else ranking_settings.provincial_rankings_product_enabled end,
      provincial_awards_enabled = false,
      revision = next_revision,
      server_sequence = sequence_value,
      updated_by = actor_user_id,
      updated_at = clock_timestamp()
  where ranking_settings.singleton;
  response := jsonb_build_object(
    'key', flag_key,
    'enabled', case when flag_key = 'provincial_awards' then false else next_enabled end,
    'revision', next_revision,
    'serverSequence', sequence_value
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    requested_operation_id, actor_user_id, actor_role, 'platform_flag.set',
    'feature_flag', flag_key, trim(reason),
    jsonb_build_object('enabled', current_enabled, 'revision', settings.revision),
    response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_platform_flag_v1(text, boolean, bigint, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_pachanga_platform_flag_v1(text, boolean, bigint, uuid, text)
  to authenticated;

comment on table public.pachanga_provincial_ranking_entries is
  'Canonical minimized provincial ranking read model. Realtime invalidates by publication revision.';

reset lock_timeout;
reset statement_timeout;
