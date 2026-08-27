-- Pachangas IQ R6A: sanitized Tournament read models and invalidation-only Realtime.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_tournament_actor_organizers_v1(
  target_actor_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with actor_organizers as (
    select 'TEAM'::text as organizer_kind, groups.id as organizer_id,
      groups.name as organizer_name,
      coalesce((select states.revision
        from public.pachanga_competition_organizer_states states
        where states.organizer_kind = 'TEAM' and states.organizer_group_id = groups.id), 0) as organizer_revision,
      case when groups.owner_id = target_actor_id then 'team_owner' else 'team_admin' end as actor_role
    from public.pachanga_groups groups
    where groups.owner_id = target_actor_id
       or exists (
         select 1 from public.pachanga_group_members members
         where members.group_id = groups.id and members.user_id = target_actor_id
           and members.role in ('owner','admin')
       )
    union all
    select 'CLUB'::text, clubs.id, clubs.name,
      coalesce((select states.revision
        from public.pachanga_competition_organizer_states states
        where states.organizer_kind = 'CLUB' and states.organizer_club_id = clubs.id), 0),
      private.pachanga_club_active_role_v1(clubs.id, target_actor_id)
    from public.pachanga_clubs clubs
    where clubs.operational_status = 'active'
      and private.pachanga_club_active_role_v1(clubs.id, target_actor_id)
        in ('club_owner','club_competition_manager')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', organizers.organizer_kind,
    'id', organizers.organizer_id,
    'name', organizers.organizer_name,
    'organizerRevision', organizers.organizer_revision,
    'actorRole', organizers.actor_role,
    'bundle', private.pachanga_tournament_bundle_snapshot_v1(
      organizers.organizer_kind, organizers.organizer_id
    )
  ) order by organizers.organizer_name, organizers.organizer_id), '[]'::jsonb)
  from actor_organizers organizers;
$$;

