-- Clubs + Referees public beta: private, append-only publication consent.
-- Product flags remain unchanged by this migration.

create sequence if not exists private.pachanga_publication_consent_sequence;
revoke all on sequence private.pachanga_publication_consent_sequence
  from public, anon, authenticated;

create table if not exists private.pachanga_publication_consents (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  subject_kind text not null,
  subject_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  content_fingerprint text not null,
  representation_authorized boolean not null default false,
  information_correct boolean not null default false,
  unverified_not_certification boolean not null default false,
  public_zones_availability boolean not null default false,
  subject_revision bigint not null check (subject_revision >= 1),
  server_sequence bigint not null unique default nextval('private.pachanga_publication_consent_sequence'),
  consented_at timestamptz not null default clock_timestamp(),
  check (subject_kind in ('CLUB', 'REFEREE_PROFILE')),
  check (length(content_fingerprint) = 64),
  check (
    (subject_kind = 'CLUB'
      and representation_authorized
      and information_correct)
    or
    (subject_kind = 'REFEREE_PROFILE'
      and information_correct
      and unverified_not_certification
      and public_zones_availability)
  )
);

create index if not exists pachanga_publication_consents_subject_idx
  on private.pachanga_publication_consents(
    subject_kind, subject_id, actor_id, server_sequence desc, id desc
  );

revoke all on table private.pachanga_publication_consents
  from public, anon, authenticated;
grant all on table private.pachanga_publication_consents to service_role;

create or replace function private.pachanga_club_public_content_fingerprint_v1(target_club_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'name', clubs.name,
    'slug', clubs.slug,
    'description', clubs.description,
    'clubType', clubs.club_type,
    'countryCode', clubs.country_code,
    'province', clubs.province,
    'municipality', clubs.municipality,
    'generalArea', clubs.general_area,
    'logoAsset', clubs.logo_asset
  )::text, 'UTF8'), 'sha256'), 'hex')
  from public.pachanga_clubs clubs
  where clubs.id = target_club_id;
$$;

create or replace function private.pachanga_referee_public_content_fingerprint_v1(target_profile_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'slug', profiles.slug,
    'displayName', profiles.public_display_name_snapshot,
    'avatar', profiles.public_avatar_snapshot,
    'bio', profiles.bio,
    'experienceSinceYear', profiles.experience_since_year,
    'experienceSummary', profiles.experience_summary,
    'availabilityStatus', profiles.availability_status,
    'availableForAssignments', profiles.available_for_assignments,
    'shareRecurringAvailability', profiles.share_recurring_availability,
    'modalities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'modality', modalities.modality,
        'experienceSinceYear', modalities.experience_since_year,
        'note', modalities.public_note
      ) order by modalities.modality, modalities.id)
      from public.pachanga_referee_modalities modalities
      where modalities.referee_profile_id = profiles.id and modalities.active
    ), '[]'::jsonb),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'countryCode', areas.country_code,
        'province', areas.province,
        'municipality', areas.municipality,
        'generalArea', areas.general_area,
        'travelRadiusKm', areas.travel_radius_km
      ) order by areas.country_code, areas.province, areas.municipality, areas.general_area, areas.id)
      from public.pachanga_referee_service_areas areas
      where areas.referee_profile_id = profiles.id and areas.status = 'active'
    ), '[]'::jsonb),
    'availabilityWindows', case when profiles.share_recurring_availability then coalesce((
      select jsonb_agg(jsonb_build_object(
        'weekday', windows.weekday,
        'startLocalTime', windows.start_local_time,
        'endLocalTime', windows.end_local_time,
        'timezone', windows.timezone
      ) order by windows.weekday, windows.start_local_time, windows.id)
      from public.pachanga_referee_availability_windows windows
      where windows.referee_profile_id = profiles.id
        and windows.status = 'active'
        and windows.public_visible
    ), '[]'::jsonb) else '[]'::jsonb end
  )::text, 'UTF8'), 'sha256'), 'hex')
  from public.pachanga_referee_profiles profiles
  where profiles.id = target_profile_id;
$$;

create or replace function private.pachanga_publication_consent_snapshot_v1(
  target_subject_kind text,
  target_subject_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  selected private.pachanga_publication_consents%rowtype;
  current_fingerprint text;
begin
  select * into selected
  from private.pachanga_publication_consents consents
  where consents.subject_kind = upper(trim(target_subject_kind))
    and consents.subject_id = target_subject_id
    and consents.actor_id = target_actor_id
  order by consents.server_sequence desc, consents.id desc
  limit 1;

  current_fingerprint := case upper(trim(target_subject_kind))
    when 'CLUB' then private.pachanga_club_public_content_fingerprint_v1(target_subject_id)
    when 'REFEREE_PROFILE' then private.pachanga_referee_public_content_fingerprint_v1(target_subject_id)
    else null
  end;

  if selected.id is null then
    return jsonb_build_object(
      'consented', false,
      'matchesCurrentContent', false,
      'subjectKind', upper(trim(target_subject_kind))
    );
  end if;

  return jsonb_build_object(
    'consented', true,
    'matchesCurrentContent', selected.content_fingerprint = current_fingerprint,
    'representationAuthorized', selected.representation_authorized,
    'informationCorrect', selected.information_correct,
    'unverifiedNotCertification', selected.unverified_not_certification,
    'publicZonesAvailability', selected.public_zones_availability,
    'subjectRevision', selected.subject_revision,
    'serverSequence', selected.server_sequence,
    'consentedAt', selected.consented_at,
    'subjectKind', selected.subject_kind
  );
end;
$$;

create or replace function private.pachanga_publication_consent_valid_v1(
  target_subject_kind text,
  target_subject_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    (private.pachanga_publication_consent_snapshot_v1(
      target_subject_kind, target_subject_id, target_actor_id
    ) ->> 'matchesCurrentContent')::boolean,
    false
  );
$$;

create or replace function private.pachanga_publication_consent_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'PUBLICATION_CONSENT_IMMUTABLE' using errcode = '42501';
end;
$$;

drop trigger if exists pachanga_publication_consents_immutable_v1
  on private.pachanga_publication_consents;
create trigger pachanga_publication_consents_immutable_v1
before update or delete on private.pachanga_publication_consents
for each row execute function private.pachanga_publication_consent_immutable_v1();

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_club_public_content_fingerprint_v1(uuid)'::regprocedure,
    'private.pachanga_referee_public_content_fingerprint_v1(uuid)'::regprocedure,
    'private.pachanga_publication_consent_snapshot_v1(text,uuid,uuid)'::regprocedure,
    'private.pachanga_publication_consent_valid_v1(text,uuid,uuid)'::regprocedure,
    'private.pachanga_publication_consent_immutable_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

comment on table private.pachanga_publication_consents is
  'Append-only evidence that a Club owner or referee accepted the exact public content fingerprint before publication.';
