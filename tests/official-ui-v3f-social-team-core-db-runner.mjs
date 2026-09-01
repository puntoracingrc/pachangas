import { spawnSync } from "node:child_process";
import process from "node:process";

const databaseUrl = process.env.SOCIAL_TEAM_V3F_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const migrations = [
  "20260901214523_social_profile_foundation_v1.sql",
  "20260901214524_social_team_core_evidence_v1.sql",
  "20260901214525_atomic_social_team_creation_v1.sql",
  "20260901214526_team_player_invitations_v2.sql",
  "20260901214527_social_team_read_models_rls_flags_v1.sql",
].flatMap((name) => ["-f", `supabase/migrations/${name}`]);

const result = spawnSync("psql", [
  "-X", "-w", databaseUrl, "-v", "ON_ERROR_STOP=1", "-c", "begin",
  ...migrations,
  "-f", "tests/official-ui-v3f-social-team-core-db.sql",
  "-c", "rollback",
], { encoding: "utf8", stdio: "pipe" });

if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.status !== 0 || /(?:^|\n)psql:.*ERROR:/m.test(result.stderr ?? "")) {
  process.exit(result.status && result.status > 0 ? result.status : 1);
}

process.stdout.write("Official UI V3F PostgreSQL authority checks passed with rollback.\n");
