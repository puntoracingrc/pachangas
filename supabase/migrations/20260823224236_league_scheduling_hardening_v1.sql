-- Pachangas IQ R4B: relation guards, publication immutability and measured indexes.

set lock_timeout = '5s';
set statement_timeout = '120s';

create index if not exists pachanga_schedule_plans_competition_status_idx
  on public.pachanga_competition_schedule_plans(competition_id, status, server_sequence desc, id);
create index if not exists pachanga_schedule_revisions_plan_status_idx
  on public.pachanga_competition_schedule_revisions(schedule_plan_id, status, version desc, id);
create index if not exists pachanga_schedule_slots_scope_time_idx
  on public.pachanga_competition_schedule_slots(edition_id, stage_id, starts_at, id)
  where status <> 'retired';
create index if not exists pachanga_schedule_slots_resource_time_idx
  on public.pachanga_competition_schedule_slots(resource_key, starts_at, ends_at, id)
  where resource_key is not null and status <> 'retired';
create index if not exists pachanga_competition_rounds_revision_number_idx
  on public.pachanga_competition_rounds(schedule_revision_id, round_number, id);
create index if not exists pachanga_schedule_items_revision_round_idx
  on public.pachanga_competition_schedule_items(schedule_revision_id, round_id, status, id);
create index if not exists pachanga_schedule_items_home_calendar_idx
  on public.pachanga_competition_schedule_items(home_entry_id, scheduled_start, id)
  where status = 'published';
create index if not exists pachanga_schedule_items_away_calendar_idx
  on public.pachanga_competition_schedule_items(away_entry_id, scheduled_start, id)
  where status = 'published';
create index if not exists pachanga_schedule_conflicts_active_revision_idx
  on private.pachanga_competition_schedule_conflicts(schedule_revision_id, severity, conflict_type, id)
  where status = 'active';
create index if not exists pachanga_competition_context_round_time_idx
  on public.pachanga_competition_match_contexts(round_id, scheduled_start, id)
  where status = 'scheduled';

-- Every R4B foreign key has a leading index. Besides joins, these indexes keep
-- parent retirement and referential-integrity checks bounded as schedules grow.
create index if not exists pachanga_schedule_plans_category_fk_idx
  on public.pachanga_competition_schedule_plans(category_id);
create index if not exists pachanga_schedule_plans_group_fk_idx
  on public.pachanga_competition_schedule_plans(competition_group_id);
create index if not exists pachanga_schedule_plans_cancelled_by_fk_idx
  on public.pachanga_competition_schedule_plans(cancelled_by);
create index if not exists pachanga_schedule_plans_created_by_fk_idx
  on public.pachanga_competition_schedule_plans(created_by);
create index if not exists pachanga_schedule_plans_division_fk_idx
  on public.pachanga_competition_schedule_plans(division_id);
create index if not exists pachanga_schedule_plans_rule_revision_fk_idx
  on public.pachanga_competition_schedule_plans(rule_revision_id);
create index if not exists pachanga_schedule_plans_stage_fk_idx
  on public.pachanga_competition_schedule_plans(stage_id);
create index if not exists pachanga_schedule_plans_current_revision_fk_idx
  on public.pachanga_competition_schedule_plans(current_revision_id);

create index if not exists pachanga_schedule_revisions_supersedes_fk_idx
  on public.pachanga_competition_schedule_revisions(supersedes_revision_id);
create index if not exists pachanga_schedule_revisions_generated_by_fk_idx
  on public.pachanga_competition_schedule_revisions(generated_by);
create index if not exists pachanga_schedule_revisions_published_by_fk_idx
  on public.pachanga_competition_schedule_revisions(published_by);
create index if not exists pachanga_schedule_revisions_rule_revision_fk_idx
  on public.pachanga_competition_schedule_revisions(rule_revision_id);
create index if not exists pachanga_schedule_revisions_validated_by_fk_idx
  on public.pachanga_competition_schedule_revisions(validated_by);