create or replace function private.pachanga_tournament_plan_input_fresh_v1(
  target_plan_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare current_revision_id uuid;
begin
  select plans.current_revision_id into current_revision_id
  from public.pachanga_competition_draw_plans plans
  where plans.id = target_plan_id;
  if not found then return false; end if;
  if current_revision_id is null then return true; end if;
  begin
    perform private.pachanga_tournament_assert_input_fresh_v1(target_plan_id);
    perform private.pachanga_tournament_assert_revision_current_v1(target_plan_id);
    return true;
  exception
    when sqlstate 'PT409' or sqlstate '22023' or sqlstate 'P0002' then return false;
  end;
end;
$$;

create or replace function private.pachanga_tournament_plan_summary_v1(
  target_plan_id uuid,
  include_private boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare revision_row public.pachanga_competition_draw_revisions%rowtype;
declare result jsonb;
declare placements jsonb := '[]'::jsonb;
declare byes jsonb := '[]'::jsonb;
declare quality jsonb;
declare pots jsonb := '[]'::jsonb;
declare constraints jsonb := '[]'::jsonb;
declare locks jsonb := '[]'::jsonb;
begin
  select * into plan_row
  from public.pachanga_competition_draw_plans plans where plans.id = target_plan_id;
  if not found then return null; end if;

  if plan_row.current_revision_id is not null then
    select * into revision_row
    from public.pachanga_competition_draw_revisions revisions
    where revisions.id = plan_row.current_revision_id;
    placements := private.pachanga_tournament_revision_placements_v1(revision_row.id);
    byes := private.pachanga_tournament_revision_byes_v1(revision_row.id);
    select jsonb_build_object(
      'hardViolations', snapshots.hard_violations,
      'softScore', snapshots.soft_score,
      'levelBalance', snapshots.level_balance,
      'sameClubCollisions', snapshots.same_club_collisions,
      'potDistribution', snapshots.pot_distribution,
      'seedDistribution', snapshots.seed_distribution,
      'groupSizeBalance', snapshots.group_size_balance,
      'manualOverrideCount', snapshots.manual_override_count,
      'unassignedEntries', snapshots.unassigned_entries,
      'explanations', case when include_private then snapshots.explanations else '[]'::jsonb end,
      'checksum', snapshots.checksum
    ) into quality
    from public.pachanga_competition_draw_quality_snapshots snapshots
    where snapshots.draw_revision_id = revision_row.id;
  end if;

  if include_private then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', pots_table.id, 'potNumber', pots_table.pot_number,
      'label', pots_table.label, 'capacity', pots_table.capacity,
      'entryIds', to_jsonb(pots_table.entry_ids),
      'seedingPolicy', pots_table.seeding_policy,
      'seedingSnapshot', pots_table.seeding_snapshot,
      'status', pots_table.status, 'revision', pots_table.revision,
      'serverSequence', pots_table.server_sequence
    ) order by pots_table.pot_number, pots_table.server_sequence, pots_table.id), '[]'::jsonb)
    into pots
    from public.pachanga_competition_draw_pots pots_table
    where pots_table.draw_plan_id = plan_row.id and pots_table.status = 'active';

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', draw_constraints.id, 'type', draw_constraints.constraint_type,
      'strength', draw_constraints.strength, 'weight', draw_constraints.weight,
      'scope', draw_constraints.scope, 'parameters', draw_constraints.parameters,
      'reason', draw_constraints.reason,
      'publicAttribution', draw_constraints.public_attribution,
      'revision', draw_constraints.revision,
      'serverSequence', draw_constraints.server_sequence
    ) order by draw_constraints.server_sequence, draw_constraints.id), '[]'::jsonb)
    into constraints
    from public.pachanga_competition_draw_constraints draw_constraints
    where draw_constraints.draw_plan_id = plan_row.id and draw_constraints.status = 'active';

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', manual_locks.id, 'lockType', manual_locks.lock_type,
      'entryId', manual_locks.entry_id, 'relatedEntryId', manual_locks.related_entry_id,
      'targetGroupNumber', manual_locks.target_group_number,
      'targetSlot', manual_locks.target_slot, 'targetHalf', manual_locks.target_half,
      'potNumber', manual_locks.pot_number, 'reason', manual_locks.reason,
      'revision', manual_locks.revision, 'serverSequence', manual_locks.server_sequence
    ) order by manual_locks.server_sequence, manual_locks.id), '[]'::jsonb)
    into locks
    from public.pachanga_competition_draw_manual_locks manual_locks
    where manual_locks.draw_plan_id = plan_row.id and manual_locks.status = 'active';
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', draw_constraints.id, 'type', draw_constraints.constraint_type,
      'strength', draw_constraints.strength, 'scope', draw_constraints.scope,
      'parameters', draw_constraints.parameters,
      'reason', draw_constraints.reason
    ) order by draw_constraints.server_sequence, draw_constraints.id), '[]'::jsonb)
    into constraints
    from public.pachanga_competition_draw_constraints draw_constraints
    where draw_constraints.draw_plan_id = plan_row.id
      and draw_constraints.status = 'active'
      and draw_constraints.public_attribution;
  end if;

  result := jsonb_build_object(
    'id', plan_row.id, 'competitionId', plan_row.competition_id,
    'editionId', plan_row.edition_id, 'stageId', plan_row.stage_id,
    'targetType', plan_row.target_type, 'mode', plan_row.mode,
    'status', plan_row.status, 'participantFreezeId', plan_row.participant_freeze_id,
    'currentRevisionId', plan_row.current_revision_id,
    'ruleRevisionId', plan_row.rule_revision_id,
    'groupCount', plan_row.group_count, 'slotCount', plan_row.slot_count,
    'qualifiersPerGroup', plan_row.qualifiers_per_group,
    'revision', plan_row.revision, 'serverSequence', plan_row.server_sequence,
    'inputFresh', private.pachanga_tournament_plan_input_fresh_v1(plan_row.id),
    'updatedAt', plan_row.updated_at, 'publishedAt', plan_row.published_at,
    'revisionSnapshot', case when revision_row.id is null then null else jsonb_build_object(
      'id', revision_row.id, 'version', revision_row.version,
      'mode', revision_row.mode, 'algorithmVersion', revision_row.algorithm_version,
      'seedMode', revision_row.seed_mode,
      'seed', case when revision_row.seed_revealed or include_private then revision_row.seed else null end,
      'seedRevealed', revision_row.seed_revealed,
      'inputChecksum', revision_row.input_checksum,
      'participantChecksum', revision_row.participant_checksum,
      'potChecksum', revision_row.pot_checksum,
      'constraintChecksum', revision_row.constraint_checksum,
      'manualLockChecksum', revision_row.manual_lock_checksum,
      'resultChecksum', revision_row.result_checksum,
      'validationStatus', revision_row.validation_status,
      'qualityScore', revision_row.quality_score,
      'generatedAt', revision_row.generated_at,
      'serverSequence', revision_row.server_sequence
    ) end,
    'placements', placements, 'byes', byes,
    'pots', pots, 'constraints', constraints, 'manualLocks', locks,
    'quality', quality,
    'diff', case when revision_row.id is null then null
      else private.pachanga_tournament_revision_diff_v1(revision_row.id) end
  );
  return result;
