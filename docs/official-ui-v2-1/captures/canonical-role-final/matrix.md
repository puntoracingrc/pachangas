# Official UI V2.1 Canonical Owner, Player And Shield Matrix

Captured on 2026-08-23 against the stable Vercel Preview and Supabase staging.
The fixture was created and updated through official product UI/API/RPC paths.
No account identity, invitation token, cookie, service key or internal group ID
is included in this evidence.

| Surface | Viewport | Expected state | Overflow X | Broken shield image |
| --- | --- | --- | ---: | ---: |
| Owner Home without profile | 1440x900 | PASS | 0 | 0 |
| Owner Home without profile | 390x844 | PASS | 0 | 0 |
| Owner Home without profile | 844x390 | PASS | 0 | 0 |
| Base shield, revision 0 | 1440x900 | PASS | 0 | 0 |
| Base shield, revision 0 | 390x844 | PASS | 0 | 0 |
| Base shield, revision 0 | 844x390 | PASS | 0 | 0 |
| Configured shield, revision 1 | 1440x900 | PASS | 0 | 0 |
| Configured shield, revision 1 | 390x844 | PASS | 0 | 0 |
| Configured shield, revision 1 | 844x390 | PASS | 0 | 0 |
| Normal player Home | 1440x900 | PASS | 0 | 0 |
| Normal player Home | 390x844 | PASS | 0 | 0 |
| Normal player Home | 844x390 | PASS | 0 | 0 |

Additional canonical outcomes:

- long QA team name: PASS;
- shield remains protagonist: PASS;
- player card is not used as the team shield: PASS;
- 12-player roster created through the official UI: PASS;
- owner with profile: `BLOCKED_EXISTING_RATING_V2_ONBOARDING`;
- second Google identity and normal player: PASS;
- player role readback: `Jugador`, never owner/admin;
- player owner/admin controls: absent;
- player Team Access: role and selector visible, invitation and deletion controls absent;
- player Match navigation: Proximo, Alineacion and Resultado PASS; Admin absent;
- player Market navigation: Jugadores, Partidos, Retos and Equipos PASS; admin
  configuration and Referees absent;
- portrait to landscape to portrait: selected Market tab and filters retained;
- wide canonical match/result data: `BLOCKED_PREVIEW_GOOGLE_PLACES_SELECTION`;
  the official venue form accepted text but returned no selectable Places
  prediction, so `Guardar campo` and consequently `Guardar partido` remained
  disabled. No direct fixture write was used;
- staging cleanup: PASS through the official owner delete action; post-delete
  readback showed no team selector, owner role or QA team, and both temporary
  sessions were closed;
- installed PWA and physical devices: PENDING.

The prior no-team canonical matrix remains in
`../authenticated-staging-final/matrix.md`. Together both sets contain 21
canonical staging captures.
