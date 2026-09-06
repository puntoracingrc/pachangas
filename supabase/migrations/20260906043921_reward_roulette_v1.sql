-- Personal roulette: one canonical economy, persistent free credits and sealed boxes.
create table private.pachanga_roulette_config (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true,
  cost integer not null default 15 check (cost > 0),
  odds integer[] not null default array[60,25,10,4,1],
  activated_at timestamptz not null default now(),
  check (array_length(odds,1)=5 and odds[1]>=0 and odds[2]>=0 and odds[3]>=0 and odds[4]>=0 and odds[5]>=0
    and odds[1]+odds[2]+odds[3]+odds[4]+odds[5]=100)
);
insert into private.pachanga_roulette_config(singleton) values(true);
create table private.pachanga_roulette_credits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  origin text not null,
  granted_at timestamptz not null,
  consumed_at timestamptz,
  unique(user_id,origin)
);
create table private.pachanga_roulette_boxes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  player_profile_id uuid not null references public.pachanga_player_profiles(id),
  rarity integer not null check(rarity between 0 and 4),
  economy_version integer not null references public.pachanga_reward_economy_versions(version),
  credit_id uuid unique references private.pachanga_roulette_credits(id),
  cost integer not null check(cost>=0),
  sealed jsonb not null,
  result jsonb,
  created_at timestamptz not null default now(),
  opened_at timestamptz
);
create index pachanga_roulette_boxes_user_idx on private.pachanga_roulette_boxes(user_id,created_at,id);
create table private.pachanga_roulette_receipts (
  operation_id uuid primary key,
  user_id uuid not null references auth.users(id),
  action text not null,
  ids uuid[],
  response jsonb not null,
  created_at timestamptz not null default now()
);
alter table private.pachanga_roulette_config enable row level security;
alter table private.pachanga_roulette_credits enable row level security;
alter table private.pachanga_roulette_boxes enable row level security;
alter table private.pachanga_roulette_receipts enable row level security;
revoke all on private.pachanga_roulette_config, private.pachanga_roulette_credits,
  private.pachanga_roulette_boxes, private.pachanga_roulette_receipts from public,anon,authenticated;
-- Roulette cosmetics have their own origin; never manufacture achievement grants.
alter table public.pachanga_player_reward_inventory alter column source_grant_id drop not null;
alter table public.pachanga_player_reward_inventory add column source_roulette_box_id uuid
  references private.pachanga_roulette_boxes(id);
alter table public.pachanga_player_reward_inventory add constraint pachanga_inventory_reward_origin_check
  check(source_grant_id is not null or source_roulette_box_id is not null);
create index pachanga_inventory_roulette_origin_idx on public.pachanga_player_reward_inventory(source_roulette_box_id)
  where source_roulette_box_id is not null;

