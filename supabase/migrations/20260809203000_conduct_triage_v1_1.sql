-- Pachangas IQ Conduct Triage V1.1.
-- Additive, disabled by default and isolated from every sporting system.

alter table private.pachanga_conduct_settings
  add column if not exists conduct_triage_enabled boolean not null default false,
  add column if not exists conduct_triage_shadow_mode boolean not null default true,
  add column if not exists triage_policy_version text not null default 'conduct-triage-v1.1-experimental',
  add column if not exists triage_urgent_sla_hours integer not null default 4,
  add column if not exists triage_priority_sla_hours integer not null default 24,
  add column if not exists triage_review_sla_hours integer not null default 72;

alter table private.pachanga_conduct_settings
  drop constraint if exists pachanga_conduct_settings_triage_sla_check;
alter table private.pachanga_conduct_settings
  add constraint pachanga_conduct_settings_triage_sla_check check (
    triage_urgent_sla_hours between 1 and 24
    and triage_priority_sla_hours between triage_urgent_sla_hours and 168
    and triage_review_sla_hours between triage_priority_sla_hours and 336
  );

create table if not exists private.pachanga_conduct_triage_category_policy (
  category text primary key,
  active_window_days integer not null,
  isolated_queue text not null,
  serious_category boolean not null default false,
  policy_version text not null default 'conduct-triage-v1.1-experimental',
  updated_at timestamptz not null default clock_timestamp(),
  check (active_window_days between 1 and 1825),
  check (isolated_queue in ('record_only', 'watch', 'review', 'priority_review', 'urgent_review'))
);

insert into private.pachanga_conduct_triage_category_policy(
  category, active_window_days, isolated_queue, serious_category
) values
  ('abusive_behavior', 180, 'record_only', false),
  ('deliberate_cheating', 180, 'record_only', false),
  ('discriminatory_behavior', 365, 'review', true),
  ('harassment', 365, 'review', true),
  ('other', 90, 'record_only', false),
  ('repeated_disruption', 180, 'record_only', false),
  ('threats_or_violence', 365, 'urgent_review', true),
  ('attendance_reliability', 180, 'review', false)
on conflict (category) do update set
  active_window_days = excluded.active_window_days,
  isolated_queue = excluded.isolated_queue,
  serious_category = excluded.serious_category,
  policy_version = excluded.policy_version,
  updated_at = clock_timestamp();

alter table private.pachanga_moderation_cases
  drop constraint if exists pachanga_moderation_cases_source_type_check;
alter table private.pachanga_moderation_cases
  add constraint pachanga_moderation_cases_source_type_check check (
    source_type in ('conduct_report', 'conduct_report_split', 'attendance_reliability', 'attendance_dispute')
  );

alter table private.pachanga_moderation_cases
  add column if not exists triage_recommendation text not null default 'review',
  add column if not exists operational_queue text not null default 'review',
  add column if not exists triage_reason_codes text[] not null default '{}',
  add column if not exists triage_policy_version text not null default 'conduct-triage-v1.1-experimental',
  add column if not exists triage_evaluated_at timestamptz,
  add column if not exists triage_due_at timestamptz,
  add column if not exists active_window_started_at timestamptz,
  add column if not exists active_window_ends_at timestamptz,
  add column if not exists triage_revision bigint not null default 0,
  add column if not exists triage_server_sequence bigint,
  add column if not exists merged_into_case_id uuid references private.pachanga_moderation_cases(id) on delete restrict;

alter table private.pachanga_moderation_cases
  drop constraint if exists pachanga_moderation_cases_triage_recommendation_check;
alter table private.pachanga_moderation_cases
  add constraint pachanga_moderation_cases_triage_recommendation_check check (
    triage_recommendation in ('record_only', 'watch', 'review', 'priority_review', 'urgent_review')
    and operational_queue in ('record_only', 'watch', 'review', 'priority_review', 'urgent_review')
    and triage_revision >= 0
  );

