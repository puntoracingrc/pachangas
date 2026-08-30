# Demo World V3.3 Guided Product Review

## Purpose

V3.3 turns the existing synthetic season into a guided product review. The
tour changes only presentation state: perspective, checkpoint, week,
competition, surface, and explanatory step. It never calls an RPC or remote
write API.

## Tours

| Tour | Coverage |
| --- | --- |
| Player / match | Home next action, attendance, lineup, result, classification |
| Team owner | Team identity, Market, challenges, registration, operational state, match |
| Free agent / public visitor | Market discovery and sanitized public competitions |
| League organizer | Setup, rounds, results, standings, incidents, discipline |
| Tournament organizer | Participants, draw, groups, bracket, final, champion |
| Referee | Public profile, market context, assignments, match evidence |
| Club organizer | Public Club identity, linked teams, organizer access and plans |
| Platform reviewer | Operational restrictions, continuity, incidents, and authority evidence |

There are exactly eight V3.3 tours with unique IDs and at least two steps each.
The public-visitor path is represented inside the free-agent tour because both
consume the same sanitized, unauthenticated discovery surfaces.

## Shareable state

Tour links persist safe semantic parameters such as:

`/demo?perspective=league-organizer&tour=league-organizer&step=1&checkpoint=4&week=8&competition=liga-barrios-iq&surface=standings&view=standings`

No UUID, Auth ID, email, token, or private identifier is present. Reload and
browser back/forward restore the selected state.

## Local progress and accessibility

- Progress is local-only and scoped to the Demo presentation.
- The UI explicitly states that the data is synthetic and real data is not
  modified.
- Previous/next controls are buttons with accessible names.
- Active choices expose current state.
- Reduced motion removes invasive animation.
- Axe found 0 violations on the Demo V3.3 representative surface.

## QA

All eight tour panels were opened and captured. The guided-review contact sheet
contains every perspective. Results: 0 root overflow, 0 broken images, 0 fresh
console errors, 0 PII, and 0 remote writes.
