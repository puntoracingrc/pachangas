create table if not exists public.pachanga_open_matches (
  id uuid primary key default gen_random_uuid(),
  source_group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  source_match_id text not null,
  group_name text not null default 'Grupo de pachangas',
  title text not null default 'Partido abierto',
  date timestamptz not null,
  date_text text not null default '',
  day text not null default '',
  modality text not null default 'futbol7',
  zone text not null default '',
  place_id text,
  lat numeric,
  lng numeric,
  field_name text not null default 'Campo por confirmar',
  field_cost numeric not null default 0,
  price_per_player numeric not null default 0,
  target_players integer not null default 0,
  confirmed_count integer not null default 0,
  open_slots integer not null default 0,
  min_media numeric not null default 0,
  max_media numeric not null default 10,
  positions text[] not null default '{}',
  requires_approval boolean not null default true,
  guests_pay boolean not null default true,
  group_level numeric,
  match_url text not null default '',
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_group_id, source_match_id)
);

create index if not exists pachanga_open_matches_active_date_idx
on public.pachanga_open_matches(active, date);

create index if not exists pachanga_open_matches_modality_idx
on public.pachanga_open_matches(modality);

create index if not exists pachanga_open_matches_positions_idx
on public.pachanga_open_matches using gin(positions);

create index if not exists pachanga_open_matches_source_idx
on public.pachanga_open_matches(source_group_id, source_match_id);

grant usage on schema public to authenticated;
grant select on public.pachanga_open_matches to authenticated;

alter table public.pachanga_open_matches enable row level security;

drop policy if exists "Authenticated users can read active open matches" on public.pachanga_open_matches;
create policy "Authenticated users can read active open matches"
on public.pachanga_open_matches
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and active = true
);

