-- Clubs + Referees public beta read models, notification routing and SEO-safe data.
-- Product flags remain unchanged by this migration.

create or replace function public.search_pachanga_public_clubs_v1(
  target_filters jsonb default '{}'::jsonb,
  target_page integer default 1,
  target_page_size integer default 24
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  safe_page integer := greatest(1, coalesce(target_page, 1));
  safe_page_size integer := least(60, greatest(1, coalesce(target_page_size, 24)));
  safe_filters jsonb := case when jsonb_typeof(target_filters) = 'object' then target_filters else '{}'::jsonb end;
  result jsonb;
begin
  if not coalesce((
    select settings.club_foundation_enabled and settings.club_public_profiles_enabled
    from private.pachanga_club_foundation_settings settings
    where settings.singleton
  ), false) then
    return jsonb_build_object(
      'enabled', false,
      'items', '[]'::jsonb,
      'page', safe_page,
      'pageSize', safe_page_size,
      'total', 0
    );
  end if;

  with eligible as materialized (
    select clubs.id
    from public.pachanga_clubs clubs
    where clubs.operational_status = 'active'
      and clubs.visibility = 'public'
      and (
        nullif(trim(safe_filters ->> 'query'), '') is null
        or concat_ws(' ', clubs.name, clubs.description, clubs.municipality, clubs.general_area)
          ilike '%' || trim(safe_filters ->> 'query') || '%'
      )
      and (
        nullif(trim(safe_filters ->> 'zone'), '') is null
        or concat_ws(' ', clubs.province, clubs.municipality, clubs.general_area)
          ilike '%' || trim(safe_filters ->> 'zone') || '%'
      )
      and (
        nullif(trim(safe_filters ->> 'municipality'), '') is null
        or clubs.municipality ilike trim(safe_filters ->> 'municipality')
      )
      and (
        nullif(trim(safe_filters ->> 'clubType'), '') is null
        or clubs.club_type = upper(trim(safe_filters ->> 'clubType'))
      )
      and (
        nullif(trim(safe_filters ->> 'verified'), '') is null
        or (clubs.verification_status = 'verified') = (safe_filters ->> 'verified')::boolean
      )
      and (
        nullif(trim(safe_filters ->> 'partner'), '') is null
        or (clubs.partnership_status = 'active') = (safe_filters ->> 'partner')::boolean
      )
  ), paged as (
    select clubs.id
    from eligible
    join public.pachanga_clubs clubs on clubs.id = eligible.id
    order by
      (clubs.verification_status = 'verified') desc,
      (clubs.partnership_status = 'active') desc,
      clubs.name,
      clubs.id
    limit safe_page_size offset (safe_page - 1) * safe_page_size
  )
  select jsonb_build_object(
    'enabled', true,
    'items', coalesce(jsonb_agg(
      private.pachanga_public_club_snapshot_v1(paged.id)
        || jsonb_build_object(
          'clubId', paged.id,
          'revision', clubs.revision,
          'updatedAt', clubs.updated_at
        )
      order by
        (clubs.verification_status = 'verified') desc,
        (clubs.partnership_status = 'active') desc,
        clubs.name,
        clubs.id
    ), '[]'::jsonb),
    'page', safe_page,
    'pageSize', safe_page_size,
    'total', (select count(*) from eligible),
    'ordering', 'verified_then_partner_then_name'
  ) into result
  from paged
  join public.pachanga_clubs clubs on clubs.id = paged.id;

  return result;
end;
$$;

create or replace function private.pachanga_club_referee_relationships_snapshot_v1(
  target_club_id uuid,
  target_actor_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case
    when not private.pachanga_club_can_v1(target_club_id, target_actor_id, 'referee_manage')
      then '[]'::jsonb
    else coalesce((
      select jsonb_agg(rows.document order by rows.server_sequence desc, rows.id desc)
      from (
        select relationships.id, relationships.server_sequence, jsonb_build_object(
          'id', relationships.id,
          'refereeProfileId', relationships.referee_profile_id,
          'refereeName', coalesce(profiles.public_display_name_snapshot, 'Invitacion pendiente'),
          'refereeSlug', profiles.slug,
          'relationshipType', relationships.relationship_type,
          'initiatedBy', relationships.initiated_by,
          'status', relationships.status,
          'showOnRefereeProfile', relationships.show_on_referee_profile,
          'showOnClubProfile', relationships.show_on_club_profile,
          'expiresAt', relationships.expires_at,
          'startedAt', relationships.started_at,
          'endedAt', relationships.ended_at,
          'revision', relationships.revision,
          'serverSequence', relationships.server_sequence,
          'updatedAt', relationships.updated_at
        ) as document
        from public.pachanga_club_referee_relationships relationships
        left join public.pachanga_referee_profiles profiles
          on profiles.id = relationships.referee_profile_id
        where relationships.club_id = target_club_id
        order by relationships.server_sequence desc, relationships.id desc
        limit 200
      ) rows
    ), '[]'::jsonb)
  end;
$$;

create or replace function private.pachanga_club_team_candidates_snapshot_v1(
  target_club_id uuid,
  target_actor_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case
    when not private.pachanga_club_can_v1(target_club_id, target_actor_id, 'team_links_manage')
      or not exists (
        select 1
        from public.pachanga_clubs clubs
        where clubs.id = target_club_id
          and clubs.operational_status = 'active'
      ) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', candidates.id,
        'name', candidates.name,
        'zone', candidates.zone_label,
        'modalities', candidates.modalities,
        'revision', candidates.revision,
        'updatedAt', candidates.updated_at
      ) order by candidates.name, candidates.id)
      from (
        select
          groups.id,
          groups.name,
          profiles.zone_label,
          profiles.modalities,
          profiles.revision,
          profiles.updated_at
        from public.pachanga_challengeable_team_profiles profiles
        join public.pachanga_groups groups on groups.id = profiles.group_id
        where profiles.enabled
          and not exists (
            select 1
            from public.pachanga_club_team_relationships relationships
            where relationships.club_id = target_club_id
              and relationships.group_id = groups.id
              and relationships.status in ('invited', 'requested', 'active')
          )
        order by groups.name, groups.id
        limit 100
      ) candidates
    ), '[]'::jsonb)
  end;