create index if not exists pachanga_schedule_slots_group_fk_idx
  on public.pachanga_competition_schedule_slots(competition_group_id);
create index if not exists pachanga_schedule_slots_competition_fk_idx
  on public.pachanga_competition_schedule_slots(competition_id);
create index if not exists pachanga_schedule_slots_created_by_fk_idx
  on public.pachanga_competition_schedule_slots(created_by);
create index if not exists pachanga_schedule_slots_division_fk_idx
  on public.pachanga_competition_schedule_slots(division_id);
create index if not exists pachanga_schedule_slots_retired_by_fk_idx
  on public.pachanga_competition_schedule_slots(retired_by);
create index if not exists pachanga_schedule_slots_stage_fk_idx
  on public.pachanga_competition_schedule_slots(stage_id);

create index if not exists pachanga_rounds_category_fk_idx
  on public.pachanga_competition_rounds(category_id);
create index if not exists pachanga_rounds_group_fk_idx
  on public.pachanga_competition_rounds(competition_group_id);
create index if not exists pachanga_rounds_competition_fk_idx
  on public.pachanga_competition_rounds(competition_id);
create index if not exists pachanga_rounds_created_by_fk_idx
  on public.pachanga_competition_rounds(created_by);
create index if not exists pachanga_rounds_division_fk_idx
  on public.pachanga_competition_rounds(division_id);
create index if not exists pachanga_rounds_edition_fk_idx
  on public.pachanga_competition_rounds(edition_id);
create index if not exists pachanga_rounds_rule_revision_fk_idx
  on public.pachanga_competition_rounds(rule_revision_id);
create index if not exists pachanga_rounds_stage_fk_idx
  on public.pachanga_competition_rounds(stage_id);

create index if not exists pachanga_round_byes_entry_fk_idx
  on public.pachanga_competition_round_byes(entry_id);
create index if not exists pachanga_round_byes_revision_fk_idx
  on public.pachanga_competition_round_byes(schedule_revision_id);

create index if not exists pachanga_schedule_items_canonical_match_fk_idx
  on public.pachanga_competition_schedule_items(canonical_match_id);
create index if not exists pachanga_schedule_items_round_fk_idx
  on public.pachanga_competition_schedule_items(round_id);
create index if not exists pachanga_schedule_items_slot_fk_idx
  on public.pachanga_competition_schedule_items(slot_id);
create index if not exists pachanga_schedule_items_context_fk_idx
  on public.pachanga_competition_schedule_items(competition_match_context_id);
create index if not exists pachanga_schedule_validations_actor_fk_idx
  on public.pachanga_competition_schedule_validations(validated_by);

create index if not exists pachanga_schedule_conflicts_plan_fk_idx
  on private.pachanga_competition_schedule_conflicts(schedule_plan_id);
create index if not exists pachanga_schedule_conflicts_item_fk_idx
  on private.pachanga_competition_schedule_conflicts(schedule_item_id);
create index if not exists pachanga_schedule_conflicts_slot_fk_idx
  on private.pachanga_competition_schedule_conflicts(slot_id);
create index if not exists pachanga_schedule_conflicts_entry_fk_idx
  on private.pachanga_competition_schedule_conflicts(entry_id);

create index if not exists pachanga_competition_context_category_fk_idx
  on public.pachanga_competition_match_contexts(category_id);
create index if not exists pachanga_competition_context_home_entry_fk_idx
  on public.pachanga_competition_match_contexts(home_entry_id);
create index if not exists pachanga_competition_context_away_entry_fk_idx
  on public.pachanga_competition_match_contexts(away_entry_id);
create index if not exists pachanga_competition_context_slot_fk_idx
  on public.pachanga_competition_match_contexts(slot_id);

drop trigger if exists touch_pachanga_schedule_plans_v1 on public.pachanga_competition_schedule_plans;
create trigger touch_pachanga_schedule_plans_v1
before update on public.pachanga_competition_schedule_plans
for each row execute function private.pachanga_competition_touch_updated_at_v1();

