import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export function createR6bPostgresHarness(label) {
  const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
  const adminUrl = process.env.TOURNAMENT_GROUP_STAGE_DATABASE_URL
    || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
  const parsedAdminUrl = new URL(adminUrl);
  if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsedAdminUrl.hostname)) {
    throw new Error("R6B_LOCAL_DATABASE_REQUIRED");
  }

  const suffix = randomBytes(5).toString("hex");
  const prefix = `pachangas_r6b_${safeIdentifier(label)}_${suffix}`;
  const infrastructureDump = resolve(tmpdir(), `${prefix}-infrastructure.sql`);
  const databases = new Set();
  const allMigrations = readdirSync(resolve(root, "supabase/migrations"))
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .sort();
  const migrations = allMigrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);

  assert.equal(
    migrations.length + manifest.absorbedMigrations.length,
    169,
    "R6B must bootstrap the exact 169-migration repository ledger",
  );

  function run(binary, args, step, input = undefined) {
    const result = spawnSync(binary, args, {
      cwd: root,
      encoding: "utf8",
      env: process.env,
      input,
      maxBuffer: 512 * 1024 * 1024,
    });
    if (result.error) throw result.error;
    if (result.status !== 0) {
      throw new Error(`${step} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
    }
    return (result.stdout ?? "").trim();
  }

  function targetUrl(databaseName) {
    const value = new URL(adminUrl);
    value.pathname = `/${databaseName}`;
    value.searchParams.set("sslmode", "disable");
    return value.toString();
  }

  function admin(sql, step = "R6B database administration") {
    return run("psql", ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], step);
  }

  function query(databaseName, sql, step = "R6B database query") {
    return run("psql", [
      "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql,
    ], step);
  }

  function psql(databaseName, args, step, input = undefined) {
    return run("psql", ["-X", "-w", "-v", "ON_ERROR_STOP=1", targetUrl(databaseName), ...args], step, input);
  }

  function databaseName(name) {
    return `${prefix}_${safeIdentifier(name)}`;
  }

  function exportInfrastructure() {
    run("pg_dump", [
      "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
      "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
      "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
      "--file", infrastructureDump, adminUrl,
    ], "export R6B Supabase infrastructure");
  }

  function bootstrap(databaseNameValue) {
    if (!databases.size) exportInfrastructure();
    admin(`create database ${databaseNameValue} template template0`, "create R6B database");
    databases.add(databaseNameValue);
    psql(databaseNameValue, ["-q", "-f", infrastructureDump], "restore R6B infrastructure");
    query(databaseNameValue, "create publication supabase_realtime;", "create R6B Realtime publication");
    const args = ["-q", "--single-transaction", "-f", resolve(root, manifest.baselinePath)];
    for (const migration of migrations) args.push("-f", resolve(root, "supabase/migrations", migration));
    psql(databaseNameValue, args, "bootstrap R6B database");
    const ledgerRows = allMigrations.map((migration) => {
      const version = migration.slice(0, 14);
      const name = migration.slice(15, -4);
      return `('${version}', null, '${name.replaceAll("'", "''")}')`;
    }).join(",");
    query(databaseNameValue, `
      create schema if not exists supabase_migrations;
      create table if not exists supabase_migrations.schema_migrations(
        version text primary key,
        statements text[],
        name text
      );
      insert into supabase_migrations.schema_migrations(version, statements, name)
      values ${ledgerRows};
    `, "record R6B ephemeral migration ledger");
    assert.equal(
      Number(query(databaseNameValue, "select count(*) from supabase_migrations.schema_migrations;")),
      169,
      "R6B bootstrap ledger mismatch",
    );
    return databaseNameValue;
  }

  function clone(sourceDatabase, name) {
    const cloneName = databaseName(name);
    admin(
      `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
       join pg_roles roles on roles.rolname=activity.usename
       where activity.datname='${sourceDatabase}'
         and activity.pid<>pg_backend_pid()
         and not roles.rolsuper;`,
      "close R6B template connections",
    );
    admin(`create database ${cloneName} template ${sourceDatabase}`, "clone R6B database");
    databases.add(cloneName);
    return cloneName;
  }

  function drop(databaseNameValue) {
    if (!databases.has(databaseNameValue)) return;
    admin(`alter database ${databaseNameValue} with allow_connections false`, "close R6B database");
    admin(
      `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
       join pg_roles roles on roles.rolname=activity.usename
       where activity.datname='${databaseNameValue}'
         and activity.pid<>pg_backend_pid()
         and not roles.rolsuper;`,
      "close R6B database connections",
    );
    for (let attempt = 0; attempt < 50; attempt += 1) {
      const connectionCount = Number(admin(
        `select count(*) from pg_stat_activity where datname='${databaseNameValue}';`,
        "inspect R6B database connections",
      ));
      if (connectionCount === 0) break;
      spawnSync("sleep", ["0.1"]);
      if (attempt === 49) {
        const inventory = admin(
          `select concat_ws(':', pid, usename, state, coalesce(wait_event_type,''), coalesce(wait_event,''))
           from pg_stat_activity where datname='${databaseNameValue}' order by pid;`,
          "inventory R6B database connections",
        );
        throw new Error(`R6B_EPHEMERAL_CONNECTIONS_REMAIN:${databaseNameValue}:${inventory}`);
      }
    }
    admin(`drop database if exists ${databaseNameValue}`, "drop R6B database");
    databases.delete(databaseNameValue);
  }

  function cleanup() {
    for (const name of [...databases].reverse()) drop(name);
    rmSync(infrastructureDump, { force: true });
  }

  return {
    adminUrl,
    bootstrap,
    cleanup,
    clone,
    databaseName,
    drop,
    psql,
    query,
    root,
    run,
    targetUrl,
  };
}

function safeIdentifier(value) {
  const normalized = String(value).toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_+|_+$/g, "");
  if (!normalized) throw new Error("R6B_DATABASE_LABEL_REQUIRED");
  return normalized.slice(0, 24);
}
