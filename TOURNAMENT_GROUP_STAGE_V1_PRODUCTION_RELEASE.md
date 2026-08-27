# Tournament Group Stage V1 Production Release

## Release identity

- Initial `origin/main`: `7f46951fd4144985b05c8029606574b82c655b73`
- Branch: `codex/tournament-group-stage-match-tracking-v1`
- Pull request: #206 (draft while release gates are in progress)
- Local ledger: 163 base migrations plus 6 R6B migrations = 169

## Ordered migrations

| Version | Purpose | SHA-256 |
| --- | --- | --- |
| 20260827105014 | Group-stage schema and qualification | `a8673226c5a6c8a4b585965826861d74b7ac5f872797642814fba7d64b926d2a` |
| 20260827105018 | R4B schedule adapter | `15d806d70830437c51baaf34bddd0e7cd6ba796dd510022a62a87c046b63c14c` |
| 20260827105022 | Canonical publication, qualification and bracket | `3ce16f0daf420b54686f62c4b8fdab7152b9a989bd402bd11967fbd2f0e09623` |
| 20260827105027 | Tournament Hub read model | `1ec49db2416371f0a64ca51f24b9962e0ca84029f14bbf3e2a2402e78c1b6eba` |
| 20260827105033 | Access, RLS and Realtime | `7ce2ba2df4f463f24619a3f7fabb71a0929005583918052c577f05bc3db9324a` |
| 20260827105036 | Hardening, indexes and flags | `d01f0fb571358fa42f34df83b18f0905f845eaddc89cf8ba355684605eb41ab9` |

Fresh 169-migration bootstrap and exact 163 to 169 upgrade produce normalized
schema hash
`d26a99f64e7ee56103254ecc7f2d9a5bd06ffdb183b0a417819a8e4a54304063`.
All R6B and R6C flags are OFF immediately after migration and no product rows
are created.

## Gates completed locally

- Canonical DB story: PASS.
- Adversarial matrix: 18/18 PASS.
- Concurrency: 10/10 PASS.
- Scale and representative volume: PASS.
- Performance bounds: PASS.
- Fresh/upgrade schema equivalence: PASS.
- Demo World V2.5 deterministic verification: PASS.
- Typecheck: PASS.
- Build: PASS.
- Tests: 20/20 Node and 536/536 TS/TSX.
- Focused lint: PASS (27 changed code/test files).
- `git diff --check`: PASS.

Global lint remains blocked by 40 findings in three files unchanged from main;
see `R6B-TEST-073`.

## Hosted staging certification

The final one-shot run used the isolated, non-production Supabase branch
`krljxecwvxbrijmrwbsn`, bootstrapped from the immutable baseline with an exact
169/169 version-and-name ledger comparison. Before fixture creation it proved
zero users, zero competitions, all R6B/R6C flags OFF, RLS enabled, one Realtime
publication and no authenticated direct inserts.

The authenticated 17-story regression then proved:

- 16 entries, 4 Groups, 12 Group rounds and 24 CanonicalMatches;
- 24 official results, 4 current standings snapshots, 30 locked squads and 30
  closed Attendance sides;
- one postponement, one no-show, one suspension/resumption, four disciplinary
  events and twelve confirmed referee assignments;
- published QualificationSnapshot and published eight-slot BracketTemplate;
- exactly zero knockout matches and public discovery still OFF;
- two authenticated devices at the same revision, one successful completion,
  one `PT409` stale conflict and one persisted completion receipt;
- a real PostgreSQL invalidation delivered to both devices, followed by a
  canonical refetch to the same completed revision 14;
- byte-equivalent idempotent replay of the winning operation.

The branch control plane still labels ordinary migration replay as
`MIGRATIONS_FAILED` because it starts with the historical pre-baseline chain.
`R6B-ENVIRONMENT-076` records that environment limitation. Direct PostgreSQL
readback, not the label, proves the exact 169 migration schema used above.

## Hosted release gates

The following fields must be replaced with real evidence during this same
release before closure:

- Preview deployment: PENDING
- Staging migration/readback: PASS
- Two-device authenticated Realtime: PASS
- Staging teardown: PENDING
- PR merge and final main SHA: PENDING
- Production backup/readback: PENDING
- Production migration ledger 169: PENDING
- Inactive smoke: PENDING
- Audited staged activation: PENDING
- Reversible 4-team production canary: PENDING
- Demo World V2.5 production smoke: PENDING
- Service Worker production smoke: PENDING
- Worktree cleanup: PENDING

No production state is claimed by this draft section.