drop trigger if exists touch_pachanga_schedule_slots_v1 on public.pachanga_competition_schedule_slots;
create trigger touch_pachanga_schedule_slots_v1
before update on public.pachanga_competition_schedule_slots
for each row execute function private.pachanga_competition_touch_updated_at_v1();

drop trigger if exists touch_pachanga_competition_rounds_v1 on public.pachanga_competition_rounds;
create trigger touch_pachanga_competition_rounds_v1
before update on public.pachanga_competition_rounds
for each row execute function private.pachanga_competition_touch_updated_at_v1();

drop trigger if exists touch_pachanga_schedule_items_v1 on public.pachanga_competition_schedule_items;
create trigger touch_pachanga_schedule_items_v1
before update on public.pachanga_competition_schedule_items
for each row execute function private.pachanga_competition_touch_updated_at_v1();

create or replace function private.pachanga_league_schedule_validate_relation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare round_row public.pachanga_competition_rounds%rowtype;
declare home_entry public.pachanga_competition_entries%rowtype;
declare away_entry public.pachanga_competition_entries%rowtype;
begin
  if tg_table_name = 'pachanga_competition_schedule_plans' then
    if not exists (
      select 1
      from public.pachanga_competition_editions editions
      join public.pachanga_competition_stages stages on stages.edition_id = editions.id
      join public.pachanga_competition_categories categories on categories.edition_id = editions.id
      join public.pachanga_competition_rule_revisions rules on rules.id = new.rule_revision_id
      join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = rules.rule_set_id
      where editions.id = new.edition_id and editions.competition_id = new.competition_id
        and stages.id = new.stage_id and categories.id = new.category_id
        and rule_sets.competition_id = new.competition_id
    ) then raise exception 'SCHEDULE_PLAN_RELATION_INVALID' using errcode = '23514'; end if;
    if new.current_revision_id is not null and not exists (
      select 1 from public.pachanga_competition_schedule_revisions revisions
      where revisions.id = new.current_revision_id and revisions.schedule_plan_id = new.id
    ) then raise exception 'SCHEDULE_CURRENT_REVISION_INVALID' using errcode = '23514'; end if;
  elsif tg_table_name = 'pachanga_competition_schedule_revisions' then
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = new.schedule_plan_id;
    if not found or new.rule_revision_id <> plan_row.rule_revision_id
       or new.engine_version <> plan_row.engine_version then
      raise exception 'SCHEDULE_REVISION_RELATION_INVALID' using errcode = '23514';
    end if;
    if new.supersedes_revision_id is not null and not exists (
      select 1 from public.pachanga_competition_schedule_revisions revisions
      where revisions.id = new.supersedes_revision_id
        and revisions.schedule_plan_id = new.schedule_plan_id
        and revisions.version < new.version
    ) then raise exception 'SCHEDULE_REVISION_LINEAGE_INVALID' using errcode = '23514'; end if;
  elsif tg_table_name = 'pachanga_competition_schedule_slots' then
    if not exists (
      select 1 from public.pachanga_competition_editions editions
      join public.pachanga_competition_stages stages on stages.edition_id = editions.id
      where editions.id = new.edition_id and editions.competition_id = new.competition_id
        and stages.id = new.stage_id
    ) then raise exception 'SCHEDULE_SLOT_SCOPE_INVALID' using errcode = '23514'; end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names zones where zones.name = new.timezone) then
      raise exception 'INVALID_TIMEZONE' using errcode = '23514';
    end if;
  elsif tg_table_name = 'pachanga_competition_rounds' then
    select * into revision_row from public.pachanga_competition_schedule_revisions revisions
    where revisions.id = new.schedule_revision_id;
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = revision_row.schedule_plan_id;
    if plan_row.id is null or new.competition_id <> plan_row.competition_id
       or new.edition_id <> plan_row.edition_id or new.category_id <> plan_row.category_id
       or new.stage_id <> plan_row.stage_id
       or new.division_id is distinct from plan_row.division_id
       or new.competition_group_id is distinct from plan_row.competition_group_id
       or new.rule_revision_id <> plan_row.rule_revision_id then
      raise exception 'SCHEDULE_ROUND_SCOPE_INVALID' using errcode = '23514';
    end if;
  elsif tg_table_name = 'pachanga_competition_schedule_items' then
    select * into revision_row from public.pachanga_competition_schedule_revisions revisions
    where revisions.id = new.schedule_revision_id;
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = revision_row.schedule_plan_id;
    select * into round_row from public.pachanga_competition_rounds rounds where rounds.id = new.round_id;
    select * into home_entry from public.pachanga_competition_entries entries where entries.id = new.home_entry_id;
    select * into away_entry from public.pachanga_competition_entries entries where entries.id = new.away_entry_id;
    if round_row.schedule_revision_id <> new.schedule_revision_id
       or home_entry.edition_id <> plan_row.edition_id
       or away_entry.edition_id <> plan_row.edition_id
       or home_entry.category_id <> plan_row.category_id
       or away_entry.category_id <> plan_row.category_id then
      raise exception 'SCHEDULE_ITEM_SCOPE_INVALID' using errcode = '23514';
    end if;
    if new.slot_id is not null and not exists (
      select 1 from public.pachanga_competition_schedule_slots slots
      where slots.id = new.slot_id and slots.edition_id = plan_row.edition_id
        and slots.stage_id = plan_row.stage_id
        and slots.division_id is not distinct from plan_row.division_id
        and slots.competition_group_id is not distinct from plan_row.competition_group_id
    ) then raise exception 'SCHEDULE_ITEM_SLOT_SCOPE_INVALID' using errcode = '23514'; end if;
  elsif tg_table_name = 'pachanga_competition_match_contexts' and new.source_kind = 'COMPETITION_GENERATED' then
    select * into round_row from public.pachanga_competition_rounds rounds where rounds.id = new.round_id;
    if round_row.id is null or round_row.competition_id <> new.competition_id
       or round_row.edition_id <> new.edition_id or round_row.stage_id <> new.stage_id
       or round_row.rule_revision_id <> new.rule_revision_id
       or not exists (
         select 1 from public.pachanga_competition_schedule_items items
         where items.id = new.schedule_item_id
           and items.round_id = new.round_id
           and items.home_entry_id = new.home_entry_id
           and items.away_entry_id = new.away_entry_id
           and items.slot_id = new.slot_id
       ) then raise exception 'COMPETITION_GENERATED_CONTEXT_INVALID' using errcode = '23514'; end if;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_schedule_validate_relation_v1()
  from public, anon, authenticated;

