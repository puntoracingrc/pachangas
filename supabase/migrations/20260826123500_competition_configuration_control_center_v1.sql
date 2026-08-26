-- Pachangas IQ Wave 5A: platform health and safe dependency shutdown.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_configuration_gate_dependencies_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not new.foundation_enabled or not new.league_private_beta_enabled then
    new.competition_configuration_center_enabled := false;
    new.league_wizard_v2_enabled := false;
  elsif not new.league_private_beta_creation_enabled then
    new.league_wizard_v2_enabled := false;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_configuration_gate_dependencies_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_competition_configuration_dependencies_v1
  on private.pachanga_competition_foundation_settings;
create trigger guard_pachanga_competition_configuration_dependencies_v1
before insert or update on private.pachanga_competition_foundation_settings
for each row execute function private.pachanga_competition_configuration_gate_dependencies_v1();

create or replace function public.get_pachanga_platform_competition_configuration_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare drafts jsonb;
declare revisions jsonb;
declare events jsonb;
declare metrics jsonb;
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  select * into settings from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;

  select jsonb_build_object(
    'drafts',count(*) filter (where configuration_drafts.status='draft'),
    'validated',count(*) filter (where configuration_drafts.status='validated'),
    'published',count(*) filter (where configuration_drafts.status='published'),
    'cancelled',count(*) filter (where configuration_drafts.status='cancelled'),
    'blockingErrors',coalesce(sum(jsonb_array_length(
      private.pachanga_competition_configuration_health_v1(
        configuration_drafts.step_data,configuration_drafts.completed_steps
      ) -> 'errors'
    )) filter (where configuration_drafts.status in ('draft','validated')),0),
    'warnings',coalesce(sum(jsonb_array_length(
      private.pachanga_competition_configuration_health_v1(
        configuration_drafts.step_data,configuration_drafts.completed_steps
      ) -> 'warnings'
    )) filter (where configuration_drafts.status in ('draft','validated')),0)
  ) into metrics
  from private.pachanga_competition_configuration_drafts configuration_drafts;

  metrics := metrics || jsonb_build_object(
    'configurationRuleRevisions',(
      select count(*) from public.pachanga_competition_rule_revisions rule_revisions
      where rule_revisions.rule_document #>> '{identity,configurationSchema}'='competition-configuration.v1'
    ),
    'presets',4,
    'legacyBackfillCount',0
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',visible.id,'competitionId',visible.competition_id,'competitionName',visible.competition_name,
    'status',visible.status,'authoringMode',visible.authoring_mode,'presetKey',visible.preset_key,
    'revision',visible.revision,'serverSequence',visible.server_sequence,
    'health',private.pachanga_competition_configuration_health_v1(visible.step_data,visible.completed_steps),
    'impact',visible.impact_snapshot,'updatedAt',visible.updated_at
  ) order by visible.server_sequence desc,visible.id desc),'[]'::jsonb) into drafts
  from (
    select configuration_drafts.*,competitions.name competition_name
    from private.pachanga_competition_configuration_drafts configuration_drafts
    join public.pachanga_competitions competitions on competitions.id=configuration_drafts.competition_id
    order by configuration_drafts.server_sequence desc,configuration_drafts.id desc limit 50
  ) visible;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',visible.id,'competitionId',visible.competition_id,'competitionName',visible.competition_name,
    'version',visible.version,'status',visible.status,'effectiveFrom',visible.effective_from,
    'effectiveScope',visible.effective_scope,'checksum',visible.checksum,
    'serverSequence',visible.server_sequence,'createdAt',visible.created_at
  ) order by visible.server_sequence desc,visible.id desc),'[]'::jsonb) into revisions
  from (
    select rule_revisions.*,rule_sets.competition_id,competitions.name competition_name
    from public.pachanga_competition_rule_revisions rule_revisions
    join public.pachanga_competition_rule_sets rule_sets on rule_sets.id=rule_revisions.rule_set_id
    join public.pachanga_competitions competitions on competitions.id=rule_sets.competition_id
    where rule_revisions.rule_document #>> '{identity,configurationSchema}'='competition-configuration.v1'
    order by rule_revisions.server_sequence desc,rule_revisions.id desc limit 50
  ) visible;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',visible.id,'competitionId',visible.competition_id,'competitionName',visible.competition_name,
    'draftId',visible.draft_id,'ruleRevisionId',visible.rule_revision_id,'action',visible.action,
    'aggregateRevision',visible.aggregate_revision,'serverSequence',visible.server_sequence,
    'reasonCode',visible.reason_code,'confirmedAt',visible.confirmed_at
  ) order by visible.server_sequence desc,visible.id desc),'[]'::jsonb) into events
  from (
    select configuration_events.*,competitions.name competition_name
    from private.pachanga_competition_configuration_events configuration_events
    join public.pachanga_competitions competitions on competitions.id=configuration_events.competition_id
    order by configuration_events.server_sequence desc,configuration_events.id desc limit 50
  ) visible;

  return jsonb_build_object(
    'flags',jsonb_build_object(
      'configurationCenterEnabled',settings.competition_configuration_center_enabled,
      'wizardV2Enabled',settings.league_wizard_v2_enabled,
      'leaguePrivateBetaEnabled',settings.league_private_beta_enabled,
      'leagueCreationEnabled',settings.league_private_beta_creation_enabled,
      'publicSurfacesOff',not (
        settings.league_private_beta_public_discovery_enabled
        or settings.league_public_registration_enabled
        or settings.league_public_calendar_enabled
        or settings.league_public_standings_enabled
        or settings.league_public_exception_status_enabled
        or settings.competition_public_discipline_enabled
      ),
      'revision',settings.revision,'serverSequence',settings.server_sequence,'updatedAt',settings.updated_at
    ),
    'metrics',metrics,'drafts',drafts,'revisions',revisions,'events',events,
    'rollbackPolicy','publish_new_revision_never_down_migration',
    'unavailable',jsonb_build_array('payments','tournaments','manual_assisted_pairing','hybrid_pairing','public_surfaces')
  );
end;
$$;

revoke all on function public.get_pachanga_platform_competition_configuration_v1()
  from public, anon;
grant execute on function public.get_pachanga_platform_competition_configuration_v1()
  to authenticated, service_role;

comment on function public.get_pachanga_platform_competition_configuration_v1() is
  'Platform-only Wave 5A health. It exposes no private referee fee or browser-authored authority.';
