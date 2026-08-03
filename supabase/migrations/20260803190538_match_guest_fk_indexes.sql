-- Cover foreign keys used by invitation and withdrawal review workflows.

create index if not exists pachanga_match_invitations_inviter_idx
  on public.pachanga_match_invitations(inviter_user_id);

create index if not exists pachanga_match_invitations_target_profile_idx
  on public.pachanga_match_invitations(target_market_profile_id);

create index if not exists pachanga_guest_withdrawal_reviews_guest_idx
  on public.pachanga_guest_withdrawal_reviews(guest_user_id);

create index if not exists pachanga_guest_withdrawal_reviews_reviewer_idx
  on public.pachanga_guest_withdrawal_reviews(reviewed_by)
  where reviewed_by is not null;