drop trigger if exists validate_pachanga_schedule_plan_relation_v1 on public.pachanga_competition_schedule_plans;
create constraint trigger validate_pachanga_schedule_plan_relation_v1
after insert or update on public.pachanga_competition_schedule_plans
deferrable initially deferred for each row
execute function private.pachanga_league_schedule_validate_relation_v1();

drop trigger if exists validate_pachanga_schedule_revision_relation_v1 on public.pachanga_competition_schedule_revisions;
create constraint trigger validate_pachanga_schedule_revision_relation_v1
after insert or update on public.pachanga_competition_schedule_revisions
deferrable initially deferred for each row
execute function private.pachanga_league_schedule_validate_relation_v1();

drop trigger if exists validate_pachanga_schedule_slot_relation_v1 on public.pachanga_competition_schedule_slots;
create constraint trigger validate_pachanga_schedule_slot_relation_v1
after insert or update on public.pachanga_competition_schedule_slots
deferrable initially deferred for each row
execute function private.pachanga_league_schedule_validate_relation_v1();

drop trigger if exists validate_pachanga_competition_round_relation_v1 on public.pachanga_competition_rounds;
create constraint trigger validate_pachanga_competition_round_relation_v1
after insert or update on public.pachanga_competition_rounds
deferrable initially deferred for each row
execute function private.pachanga_league_schedule_validate_relation_v1();

