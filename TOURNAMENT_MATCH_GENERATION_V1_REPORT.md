# Tournament Match Generation V1

## Design

R6B adapts each published R6A Group to the existing R4B scheduler. Stable group
order, not opaque UUID order, enters the schedule seed. A four-team single
round-robin Group produces three rounds and six fixtures.

Publication is one transaction:

1. Validate every mapped Group schedule and global slot compatibility.
2. Publish the R4B schedules.
3. Verify the expected fixture cardinality.
4. Verify exactly one source binding per ScheduleItem.
5. Verify exactly one `CanonicalMatch` and one `CompetitionMatchContext` per
   fixture.
6. Advance the R6B aggregate revision and return its canonical snapshot.

Any mismatch rolls back the whole publication. Repeating the same operation is
an idempotent receipt replay. Repeating the intent with a new operation after
publication returns the stable already-published outcome instead of duplicating
matches.

## Hard boundaries

- R6B only accepts Group mappings owned by its current preparation.
- Published DrawPlan, ParticipantFreeze, RuleRevision and accepted Entry lineage
  must remain current.
- Participant withdrawal races lose after Group generation.
- Schedule edits and publication use expected revisions.
- The adapter rejects any knockout source.
- `tournament_knockout_match_generation_enabled` and
  `tournament_bracket_progression_enabled` stay OFF.

## Evidence

| Scenario | Result |
| --- | --- |
| 16 teams / 4 groups | 24 fixtures, 24 matches, 24 contexts |
| 32 teams / 8 groups | 48 fixtures, exact 1:1 cardinality |
| 64 teams / 16 groups | 96 fixtures, exact 1:1 cardinality |
| duplicate fixture | rejected by canonical uniqueness |
| two publications | one winner, one `STALE_REVISION` |
| publish vs schedule edit | one winner, one `STALE_REVISION` |
| generation vs withdrawal | generation wins, withdrawal is locked |

The representative volume run contains 10,000 Group matches and 10,000
official results inside a rolled-back local PostgreSQL fixture. No duplicate or
knockout match is created.

Measured local p95 values:

| Teams | Generate | Validate | Publish |
| ---: | ---: | ---: | ---: |
| 16 | 61.390 ms | 34.670 ms | 65.402 ms |
| 32 | 87.962 ms | 46.729 ms | 90.855 ms |
| 64 | 183.760 ms | 97.968 ms | 214.358 ms |

All statements are bounded; the certification harness uses explicit lock and
statement timeouts and rolls back its product data.
