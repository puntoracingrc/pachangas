-- Official UI V3F: canonical read models, RLS, Realtime and staged activation.

set lock_timeout = '5s';
set statement_timeout = '120s';

do $$
declare selected_group record;
declare generated_operation_id uuid;
declare sequence_value bigint;
begin
  for selected_group in
    select groups.id from public.pachanga_groups groups
    where not exists (
      select 1 from public.pachanga_social_team_states_v1 states
      where states.group_id = groups.id
    )
    order by groups.id
  loop
    generated_operation_id := gen_random_uuid();
    sequence_value := nextval('private.pachanga_social_team_sequence_v1');
    insert into public.pachanga_social_team_states_v1(
      group_id, revision, server_sequence, last_operation_id
    ) values (selected_group.id, 1, sequence_value, generated_operation_id);
    insert into private.pachanga_social_team_state_revisions_v1(
      group_id, revision, reason, snapshot, operation_id, actor_id, server_sequence
    ) values (
      selected_group.id, 1, 'migration.initialization',
      jsonb_build_object(
        'groupId', selected_group.id, 'revision', 1,
        'serverSequence', sequence_value, 'source', 'V3F_MIGRATION'
      ), generated_operation_id, null, sequence_value
    );
  end loop;
end;
$$;

drop policy if exists "Members read social Team states v1"
  on public.pachanga_social_team_states_v1;
create policy "Members read social Team states v1"
on public.pachanga_social_team_states_v1
for select to authenticated
using (
  exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = pachanga_social_team_states_v1.group_id
      and members.user_id = (select auth.uid())
  )
);
grant select on table public.pachanga_social_team_states_v1 to authenticated;

drop policy if exists "Scoped social invalidations v1"
  on public.pachanga_social_invalidations_v1;
create policy "Scoped social invalidations v1"
on public.pachanga_social_invalidations_v1
for select to authenticated
using (
  audience_user_id = (select auth.uid())
  or exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = pachanga_social_invalidations_v1.audience_group_id
      and members.user_id = (select auth.uid())
  )
);
grant select on table public.pachanga_social_invalidations_v1 to authenticated, service_role;

create or replace function public.get_pachanga_social_team_feature_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'socialProfileFoundationEnabled', settings.social_profile_foundation_enabled,
    'socialProfileIndependentWriteEnabled', settings.social_profile_independent_write_enabled,
    'socialTeamCreationEnabled', settings.social_team_creation_enabled,
    'socialTeamInvitationV2Enabled', settings.social_team_invitation_v2_enabled,
    'socialTeamMembershipV2Enabled', settings.social_team_membership_v2_enabled,
    'socialTeamHomeV3fEnabled', settings.social_team_home_v3f_enabled,
    'demoSocialTeamJourneyEnabled', settings.demo_social_team_journey_enabled,
    'revision', settings.revision,
    'confirmedRevision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_social_team_settings_v1 settings where settings.singleton;
$$;

