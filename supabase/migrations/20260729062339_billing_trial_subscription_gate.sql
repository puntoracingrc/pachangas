alter table public.pachanga_groups
add column if not exists billing_status text not null default 'trial',
add column if not exists billing_trial_finalized_matches integer not null default 0,
add column if not exists stripe_customer_id text,
add column if not exists stripe_subscription_id text,
add column if not exists stripe_price_id text,
add column if not exists stripe_current_period_end timestamptz,
add column if not exists billing_interval text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_groups_billing_status_check'
  ) then
    alter table public.pachanga_groups
    add constraint pachanga_groups_billing_status_check
    check (billing_status in ('trial', 'active', 'trialing', 'past_due', 'canceled', 'unpaid', 'incomplete'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_groups_billing_interval_check'
  ) then
    alter table public.pachanga_groups
    add constraint pachanga_groups_billing_interval_check
    check (billing_interval is null or billing_interval in ('month', 'year'));
  end if;
end;
$$;

create index if not exists pachanga_groups_stripe_customer_id_idx
on public.pachanga_groups(stripe_customer_id);

create unique index if not exists pachanga_groups_stripe_subscription_id_idx
on public.pachanga_groups(stripe_subscription_id)
where stripe_subscription_id is not null;

create or replace function public.save_pachanga_payload_if_current(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_finalized_count integer;
  next_finalized_count integer;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can save the full team state';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if expected_revision is not null and current_group.payload_revision <> expected_revision then
    raise exception 'Team changed before saving. Reload and try again.' using errcode = '40001';
  end if;

  select count(*) into current_finalized_count
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) as value
  where coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA';

  select count(*) into next_finalized_count
  from jsonb_array_elements(coalesce(next_payload -> 'matches', '[]'::jsonb)) as value
  where coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA';

  if next_finalized_count > current_finalized_count then
    raise exception 'Finalize matches with finalize_pachanga_match_if_current.';
  end if;

  if current_group.payload = next_payload then
    return jsonb_build_object(
      'payload', current_group.payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );
  end if;

  update public.pachanga_groups
  set payload = next_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );
end;
$$;

create or replace function public.finalize_pachanga_match_if_current(
  target_group_id uuid,
  expected_revision bigint,
  target_match_id text,
  next_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  selected_match jsonb;
  proposed_match jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  was_finalized boolean;
  will_finalized boolean;
  billing_active boolean;
  next_trial_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can finalize matches';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if expected_revision is not null and current_group.payload_revision <> expected_revision then
    raise exception 'Team changed before saving. Reload and try again.' using errcode = '40001';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  select value into proposed_match
  from jsonb_array_elements(coalesce(next_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if proposed_match is null then
    raise exception 'Finalized match missing from payload';
  end if;

  if not coalesce((proposed_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before finalizing it';
  end if;

  was_finalized := coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA';
  will_finalized := coalesce((proposed_match ->> 'closed')::boolean, false) or proposed_match ? 'scoreA';

  if not will_finalized then
    raise exception 'Match must be finalized';
  end if;

  billing_active := current_group.billing_status in ('active', 'trialing')
    and (
      current_group.stripe_current_period_end is null
      or current_group.stripe_current_period_end > now()
    );
  next_trial_count := greatest(0, coalesce(current_group.billing_trial_finalized_matches, 0));

  if not was_finalized and not billing_active then
    if next_trial_count >= 2 then
      raise exception 'Trial limit reached. Subscription required.';
    end if;

    next_trial_count := next_trial_count + 1;
  end if;

  update public.pachanga_groups
  set
    payload = next_payload,
    billing_trial_finalized_matches = next_trial_count
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at,
    'billing_status', current_group.billing_status,
    'billing_trial_finalized_matches', next_trial_count,
    'stripe_customer_id', current_group.stripe_customer_id,
    'stripe_subscription_id', current_group.stripe_subscription_id,
    'stripe_price_id', current_group.stripe_price_id,
    'stripe_current_period_end', current_group.stripe_current_period_end,
    'billing_interval', current_group.billing_interval
  );
end;
$$;

revoke all on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from public;
revoke execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from anon;
grant execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) to authenticated;
revoke all on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb) from public;
revoke execute on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb) from anon;
grant execute on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb) to authenticated;