end;
$$;

create or replace function private.pachanga_tournament_revision_diff_v1(
  target_revision_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with current_revision as (
    select revisions.*
    from public.pachanga_competition_draw_revisions revisions
    where revisions.id = target_revision_id
  ), previous_revision as (
    select previous.*
    from current_revision current
    join public.pachanga_competition_draw_revisions previous
      on previous.id = current.supersedes_revision_id
  ), current_placements as (
    select placements.entry_id, placements.group_number,
      placements.seed_number, placements.slot_number
    from public.pachanga_competition_draw_placements placements
    where placements.draw_revision_id = target_revision_id
  ), previous_placements as (
    select placements.entry_id, placements.group_number,
      placements.seed_number, placements.slot_number
    from previous_revision previous
    join public.pachanga_competition_draw_placements placements
      on placements.draw_revision_id = previous.id
  ), moved as (
    select coalesce(current.entry_id, previous.entry_id) as entry_id,
      previous.group_number as previous_group_number,
      current.group_number as current_group_number,
      previous.seed_number as previous_seed_number,
      current.seed_number as current_seed_number,
      previous.slot_number as previous_slot_number,
      current.slot_number as current_slot_number
    from current_placements current
    full join previous_placements previous on previous.entry_id = current.entry_id
    where row(previous.group_number, previous.seed_number, previous.slot_number)
      is distinct from row(current.group_number, current.seed_number, current.slot_number)
  )
  select jsonb_build_object(
    'supersedesRevisionId', current.supersedes_revision_id,
    'teamsMoved', coalesce((select jsonb_agg(jsonb_build_object(
      'entryId', moved.entry_id,
      'previousGroupNumber', moved.previous_group_number,
      'currentGroupNumber', moved.current_group_number,
      'previousSeedNumber', moved.previous_seed_number,
      'currentSeedNumber', moved.current_seed_number,
      'previousSlotNumber', moved.previous_slot_number,
      'currentSlotNumber', moved.current_slot_number
    ) order by moved.entry_id) from moved), '[]'::jsonb),
    'seedChanged', previous.id is not null and previous.seed is distinct from current.seed,
    'constraintChecksumChanged', previous.id is not null
      and previous.constraint_checksum is distinct from current.constraint_checksum,
    'manualLockChecksumChanged', previous.id is not null
      and previous.manual_lock_checksum is distinct from current.manual_lock_checksum,
    'quality', jsonb_build_object(
      'previous', previous.quality_score,
      'current', current.quality_score
    )
  )
  from current_revision current
  left join previous_revision previous on true;
$$;

create or replace function public.get_pachanga_tournament_flags_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'flags', private.pachanga_tournament_flags_v1(),
    'organizers', private.pachanga_tournament_actor_organizers_v1(actor_id),
    'updatedAt', statement_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_tournament_home_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare tournaments jsonb;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', visible.id, 'name', visible.name, 'slug', visible.slug,
    'status', visible.status, 'visibility', visible.visibility,
    'organizerKind', visible.organizer_kind,
    'organizerId', coalesce(visible.organizer_group_id, visible.organizer_club_id),
    'tournamentRevision', visible.tournament_revision,
    'serverSequence', visible.server_sequence, 'updatedAt', visible.updated_at,
    'drawPlan', case when plans.id is null then null else jsonb_build_object(
      'id', plans.id, 'mode', plans.mode, 'status', plans.status,
      'targetType', plans.target_type, 'revision', plans.revision,
      'serverSequence', plans.server_sequence
    ) end,
    'canManage', private.pachanga_tournament_can_v1(visible.id, actor_id, 'manage'),
    'canDraw', private.pachanga_tournament_can_v1(visible.id, actor_id, 'draw_manage')
  ) order by visible.updated_at desc, visible.server_sequence desc, visible.id), '[]'::jsonb)
  into tournaments
  from public.pachanga_competitions visible
  left join lateral (
    select draw_plans.* from public.pachanga_competition_draw_plans draw_plans
    where draw_plans.competition_id = visible.id
    order by draw_plans.server_sequence desc, draw_plans.id desc limit 1
  ) plans on true
  where visible.competition_type = 'TOURNAMENT'
    and visible.product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
    and private.pachanga_tournament_can_v1(visible.id, actor_id, 'read');

  return jsonb_build_object(
    'flags', private.pachanga_tournament_flags_v1(),
    'organizers', private.pachanga_tournament_actor_organizers_v1(actor_id),
    'tournaments', tournaments,
    'remoteWrites', 0,
    'updatedAt', statement_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_tournament_snapshot_v1(
  competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare competition_row public.pachanga_competitions%rowtype;
declare manager boolean;
declare entries jsonb;
declare plans jsonb;
begin
  if actor_id is null or not private.pachanga_tournament_can_v1($1, actor_id, 'read') then
    raise exception 'TOURNAMENT_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = $1;
  if not found then raise exception 'TOURNAMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  manager := private.pachanga_tournament_can_v1($1, actor_id, 'draw_read');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', entries_table.id, 'teamId', entries_table.team_id,
    'teamName', teams.name, 'teamCrest', teams.payload -> 'teamCrest',
    'status', entries_table.status, 'revision', entries_table.revision,
    'serverSequence', entries_table.server_sequence
  ) order by entries_table.server_sequence, entries_table.id), '[]'::jsonb)
  into entries
  from public.pachanga_competition_entries entries_table
  join public.pachanga_groups teams on teams.id = entries_table.team_id
  where entries_table.competition_id = $1
    and (manager or entries_table.status in ('accepted','active','completed'));

  select coalesce(jsonb_agg(
    private.pachanga_tournament_plan_summary_v1(draw_plans.id, manager)
    order by draw_plans.server_sequence, draw_plans.id
  ), '[]'::jsonb) into plans
  from public.pachanga_competition_draw_plans draw_plans
  where draw_plans.competition_id = $1
    and (manager or draw_plans.status = 'published');

  return jsonb_build_object(
    'competition', jsonb_build_object(
      'id', competition_row.id, 'name', competition_row.name,
      'slug', competition_row.slug, 'description', competition_row.description,
      'status', competition_row.status, 'visibility', competition_row.visibility,
      'organizerKind', competition_row.organizer_kind,
      'organizerId', coalesce(competition_row.organizer_group_id, competition_row.organizer_club_id),
      'tournamentRevision', competition_row.tournament_revision,
      'serverSequence', competition_row.server_sequence,
      'updatedAt', competition_row.updated_at
    ),
    'entries', entries, 'drawPlans', plans,
    'authoringContext', (
      select jsonb_build_object(
        'editionId', editions.id,
        'stageId', stages.id,
        'ruleRevisionId', editions.rule_revision_id,
        'editionStatus', editions.status,
        'stageStatus', stages.status
      )
      from public.pachanga_competition_editions editions
      join public.pachanga_competition_stages stages on stages.edition_id = editions.id
      where editions.competition_id = $1
      order by editions.server_sequence desc, stages.stage_order, stages.id
      limit 1
    ),
    'capabilities', jsonb_build_object(
      'manage', private.pachanga_tournament_can_v1($1, actor_id, 'manage'),
      'participantsManage', private.pachanga_tournament_can_v1($1, actor_id, 'participants_manage'),
      'drawRead', manager,
      'drawManage', private.pachanga_tournament_can_v1($1, actor_id, 'draw_manage'),
      'drawValidate', private.pachanga_tournament_can_v1($1, actor_id, 'draw_validate'),
      'drawPublish', private.pachanga_tournament_can_v1($1, actor_id, 'draw_publish')
    ),
    'revision', competition_row.tournament_revision,
    'serverSequence', competition_row.server_sequence,
    'updatedAt', competition_row.updated_at
  );