drop index if exists private.pachanga_moderation_cases_open_target_category_idx;
create unique index if not exists pachanga_moderation_cases_open_intake_idx
  on private.pachanga_moderation_cases(target_profile_id, source_type, category)
  where source_type = 'conduct_report' and state not in ('dismissed', 'corrected', 'closed');
create index if not exists pachanga_moderation_cases_triage_queue_idx
  on private.pachanga_moderation_cases(operational_queue, triage_due_at, triage_server_sequence, id)
  where state not in ('dismissed', 'corrected', 'closed');

create table if not exists private.pachanga_moderation_case_relations (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  relation_type text not null,
  source_case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  target_case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  source_revision bigint not null,
  target_revision bigint not null,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, relation_type),
  check (relation_type in ('merged_into', 'split_from')),
  check (source_case_id <> target_case_id),
  check (jsonb_typeof(payload) = 'object')
);

alter table private.pachanga_conduct_triage_category_policy enable row level security;
alter table private.pachanga_moderation_case_relations enable row level security;
revoke all on table private.pachanga_conduct_triage_category_policy from public, anon, authenticated;
revoke all on table private.pachanga_moderation_case_relations from public, anon, authenticated;
grant all on table private.pachanga_conduct_triage_category_policy to service_role;
grant all on table private.pachanga_moderation_case_relations to service_role;

create or replace function private.pachanga_recount_conduct_case_v1_1(target_case_id uuid)
returns private.pachanga_moderation_cases
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare saved private.pachanga_moderation_cases%rowtype;
begin
  delete from private.pachanga_report_source_clusters clusters
  where clusters.case_id = target_case_id
    and not exists (
      select 1 from private.pachanga_conduct_reports reports
      where reports.source_cluster_id = clusters.id
    );
  update private.pachanga_report_source_clusters clusters set
    report_count = counts.report_count,
    first_reported_at = counts.first_reported_at,
    last_reported_at = counts.last_reported_at
  from (
    select reports.source_cluster_id, count(*)::integer report_count,
      min(reports.created_at) first_reported_at, max(reports.created_at) last_reported_at
    from private.pachanga_conduct_reports reports
    where reports.case_id = target_case_id and reports.state = 'active'
    group by reports.source_cluster_id
  ) counts
  where clusters.id = counts.source_cluster_id;
  update private.pachanga_moderation_cases cases set
    report_count = counts.report_count,
    source_cluster_count = counts.cluster_count,
    independent_source_count = counts.independent_count,
    correlated_source_count = greatest(counts.report_count - counts.independent_count, 0),
    correlated_reporting = counts.report_count > counts.independent_count,
    first_reported_at = coalesce(counts.first_reported_at, cases.first_reported_at),
    last_reported_at = coalesce(counts.last_reported_at, cases.last_reported_at),
    revision = cases.revision + 1,
    server_sequence = nextval('public.pachanga_conduct_sequence'),
    updated_at = clock_timestamp()
  from (
    select count(*)::integer report_count,
      count(distinct reports.source_cluster_id)::integer cluster_count,
      count(distinct reports.reporter_group_id)::integer independent_count,
      min(reports.created_at) first_reported_at,
      max(reports.created_at) last_reported_at
    from private.pachanga_conduct_reports reports
    where reports.case_id = target_case_id and reports.state = 'active'
  ) counts
  where cases.id = target_case_id
  returning cases.* into saved;
  return saved;
end;
$$;

revoke all on function private.pachanga_recount_conduct_case_v1_1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_recompute_conduct_triage_v1_1(target_case_id uuid)
returns private.pachanga_moderation_cases
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_case private.pachanga_moderation_cases%rowtype;
  settings private.pachanga_conduct_settings%rowtype;
  policy private.pachanga_conduct_triage_category_policy%rowtype;
  active_reports integer := 0;
  active_groups integer := 0;
  active_contexts integer := 0;
  prior_signals integer := 0;
  prior_contexts integer := 0;
  recommendation text;
  effective_queue text;
  reasons text[] := '{}';
  due_at timestamptz;
  evaluated_at timestamptz := clock_timestamp();
