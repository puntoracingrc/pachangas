-- Pachangas IQ Wave 5A: private authoring state for canonical CompetitionRuleRevision.
-- No Competition, RuleRevision, grant or public surface is activated by this migration.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists competition_configuration_center_enabled boolean not null default false,
  add column if not exists league_wizard_v2_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_competition_configuration_center_gate_check,
  drop constraint if exists pachanga_league_wizard_v2_gate_check,
  add constraint pachanga_competition_configuration_center_gate_check check (
    not competition_configuration_center_enabled
    or (foundation_enabled and league_private_beta_enabled)
  ),
  add constraint pachanga_league_wizard_v2_gate_check check (
    not league_wizard_v2_enabled
    or (competition_configuration_center_enabled and league_private_beta_creation_enabled)
  );

alter table private.pachanga_league_private_beta_wizards
  add column if not exists wizard_version smallint,
  add column if not exists authoring_mode text,
  add column if not exists preset_key text;

-- Completed V1 records remain historical. Drafts move forward without carrying the
-- former final consent: steps 10-12 must be reviewed explicitly in V2.
update private.pachanga_league_private_beta_wizards wizards
set wizard_version = case when wizards.status = 'draft' then 2 else 1 end,
    authoring_mode = coalesce(wizards.authoring_mode, 'SIMPLE'),
    preset_key = coalesce(wizards.preset_key, 'LEAGUE_F7_STANDARD'),
    completed_steps = case when wizards.status = 'draft'
      then array(
        select completed
        from unnest(wizards.completed_steps) completed
        where completed between 1 and 9
        order by completed
      )
      else wizards.completed_steps
    end,
    step_data = case when wizards.status = 'draft'
      then wizards.step_data - '10'
      else wizards.step_data
    end,
    consented_at = case when wizards.status = 'draft' then null else wizards.consented_at end,
    current_step = case
      when wizards.status = 'draft' and wizards.current_step >= 10 then 10
      else wizards.current_step
    end
where wizards.wizard_version is null
   or wizards.authoring_mode is null
   or wizards.preset_key is null;

alter table private.pachanga_league_private_beta_wizards
  alter column wizard_version set default 2,
  alter column wizard_version set not null,
  alter column authoring_mode set default 'SIMPLE',
  alter column authoring_mode set not null;

alter table private.pachanga_league_private_beta_wizards
  drop constraint if exists pachanga_league_private_beta_wizards_current_step_check,
  drop constraint if exists pachanga_league_private_beta_wizards_completed_steps_check,
  drop constraint if exists pachanga_league_private_beta_wizards_wizard_version_check,
  drop constraint if exists pachanga_league_private_beta_wizards_authoring_mode_check,
  drop constraint if exists pachanga_league_private_beta_wizards_preset_key_check,
  add constraint pachanga_league_private_beta_wizards_current_step_check check (
    current_step between 1 and 12
  ),
  add constraint pachanga_league_private_beta_wizards_completed_steps_check check (
    completed_steps <@ array[1,2,3,4,5,6,7,8,9,10,11,12]::smallint[]
  ),
  add constraint pachanga_league_private_beta_wizards_wizard_version_check check (
    wizard_version in (1, 2)
  ),
  add constraint pachanga_league_private_beta_wizards_authoring_mode_check check (
    authoring_mode in ('SIMPLE', 'ADVANCED')
  ),
  add constraint pachanga_league_private_beta_wizards_preset_key_check check (
    preset_key is null or preset_key in (
      'LEAGUE_F5_QUICK', 'LEAGUE_F7_STANDARD', 'LEAGUE_F11', 'LEAGUE_FUTSAL'
    )
  );

create table private.pachanga_competition_configuration_drafts (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid references public.pachanga_competition_editions(id) on delete restrict,
  rule_set_id uuid not null references public.pachanga_competition_rule_sets(id) on delete restrict,
  source_rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  materialized_rule_revision_id uuid unique references public.pachanga_competition_rule_revisions(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'draft',
  authoring_mode text not null default 'SIMPLE',
  preset_key text,
  current_step smallint not null default 1,
  completed_steps smallint[] not null default '{}'::smallint[],
  step_data jsonb not null default '{}'::jsonb,
  changed_sections text[] not null default '{}'::text[],
  validation_snapshot jsonb not null default '{}'::jsonb,
  impact_snapshot jsonb not null default '{}'::jsonb,
  effective_from timestamptz,
  effective_scope text not null default 'future_only',
  confirmed_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('draft', 'validated', 'published', 'cancelled')),
  check (authoring_mode in ('SIMPLE', 'ADVANCED')),
  check (preset_key is null or preset_key in (
    'LEAGUE_F5_QUICK', 'LEAGUE_F7_STANDARD', 'LEAGUE_F11', 'LEAGUE_FUTSAL'
  )),
  check (current_step between 1 and 12),
  check (completed_steps <@ array[1,2,3,4,5,6,7,8,9,10,11,12]::smallint[]),
  check (jsonb_typeof(step_data) = 'object'),
  check (jsonb_typeof(validation_snapshot) = 'object'),
  check (jsonb_typeof(impact_snapshot) = 'object'),
  check (effective_scope in ('future_only', 'future_stage')),
  check (revision >= 1),
  check (
    (status = 'published' and materialized_rule_revision_id is not null and confirmed_at is not null)
    or (status <> 'published' and materialized_rule_revision_id is null)
  )
);

