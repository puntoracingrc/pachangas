-- Wave 8B: fail-closed cross-product guards at the table boundary.
-- Legacy security-definer RPCs cannot bypass these triggers.

set lock_timeout = '5s';
set statement_timeout = '5min';

alter table private.pachanga_organizer_access_applications_v1
  add column if not exists operational_blocked_at timestamptz,
  add column if not exists operational_blocked_revision bigint,
  add column if not exists operational_blocked_code text;

alter table public.pachanga_competition_registration_requests
  add column if not exists operational_blocked_at timestamptz,
  add column if not exists operational_blocked_revision bigint,
  add column if not exists operational_blocked_code text;

create or replace function private.pachanga_team_operational_scope_allowed_v1(
  target_group_id uuid,
  target_scope text,
  target_competition_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_team_operational_settings_v1%rowtype;
declare state_row private.pachanga_team_operational_states_v1%rowtype;
declare normalized_scope text := upper(trim(coalesce(target_scope, '')));
declare blocked boolean;
declare continuity text;
begin
  select * into settings from private.pachanga_team_operational_settings_v1 where singleton;
  if not coalesce(settings.foundation_enabled, false)
     or not coalesce(settings.cross_product_guards_enabled, false) then
    return true;
  end if;
  select * into state_row
  from private.pachanga_team_operational_states_v1 states
  where states.group_id = target_group_id;
  if not found then return false; end if;

  if normalized_scope = 'EXISTING_COMPETITION_OPERATIONS' then
    select exists (
      select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
      where restrictions.group_id = target_group_id
        and restrictions.scope = normalized_scope
        and restrictions.status = 'ACTIVE'
        and restrictions.effective_from <= clock_timestamp()
        and (restrictions.effective_until is null or restrictions.effective_until > clock_timestamp())
    ) or state_row.lifecycle_status = 'ARCHIVED'
      or state_row.enforcement_status = 'SUSPENDED'
    into blocked;
    if not blocked then return true; end if;
    continuity := private.pachanga_team_operational_continuity_for_competition_v1(
      target_group_id, target_competition_id
    );
    return continuity = 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH';
  end if;

  if state_row.lifecycle_status = 'ARCHIVED'
     and normalized_scope in (
       'PUBLIC_DISCOVERY', 'MARKETPLACE', 'SOCIAL_CHALLENGES', 'NEW_MATCH_CREATION',
       'COMPETITION_REGISTRATION', 'COMPETITION_ORGANIZER',
       'TEAM_MEMBERSHIP_ADMINISTRATION', 'PUBLIC_PROFILE'
     ) then
    return false;
  end if;

  return not exists (
    select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
    where restrictions.group_id = target_group_id
      and restrictions.scope = normalized_scope
      and restrictions.status = 'ACTIVE'
      and restrictions.effective_from <= clock_timestamp()
      and (restrictions.effective_until is null or restrictions.effective_until > clock_timestamp())
  );
end;
$$;

create or replace function private.pachanga_assert_team_operational_scope_v1(
  target_group_id uuid,
  target_scope text,
  target_competition_id uuid default null
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare state_row private.pachanga_team_operational_states_v1%rowtype;
begin
  select * into state_row
  from private.pachanga_team_operational_states_v1 states
  where states.group_id = target_group_id
  for share;
  if not found then
    perform private.pachanga_ensure_team_operational_state_v1(target_group_id);
    select * into strict state_row
    from private.pachanga_team_operational_states_v1 states
    where states.group_id = target_group_id
    for share;
  end if;
  if not private.pachanga_team_operational_scope_allowed_v1(
    target_group_id, target_scope, target_competition_id
  ) then
    raise exception 'TEAM_OPERATIONALLY_RESTRICTED' using
      errcode = '42501',
      detail = jsonb_build_object(
        'groupId', target_group_id,
        'scope', upper(trim(target_scope)),
        'effectiveStatus', state_row.effective_status,
        'confirmedRevision', state_row.current_revision
      )::text;
  end if;
end;
$$;

create or replace function private.pachanga_team_operational_group_payload_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare old_count integer := case when jsonb_typeof(old.payload -> 'matches') = 'array' then jsonb_array_length(old.payload -> 'matches') else 0 end;
declare new_count integer := case when jsonb_typeof(new.payload -> 'matches') = 'array' then jsonb_array_length(new.payload -> 'matches') else 0 end;
begin
  if new_count > old_count then
    perform private.pachanga_assert_team_operational_scope_v1(new.id, 'NEW_MATCH_CREATION');
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_group_payload_guard_v1 on public.pachanga_groups;
create trigger pachanga_team_operational_group_payload_guard_v1
before update of payload on public.pachanga_groups
for each row execute function private.pachanga_team_operational_group_payload_guard_v1();

create or replace function private.pachanga_team_operational_membership_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare group_id uuid := coalesce(new.group_id, old.group_id);
begin
  if tg_op = 'DELETE' and old.user_id = (select auth.uid()) then return old; end if;
  perform private.pachanga_assert_team_operational_scope_v1(group_id, 'TEAM_MEMBERSHIP_ADMINISTRATION');
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_membership_guard_v1 on public.pachanga_group_members;
create trigger pachanga_team_operational_membership_guard_v1
before insert or update of role, user_id or delete on public.pachanga_group_members
for each row execute function private.pachanga_team_operational_membership_guard_v1();

create or replace function private.pachanga_team_operational_challengeable_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.enabled then
    perform private.pachanga_assert_team_operational_scope_v1(new.group_id, 'SOCIAL_CHALLENGES');
    perform private.pachanga_assert_team_operational_scope_v1(new.group_id, 'PUBLIC_DISCOVERY');
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_challengeable_guard_v1 on public.pachanga_challengeable_team_profiles;
create trigger pachanga_team_operational_challengeable_guard_v1
before insert or update of enabled on public.pachanga_challengeable_team_profiles
for each row execute function private.pachanga_team_operational_challengeable_guard_v1();

create or replace function private.pachanga_team_operational_market_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.active then
    perform private.pachanga_assert_team_operational_scope_v1(new.source_group_id, 'MARKETPLACE');
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_market_guard_v1 on public.pachanga_open_matches;
create trigger pachanga_team_operational_market_guard_v1
before insert or update of active on public.pachanga_open_matches
for each row execute function private.pachanga_team_operational_market_guard_v1();

create or replace function private.pachanga_team_operational_challenge_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.status in ('proposed', 'changes_proposed', 'accepted') then
    perform private.pachanga_assert_team_operational_scope_v1(new.sender_group_id, 'SOCIAL_CHALLENGES');
    perform private.pachanga_assert_team_operational_scope_v1(new.receiver_group_id, 'SOCIAL_CHALLENGES');
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_challenge_guard_v1 on public.pachanga_team_challenges;
create trigger pachanga_team_operational_challenge_guard_v1
before insert or update of status on public.pachanga_team_challenges
for each row execute function private.pachanga_team_operational_challenge_guard_v1();

create or replace function private.pachanga_team_operational_registration_request_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.status in ('draft', 'submitted', 'under_review', 'waitlisted', 'accepted') then
    perform private.pachanga_assert_team_operational_scope_v1(
      new.team_id, 'COMPETITION_REGISTRATION', new.competition_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_registration_request_guard_v1
  on public.pachanga_competition_registration_requests;
create trigger pachanga_team_operational_registration_request_guard_v1
before insert or update of status on public.pachanga_competition_registration_requests
for each row execute function private.pachanga_team_operational_registration_request_guard_v1();

create or replace function private.pachanga_team_operational_entry_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'INSERT' or (
    new.status in ('draft', 'submitted', 'invited', 'accepted', 'active')
    and new.status is distinct from old.status
  ) then
    perform private.pachanga_assert_team_operational_scope_v1(
      new.team_id, 'COMPETITION_REGISTRATION', new.competition_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_entry_guard_v1 on public.pachanga_competition_entries;
create trigger pachanga_team_operational_entry_guard_v1
before insert or update of status on public.pachanga_competition_entries
for each row execute function private.pachanga_team_operational_entry_guard_v1();

create or replace function private.pachanga_team_operational_competition_create_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.organizer_kind = 'TEAM' and (
    tg_op = 'INSERT' or new.status is distinct from old.status
  ) then
    perform private.pachanga_assert_team_operational_scope_v1(
      new.organizer_group_id, 'COMPETITION_ORGANIZER', new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_competition_create_guard_v1 on public.pachanga_competitions;
create trigger pachanga_team_operational_competition_create_guard_v1
before insert or update of status on public.pachanga_competitions
for each row execute function private.pachanga_team_operational_competition_create_guard_v1();

create or replace function private.pachanga_team_operational_organizer_application_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.organizer_kind = 'TEAM' and new.status in (
    'draft', 'submitted', 'under_review', 'needs_information', 'approved'
  ) then
    perform private.pachanga_assert_team_operational_scope_v1(
      new.organizer_group_id, 'COMPETITION_ORGANIZER'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_organizer_application_guard_v1
  on private.pachanga_organizer_access_applications_v1;
create trigger pachanga_team_operational_organizer_application_guard_v1
before insert or update of status on private.pachanga_organizer_access_applications_v1
for each row execute function private.pachanga_team_operational_organizer_application_guard_v1();

create or replace function private.pachanga_team_operational_organizer_grant_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.organizer_kind = 'TEAM' and new.status in ('active', 'grace', 'continuity') then
    perform private.pachanga_assert_team_operational_scope_v1(
      new.organizer_group_id, 'COMPETITION_ORGANIZER'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_organizer_grant_guard_v1
  on private.pachanga_organizer_access_grants_v1;
create trigger pachanga_team_operational_organizer_grant_guard_v1
before insert or update of status on private.pachanga_organizer_access_grants_v1
for each row execute function private.pachanga_team_operational_organizer_grant_guard_v1();

create or replace function private.pachanga_assert_team_operational_context_v1(
  target_context_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare target record;
begin
  if target_context_id is null then return; end if;
  for target in
    select distinct entries.team_id, contexts.competition_id
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_schedule_items items
      on items.competition_match_context_id = contexts.id
    join public.pachanga_competition_entries entries
      on entries.id in (items.home_entry_id, items.away_entry_id)
    where contexts.id = target_context_id
  loop
    perform private.pachanga_assert_team_operational_scope_v1(
      target.team_id, 'EXISTING_COMPETITION_OPERATIONS', target.competition_id
    );
  end loop;
end;
$$;

create or replace function private.pachanga_team_operational_context_write_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare row_json jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
declare context_id uuid := nullif(row_json ->> 'competition_match_context_id', '')::uuid;
begin
  perform private.pachanga_assert_team_operational_context_v1(context_id);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists pachanga_team_operational_participant_guard_v1 on public.pachanga_match_participants;
create trigger pachanga_team_operational_participant_guard_v1
before insert or update or delete on public.pachanga_match_participants
for each row execute function private.pachanga_team_operational_context_write_guard_v1();

drop trigger if exists pachanga_team_operational_squad_guard_v1 on public.pachanga_competition_match_squads;
create trigger pachanga_team_operational_squad_guard_v1
before insert or update or delete on public.pachanga_competition_match_squads
for each row execute function private.pachanga_team_operational_context_write_guard_v1();

drop trigger if exists pachanga_team_operational_result_guard_v1 on public.pachanga_competition_sporting_results;
create trigger pachanga_team_operational_result_guard_v1
before insert or update or delete on public.pachanga_competition_sporting_results
for each row execute function private.pachanga_team_operational_context_write_guard_v1();

drop trigger if exists pachanga_team_operational_official_result_guard_v1
  on public.pachanga_competition_official_result_decisions;
create trigger pachanga_team_operational_official_result_guard_v1
before insert or update or delete on public.pachanga_competition_official_result_decisions
for each row execute function private.pachanga_team_operational_context_write_guard_v1();

drop trigger if exists pachanga_team_operational_discipline_guard_v1
  on public.pachanga_competition_disciplinary_events;
create trigger pachanga_team_operational_discipline_guard_v1
before insert or update or delete on public.pachanga_competition_disciplinary_events
for each row execute function private.pachanga_team_operational_context_write_guard_v1();

drop trigger if exists pachanga_team_operational_fixture_change_guard_v1
  on public.pachanga_competition_fixture_changes;
create trigger pachanga_team_operational_fixture_change_guard_v1
before insert or update or delete on public.pachanga_competition_fixture_changes
for each row execute function private.pachanga_team_operational_context_write_guard_v1();

create or replace function private.pachanga_team_operational_mark_blocked_work_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.current_revision = old.current_revision then return new; end if;
  if not private.pachanga_team_operational_scope_allowed_v1(new.group_id, 'COMPETITION_ORGANIZER') then
    update private.pachanga_organizer_access_applications_v1 applications set
      operational_blocked_at = clock_timestamp(),
      operational_blocked_revision = new.current_revision,
      operational_blocked_code = 'TEAM_OPERATIONALLY_RESTRICTED'
    where applications.organizer_kind = 'TEAM'
      and applications.organizer_group_id = new.group_id
      and applications.status in ('draft','submitted','under_review','needs_information');
  end if;
  if not private.pachanga_team_operational_scope_allowed_v1(new.group_id, 'COMPETITION_REGISTRATION') then
    update public.pachanga_competition_registration_requests requests set
      operational_blocked_at = clock_timestamp(),
      operational_blocked_revision = new.current_revision,
      operational_blocked_code = 'TEAM_OPERATIONALLY_RESTRICTED'
    where requests.team_id = new.group_id
      and requests.status in ('draft','submitted','under_review','waitlisted');
  end if;
  if not private.pachanga_team_operational_scope_allowed_v1(new.group_id, 'MARKETPLACE') then
    update public.pachanga_open_matches matches set active = false, updated_at = clock_timestamp()
    where matches.source_group_id = new.group_id and matches.active;
  end if;
  if not private.pachanga_team_operational_scope_allowed_v1(new.group_id, 'SOCIAL_CHALLENGES')
     or not private.pachanga_team_operational_scope_allowed_v1(new.group_id, 'PUBLIC_DISCOVERY') then
    update public.pachanga_challengeable_team_profiles profiles set
      enabled = false, revision = profiles.revision + 1,
      updated_by = coalesce(new.updated_by, profiles.updated_by),
      updated_at = clock_timestamp()
    where profiles.group_id = new.group_id and profiles.enabled;
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_mark_blocked_work_v1
  on private.pachanga_team_operational_states_v1;
create trigger pachanga_team_operational_mark_blocked_work_v1
after update of current_revision on private.pachanga_team_operational_states_v1
for each row execute function private.pachanga_team_operational_mark_blocked_work_v1();

revoke all on function private.pachanga_team_operational_scope_allowed_v1(uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_assert_team_operational_scope_v1(uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_group_payload_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_membership_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_challengeable_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_market_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_challenge_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_registration_request_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_entry_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_competition_create_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_organizer_application_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_organizer_grant_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_assert_team_operational_context_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_context_write_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_mark_blocked_work_v1() from public, anon, authenticated;

comment on function private.pachanga_assert_team_operational_scope_v1(uuid, text, uuid) is
  'Table-boundary guard shared by legacy and V2 RPCs. It serializes against Team operational commands and fails closed.';