end;
$$;

create or replace function public.get_pachanga_tournament_draw_desk_v1(
  competition_id uuid,
  draw_plan_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare freeze_snapshot jsonb;
begin
  if actor_id is null
     or not private.pachanga_tournament_can_v1($1, actor_id, 'draw_read') then
    raise exception 'TOURNAMENT_DRAW_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into plan_row from public.pachanga_competition_draw_plans plans
  where plans.id = $2 and plans.competition_id = $1;
  if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select jsonb_build_object(
    'id', freezes.id, 'participantCount', freezes.participant_count,
    'entryIds', to_jsonb(freezes.entry_ids), 'entries', freezes.entry_snapshot,
    'rosterReadiness', freezes.roster_readiness,
    'seedingSnapshot', freezes.seeding_snapshot,
    'clubRelationshipSnapshot', freezes.club_relationship_snapshot,
    'checksum', freezes.checksum, 'tournamentRevision', freezes.tournament_revision,
    'serverSequence', freezes.server_sequence, 'frozenAt', freezes.frozen_at
  ) into freeze_snapshot
  from public.pachanga_competition_participant_freezes freezes
  where freezes.id = plan_row.participant_freeze_id;
  return jsonb_build_object(
    'flags', private.pachanga_tournament_flags_v1(),
    'plan', private.pachanga_tournament_plan_summary_v1($2, true),
    'participantFreeze', freeze_snapshot,
    'capabilities', jsonb_build_object(
      'manage', private.pachanga_tournament_can_v1($1, actor_id, 'draw_manage'),
      'validate', private.pachanga_tournament_can_v1($1, actor_id, 'draw_validate'),
      'publish', private.pachanga_tournament_can_v1($1, actor_id, 'draw_publish')
    ),
    'revision', plan_row.revision,
    'expectedRevision', (
      select competitions.tournament_revision
      from public.pachanga_competitions competitions
      where competitions.id = plan_row.competition_id
    ),
    'serverSequence', plan_row.server_sequence,
    'updatedAt', plan_row.updated_at
  );
end;
$$;

create or replace function public.get_pachanga_tournament_draw_audit_v1(
  competition_id uuid,
  draw_plan_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare revision_row public.pachanga_competition_draw_revisions%rowtype;
declare public_constraints jsonb;
declare public_placements jsonb;
declare override_count integer;
begin
  if actor_id is null or not private.pachanga_tournament_can_v1($1, actor_id, 'read') then
    raise exception 'TOURNAMENT_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into plan_row from public.pachanga_competition_draw_plans plans
  where plans.id = $2 and plans.competition_id = $1
    and plans.status = 'published';
  if not found then raise exception 'PUBLISHED_DRAW_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into revision_row from public.pachanga_competition_draw_revisions revisions
  where revisions.id = plan_row.current_revision_id and revisions.seed_revealed;
  if not found then raise exception 'PUBLISHED_DRAW_NOT_FOUND' using errcode = 'P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', constraints.constraint_type, 'strength', constraints.strength,
    'scope', constraints.scope, 'parameters', constraints.parameters,
    'reason', constraints.reason
  ) order by constraints.server_sequence, constraints.id), '[]'::jsonb)
  into public_constraints
  from public.pachanga_competition_draw_constraints constraints
  where constraints.draw_plan_id = $2 and constraints.status = 'active'
    and constraints.public_attribution;
  select count(*) into override_count
  from public.pachanga_competition_draw_placements placements
  where placements.draw_revision_id = revision_row.id
    and placements.placement_source in ('MANUAL','LOCKED','HYBRID_FILL');
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'entryId', placements.entry_id,
    'teamName', frozen.entry ->> 'teamName',
    'teamCrest', frozen.entry -> 'teamCrest',
    'groupNumber', placements.group_number,
    'slotNumber', placements.slot_number,
    'seedNumber', placements.seed_number,
    'potNumber', placements.pot_number,
    'placementSource', placements.placement_source,
    'serverSequence', placements.server_sequence
  )) order by placements.group_number nulls last, placements.slot_number nulls last,
    placements.seed_number nulls last, placements.server_sequence, placements.id), '[]'::jsonb)
  into public_placements
  from public.pachanga_competition_draw_placements placements
  join public.pachanga_competition_participant_freezes freezes
    on freezes.id = plan_row.participant_freeze_id
  left join lateral jsonb_array_elements(freezes.entry_snapshot) frozen(entry)
    on frozen.entry ->> 'entryId' = placements.entry_id::text
  where placements.draw_revision_id = revision_row.id;
  return jsonb_build_object(
    'competitionId', $1, 'drawPlanId', $2,
    'drawRevisionId', revision_row.id, 'version', revision_row.version,
    'mode', revision_row.mode, 'algorithmVersion', revision_row.algorithm_version,
    'seedMode', revision_row.seed_mode, 'seed', revision_row.seed,
    'inputChecksum', revision_row.input_checksum,
    'participantChecksum', revision_row.participant_checksum,
    'potChecksum', revision_row.pot_checksum,
    'constraintChecksum', revision_row.constraint_checksum,
    'manualLockChecksum', revision_row.manual_lock_checksum,
    'resultChecksum', revision_row.result_checksum,
    'validationStatus', revision_row.validation_status,
    'constraints', public_constraints,
    'manualOverrideCount', override_count,
    'placements', public_placements,
    'byes', private.pachanga_tournament_revision_byes_v1(revision_row.id),
    'publishedAt', plan_row.published_at,
    'serverSequence', revision_row.server_sequence
  );
