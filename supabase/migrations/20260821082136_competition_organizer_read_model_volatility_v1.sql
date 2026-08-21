-- The organizer read model resolves time-sensitive entitlement state. It must
-- not be marked STABLE after the resolver moved to one authoritative wall-clock
-- sample per invocation.

alter function public.get_my_pachanga_competition_foundation_v1() volatile;

comment on function public.get_my_pachanga_competition_foundation_v1() is
  'Canonical organizer read model. VOLATILE because entitlement status is evaluated against the server clock.';
