import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const manifest = JSON.parse(readFileSync("supabase/baselines/manifest.json", "utf8"));
const baseline = readFileSync(manifest.baselinePath);

test("the immutable baseline absorbs exactly the historical pre-Rating migrations", () => {
  const historicalVersions = readdirSync("supabase/migrations")
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .map((name) => name.slice(0, 14))
    .filter((version) => version <= manifest.absorbsThrough)
    .sort();

  assert.equal(manifest.baselineVersion, "20260731080738");
  assert.equal(manifest.firstIncrementalMigration, "20260803053357");
  assert.equal(manifest.absorbedMigrations.length, 36);
  assert.deepEqual([...manifest.absorbedMigrations].sort(), historicalVersions);
  assert.equal(createHash("sha256").update(baseline).digest("hex"), manifest.sha256);
  assert.match(baseline.toString(), /create table if not exists public\.pachanga_admin_invites/i);
  assert.doesNotMatch(baseline.toString(), /create schema if not exists simulation/i);
  assert.equal(existsSync("supabase/pachangas.sql"), false);
});

test("fresh bootstrap and schema export fail closed for remote databases", () => {
  for (const script of ["scripts/database/bootstrap-fresh.mjs", "scripts/database/export-schema-contract.mjs"]) {
    const result = spawnSync(process.execPath, [script, "--db-url", "postgresql://postgres:secret@db.example.com/product"], {
      encoding: "utf8",
    });
    assert.notEqual(result.status, 0, script);
    assert.match(result.stderr, /LOCAL_DATABASE_REQUIRED/, script);
  }
});

test("local Supabase reset cannot accidentally replay the unsupported legacy chain", () => {
  const config = readFileSync("supabase/config.toml", "utf8");
  const bootstrapScript = readFileSync("scripts/database/bootstrap-fresh.mjs", "utf8");
  assert.match(config, /\[db\.migrations\][\s\S]*?enabled = false/);
  assert.match(config, /baselines\/20260731080738_pachangas_product_baseline\.sql/);
  assert.match(bootstrapScript, /"--local"/);
  assert.doesNotMatch(bootstrapScript, /migration[\s\S]{0,100}"--db-url"/);
  assert.match(readFileSync("package.json", "utf8"), /"db:bootstrap:fresh": "node scripts\/database\/bootstrap-fresh\.mjs"/);
});

test("fresh bootstrap rejects a local URL that does not belong to the selected Supabase workdir", () => {
  const binDir = mkdtempSync(join(tmpdir(), "pachangas-bootstrap-bin-"));
  const supabaseStub = join(binDir, "supabase");
  const psqlMarker = join(binDir, "psql-was-called");
  const psqlStub = join(binDir, "psql");

  try {
    writeFileSync(supabaseStub, "#!/bin/sh\nprintf '%s\\n' '{\"DB_URL\":\"postgresql://postgres:postgres@127.0.0.1:65432/postgres\"}'\n");
    writeFileSync(psqlStub, `#!/bin/sh\ntouch '${psqlMarker}'\nexit 99\n`);
    chmodSync(supabaseStub, 0o755);
    chmodSync(psqlStub, 0o755);

    const result = spawnSync(process.execPath, [
      "scripts/database/bootstrap-fresh.mjs",
      "--db-url",
      "postgresql://postgres:postgres@127.0.0.1:55322/postgres",
    ], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${binDir}:${process.env.PATH}` },
    });

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /BOOTSTRAP_LOCAL_PROJECT_DATABASE_MISMATCH/);
    assert.equal(existsSync(psqlMarker), false);
  } finally {
    rmSync(binDir, { recursive: true, force: true });
  }
});

test("fresh bootstrap rejects migration drift in an alternate local workdir", () => {
  const workdir = mkdtempSync(join(tmpdir(), "pachangas-bootstrap-workdir-"));
  const binDir = join(workdir, "bin");
  const commandMarker = join(workdir, "external-command-was-called");

  try {
    mkdirSync(binDir);
    cpSync("supabase/migrations", join(workdir, "supabase/migrations"), { recursive: true });
    const firstMigration = readdirSync(join(workdir, "supabase/migrations")).sort()[0];
    writeFileSync(join(workdir, "supabase/migrations", firstMigration), "-- deliberate drift\n", { flag: "a" });
    for (const command of ["supabase", "psql"]) {
      const stub = join(binDir, command);
      writeFileSync(stub, `#!/bin/sh\ntouch '${commandMarker}'\nexit 99\n`);
      chmodSync(stub, 0o755);
    }

    const result = spawnSync(process.execPath, [
      "scripts/database/bootstrap-fresh.mjs",
      "--db-url",
      "postgresql://postgres:postgres@127.0.0.1:55322/postgres",
      "--supabase-workdir",
      workdir,
    ], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${binDir}:${process.env.PATH}` },
    });

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /BOOTSTRAP_WORKDIR_MIGRATION_HASH_MISMATCH/);
    assert.equal(existsSync(commandMarker), false);
  } finally {
    rmSync(workdir, { recursive: true, force: true });
  }
});