create unique index pachanga_competition_configuration_active_draft_idx
  on private.pachanga_competition_configuration_drafts(competition_id)
  where status in ('draft', 'validated');
create index pachanga_competition_configuration_drafts_edition_idx
  on private.pachanga_competition_configuration_drafts(edition_id)
  where edition_id is not null;
create index pachanga_competition_configuration_drafts_rule_set_idx
  on private.pachanga_competition_configuration_drafts(rule_set_id);
create index pachanga_competition_configuration_drafts_source_idx
  on private.pachanga_competition_configuration_drafts(source_rule_revision_id);
create index pachanga_competition_configuration_drafts_creator_idx
  on private.pachanga_competition_configuration_drafts(created_by, status, server_sequence desc, id desc);

create table private.pachanga_competition_configuration_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  aggregate_id uuid not null,
  request_hash text not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null unique,
  client_metadata jsonb not null default '{}'::jsonb,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  check (length(request_hash) = 64),
  check (confirmed_revision >= 0),
  check (jsonb_typeof(client_metadata) = 'object'),
  check (jsonb_typeof(response) = 'object')
);

create index pachanga_competition_configuration_receipts_actor_idx
  on private.pachanga_competition_configuration_receipts(actor_id, server_sequence desc, id desc)
  where actor_id is not null;

create table private.pachanga_competition_configuration_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  draft_id uuid references private.pachanga_competition_configuration_drafts(id) on delete restrict,
  rule_revision_id uuid references public.pachanga_competition_rule_revisions(id) on delete restrict,
  action text not null,
  aggregate_revision bigint not null,
  server_sequence bigint not null unique,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb,
  confirmed_at timestamptz not null default clock_timestamp(),
  check (aggregate_revision >= 0),
  check (jsonb_typeof(event_payload) = 'object')
);

create index pachanga_competition_configuration_events_actor_idx
  on private.pachanga_competition_configuration_events(actor_id, server_sequence desc, id desc)
  where actor_id is not null;
create index pachanga_competition_configuration_events_competition_idx
  on private.pachanga_competition_configuration_events(competition_id, server_sequence desc, id desc);
create index pachanga_competition_configuration_events_draft_idx
  on private.pachanga_competition_configuration_events(draft_id, server_sequence desc, id desc)
  where draft_id is not null;
create index pachanga_competition_configuration_events_revision_idx
  on private.pachanga_competition_configuration_events(rule_revision_id, server_sequence desc, id desc)
  where rule_revision_id is not null;

create table public.pachanga_competition_configuration_invalidations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  competition_id uuid not null references public.pachanga_competitions(id) on delete cascade,
  draft_id uuid references private.pachanga_competition_configuration_drafts(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  revision bigint not null,
  server_sequence bigint not null,
  changed_at timestamptz not null default clock_timestamp(),
  check (entity_type in ('competition_configuration', 'competition_rule_revision')),
  check (revision >= 0)
);

create unique index pachanga_competition_configuration_invalidation_dedupe_idx
  on public.pachanga_competition_configuration_invalidations(
    user_id, entity_type, entity_id, revision
  );
create index pachanga_competition_configuration_invalidation_user_idx
  on public.pachanga_competition_configuration_invalidations(user_id, server_sequence desc, id desc);
create index pachanga_competition_configuration_invalidation_competition_idx
  on public.pachanga_competition_configuration_invalidations(competition_id, server_sequence desc, id desc);
create index pachanga_competition_configuration_invalidation_draft_idx
  on public.pachanga_competition_configuration_invalidations(draft_id, server_sequence desc, id desc)
  where draft_id is not null;

alter table public.pachanga_competition_configuration_invalidations enable row level security;
drop policy if exists pachanga_competition_configuration_invalidations_read_self
  on public.pachanga_competition_configuration_invalidations;
create policy pachanga_competition_configuration_invalidations_read_self
  on public.pachanga_competition_configuration_invalidations
  for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on table
  private.pachanga_competition_configuration_drafts,
  private.pachanga_competition_configuration_receipts,
  private.pachanga_competition_configuration_events,
  public.pachanga_competition_configuration_invalidations
from public, anon, authenticated;

grant select on table public.pachanga_competition_configuration_invalidations to authenticated;
grant all on table
  private.pachanga_competition_configuration_drafts,
  private.pachanga_competition_configuration_receipts,
  private.pachanga_competition_configuration_events,
  public.pachanga_competition_configuration_invalidations
to service_role;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_competition_configuration_invalidations'
  ) then
    alter publication supabase_realtime
      add table public.pachanga_competition_configuration_invalidations;
  end if;
end;
$$;

comment on table private.pachanga_competition_configuration_drafts is
  'Disposable private authoring state. It is never sporting authority and can only materialize an immutable CompetitionRuleRevision.';
comment on table private.pachanga_competition_configuration_events is
  'Append-only Wave 5A audit evidence ordered by server_sequence.';
comment on table public.pachanga_competition_configuration_invalidations is
  'Scoped Realtime invalidations. Clients must refetch the canonical configuration read model.';
