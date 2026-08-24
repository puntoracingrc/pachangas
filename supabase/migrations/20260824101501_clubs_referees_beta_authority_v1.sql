-- Clubs + Referees public beta authoritative commands and publication guards.
-- Product flags remain unchanged by this migration.

create index if not exists pachanga_club_receipts_rate_limit_idx
  on private.pachanga_club_operation_receipts(actor_id, action, created_at desc)
  where actor_id is not null;

create or replace function private.pachanga_club_rate_limit_v1(
  target_actor_id uuid,
  target_action text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  hourly_limit integer := case
    when target_action = 'club.create' then 3
    when target_action = 'club.profile.update' then 20
    when target_action = 'membership.invite' then 20
    when target_action like 'team_relationship.%' then 30
    when target_action = 'publication.consent' then 20
    else 120
  end;
  daily_limit integer := case
    when target_action = 'club.create' then 5
    when target_action = 'club.profile.update' then 100
    when target_action = 'membership.invite' then 100
    when target_action like 'team_relationship.%' then 150
    when target_action = 'publication.consent' then 100
    else 1000
  end;
begin
  if target_actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'club-rate-limit:' || target_actor_id::text || ':' || target_action,
    0
  ));
  if (
    select count(*)
    from private.pachanga_club_operation_receipts receipts
    where receipts.actor_id = target_actor_id
      and receipts.action = target_action
      and receipts.created_at >= clock_timestamp() - interval '1 hour'
  ) >= hourly_limit then
    raise exception 'CLUB_RATE_LIMITED' using errcode = 'PT429';
  end if;
  if (
    select count(*)
    from private.pachanga_club_operation_receipts receipts
    where receipts.actor_id = target_actor_id
      and receipts.action = target_action
      and receipts.created_at >= clock_timestamp() - interval '24 hours'
  ) >= daily_limit then
    raise exception 'CLUB_RATE_LIMITED' using errcode = 'PT429';
  end if;
end;
$$;

revoke all on function private.pachanga_club_rate_limit_v1(uuid, text)
  from public, anon, authenticated;

-- Keep the token-safe R2 wrapper intact behind a new rate-limited public entrypoint.
alter function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) rename to command_pachanga_club_foundation_v1_pre_beta;