create function private.pachanga_roulette_random_below(n integer) returns integer
language plpgsql volatile set search_path=pg_catalog as $$
declare value bigint; bound bigint;
begin
  if n is null or n<1 or n>1000000 then raise exception 'Invalid random bound'; end if;
  bound := 4294967296 - (4294967296 % n);
  loop
    -- The first 32 UUID v4 bits are cryptographically random; reject modulo bias.
    value := ('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint;
    if value<bound then return (value % n)::integer; end if;
  end loop;
end $$;
revoke all on function private.pachanga_roulette_random_below(integer) from public,anon,authenticated;

create function private.pachanga_roulette_sync_credits(actor uuid, profile uuid) returns void
language plpgsql set search_path=pg_catalog as $$
declare activation timestamptz;
begin
  select activated_at into activation from private.pachanga_roulette_config;
  insert into private.pachanga_roulette_credits(user_id,origin,granted_at)
    select actor,'assessment:'||a.assessment_kind,greatest(a.completed_at,activation)
    from public.pachanga_player_assessments a
    where a.user_id=actor and a.assessment_kind in ('initial','advanced') and a.completed_at<=now()
    on conflict(user_id,origin) do nothing;
  -- Reconcile every eligible week since launch, including weeks without a site visit.
  -- Madrid calendar weeks; a confirmed match within the trailing 30 days qualifies.
  insert into private.pachanga_roulette_credits(user_id,origin,granted_at)
    select actor,'week:'||to_char(w.week_start,'YYYY-MM-DD'),
      greatest(activation,w.week_start at time zone 'Europe/Madrid',min(f.played_at))
    from generate_series(date_trunc('week',activation at time zone 'Europe/Madrid'),
                         date_trunc('week',now() at time zone 'Europe/Madrid'), interval '1 week') w(week_start)
    join public.pachanga_progression_player_match_facts pf on pf.player_profile_id=profile and pf.state='active'
    join public.pachanga_progression_match_facts f on f.id=pf.match_fact_id and f.state='active'
      and f.played_at<=now()
      and f.played_at < ((w.week_start+interval '1 week') at time zone 'Europe/Madrid')
      and f.played_at+interval '30 days'>greatest(activation,w.week_start at time zone 'Europe/Madrid')
    group by w.week_start
    on conflict(user_id,origin) do nothing;
end $$;
revoke all on function private.pachanga_roulette_sync_credits(uuid,uuid) from public,anon,authenticated;

create function private.pachanga_roulette_snapshot(actor uuid, profile uuid) returns jsonb
language sql stable set search_path=pg_catalog as $$
 select jsonb_build_object(
  'balance',coalesce((select balance from public.pachanga_player_point_accounts where user_id=actor),0),
  'freeSpins',(select count(*) from private.pachanga_roulette_credits where user_id=actor and consumed_at is null),
  'cost',c.cost,'odds',to_jsonb(c.odds),'enabled',c.enabled,
  'queue',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'rarity',b.rarity) order by b.created_at,b.id)
    from private.pachanga_roulette_boxes b where b.user_id=actor and b.opened_at is null),'[]'::jsonb),
  'owned',coalesce((select jsonb_agg(reward_key order by reward_key) from public.pachanga_player_reward_inventory
    where player_profile_id=profile and reward_kind='player_cosmetic' and state='unlocked'),'[]'::jsonb),
  'history',coalesce((select jsonb_agg(h.rarity order by h.created_at desc,h.id desc) from
    (select rarity,created_at,id from private.pachanga_roulette_boxes where user_id=actor order by created_at desc,id desc limit 6) h),'[]'::jsonb),
  'pools',coalesce((select jsonb_agg(jsonb_build_object('rarity',array_position(array['common','uncommon','rare','epic','legendary'],split_part(p.pool_key,'.',3))-1,
    'kind',p.reward_kind,'weight',p.weight,'min',p.points_min,'max',p.points_max,'key',p.cosmetic_key,'duplicatePoints',p.duplicate_conversion_points)
    order by p.pool_key,p.entry_key) from public.pachanga_reward_pool_catalog p join public.pachanga_reward_economy_versions e on e.version=p.economy_version and e.state='active'
    where p.active and p.pool_key like 'pool.collective.%'),'[]'::jsonb)
 ) from private.pachanga_roulette_config c;
$$;
revoke all on function private.pachanga_roulette_snapshot(uuid,uuid) from public,anon,authenticated;

