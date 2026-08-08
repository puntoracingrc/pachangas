import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(new URL(
  "../supabase/migrations/20260808185802_achievement_catalog_v2.sql",
  import.meta.url,
), "utf8");
const sqlTest = readFileSync(new URL("./achievement-catalog-v2-db.sql", import.meta.url), "utf8");
const identityUi = readFileSync(new URL("../app/equipo/identidad/page.tsx", import.meta.url), "utf8");

test("catalog V2 keeps individual merit separate from collective rewards", () => {
  assert.match(migration, /'player', 'all', 'matches', 'PLAYER_APPEARANCES'/);
  assert.match(migration, /'player', 'all', 'wins', 'PLAYER_WINS'/);
  assert.match(migration, /'player', 'all', 'goals', 'PLAYER_GOALS'/);
  assert.match(migration, /'player'.*'match_goals'.*'PLAYER_BRACES'.*'none'/s);
  assert.match(migration, /where definitions\.active\s+and definitions\.catalog_key = 'achievement_catalog_v2'\s+and definitions\.subject_type = 'team'/);
  assert.match(migration, /first_box_type = excluded\.first_box_type/);
  assert.doesNotMatch(migration, /update public\.pachanga_player_profiles/i);
});

test("catalog V2 contains the approved active families and thresholds", () => {
  assert.match(migration, /\(500, 'Historia viva', 'legendary'\)/);
  assert.match(migration, /\(250, 'Historia ganadora', 'legendary'\)/);
  assert.match(migration, /\(500, 'Historia del gol', 'legendary'\)/);
  assert.match(migration, /"goalsExact":2/);
  assert.match(migration, /"goalsExact":5/);
  assert.match(migration, /"goalsMinimum":6/);
  assert.match(migration, /PLAYER_DISTINCT_OPPONENTS/);
  assert.match(migration, /PLAYER_DISTINCT_OPPONENT_WINS/);
  assert.match(migration, /TEAM_DISTINCT_OPPONENT_WINS/);
  assert.doesNotMatch(migration, /triple[_ ]hat|goalkeeper|opponent_mvp|premium|shop|ranking/i);
});

test("only canonical new facts can unlock the maximum applicable tier", () => {
  assert.match(migration, /canonicalState'.*not in \('confirmed', 'auto_confirmed'\)/s);
  assert.match(migration, /server_sequence < definition\.activation_server_sequence/);
  assert.match(migration, /order by coalesce\(\(definitions\.parameters ->> 'goalsMinimum'\)::integer,\s+\(definitions\.parameters ->> 'goalsExact'\)::integer\) desc,\s+definitions\.achievement_key\s+limit 1/s);
  assert.match(migration, /when 'team_match_clean_sheet' then source\.clean_sheet/);
  assert.doesNotMatch(migration, /team_match_clean_sheet[^\n]*goals_for\s*>\s*0/);
});

test("the SQL suite covers lifecycle, corrections and Rating V2 isolation", () => {
  assert.match(sqlTest, /1\.\.500/);
  assert.match(sqlTest, /Pre-activation history must not create retroactive achievements/);
  assert.match(sqlTest, /A canonical 0-0 must unlock the collective clean sheet/);
  assert.match(sqlTest, /A player match may never unlock more than its highest scoring tier/);
  assert.match(sqlTest, /Replaying one canonical fact must not duplicate achievements/);
  assert.match(sqlTest, /Achievement progression must leave every Rating V2 field untouched/);
});

test("the existing screen distinguishes achievements, statistics and records", () => {
  assert.match(identityUi, /\["achievements", "Logros"\]/);
  assert.match(identityUi, /\["stats", "Estadísticas"\]/);
  assert.match(identityUi, /\["records", "Récords"\]/);
  assert.match(identityUi, /progression\?\.personalStats/);
  assert.match(identityUi, /progression\?\.teamStats/);
});