drop trigger if exists validate_pachanga_schedule_item_relation_v1 on public.pachanga_competition_schedule_items;
create constraint trigger validate_pachanga_schedule_item_relation_v1
after insert or update on public.pachanga_competition_schedule_items
deferrable initially deferred for each row
execute function private.pachanga_league_schedule_validate_relation_v1();

drop trigger if exists validate_pachanga_generated_context_relation_v1 on public.pachanga_competition_match_contexts;
create constraint trigger validate_pachanga_generated_context_relation_v1
after insert or update on public.pachanga_competition_match_contexts
deferrable initially deferred for each row
execute function private.pachanga_league_schedule_validate_relation_v1();

create or replace function private.pachanga_league_schedule_revision_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'SCHEDULE_REVISION_IMMUTABLE' using errcode = '55000';
  end if;
  if new.schedule_plan_id is distinct from old.schedule_plan_id
     or new.version is distinct from old.version
     or new.revision_kind is distinct from old.revision_kind
     or new.engine_version is distinct from old.engine_version
     or new.seed is distinct from old.seed
     or new.input_checksum is distinct from old.input_checksum
     or new.rule_revision_id is distinct from old.rule_revision_id
     or new.entry_snapshot_checksum is distinct from old.entry_snapshot_checksum
     or new.slot_snapshot_checksum is distinct from old.slot_snapshot_checksum
     or new.constraint_snapshot_checksum is distinct from old.constraint_snapshot_checksum
     or new.preference_snapshot_checksum is distinct from old.preference_snapshot_checksum
     or new.entry_order is distinct from old.entry_order
     or new.generated_by is distinct from old.generated_by
     or new.generated_at is distinct from old.generated_at
     or new.supersedes_revision_id is distinct from old.supersedes_revision_id
     or new.created_at is distinct from old.created_at then
    raise exception 'SCHEDULE_REVISION_IMMUTABLE' using errcode = '55000';
  end if;
  if old.status = 'published'
     and new.status = 'cancelled'
     and current_setting('pachangas.r4b_qa_archive', true) = 'on'
     and private.pachanga_competition_is_service_authority_v1() then
    if new.revision <> old.revision + 1 then
      raise exception 'SCHEDULE_REVISION_MONOTONICITY_REQUIRED' using errcode = 'PT409';
    end if;
    return new;
  end if;
  if old.status in ('published', 'superseded', 'cancelled') then
    raise exception 'SCHEDULE_REVISION_TERMINAL' using errcode = '55000';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception 'SCHEDULE_REVISION_MONOTONICITY_REQUIRED' using errcode = 'PT409';
  end if;
  if (old.status = 'generated' and new.status not in ('generated', 'validated', 'superseded', 'cancelled'))
     or (old.status = 'validated' and new.status not in ('generated', 'validated', 'published', 'superseded', 'cancelled')) then
    raise exception 'SCHEDULE_REVISION_TRANSITION_INVALID' using errcode = '23514';
  end if;
  if old.quality_score <> 0 and new.quality_score is distinct from old.quality_score then
    raise exception 'QUALITY_SNAPSHOT_IMMUTABLE' using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_schedule_revision_guard_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_schedule_revision_v1
  on public.pachanga_competition_schedule_revisions;
create trigger guard_pachanga_schedule_revision_v1
before update or delete on public.pachanga_competition_schedule_revisions
for each row execute function private.pachanga_league_schedule_revision_guard_v1();