begin
  select * into selected_case from private.pachanga_moderation_cases cases
  where cases.id = target_case_id for update;
  if not found then raise exception 'Moderation case not found'; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  select * into policy from private.pachanga_conduct_triage_category_policy rows
  where rows.category = selected_case.category;
  if not found then
    select selected_case.category, 90, 'review', false,
      settings.triage_policy_version, evaluated_at into policy;
  end if;

  if selected_case.source_type in ('attendance_reliability', 'attendance_dispute') then
    recommendation := case
      when selected_case.priority in ('high', 'urgent_review') or selected_case.restriction_recommended
        then 'priority_review'
      else 'review'
    end;
    reasons := array['ATTENDANCE_RELIABILITY_SEPARATE'];
  else
    select count(*)::integer,
      count(distinct reports.reporter_group_id)::integer,
      count(distinct (reports.context_kind || ':' || reports.context_id))::integer
    into active_reports, active_groups, active_contexts
    from private.pachanga_conduct_reports reports
    where reports.case_id = selected_case.id
      and reports.state = 'active'
      and reports.created_at >= evaluated_at - make_interval(days => policy.active_window_days);

    select count(*)::integer,
      count(distinct (reports.context_kind || ':' || reports.context_id))::integer
    into prior_signals, prior_contexts
    from private.pachanga_conduct_reports reports
    join private.pachanga_moderation_cases cases on cases.id = reports.case_id
    where cases.target_profile_id = selected_case.target_profile_id
      and cases.category = selected_case.category
      and cases.id <> selected_case.id
      and reports.state = 'active'
      and reports.created_at >= evaluated_at - make_interval(days => policy.active_window_days);

    if selected_case.correlated_reporting then reasons := array_append(reasons, 'CORRELATED_SOURCE_CLUSTER'); end if;
    if selected_case.mutual_retaliation then reasons := array_append(reasons, 'MUTUAL_RETALIATION'); end if;
    if active_groups >= 2 then reasons := array_append(reasons, 'INDEPENDENT_SOURCES_' || active_groups::text); end if;
    if active_contexts >= 2 then reasons := array_append(reasons, 'DISTINCT_CONTEXTS_' || active_contexts::text); end if;
    if prior_signals = 1 then reasons := array_append(reasons, 'RECENT_COMPATIBLE_SIGNALS_1'); end if;
    if prior_signals >= 2 then reasons := array_append(reasons, 'RECENT_COMPATIBLE_SIGNALS_2_PLUS'); end if;

    if selected_case.category = 'threats_or_violence' then
      recommendation := 'urgent_review';
      reasons := array_append(reasons, 'CATEGORY_THREATS_OR_VIOLENCE');
    elsif active_groups >= 3 and active_contexts >= 2 then
      recommendation := 'priority_review';
    elsif active_groups >= 2 and active_contexts >= 2 then
      recommendation := 'review';
    elsif prior_signals >= 2 and prior_contexts >= 2 then
      recommendation := 'priority_review';
    elsif prior_signals >= 1 then
      recommendation := 'watch';
    elsif active_reports = 0 then
      recommendation := 'record_only';
      reasons := array_append(reasons, 'ACTIVE_WINDOW_EXPIRED');
    else
      recommendation := policy.isolated_queue;
      if recommendation = 'record_only' then
        reasons := array_append(reasons, 'ISOLATED_NON_SERIOUS_SIGNAL');
      else
        reasons := array_append(reasons, 'CATEGORY_' || upper(selected_case.category));
      end if;
    end if;
  end if;

  effective_queue := case
    when settings.conduct_triage_enabled and not settings.conduct_triage_shadow_mode
      then recommendation
    when selected_case.priority = 'urgent_review' then 'urgent_review'
    when selected_case.priority = 'high' then 'priority_review'
    else 'review'
  end;
  due_at := case effective_queue
    when 'urgent_review' then evaluated_at + make_interval(hours => settings.triage_urgent_sla_hours)
    when 'priority_review' then evaluated_at + make_interval(hours => settings.triage_priority_sla_hours)
    when 'review' then evaluated_at + make_interval(hours => settings.triage_review_sla_hours)
    else null
  end;

  update private.pachanga_moderation_cases cases set
    triage_recommendation = recommendation,
    operational_queue = effective_queue,
    triage_reason_codes = reasons,
    triage_policy_version = settings.triage_policy_version,
    triage_evaluated_at = evaluated_at,
    triage_due_at = due_at,
    active_window_started_at = evaluated_at - make_interval(days => policy.active_window_days),
    active_window_ends_at = selected_case.last_reported_at + make_interval(days => policy.active_window_days),
    triage_revision = cases.triage_revision + 1,
    triage_server_sequence = nextval('public.pachanga_conduct_sequence')
  where cases.id = selected_case.id
  returning cases.* into selected_case;
  return selected_case;