create or replace function public.get_my_pachanga_social_teams_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare enabled boolean;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select settings.social_team_home_v3f_enabled into enabled
  from private.pachanga_social_team_settings_v1 settings where settings.singleton;
  if not coalesce(enabled, false) then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(private.pachanga_social_team_snapshot_v1(members.group_id, actor_id)
      order by groups.updated_at desc, groups.id)
    from public.pachanga_group_members members
    join public.pachanga_groups groups on groups.id = members.group_id
    where members.user_id = actor_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.lookup_pachanga_social_team_code_v1(target_team_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare code_value text := upper(trim(coalesce(target_team_code, '')));
declare enabled boolean;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select settings.social_team_home_v3f_enabled into enabled
  from private.pachanga_social_team_settings_v1 settings where settings.singleton;
  if not coalesce(enabled, false) or code_value !~ '^[A-Z0-9]{6,12}$' then return null; end if;
  return (
    select jsonb_build_object(
      'kind', 'SocialTeamCodeLookup',
      'groupId', groups.id,
      'name', groups.name,
      'teamCode', groups.team_code,
      'modality', groups.social_modality,
      'generalArea', groups.social_general_area,
      'memberCount', (select count(*) from public.pachanga_group_members members where members.group_id = groups.id),
      'acceptsPlayerInvitationOnly', true
    )
    from public.pachanga_groups groups
    left join private.pachanga_team_operational_states_v1 operational on operational.group_id = groups.id
    where groups.team_code = code_value
      and coalesce(operational.effective_status, 'ACTIVE') <> 'ARCHIVED'
  );
end;
$$;

create or replace function public.get_pachanga_social_team_home_v1(target_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare team_snapshot jsonb;
declare enabled boolean;
declare actor_role text;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select settings.social_team_home_v3f_enabled into enabled
  from private.pachanga_social_team_settings_v1 settings where settings.singleton;
  if not coalesce(enabled, false) then raise exception 'SOCIAL_TEAM_HOME_DISABLED' using errcode = '42501'; end if;
  select members.role into actor_role from public.pachanga_group_members members
  where members.group_id = target_group_id and members.user_id = actor_id;
  if actor_role is null then raise exception 'TEAM_MEMBERSHIP_REQUIRED' using errcode = '42501'; end if;
  team_snapshot := private.pachanga_social_team_snapshot_v1(target_group_id, actor_id);
  return team_snapshot || jsonb_build_object(
    'actions', jsonb_build_object(
      'canInvitePlayers', actor_role in ('owner','admin'),
      'canManageRoster', actor_role in ('owner','admin'),
      'canEditTeam', actor_role in ('owner','admin'),
      'canCreateMatch', actor_role in ('owner','admin')
    ),
    'activeInvitationCount', (
      select count(*) from public.pachanga_team_player_invitations_v2 invitations
      where invitations.group_id = target_group_id and invitations.state = 'ACTIVE'
        and invitations.expires_at > clock_timestamp()
    )
  );
end;
$$;

create or replace function public.get_pachanga_social_team_roster_v1(target_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.pachanga_group_members own
    where own.group_id = target_group_id and own.user_id = actor_id
  ) then raise exception 'TEAM_MEMBERSHIP_REQUIRED' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'memberId', members.user_id,
      'displayName', coalesce(profiles.display_name, members.display_name, 'Jugador'),
      'avatarRef', profiles.avatar_ref,
      'primaryPosition', profiles.primary_position,
      'secondaryPosition', profiles.secondary_position,
      'preferredModality', profiles.preferred_modality,
      'role', members.role,
      'joinedAt', members.created_at,
      'roleChangedAt', members.role_changed_at,
      'isCurrentUser', members.user_id = actor_id
    )) order by
      case members.role when 'owner' then 0 when 'admin' then 1 else 2 end,
      coalesce(profiles.display_name, members.display_name, ''), members.user_id)
    from public.pachanga_group_members members
    left join public.pachanga_social_player_profiles_v1 profiles on profiles.user_id = members.user_id
    where members.group_id = target_group_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_pachanga_social_team_invitations_v2(target_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then raise exception 'TEAM_ADMIN_REQUIRED' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(private.pachanga_team_player_invitation_snapshot_v2(invitations.id, false)
      order by invitations.server_sequence desc, invitations.id)
    from public.pachanga_team_player_invitations_v2 invitations
    where invitations.group_id = target_group_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.command_pachanga_social_team_settings_v1(
  operation_id uuid,
  expected_revision bigint,
  payload jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare body jsonb := coalesce(payload, '{}'::jsonb);
declare settings private.pachanga_social_team_settings_v1%rowtype;
declare existing_receipt private.pachanga_social_operation_receipts_v1%rowtype;
declare request_hash text;
declare response jsonb;
declare next_sequence bigint;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'AUTHENTICATION_OPERATION_AND_REVISION_REQUIRED' using errcode = '42501';
  end if;
  perform private.pachanga_platform_require_v1('flags.write');
  if jsonb_typeof(body) <> 'object' or body - array[
    'socialProfileFoundationEnabled','socialProfileIndependentWriteEnabled',
    'socialTeamCreationEnabled','socialTeamInvitationV2Enabled',
    'socialTeamMembershipV2Enabled','socialTeamHomeV3fEnabled',
    'demoSocialTeamJourneyEnabled'
  ]::text[] <> '{}'::jsonb then raise exception 'INVALID_SOCIAL_TEAM_SETTINGS' using errcode = '22023'; end if;

  request_hash := private.pachanga_social_request_hash_v1(
    'social_team.settings.update', 'singleton', expected_revision, body
  );
  perform pg_advisory_xact_lock(hashtextextended('social-operation:' || operation_id::text, 0));
  select * into existing_receipt from private.pachanga_social_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_social_team_settings_v1.operation_id;
  if found then
    if existing_receipt.actor_id <> actor_id
       or existing_receipt.action <> 'social_team.settings.update'
       or existing_receipt.request_hash <> request_hash then
      raise exception 'OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return existing_receipt.response;
  end if;

  select * into settings from private.pachanga_social_team_settings_v1 where singleton for update;
  if settings.revision <> expected_revision then raise exception 'STALE_SOCIAL_TEAM_SETTINGS_REVISION' using errcode = 'PT409'; end if;
  next_sequence := nextval('private.pachanga_social_team_sequence_v1');
  update private.pachanga_social_team_settings_v1 current_settings set
    social_profile_foundation_enabled = coalesce((body ->> 'socialProfileFoundationEnabled')::boolean, current_settings.social_profile_foundation_enabled),
    social_profile_independent_write_enabled = coalesce((body ->> 'socialProfileIndependentWriteEnabled')::boolean, current_settings.social_profile_independent_write_enabled),
    social_team_creation_enabled = coalesce((body ->> 'socialTeamCreationEnabled')::boolean, current_settings.social_team_creation_enabled),
    social_team_invitation_v2_enabled = coalesce((body ->> 'socialTeamInvitationV2Enabled')::boolean, current_settings.social_team_invitation_v2_enabled),
    social_team_membership_v2_enabled = coalesce((body ->> 'socialTeamMembershipV2Enabled')::boolean, current_settings.social_team_membership_v2_enabled),
    social_team_home_v3f_enabled = coalesce((body ->> 'socialTeamHomeV3fEnabled')::boolean, current_settings.social_team_home_v3f_enabled),
    demo_social_team_journey_enabled = coalesce((body ->> 'demoSocialTeamJourneyEnabled')::boolean, current_settings.demo_social_team_journey_enabled),
    revision = current_settings.revision + 1,
    server_sequence = next_sequence,
    updated_by = actor_id,
    updated_at = clock_timestamp()
  where current_settings.singleton;
  response := public.get_pachanga_social_team_feature_flags_v1()
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', expected_revision + 1,
      'serverSequence', next_sequence,
      'confirmedAt', clock_timestamp()
    );
  perform private.pachanga_social_record_evidence_v1(
    operation_id, actor_id, 'social_team.settings.update', 'social_team_settings', 'singleton',
    request_hash, expected_revision, expected_revision + 1,
    jsonb_build_object('changedFields', coalesce((select jsonb_agg(keys.key order by keys.key) from jsonb_object_keys(body) keys(key)), '[]'::jsonb)),
    response, client_metadata, next_sequence
  );
  return response;
end;
$$;

revoke insert, update, delete on table public.pachanga_groups from authenticated;
revoke insert, update, delete on table public.pachanga_group_members from authenticated;
revoke insert, update, delete on table public.pachanga_social_player_profiles_v1 from authenticated;
revoke insert, update, delete on table public.pachanga_social_team_states_v1 from authenticated;
revoke insert, update, delete on table public.pachanga_team_player_invitations_v2 from authenticated;
revoke insert, update, delete on table public.pachanga_social_invalidations_v1 from authenticated;

revoke execute on function public.join_pachanga_group(uuid) from public, anon, authenticated;
revoke execute on function public.join_pachanga_team(uuid,text) from public, anon, authenticated;

revoke all on function public.get_pachanga_social_team_feature_flags_v1() from public, anon;
grant execute on function public.get_pachanga_social_team_feature_flags_v1() to authenticated, service_role;
revoke all on function public.get_my_pachanga_social_teams_v1() from public, anon;
grant execute on function public.get_my_pachanga_social_teams_v1() to authenticated, service_role;
revoke all on function public.lookup_pachanga_social_team_code_v1(text) from public, anon;
grant execute on function public.lookup_pachanga_social_team_code_v1(text) to authenticated, service_role;
revoke all on function public.get_pachanga_social_team_home_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_social_team_home_v1(uuid) to authenticated, service_role;
revoke all on function public.get_pachanga_social_team_roster_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_social_team_roster_v1(uuid) to authenticated, service_role;
revoke all on function public.get_pachanga_social_team_invitations_v2(uuid) from public, anon;
grant execute on function public.get_pachanga_social_team_invitations_v2(uuid) to authenticated, service_role;
revoke all on function public.command_pachanga_social_team_settings_v1(uuid,bigint,jsonb,jsonb) from public, anon;
grant execute on function public.command_pachanga_social_team_settings_v1(uuid,bigint,jsonb,jsonb) to authenticated, service_role;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'pachanga_social_invalidations_v1'
  ) then alter publication supabase_realtime add table public.pachanga_social_invalidations_v1; end if;
end;
$$;

comment on function public.lookup_pachanga_social_team_code_v1(text) is
  'Exact Team-code lookup only. Team code identifies a Team and never grants membership.';
comment on function public.command_pachanga_social_team_settings_v1(uuid,bigint,jsonb,jsonb) is
  'Platform-only staged V3F activation with expected revision and immutable receipt.';