create or replace function public.sync_pachanga_open_match(
  target_group_id uuid,
  target_match_id text,
  match_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  match_public_patch jsonb;
  max_media numeric;
  min_media numeric;
  next_matches jsonb;
  open_match public.pachanga_open_matches%rowtype;
  open_slots integer;
  sanitized_positions text[];
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  selected_match jsonb;
  wants_active boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can publish open matches';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  wants_active := coalesce((match_patch ->> 'active')::boolean, false);

  if not wants_active then
    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_match_id then value || jsonb_build_object('publicOpen', false)
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_matches
    from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

    current_payload := current_payload || jsonb_build_object('matches', next_matches);

    update public.pachanga_open_matches
    set active = false,
        updated_at = now()
    where source_group_id = target_group_id
      and source_match_id = target_match_id;

    update public.pachanga_groups
    set payload = current_payload
    where id = target_group_id
    returning payload, payload_revision, updated_at
    into saved_payload, saved_revision, saved_updated_at;

    return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before publishing it';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'Finalized matches cannot be published';
  end if;
  if coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'Closed lineups cannot be published';
  end if;

  open_slots := greatest(0, least(
    greatest(1, coalesce((selected_match ->> 'targetPlayers')::integer, 1)),
    greatest(0, coalesce((match_patch ->> 'openSlots')::integer, 0))
  ));

  if open_slots < 1 then
    raise exception 'Open matches need at least one available slot';
  end if;

  min_media := greatest(0, least(10, coalesce((match_patch ->> 'minRating')::numeric, 0)));
  max_media := greatest(0, least(10, coalesce((match_patch ->> 'maxRating')::numeric, 10)));
  if min_media > max_media then
    min_media := max_media;
  end if;

  select coalesce(array_agg(value), '{}'::text[])
  into sanitized_positions
  from (
    select distinct value
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(match_patch -> 'positions') = 'array' then match_patch -> 'positions'
        else '[]'::jsonb
      end
    ) as positions(value)
    where value in ('Portero', 'Defensa', 'Medio', 'Ataque')
  ) as position_values;

  match_public_patch := jsonb_build_object(
    'publicOpen', true,
    'publicOpenSlots', open_slots,
    'publicMinRating', min_media,
    'publicMaxRating', max_media,
    'publicPositions', to_jsonb(sanitized_positions),
    'publicRequiresApproval', coalesce((match_patch ->> 'requiresApproval')::boolean, true),
    'publicGuestsPay', coalesce((match_patch ->> 'guestsPay')::boolean, true)
  );

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_match_id then value || match_public_patch
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('matches', next_matches);

  insert into public.pachanga_open_matches (
    source_group_id,
    source_match_id,
    group_name,
    title,
    date,
    date_text,
    day,
    modality,
    zone,
    place_id,
    lat,
    lng,
    field_name,
    field_cost,
    price_per_player,
    target_players,
    confirmed_count,
    open_slots,
    min_media,
    max_media,
    positions,
    requires_approval,
    guests_pay,
    group_level,
    match_url,
    active,
    created_by
  )
  values (
    target_group_id,
    target_match_id,
    left(coalesce(nullif(trim(match_patch ->> 'groupName'), ''), current_group.name, 'Grupo de pachangas'), 120),
    left(coalesce(nullif(trim(match_patch ->> 'title'), ''), selected_match ->> 'title', 'Partido abierto'), 120),
    coalesce(nullif(match_patch ->> 'date', ''), selected_match ->> 'date')::timestamptz,
    left(coalesce(match_patch ->> 'dateText', ''), 80),
    left(coalesce(match_patch ->> 'day', ''), 20),
    case when coalesce(match_patch ->> 'modality', selected_match ->> 'kind', 'futbol7') in ('sala', 'futbol7', 'futbol11')
      then coalesce(match_patch ->> 'modality', selected_match ->> 'kind', 'futbol7')
      else 'futbol7'
    end,
    left(coalesce(match_patch ->> 'zone', ''), 180),
    nullif(left(coalesce(match_patch ->> 'placeId', ''), 180), ''),
    case
      when coalesce(match_patch ->> 'lat', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-90::numeric, least(90::numeric, (match_patch ->> 'lat')::numeric))
      else null
    end,
    case
      when coalesce(match_patch ->> 'lng', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-180::numeric, least(180::numeric, (match_patch ->> 'lng')::numeric))
      else null
    end,
    left(coalesce(nullif(trim(match_patch ->> 'fieldName'), ''), selected_match ->> 'place', 'Campo por confirmar'), 140),
    greatest(0, coalesce((match_patch ->> 'fieldCost')::numeric, 0)),
    greatest(0, coalesce((match_patch ->> 'pricePerPlayer')::numeric, 0)),
    greatest(0, coalesce((match_patch ->> 'targetPlayers')::integer, coalesce((selected_match ->> 'targetPlayers')::integer, 0))),
    greatest(0, coalesce((match_patch ->> 'confirmedCount')::integer, 0)),
    open_slots,
    min_media,
    max_media,
    sanitized_positions,
    coalesce((match_patch ->> 'requiresApproval')::boolean, true),
    coalesce((match_patch ->> 'guestsPay')::boolean, true),
    case
      when coalesce(match_patch ->> 'groupLevel', '') ~ '^[0-9]+(\.[0-9]+)?$' then greatest(0::numeric, least(10::numeric, (match_patch ->> 'groupLevel')::numeric))
      else null
    end,
    left(coalesce(match_patch ->> 'matchUrl', ''), 500),
    true,
    auth.uid()
  )
  on conflict (source_group_id, source_match_id) do update set
    group_name = excluded.group_name,
    title = excluded.title,
    date = excluded.date,
    date_text = excluded.date_text,
    day = excluded.day,
    modality = excluded.modality,
    zone = excluded.zone,
    place_id = excluded.place_id,
    lat = excluded.lat,
    lng = excluded.lng,
    field_name = excluded.field_name,
    field_cost = excluded.field_cost,
    price_per_player = excluded.price_per_player,
    target_players = excluded.target_players,
    confirmed_count = excluded.confirmed_count,
    open_slots = excluded.open_slots,
    min_media = excluded.min_media,
    max_media = excluded.max_media,
    positions = excluded.positions,
    requires_approval = excluded.requires_approval,
    guests_pay = excluded.guests_pay,
    group_level = excluded.group_level,
    match_url = excluded.match_url,
    active = true,
    updated_at = now()
  returning * into open_match;

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

revoke all on function public.sync_pachanga_open_match(uuid, text, jsonb) from public;
revoke execute on function public.sync_pachanga_open_match(uuid, text, jsonb) from anon;
grant execute on function public.sync_pachanga_open_match(uuid, text, jsonb) to authenticated;