create function public.pachanga_roulette_v1(p_action text default 'snapshot', p_operation_id uuid default null, p_box_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
<<roulette>>
declare
 actor uuid:=auth.uid(); profile uuid; config private.pachanga_roulette_config%rowtype;
 receipt private.pachanga_roulette_receipts%rowtype; box private.pachanga_roulette_boxes%rowtype;
 credit uuid; version integer; picked integer; cumulative integer:=0; rarity integer:=0;
 entry public.pachanga_reward_pool_catalog%rowtype; total_weight integer; pool text;
 points integer; awarded boolean; duplicate boolean; result jsonb; output jsonb:='{}';
 opened jsonb:='[]'; ids uuid[]; box_id uuid; points_total integer:=0;
begin
 if actor is null then raise exception 'Inicia sesión para acceder a tus premios' using errcode='PT401'; end if;
 if p_action not in ('snapshot','spin','open','open_all') or p_action is null then raise exception 'Invalid roulette action'; end if;
 if p_action<>'snapshot' and p_operation_id is null then raise exception 'Operation id required'; end if;
 select id into profile from public.pachanga_player_profiles where user_id=actor;
 if profile is null then raise exception 'Completa tu perfil para acceder a tus premios' using errcode='PT409'; end if;
 perform pg_advisory_xact_lock(hashtextextended('roulette:'||actor::text,0));
 select * into config from private.pachanga_roulette_config;
 perform private.pachanga_roulette_sync_credits(actor,profile);
 if p_action='snapshot' then return private.pachanga_roulette_snapshot(actor,profile); end if;
 select * into receipt from private.pachanga_roulette_receipts where operation_id=p_operation_id;
 if found then
   if receipt.user_id<>actor or receipt.action<>p_action or receipt.ids is distinct from p_box_ids then
     raise exception 'Operation conflicts with existing evidence' using errcode='PT409';
   end if;
   return receipt.response||jsonb_build_object('snapshot',private.pachanga_roulette_snapshot(actor,profile));
 end if;
 if p_action='spin' then
   if not config.enabled then raise exception 'La ruleta no está disponible ahora' using errcode='PT409'; end if;
   if p_box_ids is not null then raise exception 'Spin does not accept box ids'; end if;
   select e.version into version from public.pachanga_reward_economy_versions e where e.state='active';
   if version is null then raise exception 'Reward economy unavailable'; end if;
   picked:=private.pachanga_roulette_random_below(100);
   for i in 1..5 loop
     cumulative:=cumulative+config.odds[i];
     if picked<cumulative then rarity:=i-1; exit; end if;
   end loop;
   select b.reward_pool_key into pool from public.pachanga_reward_box_catalog b
     where b.economy_version=version and b.box_type='collective.'||(array['common','uncommon','rare','epic','legendary'])[roulette.rarity+1] and b.active;
   select sum(p.weight) into total_weight from public.pachanga_reward_pool_catalog p where p.economy_version=version and p.pool_key=pool and p.active;
   if coalesce(total_weight,0)<1 then raise exception 'Reward pool unavailable'; end if;
   picked:=private.pachanga_roulette_random_below(total_weight); cumulative:=0;
   for entry in select * from public.pachanga_reward_pool_catalog p where p.economy_version=version and p.pool_key=pool and p.active order by p.entry_key loop
     cumulative:=cumulative+entry.weight;
     if picked<cumulative then exit; end if;
   end loop;
   points:=entry.points_min+private.pachanga_roulette_random_below(entry.points_max-entry.points_min+1);
   select id into credit from private.pachanga_roulette_credits where user_id=actor and consumed_at is null order by granted_at,id limit 1 for update;
   insert into private.pachanga_roulette_boxes(user_id,player_profile_id,rarity,economy_version,credit_id,cost,sealed)
   values(actor,profile,rarity,version,credit,case when credit is null then config.cost else 0 end,
     jsonb_build_object('key',entry.cosmetic_key,'points',points,'duplicatePoints',entry.duplicate_conversion_points,'entry',entry.entry_key)) returning * into box;
   if credit is not null then
     update private.pachanga_roulette_credits set consumed_at=now() where id=credit;
   else
     perform private.pachanga_apply_player_points_v1(profile,actor,-config.cost,'box_purchase',box.id,null,null,null,
       'roulette:spin:'||box.id::text,jsonb_build_object('source','roulette','economyVersion',version));
   end if;
   output:=jsonb_build_object('chest',jsonb_build_object('id',box.id,'rarity',box.rarity));
 else
   if p_action='open_all' then
     if p_box_ids is not null then raise exception 'Open all does not accept box ids'; end if;
     select array_agg(b.id order by b.created_at,b.id) into ids from private.pachanga_roulette_boxes b where b.user_id=actor and b.opened_at is null;
   else
     if cardinality(p_box_ids) is distinct from 1 then raise exception 'Select one chest'; end if;
     ids:=p_box_ids;
   end if;
   foreach box_id in array coalesce(ids,array[]::uuid[]) loop
     select * into box from private.pachanga_roulette_boxes b where b.id=box_id and b.user_id=actor for update;
     if not found then raise exception 'Cofre no encontrado' using errcode='PT404'; end if;
     if box.result is null then
       points:=(box.sealed->>'points')::integer; awarded:=false; duplicate:=false;
       if box.sealed->>'key' is not null then
         insert into public.pachanga_player_reward_inventory(player_profile_id,reward_kind,reward_key,source_roulette_box_id,source_box_id,state,acquired_at,metadata)
           values(profile,'player_cosmetic',box.sealed->>'key',box.id,null,'unlocked',now(),jsonb_build_object('source','roulette','catalogVersion',box.economy_version))
           on conflict(player_profile_id,reward_kind,reward_key) do nothing returning true into awarded;
         duplicate:=not coalesce(awarded,false);
         if duplicate then points:=points+(box.sealed->>'duplicatePoints')::integer; end if;
       end if;
       if points>0 then
         perform private.pachanga_apply_player_points_v1(profile,actor,points,'reward_box',box.id,null,null,null,
           'roulette:open:'||box.id::text,jsonb_build_object('source','roulette','duplicate',duplicate,'key',box.sealed->>'key'));
       end if;
       result:=jsonb_build_object('key',box.sealed->>'key','points',points,'duplicate',duplicate);
       update private.pachanga_roulette_boxes set result=roulette.result,opened_at=now() where id=box.id;
       perform private.pachanga_progression_bump_user_v1(actor);
     else result:=box.result; end if;
     opened:=opened||jsonb_build_array(jsonb_build_object('chest',jsonb_build_object('id',box.id,'rarity',box.rarity),'loot',result));
     points_total:=points_total+(result->>'points')::integer;
   end loop;
   output:=jsonb_build_object('entries',opened,'points',points_total);
 end if;
 insert into private.pachanga_roulette_receipts(operation_id,user_id,action,ids,response) values(p_operation_id,actor,p_action,p_box_ids,output);
 return output||jsonb_build_object('snapshot',private.pachanga_roulette_snapshot(actor,profile));
end $$;
revoke all on function public.pachanga_roulette_v1(text,uuid,uuid[]) from public,anon;
grant execute on function public.pachanga_roulette_v1(text,uuid,uuid[]) to authenticated;
