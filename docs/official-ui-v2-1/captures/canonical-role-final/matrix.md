# Official UI V2.1 Canonical Owner And Shield Matrix

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

Additional canonical outcomes:

- long QA team name: PASS;
- shield remains protagonist: PASS;
- player card is not used as the team shield: PASS;
- 12-player roster created through the official UI: PASS;
- owner with profile: `BLOCKED_EXISTING_RATING_V2_ONBOARDING`;
- normal player: `PENDING_SECOND_IDENTITY`;
- installed PWA and physical devices: PENDING.

The prior no-team canonical matrix remains in
`../authenticated-staging-final/matrix.md`. Together both sets contain 18
canonical staging captures.
