-- Wave 8A: private review messages and immutable platform decisions.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table private.pachanga_organizer_access_messages_v1 (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references private.pachanga_organizer_access_applications_v1(id) on delete restrict,
  application_revision bigint not null,
  author_id uuid references auth.users(id) on delete set null,
  author_kind text not null,
  message_kind text not null,
  visibility text not null,
  body text not null,
  content_fingerprint text not null,
  server_sequence bigint not null unique default nextval('private.pachanga_organizer_access_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (application_revision >= 1),
  check (author_kind in ('applicant', 'platform', 'service_authority')),
  check (message_kind in ('applicant_message', 'information_request', 'information_response', 'support_message', 'review_note')),
  check (visibility in ('APPLICANT_SHARED', 'PLATFORM_PRIVATE')),
  check (length(trim(body)) between 1 and 4000),
  check (length(content_fingerprint) = 64),
  check (message_kind <> 'review_note' or visibility = 'PLATFORM_PRIVATE')
);

create table private.pachanga_organizer_access_decisions_v1 (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references private.pachanga_organizer_access_applications_v1(id) on delete restrict,
  application_revision bigint not null,
  decision_type text not null,
  decision_code text not null,
  applicant_message text not null default '',
  private_note text not null default '',
  grant_plan_code text references public.pachanga_organizer_plan_catalog(plan_code) on delete restrict,
  grant_source text,
  grant_valid_from timestamptz,
  grant_valid_until timestamptz,
  grant_limits jsonb not null default '{}'::jsonb,
  grant_capabilities jsonb not null default '[]'::jsonb,
  resulting_access_grant_id uuid references private.pachanga_organizer_access_grants_v1(id) on delete restrict,
  supersedes_decision_id uuid references private.pachanga_organizer_access_decisions_v1(id) on delete restrict,
  decided_by uuid not null references auth.users(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_organizer_access_sequence'),
  decided_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (application_revision >= 1),
  check (decision_type in ('APPROVED', 'APPROVED_INTEREST', 'REJECTED', 'EXPIRED', 'RECONSIDERED')),
  check (decision_code ~ '^[A-Z][A-Z0-9_]{2,79}$'),
  check (length(applicant_message) <= 2000),
  check (length(private_note) <= 4000),
  check (grant_source is null or grant_source in ('PARTNERSHIP', 'PROMOTION', 'PRIVATE_BETA', 'PLATFORM_GRANT')),
  check (grant_valid_until is null or (grant_valid_from is not null and grant_valid_until > grant_valid_from)),
  check (jsonb_typeof(grant_limits) = 'object'),
  check (jsonb_typeof(grant_capabilities) = 'array'),
  check (revision = 1),
  check (
    (decision_type = 'APPROVED' and grant_plan_code is not null and grant_source is not null)
    or (decision_type <> 'APPROVED' and resulting_access_grant_id is null)
  ),
  check (decision_type <> 'APPROVED_INTEREST' or (grant_plan_code is null and grant_source is null))
);

alter table private.pachanga_organizer_access_grants_v1
  add column organizer_access_decision_id uuid
  references private.pachanga_organizer_access_decisions_v1(id) on delete restrict;

create unique index pachanga_organizer_access_grant_decision_idx
  on private.pachanga_organizer_access_grants_v1(organizer_access_decision_id)
  where organizer_access_decision_id is not null;

create unique index pachanga_organizer_access_terminal_decision_idx
  on private.pachanga_organizer_access_decisions_v1(application_id)
  where decision_type in ('APPROVED', 'APPROVED_INTEREST', 'REJECTED', 'EXPIRED');
create index pachanga_organizer_access_message_application_idx
  on private.pachanga_organizer_access_messages_v1(application_id, server_sequence, id);
create index pachanga_organizer_access_decision_application_idx
  on private.pachanga_organizer_access_decisions_v1(application_id, server_sequence desc, id);
create index pachanga_organizer_access_decision_grant_idx
  on private.pachanga_organizer_access_decisions_v1(resulting_access_grant_id)
  where resulting_access_grant_id is not null;

revoke all on table private.pachanga_organizer_access_messages_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_access_decisions_v1 from public, anon, authenticated;
grant all on table private.pachanga_organizer_access_messages_v1 to service_role;
grant all on table private.pachanga_organizer_access_decisions_v1 to service_role;

comment on column private.pachanga_organizer_access_decisions_v1.private_note is
  'Platform-only moderation evidence. Never returned to an applicant read model.';
comment on column private.pachanga_organizer_access_decisions_v1.resulting_access_grant_id is
  'Trace to the existing Organizer Access Grant projected into CompetitionEntitlementGrant.';