end;
$$;

create or replace function public.get_pachanga_platform_tournament_control_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare metrics jsonb;
declare grants jsonb;
declare recent_plans jsonb;
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  with tournament_set as (
    select competitions.id, competitions.status
    from public.pachanga_competitions competitions
    where competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
  ), freeze_set as (
    select freezes.id
    from public.pachanga_competition_participant_freezes freezes
    join tournament_set tournaments on tournaments.id = freezes.competition_id
  ), plan_set as (
    select plans.id, plans.status, plans.current_revision_id,
      private.pachanga_tournament_plan_input_fresh_v1(plans.id) as input_fresh
    from public.pachanga_competition_draw_plans plans
    join tournament_set tournaments on tournaments.id = plans.competition_id
  ), revision_set as (
    select revisions.id, revisions.validation_status, revisions.quality_score
    from public.pachanga_competition_draw_revisions revisions
    join plan_set plans on plans.id = revisions.draw_plan_id
  ), current_revision_set as (
    select plans.id, plans.input_fresh, revisions.validation_status
    from plan_set plans
    left join public.pachanga_competition_draw_revisions revisions
      on revisions.id = plans.current_revision_id
  ), quality_set as (
    select quality.hard_violations, quality.manual_override_count
    from public.pachanga_competition_draw_quality_snapshots quality
    join revision_set revisions on revisions.id = quality.draw_revision_id
  )
  select jsonb_build_object(
    'tournaments', (select count(*) from tournament_set),
    'drafts', (select count(*) from tournament_set tournaments where tournaments.status = 'draft'),
    'freezes', (select count(*) from freeze_set),
    'drawPlans', (select count(*) from plan_set),
    'generated', (select count(*) from plan_set plans where plans.status = 'generated'),
    'validated', (select count(*) from plan_set plans where plans.status = 'validated'),
    'published', (select count(*) from plan_set plans where plans.status = 'published'),
    'cancelled', (select count(*) from plan_set plans where plans.status = 'cancelled'),
    'revisions', (select count(*) from revision_set),
    'invalidOrStale', (select count(*) from current_revision_set current_revisions
      where not current_revisions.input_fresh
        or current_revisions.validation_status in ('INVALID','UNSATISFIABLE','STALE')),
    'hardConflicts', (select coalesce(sum(quality.hard_violations), 0) from quality_set quality),
    'manualOverrides', (select coalesce(sum(quality.manual_override_count), 0) from quality_set quality),
    'averageQuality', (select coalesce(round(avg(revisions.quality_score), 3), 0)
      from revision_set revisions),
    'tournamentMatches', 0,
    'bracketProgressions', 0
  ) into metrics;

  select coalesce(jsonb_agg(jsonb_build_object(
    'bundleId', grants_table.bundle_id, 'organizerKind', grants_table.organizer_kind,
    'organizerId', coalesce(grants_table.organizer_group_id, grants_table.organizer_club_id),
    'organizerRevision', coalesce((select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_kind = grants_table.organizer_kind
        and ((states.organizer_kind = 'TEAM' and states.organizer_group_id = grants_table.organizer_group_id)
          or (states.organizer_kind = 'CLUB' and states.organizer_club_id = grants_table.organizer_club_id))
    ), 0),
    'status', grants_table.status, 'capability', grants_table.capability,
    'teamCap', grants_table.beta_team_cap,
    'expiresAt', grants_table.expires_at, 'serverSequence', grants_table.server_sequence
  ) order by grants_table.server_sequence desc, grants_table.id desc), '[]'::jsonb)
  into grants
  from public.pachanga_competition_entitlement_grants grants_table
  where grants_table.program_key = 'TOURNAMENT_PRIVATE_BETA_V1';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', visible.id, 'competitionId', visible.competition_id,
    'competitionName', visible.competition_name,
    'mode', visible.mode, 'status', visible.status,
    'revision', visible.revision, 'serverSequence', visible.server_sequence,
    'updatedAt', visible.updated_at,
    'inputFresh', private.pachanga_tournament_plan_input_fresh_v1(visible.id)
  ) order by visible.server_sequence desc, visible.id desc), '[]'::jsonb)
  into recent_plans
  from (
    select plans.*, competitions.name as competition_name
    from public.pachanga_competition_draw_plans plans
    join public.pachanga_competitions competitions on competitions.id = plans.competition_id
    order by plans.server_sequence desc, plans.id desc limit 50
  ) visible;

  return jsonb_build_object(
    'flags', private.pachanga_tournament_flags_v1(),
    'metrics', metrics, 'grants', grants, 'recentPlans', recent_plans,
    'health', jsonb_build_object(
      'publicDiscoveryOff', not (private.pachanga_tournament_flags_v1() ->> 'publicDiscoveryEnabled')::boolean,
      'matchGenerationOff', not (private.pachanga_tournament_flags_v1() ->> 'matchGenerationEnabled')::boolean,
      'bracketProgressionOff', not (private.pachanga_tournament_flags_v1() ->> 'bracketProgressionEnabled')::boolean,
      'legacyBackfillCount', 0
    ),
    'updatedAt', statement_timestamp()
  );
