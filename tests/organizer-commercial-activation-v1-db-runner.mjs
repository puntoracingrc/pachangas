import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const databaseUrl = process.env.ORGANIZER_BILLING_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(databaseUrl).hostname)) {
  throw new Error("ORGANIZER_COMMERCIAL_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

function psql(args, label) {
  const result = spawnSync(process.env.PSQL_BIN || "psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", ...args,
  ], { cwd: root, encoding: "utf8", env: process.env, maxBuffer: 96 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

const ledger = psql(["-Atq", databaseUrl, "-c",
  "select count(*)||'|'||max(version) from supabase_migrations.schema_migrations"], "read Wave 7C ledger");
assert.equal(ledger, "197|20260829080812");

const output = psql([
  "-Atq", databaseUrl, "-c", "begin",
  "-f", resolve(root, "tests/organizer-plans-stripe-billing-v1-fixture.sql"),
  "-f", resolve(root, "tests/organizer-commercial-activation-v1-db.sql"),
  "-c", "rollback",
], "Wave 7C SQL, RLS, idempotency, TEST and live-gate suite");
assert.match(output, /ORGANIZER_COMMERCIAL_ACTIVATION_V1_DB_OK/);

process.stdout.write(`${JSON.stringify({
  commercialDecisions: 3,
  database: "local",
  finalLedger: 197,
  liveObjectsCreated: 0,
  migrations: 6,
  sqlRlsIdempotencyActivation: "PASS",
  testPriceMappings: 4,
})}\n`);
