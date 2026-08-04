\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email) values
  ('81000000-0000-0000-0000-000000000001', 'guest-owner@example.test'),
  ('81000000-0000-0000-0000-000000000002', 'guest-admin@example.test'),
  ('81000000-0000-0000-0000-000000000003', 'invited-player@example.test'),
  ('81000000-0000-0000-0000-000000000004', 'public-player@example.test'),
  ('81000000-0000-0000-0000-000000000005', 'outsider@example.test'),
  ('81000000-0000-0000-0000-000000000006', 'second-outsider@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values (
  '82000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  'Guest access test',
  'GUESTTEST',
  jsonb_build_object(
    'activeMatchId', 'guest-match-1',
    'players', jsonb_build_array(jsonb_build_object(
      'id', 'owner-player',
      'name', 'Owner',
      'phone', '+34999999999',
      'birthDate', '1990-01-01',
      'position', 'Mediocentro / pivote',
      'rating', 7,
      'ownerUserId', '81000000-0000-0000-0000-000000000001',
      'ratingVotes', jsonb_build_array(jsonb_build_object('secret', true))
    )),
    'matches', jsonb_build_array(jsonb_build_object(
      'id', 'guest-match-1',
      'title', 'Partido seguro',
      'date', '2030-08-03T21:00:00.000Z',
      'place', 'Campo sintético',
      'kind', 'futbol7',
      'configured', true,
      'lineupClosed', false,
      'targetPlayers', 4,
      'reserveLimit', 0,
      'reservesAttend', false,
      'fieldCost', 56,
      'payerPlayerId', 'owner-player',
      'players', jsonb_build_array(jsonb_build_object(
        'playerId', 'owner-player', 'status', 'voy', 'paid', true,
        'joinedAt', '2030-08-01T10:00:00.000Z'
      )),
      'teamA', jsonb_build_array('owner-player'),
      'teamB', '[]'::jsonb,
      'lineupSlots', jsonb_build_object(
        'teamA', jsonb_build_array('owner-player', null),
        'teamB', jsonb_build_array(null, null)
      ),
      'publicOpen', true,
      'publicOpenSlots', 3
    )),
    'siteSettings', jsonb_build_object('privatePhone', '+34111111111'),
    'venues', '[]'::jsonb
  )
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'owner', 'Owner'),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000002', 'admin', 'Admin');

insert into public.pachanga_market_profiles(
  id, user_id, source_player_id, display_name, group_name, birth_date, position,
  media, zones, modalities, open_to_guest, active
) values
  (
    '83000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000003',
    'market-invited', 'Invited Player', 'External team', '1995-02-03',
    'Delantero centro', 6.5, array['Barcelona'], array['futbol7'], true, true
  ),
  (
    '83000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000004',
    'market-public', 'Public Player', 'Another team', '1996-03-04',
    'Defensa central', 6.2, array['Barcelona'], array['futbol7'], true, true
  );

insert into public.pachanga_open_matches(
  id, source_group_id, source_match_id, source_payload_revision, group_name, title,
  date, date_text, day, modality, zone, place_id, lat, lng, field_name, field_cost,
  price_per_player, target_players, confirmed_count, open_slots, min_media, max_media,
  positions, requires_approval, guests_pay, group_level, match_url, active, created_by
) values (
  '84000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  'guest-match-1',
  (select payload_revision from public.pachanga_groups where id = '82000000-0000-0000-0000-000000000001'),
  'Guest access test', 'Partido seguro', '2030-08-03T21:00:00Z', '03/08/2030', 'sábado',
  'futbol7', 'Barcelona', 'sensitive-place-id', 41.3874, 2.1686, 'Campo sintético',
  56, 14, 4, 1, 3, 0, 10, '{}', true, true, 6.4,
  '/?privateMatch=guest-match-1', true, '81000000-0000-0000-0000-000000000001'
);

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_match_invitations', 'SELECT'),
  'Authenticated clients must not read invitation identities directly'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_guest_withdrawal_reviews', 'SELECT'),
  'Authenticated clients must not read conduct-review identities directly'
);
select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.pachanga_match_guest_access', 'SELECT'),
  'Guests need their own Realtime access row'
);
select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.pachanga_match_guest_snapshots', 'SELECT'),
  'Guests need the canonical safe snapshot'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_open_matches', 'SELECT'),
  'The final closure must block direct market-table reads'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.create_pachanga_match_invitation_v1(
  '82000000-0000-0000-0000-000000000001',
  'guest-match-1',
  '83000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000001',
  0,
  '{"sessionId":"admin-device-a","surface":"db-test"}'::jsonb
) as invitation_created \gset
select public.create_pachanga_match_invitation_v1(
  '82000000-0000-0000-0000-000000000001',
  'guest-match-1',
  '83000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000001',
  0,
  '{"sessionId":"admin-device-a","surface":"db-test"}'::jsonb
) as invitation_replayed \gset
reset role;