create or replace function private.pachanga_league_schedule_round_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare is_current boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'SCHEDULE_ROUND_IMMUTABLE' using errcode = '55000';
  end if;
  if new.competition_id is distinct from old.competition_id
     or new.edition_id is distinct from old.edition_id
     or new.category_id is distinct from old.category_id
     or new.stage_id is distinct from old.stage_id
     or new.division_id is distinct from old.division_id
     or new.competition_group_id is distinct from old.competition_group_id
     or new.schedule_revision_id is distinct from old.schedule_revision_id
     or new.round_number is distinct from old.round_number
     or new.leg_number is distinct from old.leg_number
     or new.rule_revision_id is distinct from old.rule_revision_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'SCHEDULE_ROUND_IDENTITY_IMMUTABLE' using errcode = '55000';
  end if;
  if old.status = 'published'
     and new.status = 'cancelled'
     and current_setting('pachangas.r4b_qa_archive', true) = 'on'
     and private.pachanga_competition_is_service_authority_v1() then
    if new.revision <> old.revision + 1 then
      raise exception 'SCHEDULE_ROUND_MONOTONICITY_REQUIRED' using errcode = 'PT409';
    end if;
    return new;
  end if;
  if old.status in ('published', 'cancelled') then
    raise exception 'SCHEDULE_ROUND_TERMINAL' using errcode = '55000';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception 'SCHEDULE_ROUND_MONOTONICITY_REQUIRED' using errcode = 'PT409';
  end if;
  select exists (
    select 1
    from public.pachanga_competition_schedule_plans plans
    where plans.current_revision_id = old.schedule_revision_id
  ) into is_current;
  if is_current and (
    new.display_name is distinct from old.display_name
    or new.starts_at is distinct from old.starts_at
    or new.ends_at is distinct from old.ends_at
  ) then raise exception 'SCHEDULE_ROUND_REQUIRES_NEW_REVISION' using errcode = 'PT409'; end if;
  return new;
end;
$$;