end;
$$;

revoke all on function private.pachanga_recompute_conduct_triage_v1_1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_recompute_conduct_triage_trigger_v1_1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_recompute_conduct_triage_v1_1(new.id);
  return new;
end;
$$;

revoke all on function private.pachanga_recompute_conduct_triage_trigger_v1_1()
  from public, anon, authenticated;

drop trigger if exists pachanga_recompute_conduct_triage_v1_1
  on private.pachanga_moderation_cases;
create trigger pachanga_recompute_conduct_triage_v1_1
after insert or update of report_count, independent_source_count, correlated_source_count,
  mutual_retaliation, restriction_recommended, priority, last_reported_at
on private.pachanga_moderation_cases
for each row execute function private.pachanga_recompute_conduct_triage_trigger_v1_1();

-- Recompute existing cases only as a shadow recommendation. Historical decisions remain unchanged.
do $$
declare row record;
begin
  for row in select id from private.pachanga_moderation_cases loop
    perform private.pachanga_recompute_conduct_triage_v1_1(row.id);
  end loop;
end;
$$;

create or replace function private.pachanga_conduct_notify_moderators_v1(
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_dedupe_prefix text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  moderator record;
  settings private.pachanga_conduct_settings%rowtype;
  case_queue text;
begin
  select * into settings from private.pachanga_conduct_settings where singleton;
  if target_kind in ('conduct_warning_review', 'conduct_warning_urgent_review')
    and settings.conduct_triage_enabled and not settings.conduct_triage_shadow_mode
    and coalesce(target_payload ->> 'caseReference', '')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select cases.operational_queue into case_queue
    from private.pachanga_moderation_cases cases
    where cases.opaque_reference = (target_payload ->> 'caseReference')::uuid;
    if case_queue in ('record_only', 'watch') then return; end if;
  end if;
  for moderator in
    select users.id from auth.users users
    where coalesce(users.raw_app_meta_data ->> 'pachangas_security_role', '')
      in ('moderator', 'security_admin')
  loop
    perform private.pachanga_notify_v1(
      moderator.id, target_kind, target_title, target_body, target_action_url,
      coalesce(target_payload, '{}'::jsonb), target_dedupe_prefix || ':' || moderator.id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_conduct_notify_moderators_v1(text, text, text, text, jsonb, text)
  from public, anon, authenticated;

create or replace function public.get_pachanga_conduct_capabilities_v1()
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'policyVersion', settings.policy_version,
    'attendanceClosureEnabled', settings.attendance_closure_enabled,
    'conductReportsEnabled', settings.conduct_reports_enabled,
    'socialRestrictionsEnabled', settings.social_restrictions_enabled,
    'conductTriageEnabled', settings.conduct_triage_enabled,
    'conductTriageShadowMode', settings.conduct_triage_shadow_mode,
    'triagePolicyVersion', settings.triage_policy_version,
    'serverAuthoritative', true,
    'affectsSportRating', false
  ) from private.pachanga_conduct_settings settings where settings.singleton;
$$;

revoke all on function public.get_pachanga_conduct_capabilities_v1() from public, anon, authenticated;
grant execute on function public.get_pachanga_conduct_capabilities_v1() to authenticated;

create or replace function public.get_pachanga_moderation_queue_v1_1(
  target_queue text default null,
  target_limit integer default 100
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare settings private.pachanga_conduct_settings%rowtype;
begin
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  if target_queue is not null and target_queue not in (
    'record_only', 'watch', 'review', 'priority_review', 'urgent_review'
  ) then raise exception 'Invalid moderation queue'; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  return jsonb_build_object(
    'triageEnabled', settings.conduct_triage_enabled,
    'shadowMode', settings.conduct_triage_shadow_mode,
    'policyVersion', settings.triage_policy_version,
    'counts', (
      select jsonb_build_object(
        'urgent_review', count(*) filter (where cases.triage_recommendation = 'urgent_review'),
        'priority_review', count(*) filter (where cases.triage_recommendation = 'priority_review'),
        'review', count(*) filter (where cases.triage_recommendation = 'review'),
        'watch', count(*) filter (where cases.triage_recommendation = 'watch'),
        'record_only', count(*) filter (where cases.triage_recommendation = 'record_only')
      ) from private.pachanga_moderation_cases cases
      where cases.state not in ('dismissed', 'corrected', 'closed')
    ),
    'cases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'caseReference', cases.opaque_reference,
        'targetProfileId', cases.target_profile_id,
        'targetName', profiles.display_name,
        'sourceType', cases.source_type,
        'category', cases.category,
        'state', cases.state,
        'priority', cases.priority,
        'triageRecommendation', cases.triage_recommendation,
        'operationalQueue', cases.operational_queue,
        'triageReasonCodes', cases.triage_reason_codes,
        'triagePolicyVersion', cases.triage_policy_version,
        'triageRevision', cases.triage_revision,
        'triageDueAt', cases.triage_due_at,
        'activeWindowEndsAt', cases.active_window_ends_at,
        'reportCount', cases.report_count,
        'sourceClusterCount', cases.source_cluster_count,
        'independentSourceCount', cases.independent_source_count,
        'correlatedSourceCount', cases.correlated_source_count,
        'correlatedReporting', cases.correlated_reporting,
        'mutualRetaliation', cases.mutual_retaliation,
        'restrictionRecommended', cases.restriction_recommended,
        'revision', cases.revision,
        'serverSequence', cases.server_sequence,
        'updatedAt', cases.updated_at
      ) order by
        case cases.triage_recommendation
          when 'urgent_review' then 0 when 'priority_review' then 1 when 'review' then 2
          when 'watch' then 3 else 4 end,
        cases.triage_due_at nulls last, cases.server_sequence, cases.id)
      from (
        select rows.* from private.pachanga_moderation_cases rows
        where rows.state not in ('dismissed', 'corrected', 'closed')
          and (target_queue is null or rows.triage_recommendation = target_queue)
        order by case rows.triage_recommendation
          when 'urgent_review' then 0 when 'priority_review' then 1 when 'review' then 2
          when 'watch' then 3 else 4 end,
          rows.triage_due_at nulls last, rows.server_sequence, rows.id
        limit greatest(1, least(target_limit, 500))
      ) cases
      join public.pachanga_player_profiles profiles on profiles.id = cases.target_profile_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_moderation_queue_v1_1(text, integer)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_moderation_queue_v1_1(text, integer)
  to authenticated;

create or replace function public.get_pachanga_moderation_case_evidence_v1_1(target_case_reference uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare selected_case private.pachanga_moderation_cases%rowtype;
declare base jsonb;
begin
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  select * into selected_case from private.pachanga_moderation_cases cases
  where cases.opaque_reference = target_case_reference;
  if not found then raise exception 'Moderation case not found'; end if;
  base := public.get_pachanga_moderation_case_evidence_v1(target_case_reference);
  return base || jsonb_build_object(
    'triageRecommendation', selected_case.triage_recommendation,
    'operationalQueue', selected_case.operational_queue,
    'triageReasonCodes', selected_case.triage_reason_codes,
    'triagePolicyVersion', selected_case.triage_policy_version,
    'triageRevision', selected_case.triage_revision,
    'triageDueAt', selected_case.triage_due_at,
    'activeWindowEndsAt', selected_case.active_window_ends_at,
    'relations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', relations.relation_type,
        'sourceCaseReference', source_case.opaque_reference,
        'targetCaseReference', target_case.opaque_reference,
        'payload', relations.payload,
        'serverSequence', relations.server_sequence,
        'createdAt', relations.created_at
      ) order by relations.server_sequence, relations.id)
      from private.pachanga_moderation_case_relations relations
      join private.pachanga_moderation_cases source_case on source_case.id = relations.source_case_id
      join private.pachanga_moderation_cases target_case on target_case.id = relations.target_case_id
      where relations.source_case_id = selected_case.id or relations.target_case_id = selected_case.id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_moderation_case_evidence_v1_1(uuid)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_moderation_case_evidence_v1_1(uuid)
  to authenticated;

create or replace function public.merge_pachanga_conduct_cases_v1_1(
  source_case_reference uuid,
  target_case_reference uuid,
  operation_id uuid,
  expected_source_revision bigint,
  expected_target_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor uuid := auth.uid();
  replay jsonb;
  source_case private.pachanga_moderation_cases%rowtype;
  target_case private.pachanga_moderation_cases%rowtype;
  report_row private.pachanga_conduct_reports%rowtype;
  target_cluster private.pachanga_report_source_clusters%rowtype;
  event_sequence bigint;
  response jsonb;
begin
  if actor is null or operation_id is null or source_case_reference = target_case_reference then
    raise exception 'Moderator, distinct cases and operation id required';
  end if;
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.case.merge.v1.1', actor);
  if replay is not null then return replay; end if;
  perform 1 from private.pachanga_moderation_cases cases
  where cases.opaque_reference in (source_case_reference, target_case_reference)
  order by cases.id for update;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.case.merge.v1.1', actor);
  if replay is not null then return replay; end if;
  select * into source_case from private.pachanga_moderation_cases cases where cases.opaque_reference = source_case_reference;
  select * into target_case from private.pachanga_moderation_cases cases where cases.opaque_reference = target_case_reference;
  if source_case.id is null or target_case.id is null then raise exception 'Moderation case not found'; end if;
  if source_case.revision <> expected_source_revision or target_case.revision <> expected_target_revision then
    raise exception 'Server revision is newer. Reload both moderation cases.' using errcode = 'PT409';
  end if;
  if source_case.target_profile_id <> target_case.target_profile_id
    or source_case.category <> target_case.category
    or source_case.source_type not in ('conduct_report', 'conduct_report_split')
    or target_case.source_type not in ('conduct_report', 'conduct_report_split') then
    raise exception 'Only compatible conduct cases for the same target can be merged';
  end if;
  if source_case.category = 'threats_or_violence' then
    raise exception 'Threat or violence incidents must remain distinct for human review';
  end if;
  if abs(extract(epoch from (source_case.last_reported_at - target_case.last_reported_at)))
    > 365 * 86400 then raise exception 'Cases are outside the compatible temporal window'; end if;

  for report_row in select * from private.pachanga_conduct_reports reports
    where reports.case_id = source_case.id order by reports.server_sequence, reports.id
  loop
    select * into target_cluster from private.pachanga_report_source_clusters clusters
    where clusters.case_id = target_case.id
      and clusters.source_group_id = report_row.reporter_group_id
      and clusters.context_kind = report_row.context_kind
      and clusters.context_id = report_row.context_id for update;
    if not found then
      insert into private.pachanga_report_source_clusters(
        case_id, source_group_id, context_kind, context_id
      ) values (
        target_case.id, report_row.reporter_group_id, report_row.context_kind, report_row.context_id
      ) returning * into target_cluster;
    end if;
    update private.pachanga_conduct_reports set
      case_id = target_case.id, source_cluster_id = target_cluster.id
    where id = report_row.id;
  end loop;
  delete from private.pachanga_report_source_clusters where case_id = source_case.id;
  target_case := private.pachanga_recount_conduct_case_v1_1(target_case.id);
  event_sequence := nextval('public.pachanga_conduct_sequence');
  update private.pachanga_moderation_cases set
    state = 'closed', merged_into_case_id = target_case.id,
    decision_summary = 'Merged into a compatible moderation case',
    report_count = 0, source_cluster_count = 0, independent_source_count = 0,
    correlated_source_count = 0, correlated_reporting = false,
    revision = revision + 1, server_sequence = event_sequence,
    resolved_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = source_case.id returning * into source_case;
  insert into private.pachanga_moderation_case_relations(
    operation_id, relation_type, source_case_id, target_case_id, actor_user_id,
    source_revision, target_revision, payload, server_sequence
  ) values (
    operation_id, 'merged_into', source_case.id, target_case.id, actor,
    source_case.revision, target_case.revision,
    jsonb_build_object('automaticSanctionApplied', false, 'affectsSportRating', false), event_sequence
  );
  insert into private.pachanga_moderation_events(
    case_id, operation_id, actor_user_id, event_type, from_state, to_state, case_revision, payload
  ) values (
    target_case.id, operation_id, actor, 'moderation_cases_merged', target_case.state,
    target_case.state, target_case.revision,
    jsonb_build_object('sourceCaseReference', source_case.opaque_reference,
      'automaticSanctionApplied', false, 'affectsSportRating', false)
  );
  target_case := private.pachanga_recompute_conduct_triage_v1_1(target_case.id);
  response := jsonb_build_object(
    'operationId', operation_id,
    'sourceCaseReference', source_case.opaque_reference,
    'targetCaseReference', target_case.opaque_reference,
    'sourceState', source_case.state,
    'confirmedSourceRevision', source_case.revision,
    'confirmedRevision', target_case.revision,
    'triageRevision', target_case.triage_revision,
    'serverSequence', event_sequence,
    'automaticSanctionApplied', false,
    'affectsSportRating', false
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, actor, 'conduct.case.merge.v1.1', expected_target_revision,
    target_case.revision, event_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.merge_pachanga_conduct_cases_v1_1(uuid, uuid, uuid, bigint, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.merge_pachanga_conduct_cases_v1_1(uuid, uuid, uuid, bigint, bigint, jsonb)
  to authenticated;

create or replace function public.split_pachanga_conduct_case_v1_1(
  source_case_reference uuid,
  report_references uuid[],
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor uuid := auth.uid();
  replay jsonb;
  source_case private.pachanga_moderation_cases%rowtype;
  split_case private.pachanga_moderation_cases%rowtype;
  report_row private.pachanga_conduct_reports%rowtype;
  split_cluster private.pachanga_report_source_clusters%rowtype;
  selected_count integer;
  total_count integer;
  event_sequence bigint;
  response jsonb;
begin
  if actor is null or operation_id is null or coalesce(array_length(report_references, 1), 0) = 0 then
    raise exception 'Moderator, report selection and operation id required';
  end if;
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.case.split.v1.1', actor);
  if replay is not null then return replay; end if;
  select * into source_case from private.pachanga_moderation_cases cases
  where cases.opaque_reference = source_case_reference for update;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.case.split.v1.1', actor);
  if replay is not null then return replay; end if;
  if not found or source_case.source_type not in ('conduct_report', 'conduct_report_split') then
    raise exception 'Conduct case not found';
  end if;
  if source_case.revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the moderation case.' using errcode = 'PT409';
  end if;
  if source_case.category = 'threats_or_violence' then
    raise exception 'Threat or violence incidents require explicit case-by-case review';
  end if;
  select count(*)::integer into total_count from private.pachanga_conduct_reports reports
  where reports.case_id = source_case.id and reports.state = 'active';
  select count(*)::integer into selected_count from private.pachanga_conduct_reports reports
  where reports.case_id = source_case.id and reports.state = 'active'
    and reports.opaque_reference = any(report_references);
  if selected_count <> cardinality(report_references) or selected_count >= total_count then
    raise exception 'Select a valid proper subset of active reports';
  end if;

  insert into private.pachanga_moderation_cases(
    target_profile_id, target_user_id, source_type, category, state, priority,
    mutual_retaliation, first_reported_at, last_reported_at
  ) values (
    source_case.target_profile_id, source_case.target_user_id, 'conduct_report_split',
    source_case.category, 'triaged', source_case.priority, source_case.mutual_retaliation,
    source_case.first_reported_at, source_case.last_reported_at
  ) returning * into split_case;

  for report_row in select * from private.pachanga_conduct_reports reports
    where reports.case_id = source_case.id and reports.opaque_reference = any(report_references)
    order by reports.server_sequence, reports.id
  loop
    select * into split_cluster from private.pachanga_report_source_clusters clusters
    where clusters.case_id = split_case.id
      and clusters.source_group_id = report_row.reporter_group_id
      and clusters.context_kind = report_row.context_kind
      and clusters.context_id = report_row.context_id for update;
    if not found then
      insert into private.pachanga_report_source_clusters(
        case_id, source_group_id, context_kind, context_id
      ) values (
        split_case.id, report_row.reporter_group_id, report_row.context_kind, report_row.context_id
      ) returning * into split_cluster;
    end if;
    update private.pachanga_conduct_reports set
      case_id = split_case.id, source_cluster_id = split_cluster.id
    where id = report_row.id;
  end loop;
  delete from private.pachanga_report_source_clusters clusters
  where clusters.case_id = source_case.id
    and not exists (select 1 from private.pachanga_conduct_reports reports where reports.source_cluster_id = clusters.id);
  source_case := private.pachanga_recount_conduct_case_v1_1(source_case.id);
  split_case := private.pachanga_recount_conduct_case_v1_1(split_case.id);
  source_case := private.pachanga_recompute_conduct_triage_v1_1(source_case.id);
  split_case := private.pachanga_recompute_conduct_triage_v1_1(split_case.id);
  event_sequence := nextval('public.pachanga_conduct_sequence');
  insert into private.pachanga_moderation_case_relations(
    operation_id, relation_type, source_case_id, target_case_id, actor_user_id,
    source_revision, target_revision, payload, server_sequence
  ) values (
    operation_id, 'split_from', split_case.id, source_case.id, actor,
    split_case.revision, source_case.revision,
    jsonb_build_object('reportCount', selected_count,
      'automaticSanctionApplied', false, 'affectsSportRating', false), event_sequence
  );
  insert into private.pachanga_moderation_events(
    case_id, operation_id, actor_user_id, event_type, from_state, to_state, case_revision, payload
  ) values (
    source_case.id, operation_id, actor, 'moderation_case_split', source_case.state,
    source_case.state, source_case.revision,
    jsonb_build_object('splitCaseReference', split_case.opaque_reference,
      'reportCount', selected_count, 'automaticSanctionApplied', false, 'affectsSportRating', false)
  );
  response := jsonb_build_object(
    'operationId', operation_id,
    'sourceCaseReference', source_case.opaque_reference,
    'splitCaseReference', split_case.opaque_reference,
    'confirmedRevision', source_case.revision,
    'splitRevision', split_case.revision,
    'serverSequence', event_sequence,
    'automaticSanctionApplied', false,
    'affectsSportRating', false
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, actor, 'conduct.case.split.v1.1', expected_revision,
    source_case.revision, event_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.split_pachanga_conduct_case_v1_1(uuid, uuid[], uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.split_pachanga_conduct_case_v1_1(uuid, uuid[], uuid, bigint, jsonb)
  to authenticated;

comment on table private.pachanga_conduct_triage_category_policy is
  'Explainable triage policy only. It is not a conduct score and never decides guilt or sanctions.';
comment on column private.pachanga_moderation_cases.triage_recommendation is
  'Shadow or active review recommendation; never a finding of guilt.';
comment on column private.pachanga_moderation_cases.operational_queue is
  'Effective queue. V1 remains effective while triage is disabled or in shadow mode.';
comment on table private.pachanga_moderation_case_relations is
  'Immutable audit lineage for moderator-initiated case merge and split operations.';
