-- Pachangas IQ Wave 5A: R5 and Referee Assignment engines consume CompetitionRuleRevision.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_discipline_policy_for_rule_v1(
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb;
declare policy jsonb;
begin
  select revisions.rule_document into document
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id=target_rule_revision_id;
  if document is null then raise exception 'RULE_REVISION_NOT_FOUND' using errcode='P0002'; end if;
  policy:=document #> '{discipline,policy}';
  if jsonb_typeof(policy)='object' and policy ? 'policyVersion' then return policy; end if;
  return private.pachanga_competition_discipline_default_policy_v1();
end;
$$;

revoke all on function private.pachanga_competition_discipline_policy_for_rule_v1(uuid)
  from public,anon,authenticated;

create or replace function private.pachanga_competition_discipline_catalog_from_rule_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare target_competition_id uuid;
declare target_product_key text;
declare policy jsonb;
begin
  if new.status not in ('published','frozen') then return new; end if;
  select sets.competition_id,competitions.product_key into target_competition_id,target_product_key
  from public.pachanga_competition_rule_sets sets
  join public.pachanga_competitions competitions on competitions.id=sets.competition_id
  where sets.id=new.rule_set_id;
  if target_product_key<>'LEAGUE_PRIVATE_BETA_V1' then return new; end if;
  policy:=private.pachanga_competition_discipline_policy_for_rule_v1(new.id);
  insert into public.pachanga_competition_discipline_rule_catalogs(
    rule_revision_id,competition_id,policy_version,card_type_catalog,cycle_policy,
    sanction_policy,appeal_policy,public_reason_categories,checksum,created_by
  ) values (
    new.id,target_competition_id,policy ->> 'policyVersion',
    coalesce(policy -> 'cardTypeCatalog','[]'::jsonb),
    coalesce(policy -> 'cyclePolicy',jsonb_build_object('scopeType','EDITION','carryPolicy','RESET')),
    coalesce(policy -> 'sanctionPolicy',jsonb_build_object(
      'eligibleFixtureStatuses',jsonb_build_array('official','played'),
      'consumePostponed',false,'consumeCancelled',false,'consumeBye',false
    )),
    coalesce(policy -> 'appealPolicy',jsonb_build_object('deadlineHours',72,'suspensiveEffect',false)),
    coalesce(policy -> 'publicReasonCategories',jsonb_build_array(
      'accumulation','dismissal','temporary_dismissal','administrative'
    )),
    encode(extensions.digest(convert_to(policy::text,'UTF8'),'sha256'),'hex'),new.created_by
  ) on conflict (rule_revision_id) do nothing;
  return new;
end;
$$;

create or replace function private.pachanga_competition_discipline_ensure_catalog_v1(
  target_competition_id uuid,
  target_rule_revision_id uuid,
  target_actor_id uuid
)
returns public.pachanga_competition_discipline_rule_catalogs
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_catalog public.pachanga_competition_discipline_rule_catalogs%rowtype;
declare selected_competition public.pachanga_competitions%rowtype;
declare policy jsonb;
declare computed_checksum text;
begin
  select * into selected_catalog from public.pachanga_competition_discipline_rule_catalogs catalogs
  where catalogs.rule_revision_id=target_rule_revision_id;
  if found then
    if selected_catalog.competition_id<>target_competition_id then
      raise exception 'DISCIPLINE_RULE_COMPETITION_MISMATCH' using errcode='22023';
    end if;
    return selected_catalog;
  end if;
  select * into selected_competition from public.pachanga_competitions competitions
  where competitions.id=target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode='P0002'; end if;
  if selected_competition.product_key<>'LEAGUE_PRIVATE_BETA_V1' then
    raise exception 'DISCIPLINE_RULE_CATALOG_REQUIRED' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.pachanga_competition_rule_revisions revisions
    join public.pachanga_competition_rule_sets sets on sets.id=revisions.rule_set_id
    where revisions.id=target_rule_revision_id and sets.competition_id=target_competition_id
      and revisions.status in ('published','frozen')
  ) then raise exception 'RULE_REVISION_NOT_PUBLISHED' using errcode='22023'; end if;
  policy:=private.pachanga_competition_discipline_policy_for_rule_v1(target_rule_revision_id);
  computed_checksum:=encode(extensions.digest(convert_to(policy::text,'UTF8'),'sha256'),'hex');
  insert into public.pachanga_competition_discipline_rule_catalogs(
    rule_revision_id,competition_id,policy_version,card_type_catalog,cycle_policy,
    sanction_policy,appeal_policy,public_reason_categories,checksum,created_by
  ) values (
    target_rule_revision_id,target_competition_id,policy ->> 'policyVersion',
    coalesce(policy -> 'cardTypeCatalog','[]'::jsonb),policy -> 'cyclePolicy',
    policy -> 'sanctionPolicy',policy -> 'appealPolicy',policy -> 'publicReasonCategories',
    computed_checksum,target_actor_id
  ) returning * into selected_catalog;
  return selected_catalog;