$$;

create or replace function public.get_my_pachanga_clubs_beta_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  base jsonb;
  enriched_clubs jsonb;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  base := public.get_my_pachanga_club_foundation_v1();

  select coalesce(jsonb_agg(
    items.item || jsonb_build_object(
      'capabilities', coalesce(items.item -> 'capabilities', '{}'::jsonb)
        || jsonb_build_object(
          'refereeManage', private.pachanga_club_can_v1(
            (items.item -> 'club' ->> 'id')::uuid, actor_id, 'referee_manage'
          )
        ),
      'publicationConsent', private.pachanga_publication_consent_snapshot_v1(
        'CLUB', (items.item -> 'club' ->> 'id')::uuid, actor_id
      ),
      'refereeRelationships', private.pachanga_club_referee_relationships_snapshot_v1(
        (items.item -> 'club' ->> 'id')::uuid, actor_id
      ),
      'teamCandidates', private.pachanga_club_team_candidates_snapshot_v1(
        (items.item -> 'club' ->> 'id')::uuid, actor_id
      )
    ) order by items.ordinality
  ), '[]'::jsonb) into enriched_clubs
  from jsonb_array_elements(coalesce(base -> 'clubs', '[]'::jsonb))
    with ordinality as items(item, ordinality);

  return jsonb_set(base, '{clubs}', enriched_clubs, true)
    || jsonb_build_object(
      'ownedTeams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', groups.id,
          'name', groups.name,
          'revision', groups.payload_revision,
          'updatedAt', groups.updated_at
        ) order by groups.name, groups.id)
        from public.pachanga_groups groups
        where groups.owner_id = actor_id
      ), '[]'::jsonb)
    );
end;
$$;

create or replace function public.get_my_pachanga_referee_beta_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  base jsonb;
  profile_id uuid;
  enriched_profile jsonb;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  base := public.get_my_pachanga_referee_platform_v1();
  profile_id := nullif(base -> 'profile' -> 'profile' ->> 'id', '')::uuid;
  if profile_id is null then return base; end if;
  enriched_profile := coalesce(base -> 'profile', '{}'::jsonb)
    || jsonb_build_object(
      'publicationConsent', private.pachanga_publication_consent_snapshot_v1(
        'REFEREE_PROFILE', profile_id, actor_id
      )
    );
  return jsonb_set(base, '{profile}', enriched_profile, true);
end;
$$;

