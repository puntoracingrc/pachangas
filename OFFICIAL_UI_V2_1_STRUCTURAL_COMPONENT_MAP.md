# Official UI V2.1 Structural Component Map

## Boundary

Official UI V2.1 changes composition only. `app/page.tsx` and `app/mercado/page.tsx` remain the owners of authenticated state, read models, permissions and callbacks. The extracted components do not query Supabase, call RPCs, calculate ratings or persist sporting state.

## Production Map

| Previous presentation | V2.1 component | Inputs from official product | Existing callbacks preserved | Authority |
| --- | --- | --- | --- | --- |
| Authenticated Home legacy hero and peer action wall | `OfficialHomeGameDashboard` | identity, next action, metrics, player object, upcoming matches, activity | callbacks are passed through its child models | `app/page.tsx` |
| Repeated team heading and small object | `OfficialTeamIdentityBand` | `currentTeamName`, `siteSettings.subtitle`, displayed role, sync status, `PlayerCosmeticCard` | `openPlayerProfile` remains on the object button | `app/page.tsx` and cosmetic read model |
| Eight visually competing Home actions | Internal `ActionControl` with `OfficialHomeAction` | one state-derived label, detail, link or callback | `openMatchFromInicio`, `createMatch` or `/mercado` | existing match/team permissions |
| Four dispersed counters | `OfficialSeasonMetrics` | closed matches, open matches, active roster count and canonical group level | none | existing derived product values |
| Vertical next-match list | `OfficialUpcomingMatchesRail` | first eight real open matches | `openMatchFromInicio(matchId, "proximo")` | existing matches array |
| Generic history/activity blocks | `OfficialActivityRail` | first eight real closed matches | `openMatchFromInicio(matchId, "resultado")` | existing closed-match read model |
| Permanent Team Access band | `OfficialTeamAccess` | real group selector, code, role, level, roster and sync status | `selectTeam`, invite sharing and `deleteCurrentTeam` | existing membership and permission guards |
| Manual/profile/create/settings actions in Home hero | `OfficialSecondaryActions` | actual links and guarded commands | existing profile, team, create, settings and session callbacks | existing product guards |
| Inline match subnav plus repeated active context | `OfficialMatchGameHub` | active pane, pane list, active match context, lineup status, optional tools/share | `setActiveMatchManagerPane`, `toggleLineupClosed`, `applyRandomTeams`, `applyBalancedTeams` | `app/page.tsx` |
| Match bodies competing as peer panels | Existing bodies under `data-official-match-hub="v2.1"` | current match, roster, pitch, result and admin state | all original handlers remain in place | existing match state and RPC/API paths |
| Market title, duplicate subnav, context and filters | `OfficialMarketGameView` | current tab, allowed tab set, admin URL, context, filters and result body | `selectMarketTab` and existing child callbacks | `app/mercado/page.tsx` |
| Own rank after public ranking | `ProvincialRankingBoard` reordered layout | canonical `ownRank` and `ranking` payloads | none | existing ranking endpoint/read model |

## Match Pane Mapping

| Pane | V2.1 hierarchy | Functional body retained |
| --- | --- | --- |
| Próximo | persistent match context, attendance first, roster next | attendance, payment, weather, sharing and player status callbacks |
| Alineación | pitch as stage, compact tools, bench/list as support | current `MatchPitch`, drag logic, random/balanced teams and lineup closing |
| Resultado | score and scorers before secondary controls | score inputs, scorer controls, photo and finalization guards |
| Admin | grouped Configuration, Market/Guests, Privacy and Danger | existing match configuration, invitations, public market and deletion/cancellation paths |

The pane bodies were not rewritten into a second functional tree. V2.1 changes their surrounding hierarchy and responsive layout so orientation changes do not remount or fork the official state.

## Market Mapping

| Visual slot | Official source |
| --- | --- |
| Context | `marketContext`, only when player search is attached to an active match |
| Filters | existing zone, day, modality and position state |
| Player results | `filteredProfiles` and existing invitation state |
| Open matches | `filteredOpenMatches` and existing request state |
| Challenges | existing `TeamChallengesPanel` |
| Teams | existing `ChallengeableTeamsPanel` |
| Referees | existing `RefereeMarketplacePanel`, mounted only when the canonical feature flag allows it |
| Admin link | existing permission check plus `marketAdminMatchUrl` |

## Visual Lab

`/laboratorio-official-ui-v2-1` composes the same extracted presentation components with labelled visual fixtures. It is noindex/nofollow, contains no network authority and never feeds data back into the product. Its query controls cover surface, pane, role, state and theme solely for comparison and capture.

## Deliberately Unchanged

- `OfficialProductShellV2` and its single-tree orientation behavior.
- Demo World source and fixtures.
- Control Center `PLATFORM_ADMIN` shell.
- Rating V2, attendance, lineup, result, notification, Market, ranking and cosmetics contracts.
- Supabase paths, SQL, migrations, RPC, RLS and remote flags.