end;
$$;

create or replace function private.pachanga_tournament_realtime_can_read_v1(
  target_competition_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_tournament_can_v1(
    target_competition_id, (select auth.uid()), 'read'
  );
$$;

revoke all on function private.pachanga_tournament_realtime_can_read_v1(uuid)
  from public, anon, authenticated;
grant execute on function private.pachanga_tournament_realtime_can_read_v1(uuid)
  to authenticated;

create policy pachanga_tournament_invalidations_read_authorized_v1
on public.pachanga_tournament_invalidations
for select to authenticated
using (
  target_user_id = (select auth.uid())
  or private.pachanga_tournament_realtime_can_read_v1(competition_id)
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_tournament_invalidations'
  ) then
    alter publication supabase_realtime
      add table public.pachanga_tournament_invalidations;
  end if;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_actor_organizers_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_plan_input_fresh_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_plan_summary_v1(uuid,boolean)'::regprocedure,
    'private.pachanga_tournament_revision_diff_v1(uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

revoke all on function public.get_pachanga_tournament_flags_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_tournament_home_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_tournament_snapshot_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_tournament_draw_desk_v1(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_tournament_draw_audit_v1(uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_platform_tournament_control_v1()
  from public, anon, authenticated, service_role;

grant execute on function public.get_pachanga_tournament_flags_v1()
  to authenticated;
grant execute on function public.get_pachanga_tournament_home_v1()
  to authenticated;
grant execute on function public.get_pachanga_tournament_snapshot_v1(uuid)
  to authenticated;
grant execute on function public.get_pachanga_tournament_draw_desk_v1(uuid,uuid)
  to authenticated;
grant execute on function public.get_pachanga_tournament_draw_audit_v1(uuid,uuid)
  to authenticated;
grant execute on function public.get_pachanga_platform_tournament_control_v1()
  to authenticated, service_role;

comment on function public.get_pachanga_tournament_draw_audit_v1(uuid,uuid) is
  'Published Tournament draw evidence sanitized for authorized participants; Auth identities and private reasons are never exposed.';
comment on table public.pachanga_tournament_invalidations is
  'Realtime transport only. SUBSCRIBED, reconnect and each invalidation require a canonical RPC refetch.';