revoke all on function public.search_pachanga_public_clubs_v1(jsonb, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.search_pachanga_public_clubs_v1(jsonb, integer, integer)
  to anon, authenticated, service_role;

revoke all on function public.get_my_pachanga_clubs_beta_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_clubs_beta_v1()
  to authenticated, service_role;

revoke all on function public.get_my_pachanga_referee_beta_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_referee_beta_v1()
  to authenticated, service_role;

revoke all on function private.pachanga_club_referee_relationships_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_club_team_candidates_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_notification_policy_v1(target_kind text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select lower(coalesce(nullif(trim(target_kind), ''), 'general')) as kind
  )
  select jsonb_build_object(
    'category', case
      when kind like '%achievement%' or kind like '%reward%' then 'achievement'
      when kind like '%challenge%' or kind like '%external_result%' then 'challenge'
      when kind like '%invitation%' or kind like '%open_match_request%'
        or kind like '%withdrawal%' or kind like '%market%'
        or kind like 'club_team_%' or kind like 'referee_club_%'
        or kind like 'club_referee_%' then 'market'
      when kind like '%attendance%' or kind like '%availability%'
        or kind like 'match_%' then 'match'
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' then 'security'
      else 'group'
    end,
    'priority', case
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' or kind like '%challenge%'
        or kind like '%external_result%' or kind like '%invitation%'
        or kind like '%open_match_request%' or kind like '%withdrawal%'
        or kind in (
          'club_team_request', 'club_team_invitation',
          'club_review_approved', 'club_review_rejected',
          'referee_club_request'
        ) then 'critical'
      when kind like '%achievement%' or kind like '%reward%'
        or kind in ('group_member_removed', 'match_attendance_cancelled') then 'high'
      else 'normal'
    end,
    'mandatoryInApp', (
      kind like '%security%' or kind like '%sanction%' or kind like '%warning%'
      or kind like '%challenge%' or kind like '%external_result%'
      or kind like '%invitation%' or kind like '%open_match_request%'
      or kind like '%withdrawal%' or kind like '%achievement%' or kind like '%reward%'
      or kind in (
        'group_member_removed', 'club_team_request',
        'club_review_approved', 'club_review_rejected',
        'referee_club_request'
      )
    )
  )
  from normalized;
$$;

revoke all on function private.pachanga_notification_policy_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_product_notification_route_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  club_id text := nullif(new.payload ->> 'clubId', '');
  relationship_id text := nullif(new.payload ->> 'relationshipId', '');
  relationship_initiated_by text;
begin
  if relationship_id is not null and new.kind like 'referee_club_%' then
    select relationships.initiated_by into relationship_initiated_by
    from public.pachanga_club_referee_relationships relationships
    where relationships.id = relationship_id::uuid;
  end if;

  if new.kind like 'club_team_%' then
    new.action_url := '/clubes/gestionar?club=' || coalesce(club_id, '')
      || '&section=equipos'
      || case when relationship_id is null then '' else '&relationship=' || relationship_id end;
  elsif new.kind = 'referee_club_invitation'
        or (
          new.kind in ('referee_club_relationship_accepted', 'referee_club_relationship_rejected')
          and relationship_initiated_by = 'REFEREE'
        )
        or new.kind like 'referee_relationship_%' then
    new.action_url := '/perfil/arbitro?section=clubs'
      || case when relationship_id is null then '' else '&relationship=' || relationship_id end;
  elsif new.kind = 'referee_club_request'
        or (
          new.kind in ('referee_club_relationship_accepted', 'referee_club_relationship_rejected')
          and relationship_initiated_by = 'CLUB'
        )
        or new.kind like 'club_referee_%' then
    new.action_url := '/clubes/gestionar?club=' || coalesce(club_id, '')
      || '&section=arbitros'
      || case when relationship_id is null then '' else '&relationship=' || relationship_id end;
  elsif new.kind in ('club_created', 'club_review_submitted', 'club_review_approved', 'club_review_rejected') then
    new.action_url := '/clubes/gestionar?club=' || coalesce(club_id, '');
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_product_notification_route_v1
  on public.pachanga_user_notifications;
create trigger pachanga_product_notification_route_v1
before insert on public.pachanga_user_notifications
for each row execute function private.pachanga_product_notification_route_v1();

create or replace function private.pachanga_club_beta_lifecycle_notify_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipient_id uuid;
  notification_kind text;
  notification_title text;
  notification_body text;
  club_name text;
begin
  if new.club_id is null then return new; end if;
  select clubs.primary_owner_id, clubs.name into recipient_id, club_name
  from public.pachanga_clubs clubs where clubs.id = new.club_id;
  if recipient_id is null then return new; end if;

  if new.action = 'club.create' then
    notification_kind := 'club_created';
    notification_title := 'Club creado';
    notification_body := club_name || ' se ha guardado como borrador privado.';
  elsif new.action = 'club.review.submit' then
    notification_kind := 'club_review_submitted';
    notification_title := 'Club enviado a revisión';
    notification_body := club_name || ' está pendiente de revisión por Pachangas IQ.';
  elsif new.action = 'club.status.set' and new.event_payload ->> 'nextValue' = 'active' then
    notification_kind := 'club_review_approved';
    notification_title := 'Club aprobado';
    notification_body := club_name || ' ya puede mostrarse públicamente.';
  elsif new.action = 'club.status.set' and new.event_payload ->> 'nextValue' = 'rejected' then
    notification_kind := 'club_review_rejected';
    notification_title := 'Revisión del Club rechazada';
    notification_body := 'Revisa el perfil de ' || club_name || ' antes de volver a enviarlo.';
  else
    return new;
  end if;

  perform private.pachanga_club_notify_v1(
    recipient_id,
    notification_kind,
    notification_title,
    notification_body,
    '/clubes/gestionar?club=' || new.club_id::text,
    jsonb_build_object('clubId', new.club_id),
    'club-beta-lifecycle:' || new.operation_id::text || ':' || recipient_id::text
  );
  return new;
end;
$$;

drop trigger if exists pachanga_club_beta_lifecycle_notify_v1
  on private.pachanga_club_events;
create trigger pachanga_club_beta_lifecycle_notify_v1
after insert on private.pachanga_club_events
for each row execute function private.pachanga_club_beta_lifecycle_notify_v1();

create or replace function private.pachanga_referee_beta_lifecycle_notify_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipient_id uuid;
  display_name text;
  notification_kind text;
  notification_title text;
  notification_body text;
begin
  if new.profile_id is null or new.action not in ('profile.activate', 'marketplace.list') then
    return new;
  end if;
  select profiles.user_id, profiles.public_display_name_snapshot
    into recipient_id, display_name
  from public.pachanga_referee_profiles profiles where profiles.id = new.profile_id;
  if recipient_id is null then return new; end if;

  if new.action = 'profile.activate' then
    notification_kind := 'referee_profile_activated';
    notification_title := 'Ficha de árbitro activada';
    notification_body := display_name || ' ya tiene una ficha arbitral activa.';
  else
    notification_kind := 'referee_marketplace_listed';
    notification_title := 'Ficha publicada en Mercado';
    notification_body := 'Tu ficha arbitral ya aparece en el Mercado de árbitros.';
  end if;

  perform private.pachanga_referee_notify_v1(
    recipient_id,
    notification_kind,
    notification_title,
    notification_body,
    '/perfil/arbitro',
    jsonb_build_object('profileId', new.profile_id),
    'referee-beta-lifecycle:' || new.operation_id::text || ':' || recipient_id::text
  );
  return new;
end;
$$;

drop trigger if exists pachanga_referee_beta_lifecycle_notify_v1
  on private.pachanga_referee_events;
create trigger pachanga_referee_beta_lifecycle_notify_v1
after insert on private.pachanga_referee_events
for each row execute function private.pachanga_referee_beta_lifecycle_notify_v1();

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_product_notification_route_v1()'::regprocedure,
    'private.pachanga_club_beta_lifecycle_notify_v1()'::regprocedure,
    'private.pachanga_referee_beta_lifecycle_notify_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

comment on function public.search_pachanga_public_clubs_v1(jsonb, integer, integer) is
  'Public paginated Club directory. Returns active/public profiles only and never contact, staff, invitation or entitlement data.';
comment on function public.get_my_pachanga_clubs_beta_v1() is
  'Authenticated Clubs beta workspace with derived owned-team choices and current publication consent evidence.';
comment on function public.get_my_pachanga_referee_beta_v1() is
  'Authenticated referee beta workspace with current publication consent evidence and no assignment activation.';
comment on function private.pachanga_club_referee_relationships_snapshot_v1(uuid, uuid) is
  'Private Club-referee relationship read model. Never exposes Auth identities, email targets or invitation secrets.';
comment on function private.pachanga_club_team_candidates_snapshot_v1(uuid, uuid) is
  'Safe candidate list for Club-to-Team invitations. Returns only voluntarily public challengeable-team fields and never coordinates or owner identities.';