select pg_temp.assert_true(
  :'invitation_created'::jsonb = :'invitation_replayed'::jsonb,
  'Invitation retries must replay the exact canonical response'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_match_invitations) = 1,
  'An idempotent invitation must create one row'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000005', true);
do $$
begin
  perform public.create_pachanga_match_invitation_v1(
    '82000000-0000-0000-0000-000000000001', 'guest-match-1',
    '83000000-0000-0000-0000-000000000002',
    '85000000-0000-0000-0000-000000000002', 0, '{}'::jsonb
  );
  raise exception 'An outsider unexpectedly invited a player';
exception when others then
  if sqlerrm = 'An outsider unexpectedly invited a player' then raise; end if;
  if sqlerrm <> 'Solo los admins pueden invitar jugadores' then raise; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.get_pachanga_notification_center_v1() as invitee_notifications \gset
select set_config(
  'match_guest_test.invitation_id',
  (:'invitee_notifications'::jsonb -> 0 -> 'context' ->> 'invitationId'),
  true
);
select public.respond_pachanga_match_invitation_v1(
  current_setting('match_guest_test.invitation_id')::uuid,
  'accepted',
  '85000000-0000-0000-0000-000000000003',
  1,
  0,
  '{"sessionId":"guest-device-a","surface":"db-test"}'::jsonb
) as invitation_accepted \gset
reset role;

select set_config(
  'match_guest_test.access_id',
  (:'invitation_accepted'::jsonb ->> 'accessId'),
  false
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_group_members
    where group_id = '82000000-0000-0000-0000-000000000001'
      and user_id = '81000000-0000-0000-0000-000000000003'
  ),
  'Accepting a match invitation must never create group membership'
);
select pg_temp.assert_true(
  (select status from public.pachanga_match_guest_access
   where id = current_setting('match_guest_test.access_id')::uuid) = 'accepted',
  'The invited player must receive exact-match access'
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.pachanga_groups groups,
      jsonb_array_elements(groups.payload -> 'matches') matches,
      jsonb_array_elements(matches.value -> 'players') participants
    where groups.id = '82000000-0000-0000-0000-000000000001'
      and matches.value ->> 'id' = 'guest-match-1'
      and participants.value ->> 'playerId' = (
        select player_id from public.pachanga_match_guest_access
        where id = current_setting('match_guest_test.access_id')::uuid
      )
      and participants.value ->> 'status' = 'voy'
  ),
  'Acceptance must place the guest in the canonical match payload'
);

select pg_temp.assert_true(
  not jsonb_path_exists(snapshot, '$.**.phone')
  and not jsonb_path_exists(snapshot, '$.**.birthDate')
  and not jsonb_path_exists(snapshot, '$.**.ownerUserId')
  and not jsonb_path_exists(snapshot, '$.**.ratingVotes')
  and not jsonb_path_exists(snapshot, '$.**.teamCode')
  and not jsonb_path_exists(snapshot, '$.**.paid')
  and not jsonb_path_exists(snapshot, '$.**.payerPlayerId'),
  'The guest snapshot must exclude phones, identity links, payment state and private rating evidence'
)
from public.pachanga_match_guest_snapshots
where group_id = '82000000-0000-0000-0000-000000000001'
  and match_id = 'guest-match-1';

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.get_pachanga_guest_match_snapshot_v1(
  current_setting('match_guest_test.access_id')::uuid
) as guest_snapshot \gset
select pg_temp.assert_true(
  (select count(*) from public.pachanga_match_guest_snapshots
   where group_id = '82000000-0000-0000-0000-000000000001'
     and match_id = 'guest-match-1') = 1,
  'The accepted guest must read the safe snapshot through RLS'
);
select set_config(
  'match_guest_test.snapshot_revision',
  (:'guest_snapshot'::jsonb ->> 'snapshotRevision'),
  true
);
select public.leave_pachanga_guest_match_v1(
  current_setting('match_guest_test.access_id')::uuid,
  '85000000-0000-0000-0000-000000000004',
  current_setting('match_guest_test.snapshot_revision')::bigint,
  '{"sessionId":"guest-device-a","surface":"db-test"}'::jsonb
) as guest_left \gset
select public.leave_pachanga_guest_match_v1(
  current_setting('match_guest_test.access_id')::uuid,
  '85000000-0000-0000-0000-000000000004',
  current_setting('match_guest_test.snapshot_revision')::bigint,
  '{"sessionId":"guest-device-a","surface":"db-test"}'::jsonb
) as guest_left_replayed \gset
select public.get_pachanga_guest_match_snapshot_v1(
  current_setting('match_guest_test.access_id')::uuid
) as revoked_snapshot \gset
reset role;