end;
$$;

revoke all on function private.pachanga_competition_discipline_ensure_catalog_v1(uuid,uuid,uuid)
  from public,anon,authenticated;

create or replace function private.pachanga_competition_referee_policy_v1(
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare policy jsonb;
begin
  select revisions.rule_document #> '{operations,refereePolicy}' into policy
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id=target_rule_revision_id;
  if jsonb_typeof(policy)='object' then return policy; end if;
  return jsonb_build_object(
    'usage','NONE','role','MAIN_REFEREE','proposerRoles','[]'::jsonb,
    'acceptanceIsSufficient',false,'organizerConfirmationRequired',true,
    'responseDeadlineHours',72,'reconfirmAfterScheduleChange',true,
    'modalityRequired',true,'serviceAreaRequired',true,
    'priorClubRelationshipRequired',false,'replacementAllowed',false,
    'requiredBeforeReady',false,
    'authority',jsonb_build_object('reportCards',false,'reportIncidents',false,'observeScore',false),
    'fee',jsonb_build_object('mode','NEGOTIABLE','travelIncluded',false,'publicConsent',false,'paymentProcessing',false)
  );
end;
$$;

revoke all on function private.pachanga_competition_referee_policy_v1(uuid)
  from public,anon,authenticated;

create or replace function private.pachanga_competition_referee_assignment_policy_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare policy jsonb;
declare actor_id uuid:=auth.uid();
declare actor_role text;
declare proposer_allowed boolean;
declare organizer_club_id uuid;
begin
  if new.competition_id is null or new.competition_match_context_id is null then return new; end if;
  select * into context_row from public.pachanga_competition_match_contexts contexts
  where contexts.id=new.competition_match_context_id;
  if not found then raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode='P0002'; end if;
  policy:=private.pachanga_competition_referee_policy_v1(context_row.rule_revision_id);
  if upper(coalesce(policy ->> 'usage','NONE'))='NONE' then
    raise exception 'REFEREE_ASSIGNMENTS_DISABLED_BY_RULE_REVISION' using errcode='42501';
  end if;
  if new.assignment_role<>'MAIN_REFEREE' then
    raise exception 'REFEREE_ROLE_NOT_AVAILABLE' using errcode='0A000';
  end if;
  if tg_op='INSERT' then
    actor_role:=private.pachanga_competition_actor_role_v1(new.competition_id,actor_id);
    select exists (
      select 1 from jsonb_array_elements_text(coalesce(policy -> 'proposerRoles','[]'::jsonb)) roles(value)
      where roles.value=actor_role
    ) into proposer_allowed;
    if not proposer_allowed and actor_role not in ('platform_owner','platform_admin','service_authority') then
      raise exception 'REFEREE_PROPOSER_ROLE_NOT_ALLOWED' using errcode='42501';
    end if;
    new.response_deadline:=clock_timestamp()+make_interval(
      hours=>coalesce((policy ->> 'responseDeadlineHours')::integer,72)
    );
    if new.replaces_assignment_id is not null
       and not coalesce((policy ->> 'replacementAllowed')::boolean,false) then
      raise exception 'REFEREE_REPLACEMENT_DISABLED_BY_RULE_REVISION' using errcode='42501';
    end if;
    if coalesce((policy ->> 'priorClubRelationshipRequired')::boolean,false) then
      select competitions.organizer_club_id into organizer_club_id
      from public.pachanga_competitions competitions where competitions.id=new.competition_id;
      if organizer_club_id is null or not exists (
        select 1 from public.pachanga_club_referee_relationships relationships
        where relationships.club_id=organizer_club_id
          and relationships.referee_profile_id=new.referee_profile_id
          and relationships.status='active'
      ) then raise exception 'REFEREE_PRIOR_CLUB_RELATIONSHIP_REQUIRED' using errcode='42501'; end if;
    end if;
  elsif old.status='proposed' and new.status='accepted'
     and coalesce((policy ->> 'acceptanceIsSufficient')::boolean,false)
     and not coalesce((policy ->> 'organizerConfirmationRequired')::boolean,true) then
    new.status:='confirmed';
    new.confirmed_at:=clock_timestamp();
  end if;
  if tg_op='UPDATE' and old.schedule_state is distinct from new.schedule_state
     and not coalesce((policy ->> 'reconfirmAfterScheduleChange')::boolean,true)
     and new.schedule_state='RECONFIRMATION_REQUIRED' then
    new.schedule_state:='CURRENT';
    new.reconfirmed_at:=clock_timestamp();
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_referee_assignment_policy_guard_v1()
  from public,anon,authenticated;

drop trigger if exists zz_pachanga_competition_referee_assignment_policy_v1
  on public.pachanga_referee_assignments;
create trigger zz_pachanga_competition_referee_assignment_policy_v1
before insert or update on public.pachanga_referee_assignments
for each row execute function private.pachanga_competition_referee_assignment_policy_guard_v1();

create or replace function private.pachanga_competition_referee_terms_policy_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare assignment public.pachanga_referee_assignments%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare policy jsonb;
declare fee jsonb;
declare configured_mode text;
begin
  select * into assignment from public.pachanga_referee_assignments assignments
  where assignments.id=new.assignment_id;
  if assignment.competition_match_context_id is null then return new; end if;
  select * into context_row from public.pachanga_competition_match_contexts contexts
  where contexts.id=assignment.competition_match_context_id;
  policy:=private.pachanga_competition_referee_policy_v1(context_row.rule_revision_id);
  fee:=coalesce(policy -> 'fee','{}'::jsonb);
  configured_mode:=upper(coalesce(fee ->> 'mode','NEGOTIABLE'));
  new.fee_mode:=configured_mode;
  new.currency:='EUR';
  new.travel_included:=coalesce((fee ->> 'travelIncluded')::boolean,false);
  if configured_mode='FIXED' then
    new.proposed_fee_cents:=(fee ->> 'fixedCents')::integer;
    new.counter_fee_cents:=null;
  elsif configured_mode in ('FREE','VOLUNTEER') then
    new.proposed_fee_cents:=null;new.counter_fee_cents:=null;new.agreed_fee_cents:=null;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_referee_terms_policy_guard_v1()
  from public,anon,authenticated;

drop trigger if exists zz_pachanga_competition_referee_terms_policy_v1
  on private.pachanga_referee_assignment_terms;
create trigger zz_pachanga_competition_referee_terms_policy_v1
before insert or update on private.pachanga_referee_assignment_terms
for each row execute function private.pachanga_competition_referee_terms_policy_guard_v1();

create or replace function private.pachanga_competition_referee_ready_policy_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare policy jsonb;
begin
  if new.status='ready' and old.status is distinct from new.status then
    policy:=private.pachanga_competition_referee_policy_v1(new.rule_revision_id);
    if upper(coalesce(policy ->> 'usage','NONE'))='REQUIRED'
       and coalesce((policy ->> 'requiredBeforeReady')::boolean,true)
       and not exists (
         select 1 from public.pachanga_referee_assignments assignments
         where assignments.competition_match_context_id=new.id
           and assignments.assignment_role='MAIN_REFEREE'
           and assignments.status='confirmed' and assignments.schedule_state='CURRENT'
       ) then raise exception 'REFEREE_REQUIRED_BEFORE_MATCH_READY' using errcode='42501'; end if;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_referee_ready_policy_guard_v1()
  from public,anon,authenticated;

drop trigger if exists zz_pachanga_competition_referee_ready_policy_v1
  on public.pachanga_competition_match_contexts;
create trigger zz_pachanga_competition_referee_ready_policy_v1
before update of status on public.pachanga_competition_match_contexts
for each row execute function private.pachanga_competition_referee_ready_policy_guard_v1();

create or replace function private.pachanga_competition_referee_officiating_policy_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare assignment_id uuid;
declare assignment public.pachanga_referee_assignments%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare policy jsonb;
declare capability text;
begin
  if tg_table_name='pachanga_referee_result_observations' then
    assignment_id:=new.assignment_id;capability:='observeScore';
  else
    assignment_id:=new.referee_assignment_id;capability:='reportCards';
  end if;
  if assignment_id is null then return new; end if;
  select * into assignment from public.pachanga_referee_assignments assignments
  where assignments.id=assignment_id;
  select * into context_row from public.pachanga_competition_match_contexts contexts
  where contexts.id=assignment.competition_match_context_id;
  policy:=private.pachanga_competition_referee_policy_v1(context_row.rule_revision_id);
  if not coalesce((policy #>> array['authority',capability])::boolean,false) then
    raise exception 'REFEREE_REPORT_NOT_ALLOWED_BY_RULE_REVISION' using errcode='42501';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_referee_officiating_policy_guard_v1()
  from public,anon,authenticated;

drop trigger if exists zz_pachanga_referee_result_policy_v1
  on private.pachanga_referee_result_observations;
create trigger zz_pachanga_referee_result_policy_v1
before insert on private.pachanga_referee_result_observations
for each row execute function private.pachanga_competition_referee_officiating_policy_guard_v1();

drop trigger if exists zz_pachanga_referee_discipline_policy_v1
  on public.pachanga_competition_disciplinary_events;
create trigger zz_pachanga_referee_discipline_policy_v1
before insert on public.pachanga_competition_disciplinary_events
for each row execute function private.pachanga_competition_referee_officiating_policy_guard_v1();

create or replace function private.pachanga_competition_configuration_edition_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.status is distinct from new.status and new.status <> 'draft' then
    perform private.pachanga_competition_configuration_engine_guard_v1(
      new.competition_id,
      array['identity','edition','format','roster'],
      'edition.' || new.status
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_configuration_edition_guard_v1()
  from public,anon,authenticated;

drop trigger if exists aa_pachanga_competition_configuration_edition_guard_v1
  on public.pachanga_competition_editions;
create trigger aa_pachanga_competition_configuration_edition_guard_v1
before update of status on public.pachanga_competition_editions
for each row execute function private.pachanga_competition_configuration_edition_guard_v1();

create or replace function private.pachanga_competition_configuration_schedule_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare target_competition_id uuid;
begin
  if new.status = 'published' and old.status is distinct from new.status then
    select plans.competition_id into target_competition_id
    from public.pachanga_competition_rounds rounds
    join public.pachanga_competition_schedule_revisions revisions
      on revisions.id = rounds.schedule_revision_id
    join public.pachanga_competition_schedule_plans plans
      on plans.id = revisions.schedule_plan_id
    where rounds.id = new.round_id;
    perform private.pachanga_competition_configuration_engine_guard_v1(
      target_competition_id,
      array['format','match'],
      'schedule.publish'
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_configuration_schedule_guard_v1()
  from public,anon,authenticated;

drop trigger if exists aa_pachanga_competition_configuration_schedule_guard_v1
  on public.pachanga_competition_schedule_items;
create trigger aa_pachanga_competition_configuration_schedule_guard_v1
before update of status on public.pachanga_competition_schedule_items
for each row execute function private.pachanga_competition_configuration_schedule_guard_v1();

create or replace function private.pachanga_competition_configuration_result_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.status = 'official' and old.status is distinct from new.status then
    perform private.pachanga_competition_configuration_engine_guard_v1(
      new.competition_id,
      array['scoring'],
      'result.official'
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_configuration_result_guard_v1()
  from public,anon,authenticated;

drop trigger if exists aa_pachanga_competition_configuration_result_guard_v1
  on public.pachanga_competition_match_contexts;
create trigger aa_pachanga_competition_configuration_result_guard_v1
before update of status on public.pachanga_competition_match_contexts
for each row execute function private.pachanga_competition_configuration_result_guard_v1();

create or replace function private.pachanga_competition_configuration_discipline_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_competition_configuration_engine_guard_v1(
    new.competition_id,
    array['discipline'],
    'discipline.event'
  );
  return new;
end;
$$;

revoke all on function private.pachanga_competition_configuration_discipline_guard_v1()
  from public,anon,authenticated;

drop trigger if exists aa_pachanga_competition_configuration_discipline_guard_v1
  on public.pachanga_competition_disciplinary_events;
create trigger aa_pachanga_competition_configuration_discipline_guard_v1
before insert on public.pachanga_competition_disciplinary_events
for each row execute function private.pachanga_competition_configuration_discipline_guard_v1();

create or replace function private.pachanga_competition_configuration_assignment_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare target_competition_id uuid;
begin
  if new.status in ('confirmed','completed')
     and old.status not in ('confirmed','completed') then
    target_competition_id := coalesce(new.competition_id,new.requester_competition_id);
    if target_competition_id is null and new.competition_match_context_id is not null then
      select contexts.competition_id into target_competition_id
      from public.pachanga_competition_match_contexts contexts
      where contexts.id = new.competition_match_context_id;
    end if;
    perform private.pachanga_competition_configuration_engine_guard_v1(
      target_competition_id,
      array['referees'],
      'assignment.confirm'
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_configuration_assignment_guard_v1()
  from public,anon,authenticated;

drop trigger if exists aa_pachanga_competition_configuration_assignment_guard_v1
  on public.pachanga_referee_assignments;
create trigger aa_pachanga_competition_configuration_assignment_guard_v1
before update of status on public.pachanga_referee_assignments
for each row execute function private.pachanga_competition_configuration_assignment_guard_v1();

create table private.pachanga_referee_incident_observations (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.pachanga_referee_assignments(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  category text not null,
  public_summary text not null,
  private_note text not null default '',
  evidence_refs jsonb not null default '[]'::jsonb,
  operation_id uuid not null unique,
  server_sequence bigint not null unique default nextval('private.pachanga_referee_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  check (length(trim(category)) between 3 and 80),
  check (length(public_summary) between 3 and 500),
  check (length(private_note) <= 4000),
  check (jsonb_typeof(evidence_refs)='array' and jsonb_array_length(evidence_refs)<=20)
);

create index pachanga_referee_incident_observations_assignment_idx
  on private.pachanga_referee_incident_observations(assignment_id,server_sequence desc,id desc);
revoke all on table private.pachanga_referee_incident_observations from public,anon,authenticated;
grant all on table private.pachanga_referee_incident_observations to service_role;

create or replace function public.command_pachanga_referee_incident_observation_v1(
  operation_id uuid,
  target_assignment_id uuid,
  expected_revision bigint,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
declare payload jsonb:=coalesce(command_payload,'{}'::jsonb);
declare assignment public.pachanga_referee_assignments%rowtype;
declare profile public.pachanga_referee_profiles%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare policy jsonb;
declare request_hash text;
declare replay jsonb;
declare observation_id uuid;
declare response jsonb;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode='42501'; end if;
  if operation_id is null or target_assignment_id is null or expected_revision<1
     or jsonb_typeof(payload)<>'object'
     or payload-array['category','publicSummary','privateNote','evidenceRefs']<>'{}'::jsonb then
    raise exception 'REFEREE_INCIDENT_OBSERVATION_INVALID' using errcode='22023';
  end if;
  request_hash:=private.pachanga_referee_request_hash_v1(
    'incident.observe',target_assignment_id,expected_revision,payload
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:'||operation_id::text,0));
  replay:=private.pachanga_referee_replay_v1(operation_id,actor_id,request_hash);
  if replay is not null then return replay; end if;
  select * into assignment from public.pachanga_referee_assignments assignments
  where assignments.id=target_assignment_id for update;
  if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode='P0002'; end if;
  if assignment.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
  select * into profile from public.pachanga_referee_profiles profiles
  where profiles.id=assignment.referee_profile_id;
  if profile.user_id<>actor_id or assignment.status<>'confirmed' or assignment.schedule_state<>'CURRENT' then
    raise exception 'REFEREE_CURRENT_CONFIRMED_ASSIGNMENT_REQUIRED' using errcode='42501';
  end if;
  select * into context_row from public.pachanga_competition_match_contexts contexts
  where contexts.id=assignment.competition_match_context_id
    and contexts.status in ('ready','in_progress','played','result_pending','official');
  if not found then raise exception 'REFEREE_MATCH_STATE_NOT_OFFICIABLE' using errcode='42501'; end if;
  policy:=private.pachanga_competition_referee_policy_v1(context_row.rule_revision_id);
  if not coalesce((policy #>> '{authority,reportIncidents}')::boolean,false) then
    raise exception 'REFEREE_REPORT_NOT_ALLOWED_BY_RULE_REVISION' using errcode='42501';
  end if;
  insert into private.pachanga_referee_incident_observations(
    assignment_id,competition_match_context_id,category,public_summary,private_note,
    evidence_refs,operation_id,created_by
  ) values (
    assignment.id,context_row.id,left(trim(payload ->> 'category'),80),
    left(trim(payload ->> 'publicSummary'),500),left(coalesce(payload ->> 'privateNote',''),4000),
    coalesce(payload -> 'evidenceRefs','[]'::jsonb),operation_id,actor_id
  ) returning id into observation_id;
  perform set_config('pachangas.referee_reason','result.observe',true);
  update public.pachanga_referee_assignments assignments set
    revision=assignments.revision+1,server_sequence=nextval('private.pachanga_referee_sequence')
  where assignments.id=assignment.id returning * into assignment;
  response:=private.pachanga_referee_store_command_v1(
    operation_id,actor_id,'authenticated','incident.observe','referee_assignment',
    assignment.id::text,request_hash,assignment.revision,'incident.observe',
    jsonb_build_object('incidentObservationId',observation_id,'officialIncidentChanged',false),
    jsonb_build_object(
      'assignment',private.pachanga_referee_assignment_document_v1(assignment.id,true),
      'incidentObservation',jsonb_build_object(
        'id',observation_id,'category',payload ->> 'category',
        'publicSummary',payload ->> 'publicSummary','authority','PRIVATE_REFEREE_EVIDENCE',
        'officialIncidentChanged',false
      )
    ),assignment.referee_profile_id,assignment.requester_club_id,
    assignment.canonical_match_id,assignment.proposed_by,assignment.requester_team_id,
    'private',client_metadata
  );
  perform set_config('pachangas.referee_reason','',true);
  return response;
end;
$$;

revoke all on function public.command_pachanga_referee_incident_observation_v1(uuid,uuid,bigint,jsonb,jsonb)
  from public,anon;
grant execute on function public.command_pachanga_referee_incident_observation_v1(uuid,uuid,bigint,jsonb,jsonb)
  to authenticated,service_role;