create or replace function public.archive_pachanga_league_schedule_qa_v1(
  operation_id uuid,
  target_schedule_plan_id uuid,
  expected_revision bigint,
  reason text,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  action_name constant text := 'league_schedule.qa_archive';
  plan_row public.pachanga_competition_schedule_plans%rowtype;
  competition_slug text;
  organizer_group_id uuid;
  organizer_club_id uuid;
  request_hash text;
  replay jsonb;
  metadata jsonb;
  sequence_value bigint;
  confirmed_at timestamptz := clock_timestamp();
  confirmed_revision bigint;
  response jsonb;
  payload jsonb;
  retired_contexts integer := 0;
  retired_bindings integer := 0;
  retired_canonical_matches integer := 0;
  retired_slots integer := 0;
  cancelled_rounds integer := 0;
begin
  if not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'SERVICE_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  if operation_id is null or target_schedule_plan_id is null
     or expected_revision is null or expected_revision < 1
     or reason is null or trim(reason) !~ '^R4B_STAGING_QA_ARCHIVE:'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_R4B_QA_ARCHIVE_COMMAND' using errcode = '22023';
  end if;
  payload := jsonb_build_object('reason', left(trim(reason), 240));
  request_hash := private.pachanga_competition_request_hash_v1(
    action_name, target_schedule_plan_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended('r4b-qa-archive:' || operation_id::text, 0));
  replay := private.pachanga_competition_replay_v1(
    operation_id, null, 'service_authority', action_name,
    target_schedule_plan_id, request_hash
  );
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended('r4b-schedule:' || target_schedule_plan_id::text, 0));

  select * into plan_row
  from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id
  for update;
  if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select competitions.slug, competitions.organizer_group_id, competitions.organizer_club_id
  into competition_slug, organizer_group_id, organizer_club_id
  from public.pachanga_competitions competitions
  where competitions.id = plan_row.competition_id;
  if competition_slug not like 'r4b-qa-%' then
    raise exception 'R4B_QA_ARCHIVE_SCOPE_FORBIDDEN' using errcode = '42501';
  end if;
  if plan_row.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if plan_row.status not in ('draft', 'generated', 'validated', 'published', 'cancelled') then
    raise exception 'R4B_QA_ARCHIVE_STATUS_FORBIDDEN' using errcode = '22023';
  end if;

  sequence_value := nextval('private.pachanga_competition_sequence');
  metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  perform set_config('pachangas.r4b_qa_archive', 'on', true);

  update public.pachanga_competition_match_contexts contexts set
    status = 'retired', revision = contexts.revision + 1,
    server_sequence = sequence_value
  where contexts.status = 'scheduled'
    and contexts.schedule_item_id in (
      select items.id from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = plan_row.current_revision_id
    );
  get diagnostics retired_contexts = row_count;

  update public.pachanga_canonical_match_bindings bindings set
    binding_status = 'retired', revision = bindings.revision + 1,
    server_sequence = sequence_value
  where bindings.source_kind = 'competition_generated'
    and bindings.binding_status = 'active'
    and bindings.source_id in (
      select items.id::text from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = plan_row.current_revision_id
    );
  get diagnostics retired_bindings = row_count;

  update public.pachanga_canonical_matches canonical_matches set
    status = 'retired', revision = canonical_matches.revision + 1,
    server_sequence = sequence_value
  where canonical_matches.status = 'active'
    and canonical_matches.id in (
      select items.canonical_match_id
      from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = plan_row.current_revision_id
        and items.canonical_match_id is not null
    )
    and not exists (
      select 1 from public.pachanga_canonical_match_bindings bindings
      where bindings.canonical_match_id = canonical_matches.id
        and bindings.binding_status = 'active'
    );
  get diagnostics retired_canonical_matches = row_count;

  update public.pachanga_competition_schedule_slots slots set
    status = 'retired', retired_by = null, retired_at = confirmed_at,
    revision = slots.revision + 1, server_sequence = sequence_value
  where slots.status <> 'retired'
    and slots.competition_id = plan_row.competition_id
    and slots.edition_id = plan_row.edition_id
    and slots.stage_id = plan_row.stage_id
    and slots.division_id is not distinct from plan_row.division_id
    and slots.competition_group_id is not distinct from plan_row.competition_group_id;
  get diagnostics retired_slots = row_count;

  update public.pachanga_competition_rounds rounds set
    status = 'cancelled', revision = rounds.revision + 1,
    server_sequence = sequence_value
  where rounds.schedule_revision_id = plan_row.current_revision_id
    and rounds.status <> 'cancelled';
  get diagnostics cancelled_rounds = row_count;

  update public.pachanga_competition_schedule_revisions revisions set
    status = 'cancelled', revision = revisions.revision + 1,
    server_sequence = sequence_value
  where revisions.id = plan_row.current_revision_id
    and revisions.status in ('generated', 'validated', 'published');

  update public.pachanga_competition_schedule_plans plans set
    status = 'cancelled', cancelled_by = null, cancelled_at = confirmed_at,
    revision = plans.revision + 1, server_sequence = sequence_value
  where plans.id = plan_row.id
  returning plans.revision into confirmed_revision;

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedRevision', confirmed_revision,
    'confirmedAt', confirmed_at,
    'serverSequence', sequence_value,
    'snapshot', jsonb_build_object(
      'planId', plan_row.id,
      'status', 'cancelled',
      'retiredContexts', retired_contexts,
      'retiredBindings', retired_bindings,
      'retiredCanonicalMatches', retired_canonical_matches,
      'retiredSlots', retired_slots,
      'cancelledRounds', cancelled_rounds
    ),
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'league_schedule', 'entityId', plan_row.id,
      'revision', confirmed_revision
    ))
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, null, 'service_authority', 'league_schedule', plan_row.id::text,
    plan_row.competition_id, action_name, confirmed_revision, sequence_value,
    left(trim(reason), 120), response -> 'snapshot', confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, plan_row.competition_id, organizer_group_id, organizer_club_id, null, null,
    'league_schedule', plan_row.id::text, confirmed_revision, confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    operation_id, null, 'service_authority', action_name,
    'league_schedule', plan_row.id::text, request_hash, confirmed_revision,
    sequence_value, metadata, response, confirmed_at
  );
  return response;