select pg_temp.assert_true(
  :'guest_left'::jsonb = :'guest_left_replayed'::jsonb,
  'Leaving twice with one operation id must replay exactly once'
);
select pg_temp.assert_true(
  :'revoked_snapshot'::jsonb -> 'access' ->> 'status' = 'revoked'
  and not (:'revoked_snapshot'::jsonb ? 'snapshot'),
  'A withdrawn guest must immediately lose the match snapshot'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_guest_withdrawal_reviews
   where access_id = current_setting('match_guest_test.access_id')::uuid
     and status = 'pending') = 1,
  'Leaving after acceptance must create one pending conduct review'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_user_notifications
   where recipient_user_id in (
       '81000000-0000-0000-0000-000000000001',
       '81000000-0000-0000-0000-000000000002'
     )
     and kind = 'match_guest_withdrawal_review'
     and title = 'Invited Player ha abandonado') = 2,
  'Each match admin must know which accepted guest left before reviewing conduct'
);
select set_config(
  'match_guest_test.review_id',
  (:'guest_left'::jsonb ->> 'withdrawalReviewId'),
  false
);
select set_config(
  'match_guest_test.group_revision',
  (:'guest_left'::jsonb ->> 'confirmedRevision'),
  false
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
do $$
begin
  perform public.review_pachanga_guest_withdrawal_v1(
    current_setting('match_guest_test.review_id')::uuid, 'confirmed',
    '85000000-0000-0000-0000-000000000005', 1,
    current_setting('match_guest_test.group_revision')::bigint, '{}'::jsonb
  );
  raise exception 'The guest unexpectedly reviewed their own withdrawal';
exception when others then
  if sqlerrm = 'The guest unexpectedly reviewed their own withdrawal' then raise; end if;
  if sqlerrm <> 'Solo los admins pueden revisar abandonos' then raise; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select public.review_pachanga_guest_withdrawal_v1(
  current_setting('match_guest_test.review_id')::uuid,
  'confirmed',
  '85000000-0000-0000-0000-000000000006',
  1,
  current_setting('match_guest_test.group_revision')::bigint,
  '{"sessionId":"admin-device-b","surface":"db-test"}'::jsonb
) as review_confirmed \gset
select public.review_pachanga_guest_withdrawal_v1(
  current_setting('match_guest_test.review_id')::uuid,
  'confirmed',
  '85000000-0000-0000-0000-000000000006',
  1,
  current_setting('match_guest_test.group_revision')::bigint,
  '{"sessionId":"admin-device-b","surface":"db-test"}'::jsonb
) as review_replayed \gset
reset role;

select pg_temp.assert_true(
  :'review_confirmed'::jsonb = :'review_replayed'::jsonb,
  'A conduct-review retry must replay the exact response'
);
select pg_temp.assert_true(
  (select status from public.pachanga_guest_withdrawal_reviews
   where id = current_setting('match_guest_test.review_id')::uuid) = 'confirmed',
  'An admin must be able to confirm only the withdrawal evidence'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_group_events
    where group_id = '82000000-0000-0000-0000-000000000001'
      and match_id = 'guest-match-1'
      and event_type = 'match_guest_withdrawal_confirmed'
      and payload ->> 'affectsSportRating' = 'false'
  ),
  'Confirmed abandonment evidence must explicitly exclude the sports rating'
);