revoke all on function public.command_pachanga_club_foundation_v1_pre_beta(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;

create function public.command_pachanga_club_foundation_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if command_action in ('team_relationship.invite', 'team_relationship.request')
     and not exists (
       select 1
       from public.pachanga_clubs clubs
       where clubs.id = aggregate_id
         and clubs.operational_status = 'active'
     ) then
    raise exception 'CLUB_NOT_ACTIVE' using errcode = '42501';
  end if;
  if not exists (
    select 1 from private.pachanga_club_operation_receipts receipts
    where receipts.operation_id = command_pachanga_club_foundation_v1.operation_id
  ) then
    perform private.pachanga_club_rate_limit_v1(actor_id, command_action);
  end if;
  return public.command_pachanga_club_foundation_v1_pre_beta(
    operation_id,
    aggregate_id,
    expected_revision,
    command_action,
    coalesce(command_payload, '{}'::jsonb),
    coalesce(client_metadata, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function private.pachanga_referee_rate_limit_v1(
  target_actor_id uuid,
  target_action text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  hourly_limit integer := case
    when target_action = 'profile.create' then 5
    when target_action = 'profile.update' then 20
    when target_action in ('profile.modalities.replace', 'profile.areas.replace', 'profile.availability.replace') then 30
    when target_action like 'marketplace.%' then 12
    when target_action like 'relationship.%' then 30
    when target_action = 'publication.consent' then 20
    else 120
  end;
  daily_limit integer := case
    when target_action = 'profile.create' then 5
    when target_action = 'profile.update' then 100
    when target_action in ('profile.modalities.replace', 'profile.areas.replace', 'profile.availability.replace') then 200
    when target_action like 'marketplace.%' then 60
    when target_action like 'relationship.%' then 150
    when target_action = 'publication.consent' then 100
    else 1000
  end;
begin
  if target_actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'referee-rate-limit:' || target_actor_id::text || ':' || target_action,
    0
  ));
  if (
    select count(*)
    from private.pachanga_referee_operation_receipts receipts
    where receipts.actor_id = target_actor_id
      and receipts.action = target_action
      and receipts.created_at >= clock_timestamp() - interval '1 hour'
  ) >= hourly_limit then
    raise exception 'REFEREE_RATE_LIMITED' using errcode = 'PT429';
  end if;
  if (
    select count(*)
    from private.pachanga_referee_operation_receipts receipts
    where receipts.actor_id = target_actor_id
      and receipts.action = target_action
      and receipts.created_at >= clock_timestamp() - interval '24 hours'
  ) >= daily_limit then
    raise exception 'REFEREE_RATE_LIMITED' using errcode = 'PT429';
  end if;
end;
$$;

revoke all on function private.pachanga_referee_rate_limit_v1(uuid, text)
  from public, anon, authenticated;

-- Preserve the R3 implementation behind an authenticated, rate-limited entrypoint.
alter function public.command_pachanga_referee_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) rename to command_pachanga_referee_platform_v1_pre_beta;

revoke all on function public.command_pachanga_referee_platform_v1_pre_beta(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;

create function public.command_pachanga_referee_platform_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  replay jsonb;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or command_action is null then
    raise exception 'INVALID_REFEREE_COMMAND' using errcode = '22023';
  end if;
  replay := private.pachanga_referee_replay_v1(
    operation_id,
    actor_id,
    private.pachanga_referee_request_hash_v1(
      command_action,
      aggregate_id,
      expected_revision,
      coalesce(command_payload, '{}'::jsonb)
    )
  );
  if replay is null then
    if command_action in ('relationship.invite', 'relationship.request')
       and not exists (
         select 1
         from public.pachanga_clubs clubs
         where clubs.id = nullif(command_payload ->> 'clubId', '')::uuid
           and clubs.operational_status = 'active'
       ) then
      raise exception 'REFEREE_RELATIONSHIP_CLUB_NOT_ACTIVE' using errcode = '42501';
    end if;
    perform private.pachanga_referee_rate_limit_v1(actor_id, command_action);
  end if;
  return public.command_pachanga_referee_platform_v1_pre_beta(
    operation_id,
    aggregate_id,
    expected_revision,
    command_action,
    coalesce(command_payload, '{}'::jsonb),
    coalesce(client_metadata, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.command_pachanga_referee_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_referee_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function public.command_pachanga_publication_consent_v1(
  operation_id uuid,
  subject_kind text,
  subject_id uuid,
  expected_revision bigint,
  confirmations jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  normalized_kind text := upper(trim(coalesce(subject_kind, '')));
  action_name constant text := 'publication.consent';
  request_hash text;
  replay jsonb;
  fingerprint text;
  sequence_value bigint;
  confirmed_at timestamptz := clock_timestamp();
  snapshot jsonb;
  selected_club public.pachanga_clubs%rowtype;
  selected_profile public.pachanga_referee_profiles%rowtype;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if operation_id is null or subject_id is null or expected_revision is null or expected_revision < 1
     or normalized_kind not in ('CLUB', 'REFEREE_PROFILE')
     or jsonb_typeof(coalesce(confirmations, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_PUBLICATION_CONSENT' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('publication-consent:' || operation_id::text, 0));

  if normalized_kind = 'CLUB' then
    request_hash := private.pachanga_club_request_hash_v1(
      action_name, subject_id, expected_revision, confirmations
    );
    replay := private.pachanga_club_replay_v1(
      operation_id, actor_id, 'authenticated', action_name, subject_id, request_hash
    );
    if replay is not null then return replay; end if;
    perform private.pachanga_club_rate_limit_v1(actor_id, action_name);

    select * into selected_club
    from public.pachanga_clubs clubs
    where clubs.id = subject_id
    for update;
    if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_club.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if selected_club.primary_owner_id <> actor_id
       or private.pachanga_club_active_role_v1(selected_club.id, actor_id) <> 'club_owner' then
      raise exception 'CLUB_PRIMARY_OWNER_REQUIRED' using errcode = '42501';
    end if;
    if selected_club.operational_status in ('suspended', 'archived') then
      raise exception 'CLUB_PUBLICATION_CONSENT_NOT_ALLOWED' using errcode = '42501';
    end if;
    if coalesce((confirmations ->> 'representationAuthorized')::boolean, false) is not true
       or coalesce((confirmations ->> 'informationCorrect')::boolean, false) is not true then
      raise exception 'CLUB_PUBLICATION_CONFIRMATIONS_REQUIRED' using errcode = '22023';
    end if;

    fingerprint := private.pachanga_club_public_content_fingerprint_v1(selected_club.id);
    sequence_value := nextval('private.pachanga_club_sequence');
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where clubs.id = selected_club.id
    returning * into selected_club;

    insert into private.pachanga_publication_consents(
      operation_id, subject_kind, subject_id, actor_id, content_fingerprint,
      representation_authorized, information_correct, subject_revision, consented_at
    ) values (
      operation_id, normalized_kind, selected_club.id, actor_id, fingerprint,
      true, true, selected_club.revision, confirmed_at
    );

    snapshot := private.pachanga_club_snapshot_v1(selected_club.id, actor_id)
      || jsonb_build_object('publicationConsent',
        private.pachanga_publication_consent_snapshot_v1('CLUB', selected_club.id, actor_id));

    return private.pachanga_club_store_command_v1(
      operation_id, actor_id, 'authenticated', action_name, 'club', selected_club.id,
      selected_club.id, selected_club.revision, sequence_value, action_name,
      request_hash, private.pachanga_club_client_metadata_v1(client_metadata),
      jsonb_build_object('contentFingerprint', fingerprint), snapshot,
      actor_id, null, confirmed_at
    );
  end if;

  request_hash := private.pachanga_referee_request_hash_v1(
    action_name, subject_id, expected_revision, confirmations
  );
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  perform private.pachanga_referee_rate_limit_v1(actor_id, action_name);

  select * into selected_profile
  from public.pachanga_referee_profiles profiles
  where profiles.id = subject_id
  for update;
  if not found then raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected_profile.user_id <> actor_id then
    raise exception 'REFEREE_PROFILE_OWNER_REQUIRED' using errcode = '42501';
  end if;
  if selected_profile.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if selected_profile.operational_status in ('suspended', 'archived') then
    raise exception 'REFEREE_PUBLICATION_CONSENT_NOT_ALLOWED' using errcode = '42501';
  end if;
  if coalesce((confirmations ->> 'informationCorrect')::boolean, false) is not true
     or coalesce((confirmations ->> 'unverifiedNotCertification')::boolean, false) is not true
     or coalesce((confirmations ->> 'publicZonesAvailability')::boolean, false) is not true then
    raise exception 'REFEREE_PUBLICATION_CONFIRMATIONS_REQUIRED' using errcode = '22023';
  end if;

  fingerprint := private.pachanga_referee_public_content_fingerprint_v1(selected_profile.id);
  update public.pachanga_referee_profiles profiles set
    revision = profiles.revision + 1,
    server_sequence = nextval('private.pachanga_referee_sequence'),
    updated_at = confirmed_at
  where profiles.id = selected_profile.id
  returning * into selected_profile;

  insert into private.pachanga_publication_consents(
    operation_id, subject_kind, subject_id, actor_id, content_fingerprint,
    information_correct, unverified_not_certification, public_zones_availability,
    subject_revision, consented_at
  ) values (
    operation_id, normalized_kind, selected_profile.id, actor_id, fingerprint,
    true, true, true, selected_profile.revision, confirmed_at
  );

  snapshot := private.pachanga_referee_private_snapshot_v1(selected_profile.id, actor_id)
    || jsonb_build_object('publicationConsent',
      private.pachanga_publication_consent_snapshot_v1('REFEREE_PROFILE', selected_profile.id, actor_id));

  return private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', action_name, 'referee_profile',
    selected_profile.id::text, request_hash, selected_profile.revision, action_name,
    jsonb_build_object('contentFingerprint', fingerprint), snapshot,
    selected_profile.id, null, null, actor_id, null, 'private', client_metadata
  );
exception
  when unique_violation then
    raise exception 'PUBLICATION_CONSENT_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_publication_consent_v1(
  uuid, text, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_publication_consent_v1(
  uuid, text, uuid, bigint, jsonb, jsonb
) to authenticated;

create or replace function private.pachanga_club_publication_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.operational_status = 'active'
     and old.visibility = 'public'
     and new.operational_status = 'active'
     and new.visibility = 'public'
     and (
       new.name, new.slug, new.description, new.club_type, new.country_code,
       new.province, new.municipality, new.general_area, new.logo_asset
     ) is distinct from (
       old.name, old.slug, old.description, old.club_type, old.country_code,
       old.province, old.municipality, old.general_area, old.logo_asset
     ) then
    raise exception 'CLUB_PUBLICATION_PAUSE_REQUIRED' using errcode = '42501';
  end if;

  if new.operational_status = 'active'
     and new.visibility = 'public'
     and old.visibility is distinct from 'public' then
    if (
      new.name, new.slug, new.description, new.club_type, new.country_code,
      new.province, new.municipality, new.general_area, new.logo_asset
    ) is distinct from (
      old.name, old.slug, old.description, old.club_type, old.country_code,
      old.province, old.municipality, old.general_area, old.logo_asset
    ) then
      raise exception 'CLUB_PUBLICATION_RECONFIRM_REQUIRED' using errcode = '42501';
    end if;
    if not private.pachanga_publication_consent_valid_v1(
      'CLUB', new.id, new.primary_owner_id
    ) then
      raise exception 'CLUB_PUBLICATION_CONSENT_REQUIRED' using errcode = '42501';
    end if;
  end if;

  if new.operational_status = 'pending_review'
     and old.operational_status is distinct from 'pending_review' then
    if old.operational_status not in ('draft', 'rejected') then
      raise exception 'CLUB_REVIEW_TRANSITION_NOT_ALLOWED' using errcode = '22023';
    end if;
    if not private.pachanga_publication_consent_valid_v1(
      'CLUB', new.id, new.primary_owner_id
    ) then
      raise exception 'CLUB_PUBLICATION_CONSENT_REQUIRED' using errcode = '42501';
    end if;
  end if;

  if new.operational_status = 'active'
     and old.operational_status is distinct from 'active' then
    if old.operational_status not in ('pending_review', 'suspended') then
      raise exception 'CLUB_APPROVAL_REQUIRES_PENDING_REVIEW' using errcode = '22023';
    end if;
    if not private.pachanga_publication_consent_valid_v1(
      'CLUB', new.id, new.primary_owner_id
    ) then
      raise exception 'CLUB_PUBLICATION_CONSENT_REQUIRED' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_club_publication_guard_v1 on public.pachanga_clubs;
create trigger pachanga_club_publication_guard_v1
before update of operational_status, visibility, name, slug, description, club_type,
  country_code, province, municipality, general_area, logo_asset
on public.pachanga_clubs
for each row execute function private.pachanga_club_publication_guard_v1();

create or replace function private.pachanga_referee_publication_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.operational_status = 'active'
     and old.visibility = 'public'
     and new.operational_status = 'active'
     and new.visibility = 'public'
     and (
       new.slug, new.public_display_name_snapshot, new.public_avatar_snapshot,
       new.bio, new.experience_since_year, new.experience_summary,
       new.availability_status, new.available_for_assignments,
       new.share_recurring_availability
     ) is distinct from (
       old.slug, old.public_display_name_snapshot, old.public_avatar_snapshot,
       old.bio, old.experience_since_year, old.experience_summary,
       old.availability_status, old.available_for_assignments,
       old.share_recurring_availability
     ) then
    raise exception 'REFEREE_PUBLICATION_PAUSE_REQUIRED' using errcode = '42501';
  end if;

  if new.operational_status = 'active'
     and new.visibility = 'public'
     and old.visibility is distinct from 'public'
     and (
       new.slug, new.public_display_name_snapshot, new.public_avatar_snapshot,
       new.bio, new.experience_since_year, new.experience_summary,
       new.availability_status, new.available_for_assignments,
       new.share_recurring_availability
     ) is distinct from (
       old.slug, old.public_display_name_snapshot, old.public_avatar_snapshot,
       old.bio, old.experience_since_year, old.experience_summary,
       old.availability_status, old.available_for_assignments,
       old.share_recurring_availability
     ) then
    raise exception 'REFEREE_PUBLICATION_RECONFIRM_REQUIRED' using errcode = '42501';
  end if;

  if (
    (new.operational_status = 'active' and old.operational_status is distinct from 'active')
    or (new.marketplace_status = 'listed' and old.marketplace_status is distinct from 'listed')
    or (new.visibility = 'public' and old.visibility is distinct from 'public'
        and new.operational_status = 'active')
  ) and not private.pachanga_publication_consent_valid_v1(
    'REFEREE_PROFILE', new.id, new.user_id
  ) then
    raise exception 'REFEREE_PUBLICATION_CONSENT_REQUIRED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_referee_publication_guard_v1 on public.pachanga_referee_profiles;
create trigger pachanga_referee_publication_guard_v1
before update of operational_status, marketplace_status, visibility, slug,
  public_display_name_snapshot, public_avatar_snapshot, bio, experience_since_year,
  experience_summary, availability_status, available_for_assignments,
  share_recurring_availability
on public.pachanga_referee_profiles
for each row execute function private.pachanga_referee_publication_guard_v1();

create or replace function private.pachanga_referee_listed_content_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare target_profile_id uuid;
begin
  target_profile_id := case when tg_op = 'DELETE' then old.referee_profile_id else new.referee_profile_id end;
  if exists (
    select 1 from public.pachanga_referee_profiles profiles
    where profiles.id = target_profile_id
      and (
        profiles.marketplace_status = 'listed'
        or (profiles.operational_status = 'active' and profiles.visibility = 'public')
      )
  ) then
    raise exception 'REFEREE_PUBLICATION_PAUSE_REQUIRED' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists pachanga_referee_modalities_listed_guard_v1 on public.pachanga_referee_modalities;
create trigger pachanga_referee_modalities_listed_guard_v1
before insert or update or delete on public.pachanga_referee_modalities
for each row execute function private.pachanga_referee_listed_content_guard_v1();

drop trigger if exists pachanga_referee_areas_listed_guard_v1 on public.pachanga_referee_service_areas;
create trigger pachanga_referee_areas_listed_guard_v1
before insert or update or delete on public.pachanga_referee_service_areas
for each row execute function private.pachanga_referee_listed_content_guard_v1();

drop trigger if exists pachanga_referee_windows_listed_guard_v1 on public.pachanga_referee_availability_windows;
create trigger pachanga_referee_windows_listed_guard_v1
before insert or update or delete on public.pachanga_referee_availability_windows
for each row execute function private.pachanga_referee_listed_content_guard_v1();

create or replace function public.command_pachanga_club_referee_invite_by_profile_v1(
  operation_id uuid,
  target_club_id uuid,
  expected_club_revision bigint,
  target_referee_profile_id uuid,
  relationship_type text default 'REGULAR',
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  selected_club public.pachanga_clubs%rowtype;
  selected_profile public.pachanga_referee_profiles%rowtype;
  normalized_relationship text := upper(trim(coalesce(relationship_type, 'REGULAR')));
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if operation_id is null or target_club_id is null or target_referee_profile_id is null
     or expected_club_revision is null or expected_club_revision < 1
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_REFEREE_INVITATION' using errcode = '22023';
  end if;
  if normalized_relationship not in ('REGULAR', 'COLLABORATOR', 'PREFERRED') then
    raise exception 'INVALID_REFEREE_RELATIONSHIP_TYPE' using errcode = '22023';
  end if;

  select * into selected_club
  from public.pachanga_clubs clubs
  where clubs.id = target_club_id
  for update;
  if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected_club.revision <> expected_club_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if selected_club.operational_status <> 'active'
     or not private.pachanga_club_can_v1(selected_club.id, actor_id, 'referee_manage') then
    raise exception 'CLUB_REFEREE_CAPABILITY_REQUIRED' using errcode = '42501';
  end if;

  select * into selected_profile
  from public.pachanga_referee_profiles profiles
  where profiles.id = target_referee_profile_id;
  if not found or selected_profile.operational_status <> 'active'
     or selected_profile.visibility <> 'public'
     or selected_profile.marketplace_status <> 'listed' then
    raise exception 'REFEREE_PROFILE_NOT_AVAILABLE' using errcode = 'P0002';
  end if;

  return public.command_pachanga_referee_platform_v1(
    operation_id,
    operation_id,
    0,
    'relationship.invite',
    jsonb_build_object(
      'clubId', selected_club.id,
      'contextClubRevision', selected_club.revision,
      'reason', 'club_referee_marketplace_invite',
      'relationshipType', normalized_relationship,
      'targetKind', 'registered_user',
      'targetUserId', selected_profile.user_id
    ),
    coalesce(client_metadata, '{}'::jsonb) || jsonb_build_object('surface', 'club_referee_marketplace')
  );
end;
$$;

revoke all on function public.command_pachanga_club_referee_invite_by_profile_v1(
  uuid, uuid, bigint, uuid, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_club_referee_invite_by_profile_v1(
  uuid, uuid, bigint, uuid, text, jsonb
) to authenticated;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_club_publication_guard_v1()'::regprocedure,
    'private.pachanga_referee_publication_guard_v1()'::regprocedure,
    'private.pachanga_referee_listed_content_guard_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

comment on function public.command_pachanga_publication_consent_v1(
  uuid, text, uuid, bigint, jsonb, jsonb
) is 'Idempotent publication consent tied to the current canonical public-content fingerprint.';
comment on function public.command_pachanga_club_referee_invite_by_profile_v1(
  uuid, uuid, bigint, uuid, text, jsonb
) is 'Club invitation by opaque referee profile. Resolves the target Auth identity only inside PostgreSQL.';