end;
$$;

revoke all on function public.archive_pachanga_league_schedule_qa_v1(
  uuid, uuid, bigint, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.archive_pachanga_league_schedule_qa_v1(
  uuid, uuid, bigint, text, jsonb
) to service_role;

comment on function public.archive_pachanga_league_schedule_qa_v1(uuid, uuid, bigint, text, jsonb) is
  'Service-only, idempotent cleanup for R4B staging schedules whose competition slug starts with r4b-qa-. It safely cancels unpublished work or retires generated authorities without deleting audit history.';

revoke all on function private.pachanga_league_schedule_round_guard_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_schedule_round_v1 on public.pachanga_competition_rounds;
create trigger guard_pachanga_schedule_round_v1
before update or delete on public.pachanga_competition_rounds
for each row execute function private.pachanga_league_schedule_round_guard_v1();

create or replace function private.pachanga_league_schedule_item_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare is_current boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'SCHEDULE_ITEM_IMMUTABLE' using errcode = '55000';
  end if;
  if new.schedule_revision_id is distinct from old.schedule_revision_id
     or new.pairing_key is distinct from old.pairing_key
     or new.leg_number is distinct from old.leg_number
     or new.created_at is distinct from old.created_at then
    raise exception 'SCHEDULE_ITEM_IDENTITY_IMMUTABLE' using errcode = '55000';
  end if;
  if old.status = 'published' then
    raise exception 'SCHEDULE_ITEM_TERMINAL' using errcode = '55000';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception 'SCHEDULE_ITEM_MONOTONICITY_REQUIRED' using errcode = 'PT409';
  end if;
  select exists (
    select 1
    from public.pachanga_competition_schedule_plans plans
    where plans.current_revision_id = old.schedule_revision_id
  ) into is_current;
  if is_current and (
    new.round_id is distinct from old.round_id
    or new.home_entry_id is distinct from old.home_entry_id
    or new.away_entry_id is distinct from old.away_entry_id
    or new.slot_id is distinct from old.slot_id
    or new.scheduled_start is distinct from old.scheduled_start
    or new.scheduled_end is distinct from old.scheduled_end
    or new.timezone is distinct from old.timezone
    or new.venue_id is distinct from old.venue_id
    or new.venue_label is distinct from old.venue_label
    or new.venue_status is distinct from old.venue_status
  ) then raise exception 'SCHEDULE_ITEM_REQUIRES_NEW_REVISION' using errcode = 'PT409'; end if;
  if (new.canonical_match_id is distinct from old.canonical_match_id
      or new.competition_match_context_id is distinct from old.competition_match_context_id)
     and new.status <> 'published' then
    raise exception 'SCHEDULE_ITEM_PUBLICATION_BINDING_INVALID' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_schedule_item_guard_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_schedule_item_v1 on public.pachanga_competition_schedule_items;
create trigger guard_pachanga_schedule_item_v1
before update or delete on public.pachanga_competition_schedule_items
for each row execute function private.pachanga_league_schedule_item_guard_v1();

do $$
declare target_table regclass;
begin
  foreach target_table in array array[
    'public.pachanga_competition_round_byes'::regclass,
    'public.pachanga_competition_schedule_validations'::regclass,
    'private.pachanga_competition_schedule_conflicts'::regclass,
    'private.pachanga_competition_schedule_quality_snapshots'::regclass
  ] loop
    execute format('drop trigger if exists guard_r4b_append_only_v1 on %s', target_table);
    execute format(
      'create trigger guard_r4b_append_only_v1 before update or delete on %s for each row execute function private.pachanga_competition_immutable_ledger_v1()',
      target_table
    );
  end loop;
end;
$$;