select id, revision
from public.pachanga_user_notifications
where recipient_user_id = '81000000-0000-0000-0000-000000000003'
order by server_sequence desc, id desc
limit 1 \gset latest_notice_

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.mark_pachanga_notification_read_v1(
  :'latest_notice_id'::uuid,
  '85000000-0000-0000-0000-000000000007',
  :'latest_notice_revision'::bigint
) as notification_read \gset
select public.mark_pachanga_notification_read_v1(
  :'latest_notice_id'::uuid,
  '85000000-0000-0000-0000-000000000007',
  :'latest_notice_revision'::bigint
) as notification_read_replayed \gset
reset role;

select pg_temp.assert_true(
  :'notification_read'::jsonb = :'notification_read_replayed'::jsonb,
  'Reading one notification twice must return the same receipt'
);
select pg_temp.assert_true(
  (select revision from public.pachanga_user_notifications where id = :'latest_notice_id'::uuid)
    = :'latest_notice_revision'::bigint + 1,
  'A repeated read receipt must not bump the notification twice'
);

select source_payload_revision
from public.pachanga_open_matches
where id = '84000000-0000-0000-0000-000000000001'
\gset public_match_
select payload_revision
from public.pachanga_groups
where id = '82000000-0000-0000-0000-000000000001'
\gset public_group_

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select public.request_pachanga_open_match_authoritative_v2(
  '84000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000008',
  :'public_match_source_payload_revision'::bigint,
  '{"sessionId":"public-device-a","surface":"db-test"}'::jsonb
) as public_requested \gset
reset role;
select set_config(
  'match_guest_test.public_request_id',
  (:'public_requested'::jsonb -> 'request' ->> 'id'),
  false
);
select pg_temp.assert_true(
  (select status from public.pachanga_open_match_requests
   where id = current_setting('match_guest_test.public_request_id')::uuid) = 'pending',
  'A public request must begin pending'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.get_pachanga_notification_center_v1() as admin_request_notifications \gset
reset role;
select pg_temp.assert_true(
  exists (
    select 1
    from jsonb_array_elements(:'admin_request_notifications'::jsonb) notifications
    where notifications.value -> 'context' ->> 'requestId' = current_setting('match_guest_test.public_request_id')
      and notifications.value -> 'context' ->> 'requestStatus' = 'pending'
      and notifications.value -> 'context' ->> 'requestGroupId' = '82000000-0000-0000-0000-000000000001'
      and (notifications.value -> 'context' ->> 'requestGroupRevision')::bigint = :'public_group_payload_revision'::bigint
  ),
  'Admins must receive an actionable canonical public-request notification'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.review_pachanga_open_match_request_authoritative_v2(
  '82000000-0000-0000-0000-000000000001',
  current_setting('match_guest_test.public_request_id')::uuid,
  'rejected',
  '85000000-0000-0000-0000-000000000009',
  :'public_group_payload_revision'::bigint,
  '{"sessionId":"admin-device-a","surface":"db-test"}'::jsonb
) as public_rejected \gset
reset role;
select pg_temp.assert_true(
  (select status from public.pachanga_open_match_requests
   where id = current_setting('match_guest_test.public_request_id')::uuid) = 'rejected',
  'The admin rejection must reach the canonical request'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select public.get_pachanga_notification_center_v1() as rejected_admin_notifications \gset
reset role;
select pg_temp.assert_true(
  exists (
    select 1
    from jsonb_array_elements(:'rejected_admin_notifications'::jsonb) notifications
    where notifications.value -> 'context' ->> 'requestId' = current_setting('match_guest_test.public_request_id')
      and notifications.value -> 'context' ->> 'requestStatus' = 'rejected'
  ),
  'All admins must converge from pending to the canonical rejected request'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select public.request_pachanga_open_match_authoritative_v2(
  '84000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000010',
  :'public_match_source_payload_revision'::bigint,
  '{"sessionId":"public-device-a","surface":"db-test"}'::jsonb
) as public_retried \gset
reset role;
select pg_temp.assert_true(
  (select status from public.pachanga_open_match_requests
   where id = current_setting('match_guest_test.public_request_id')::uuid) = 'pending',
  'A rejected public request must be requestable again'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select public.review_pachanga_open_match_request_authoritative_v2(
  '82000000-0000-0000-0000-000000000001',
  current_setting('match_guest_test.public_request_id')::uuid,
  'accepted',
  '85000000-0000-0000-0000-000000000011',
  :'public_group_payload_revision'::bigint,
  '{"sessionId":"admin-device-b","surface":"db-test"}'::jsonb
) as public_accepted \gset
reset role;

select access.id, snapshots.snapshot_revision
from public.pachanga_match_guest_access access
join public.pachanga_match_guest_snapshots snapshots using (group_id, match_id)
where access.source_kind = 'open_request'
  and access.source_id = current_setting('match_guest_test.public_request_id')::uuid
  and access.status = 'accepted'
\gset public_access_

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_group_members
    where group_id = '82000000-0000-0000-0000-000000000001'
      and user_id = '81000000-0000-0000-0000-000000000004'
  ),
  'Accepting a public request must grant match access, never group membership'
);

update public.pachanga_open_matches
set active = false, open_slots = 0
where id = '84000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select public.search_pachanga_open_matches_v1() as accepted_full_match_search \gset
reset role;
select pg_temp.assert_true(
  exists (
    select 1
    from jsonb_array_elements(:'accepted_full_match_search'::jsonb) matches
    where matches.value ->> 'id' = '84000000-0000-0000-0000-000000000001'
  ),
  'An accepted guest must keep the exact match entry even after its final slot closes'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select public.leave_pachanga_guest_match_v1(
  :'public_access_id'::uuid,
  '85000000-0000-0000-0000-000000000012',
  :'public_access_snapshot_revision'::bigint,
  '{"sessionId":"public-device-a","surface":"db-test"}'::jsonb
) as public_guest_left \gset
reset role;

select pg_temp.assert_true(
  (select status from public.pachanga_open_match_requests
   where id = current_setting('match_guest_test.public_request_id')::uuid) = 'cancelled'
  and (select decision_note from public.pachanga_open_match_requests
       where id = current_setting('match_guest_test.public_request_id')::uuid) = 'guest_left',
  'Leaving an accepted public match must close its request and free reapplication'
);

select source_payload_revision
from public.pachanga_open_matches
where id = '84000000-0000-0000-0000-000000000001'
\gset public_match_after_leave_

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select public.request_pachanga_open_match_authoritative_v2(
  '84000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000013',
  :'public_match_after_leave_source_payload_revision'::bigint,
  '{"sessionId":"public-device-b","surface":"db-test"}'::jsonb
) as public_requested_after_leave \gset
reset role;
select pg_temp.assert_true(
  (select status from public.pachanga_open_match_requests
   where id = current_setting('match_guest_test.public_request_id')::uuid) = 'pending',
  'A guest who leaves must be able to submit a fresh request later'
);

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_match_guest_snapshots newer
    join public.pachanga_match_guest_snapshots older
      on newer.group_id = older.group_id and newer.match_id = older.match_id
    where newer.server_sequence = older.server_sequence and newer.id <> older.id
  ),
  'Snapshot identity must remain unambiguous through server sequence and stable id'
);

-- A shared-link invitation is intentionally different from a permanent group
-- invitation. It can be previewed before signup, but acceptance grants only the
-- safe match guest access model.
select payload_revision
from public.pachanga_groups
where id = '82000000-0000-0000-0000-000000000001'
\gset link_group_
select set_config('match_guest_test.link_group_revision', :'link_group_payload_revision', false);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.create_pachanga_match_link_invitation_v1(
  '82000000-0000-0000-0000-000000000001',
  'guest-match-1',
  '85000000-0000-0000-0000-000000000014',
  :'link_group_payload_revision'::bigint,
  '{"sessionId":"admin-link-device","surface":"db-test"}'::jsonb
) as link_created \gset
select public.create_pachanga_match_link_invitation_v1(
  '82000000-0000-0000-0000-000000000001',
  'guest-match-1',
  '85000000-0000-0000-0000-000000000014',
  :'link_group_payload_revision'::bigint,
  '{"sessionId":"admin-link-device","surface":"db-test"}'::jsonb
) as link_replayed \gset
reset role;

select pg_temp.assert_true(
  :'link_created'::jsonb = :'link_replayed'::jsonb
  and (select count(*) from public.pachanga_match_link_invitations) = 1,
  'Shared-link creation must be idempotent'
);
select set_config(
  'match_guest_test.link_token',
  (:'link_created'::jsonb -> 'invitation' ->> 'token'),
  false
);

set local role anon;
select public.get_pachanga_match_link_invitation_v1(
  current_setting('match_guest_test.link_token')::uuid
) as anonymous_link_preview \gset
reset role;
select pg_temp.assert_true(
  not jsonb_path_exists(:'anonymous_link_preview'::jsonb, '$.**.phone')
  and not jsonb_path_exists(:'anonymous_link_preview'::jsonb, '$.**.paid')
  and not jsonb_path_exists(:'anonymous_link_preview'::jsonb, '$.**.ownerUserId')
  and not jsonb_path_exists(:'anonymous_link_preview'::jsonb, '$.**.inviteToken'),
  'Anonymous shared-link preview must not expose private group data'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000005', true);
select public.respond_pachanga_match_link_invitation_v1(
  current_setting('match_guest_test.link_token')::uuid,
  'rejected',
  '85000000-0000-0000-0000-000000000015',
  1,
  :'link_group_payload_revision'::bigint,
  '{"sessionId":"new-user-device","surface":"db-test"}'::jsonb
) as link_rejected \gset
reset role;
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_group_members
    where group_id = '82000000-0000-0000-0000-000000000001'
      and user_id = '81000000-0000-0000-0000-000000000005'
  )
  and not exists (
    select 1 from public.pachanga_match_guest_access
    where guest_user_id = '81000000-0000-0000-0000-000000000005'
  ),
  'Rejecting a shared link must grant no access and no membership'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select public.create_pachanga_match_link_invitation_v1(
  '82000000-0000-0000-0000-000000000001',
  'guest-match-1',
  '85000000-0000-0000-0000-000000000016',
  :'link_group_payload_revision'::bigint,
  '{"sessionId":"admin-link-device-b","surface":"db-test"}'::jsonb
) as accepted_link_created \gset
reset role;
select set_config(
  'match_guest_test.accepted_link_token',
  (:'accepted_link_created'::jsonb -> 'invitation' ->> 'token'),
  false
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000005', true);
select public.respond_pachanga_match_link_invitation_v1(
  current_setting('match_guest_test.accepted_link_token')::uuid,
  'accepted',
  '85000000-0000-0000-0000-000000000017',
  1,
  :'link_group_payload_revision'::bigint,
  '{"sessionId":"new-user-device","surface":"db-test"}'::jsonb
) as accepted_link_response \gset
reset role;
select set_config(
  'match_guest_test.accepted_link_access_id',
  (:'accepted_link_response'::jsonb ->> 'accessId'),
  false
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_group_members
    where group_id = '82000000-0000-0000-0000-000000000001'
      and user_id = '81000000-0000-0000-0000-000000000005'
  )
  and (select status from public.pachanga_match_guest_access
       where id = current_setting('match_guest_test.accepted_link_access_id')::uuid) = 'accepted',
  'Accepting a shared link must grant exact-match access without group membership'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000006', true);
do $$
begin
  perform public.respond_pachanga_match_link_invitation_v1(
    current_setting('match_guest_test.accepted_link_token')::uuid,
    'accepted',
    '85000000-0000-0000-0000-000000000018',
    1,
    current_setting('match_guest_test.link_group_revision')::bigint,
    '{}'::jsonb
  );
  raise exception 'A second account unexpectedly claimed a one-use link';
exception when others then
  if sqlerrm = 'A second account unexpectedly claimed a one-use link' then raise; end if;
  if sqlerrm not like '%revision is newer%' and sqlerrm not like '%ya estaba decidida%' then raise; end if;
end;
$$;
reset role;

select payload_revision,
       (select player_id from public.pachanga_match_guest_access
        where id = current_setting('match_guest_test.accepted_link_access_id')::uuid) as guest_player_id
from public.pachanga_groups
where id = '82000000-0000-0000-0000-000000000001'
\gset accepted_link_group_
select set_config(
  'match_guest_test.accepted_link_group_revision',
  :'accepted_link_group_payload_revision',
  false
);
select set_config(
  'match_guest_test.accepted_link_guest_player_id',
  :'accepted_link_group_guest_player_id',
  false
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000005', true);
do $$
begin
  perform public.patch_pachanga_match_player_paid_authoritative_v2(
    '82000000-0000-0000-0000-000000000001',
    'guest-match-1',
    current_setting('match_guest_test.accepted_link_guest_player_id'),
    true,
    '85000000-0000-0000-0000-000000000019',
    current_setting('match_guest_test.accepted_link_group_revision')::bigint,
    '{}'::jsonb
  );
  raise exception 'A match-only guest unexpectedly modified payment state';
exception when others then
  if sqlerrm = 'A match-only guest unexpectedly modified payment state' then raise; end if;
  if sqlerrm <> 'Solo los miembros del grupo pueden modificar este dato' then raise; end if;
end;
$$;
reset role;

rollback;
