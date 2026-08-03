-- Apply only after the frontend reads the public market through
-- search_pachanga_open_matches_v1(). The old table includes match_url and
-- exact location metadata that must not be exposed to market clients.
revoke select on table public.pachanga_open_matches from anon, authenticated;

comment on table public.pachanga_open_matches is
  'Server-owned open-match source. Clients use search_pachanga_open_matches_v1; direct reads are closed to prevent match URL, team-code and exact-coordinate disclosure.';
