-- Keep the platform overview aligned with the canonical Conduct V1 schema.

create or replace function public.get_pachanga_platform_overview_v1(selected_period text default 'today')
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  since_at timestamptz;
  period_key text := lower(coalesce(selected_period, 'today'));
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('overview.read');
  if period_key = 'today' then since_at := date_trunc('day', clock_timestamp());
  elsif period_key = '7d' then since_at := clock_timestamp() - interval '7 days';
  elsif period_key = '30d' then since_at := clock_timestamp() - interval '30 days';
  elsif period_key = 'season' then since_at := null;
  else raise exception 'Invalid period'; end if;

  select jsonb_build_object(
    'period', period_key,
    'periodStart', since_at,
    'periodNote', case when period_key = 'season'
      then 'No existe una temporada global canonica; se muestra todo el historico disponible.' else null end,
    'users', jsonb_build_object(
      'total', (select count(*) from auth.users),
      'new', (select count(*) from auth.users users where since_at is null or users.created_at >= since_at),
      'banned', (select count(*) from auth.users users where users.banned_until > clock_timestamp())
    ),
    'teams', jsonb_build_object(
      'total', (select count(*) from public.pachanga_groups),
      'active', (select count(*) from public.pachanga_groups groups
        where exists (
          select 1 from public.pachanga_group_members members where members.group_id = groups.id
        )),
      'new', (select count(*) from public.pachanga_groups groups
        where since_at is null or groups.created_at >= since_at)
    ),
    'players', jsonb_build_object(
      'registered', (select count(*) from public.pachanga_player_profiles profiles where profiles.user_id is not null),
      'totalProfiles', (select count(*) from public.pachanga_player_profiles)
    ),
    'matches', jsonb_build_object(
      'total', (select count(*) from public.pachanga_match_read_model),
      'changedInPeriod', (select count(*) from public.pachanga_match_read_model matches
        where since_at is null or matches.updated_at >= since_at),
      'finalized', (select count(*) from public.pachanga_match_read_model matches where matches.finalized),
      'pending', (select count(*) from public.pachanga_match_read_model matches where not matches.finalized)
    ),
    'challenges', jsonb_build_object(
      'total', (select count(*) from public.pachanga_team_challenges),
      'createdInPeriod', (select count(*) from public.pachanga_team_challenges challenges
        where since_at is null or challenges.created_at >= since_at),
      'accepted', (select count(*) from public.pachanga_team_challenges challenges where challenges.status = 'accepted'),
      'pending', (select count(*) from public.pachanga_team_challenges challenges
        where challenges.status in ('proposed', 'changes_proposed'))
    ),
    'market', jsonb_build_object(
      'teams', (select count(*) from public.pachanga_challengeable_team_profiles profiles where profiles.enabled),
      'players', (select count(*) from public.pachanga_player_profiles profiles where profiles.market_enabled)
    ),
    'moderation', jsonb_build_object(
      'pending', (select count(*) from private.pachanga_moderation_cases cases
        where cases.state not in ('dismissed', 'corrected', 'closed')),
      'urgent', (select count(*) from private.pachanga_moderation_cases cases
        where cases.state not in ('dismissed', 'corrected', 'closed')
          and cases.triage_recommendation = 'urgent_review'),
      'restrictedUsers', (select count(distinct restrictions.target_user_id)
        from private.pachanga_social_restrictions restrictions
        where restrictions.state = 'active'
          and (restrictions.effective_until is null or restrictions.effective_until > clock_timestamp()))
    ),
    'billing', jsonb_build_object(
      'trial', (select count(*) from public.pachanga_groups groups where groups.billing_status = 'trial'),
      'active', (select count(*) from public.pachanga_groups groups where groups.billing_status in ('active', 'trialing')),
      'pastDue', (select count(*) from public.pachanga_groups groups where groups.billing_status in ('past_due', 'unpaid', 'incomplete')),
      'canceled', (select count(*) from public.pachanga_groups groups where groups.billing_status = 'canceled'),
      'failedWebhooks', (select count(*) from public.pachanga_stripe_webhook_events events
        where events.processing_status = 'failed')
    ),
    'rewards', jsonb_build_object(
      'achievementGrants', (select count(*) from public.pachanga_achievement_grants grants
        where since_at is null or grants.awarded_at >= since_at),
      'rewardGrants', (select count(*) from public.pachanga_reward_grants grants
        where since_at is null or grants.granted_at >= since_at),
      'pendingBoxes', (select count(*) from public.pachanga_reward_recipients recipients
        where recipients.status = 'pending'),
      'openedBoxes', (select count(*) from public.pachanga_reward_open_receipts receipts
        where since_at is null or receipts.created_at >= since_at)
    ),
    'notifications', jsonb_build_object(
      'created', (select count(*) from public.pachanga_user_notifications notifications
        where since_at is null or notifications.created_at >= since_at),
      'unread', (select count(*) from public.pachanga_user_notifications notifications
        where notifications.read_at is null and notifications.visible_in_app),
      'failedDeliveries', (select count(*) from private.pachanga_notification_delivery_outbox outbox
        where outbox.state = 'failed')
    ),
    'alerts', jsonb_strip_nulls(jsonb_build_object(
      'moderationUrgent', (select count(*) from private.pachanga_moderation_cases cases
        where cases.state not in ('dismissed', 'corrected', 'closed')
          and cases.triage_recommendation = 'urgent_review'),
      'billingFailures', (select count(*) from public.pachanga_groups groups
        where groups.billing_status in ('past_due', 'unpaid', 'incomplete')),
      'webhookFailures', (select count(*) from public.pachanga_stripe_webhook_events events
        where events.processing_status = 'failed'),
      'newClientErrors', (select count(*) from private.pachanga_client_error_telemetry errors
        where errors.last_seen_at >= clock_timestamp() - interval '24 hours')
    ))
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_pachanga_platform_overview_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_overview_v1(text) to authenticated;
