create index if not exists pachanga_group_events_actor_id_idx
on public.pachanga_group_events(actor_id, created_at desc)
where actor_id is not null;

revoke execute on function public.record_pachanga_group_event(uuid, text, text, jsonb, uuid, boolean) from authenticated;
revoke execute on function public.remember_pachanga_operation(uuid, uuid, text, jsonb) from authenticated;
revoke execute on function public.sync_pachanga_match_read_model(uuid, jsonb, bigint) from authenticated;
revoke execute on function public.sync_pachanga_group_read_model(uuid, jsonb, bigint) from authenticated;
