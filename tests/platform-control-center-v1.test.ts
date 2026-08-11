import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { sanitizeClientErrorRoute, sanitizeClientErrorTelemetry } from "../app/api/client-error-telemetry/_contract";

const root = new URL("../", import.meta.url);

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

async function filesBelow(path: string): Promise<string[]> {
  const directory = new URL(path, root);
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const relative = `${path.replace(/\/$/, "")}/${entry.name}`;
    return entry.isDirectory() ? filesBelow(relative) : [relative];
  }));
  return nested.flat();
}

test("platform RBAC is private, explicit and separate from team roles", async () => {
  const [migration, contract] = await Promise.all([
    source("supabase/migrations/20260811150309_platform_control_center_v1.sql"),
    source("app/admin/_lib/platform-contract.ts"),
  ]);
  for (const role of ["platform_owner", "platform_admin", "moderator", "support", "finance", "ops"]) {
    assert.match(migration, new RegExp(`'${role}'`));
    assert.match(contract, new RegExp(`"${role}"`));
  }
  assert.match(migration, /private\.pachanga_platform_admin_roles/);
  assert.match(migration, /private\.pachanga_platform_require_v1/);
  assert.match(migration, /revoke all on table private\.pachanga_platform_admin_roles from public, anon, authenticated/);
  assert.doesNotMatch(migration, /team owner.*platform_owner|team admin.*platform_admin/i);
  assert.match(migration, /when 'moderator' then jsonb_build_array\([\s\S]*?'moderation\.write'/);
  const moderatorCapabilities = migration.match(/when 'moderator' then jsonb_build_array\(([\s\S]*?)\)\s*when 'support'/)?.[1] ?? "";
  assert.doesNotMatch(moderatorCapabilities, /users\.pii\.read|billing\.read|flags\.write/);
  const supportCapabilities = migration.match(/when 'support' then jsonb_build_array\(([\s\S]*?)\)\s*when 'finance'/)?.[1] ?? "";
  assert.match(supportCapabilities, /users\.pii\.read/);
  assert.doesNotMatch(supportCapabilities, /flags\.write|moderation\.write/);
});

test("all platform pages and APIs authorize on the server", async () => {
  const pageFiles = (await filesBelow("app/admin"))
    .filter((path) => path.endsWith("/page.tsx") && !path.includes("/_components/"));
  for (const path of pageFiles) {
    const content = await source(path);
    if (path.endsWith("simulation-world/page.tsx")) assert.match(content, /requirePlatformPage\("labs\.read"\)/, path);
    else assert.match(content, /requirePlatformPage\("[a-z.]+"\)/, path);
  }
  const routeFiles = (await filesBelow("app/api/platform-admin")).filter((path) => path.endsWith("/route.ts"));
  for (const path of routeFiles) {
    const content = await source(path);
    if (path.endsWith("/session/route.ts")) assert.match(content, /verifyPlatformToken\(/, path);
    else assert.match(content, /requirePlatformRequest\(request, "[a-z.]+"\)/, path);
    assert.match(content, /dynamic = "force-dynamic"/, path);
    assert.match(content, /revalidate = 0/, path);
    if (/export async function POST/.test(content)) assert.match(content, /requireSameOriginMutation\(request\)/, path);
  }
});

test("sensitive mutations are revisioned, reasoned, idempotent and audited", async () => {
  const migration = await source("supabase/migrations/20260811150309_platform_control_center_v1.sql");
  assert.match(migration, /pachanga_platform_admin_replay_v1/);
  assert.match(migration, /pg_advisory_xact_lock\([\s\S]*platform-admin-operation/);
  for (const action of [
    "platform_owner.bootstrap",
    "platform_role.set",
    "platform_user_state.set",
    "platform_flag.set",
    "platform_announcement.create",
    "platform_announcement.send",
    "platform_incident.set",
  ]) assert.match(migration, new RegExp(`'${action.replaceAll(".", "\\.")}'`));
  assert.match(migration, /operationId already belongs to a different platform action/);
  assert.match(migration, /Cannot remove the last platform owner/);
  assert.match(migration, /Administrators cannot suspend themselves/);
  assert.match(migration, /private\.pachanga_set_team_cosmetic_rewards_enabled_v1\(next_enabled, operation_id, 1\)/);
  assert.match(migration, /private\.pachanga_platform_sanitize_error_v1\(events\.error_message\)/);
  assert.doesNotMatch(migration, /delete from auth\.users|delete from public\.pachanga_groups|delete from public\.pachanga_match_read_model/i);
});

test("large lists are bounded and filtered before reaching the browser", async () => {
  const [migration, data] = await Promise.all([
    source("supabase/migrations/20260811150309_platform_control_center_v1.sql"),
    source("app/admin/_lib/platform-data.ts"),
  ]);
  assert.match(migration, /list_pachanga_platform_users_v1/);
  assert.match(migration, /list_pachanga_platform_teams_v1/);
  assert.match(migration, /list_pachanga_platform_matches_v1/);
  assert.match(migration, /list_pachanga_platform_challenges_v1/);
  assert.match(migration, /least\(greatest\(coalesce\(page_size, 30\), 10\), 100\)/);
  assert.match(migration, /safe_market = 'enabled'/);
  assert.match(migration, /locality_filter/);
  assert.match(migration, /owner_filter/);
  assert.match(migration, /minimum_level/);
  assert.match(migration, /active_restriction_count/);
  assert.match(migration, /can_read_billing := actor_role in \('platform_owner', 'platform_admin', 'finance'\)/);
  assert.match(migration, /users\.raw_user_meta_data ->> 'full_name'/);
  assert.match(data, /rpcOrThrow<JsonRecord>\(session\.client, "list_pachanga_platform_teams_v1"/);
  assert.match(data, /rpcOrThrow<JsonRecord>\(session\.client, "list_pachanga_platform_matches_v1"/);
  assert.match(data, /rpcOrThrow<JsonRecord>\(session\.client, "list_pachanga_platform_challenges_v1"/);
  assert.doesNotMatch(data, /\.filter\(\(group\) => input\.market/);
});

test("the administrative ledger is server-paginated", async () => {
  const audit = await source("app/admin/audit/page.tsx");
  assert.match(audit, /paginationFromSearchParams\(params, 50\)/);
  assert.match(audit, /getPlatformSection\(session, "audit", page, pageSize\)/);
  assert.match(audit, /<Pagination page=\{page\} pageSize=\{pageSize\}/);
});

test("overview metrics consume the canonical response keys", async () => {
  const [overview, repair] = await Promise.all([
    source("app/admin/page.tsx"),
    source("supabase/migrations/20260811172700_platform_control_center_overview_restriction_fix.sql"),
  ]);
  assert.match(overview, /const market = record\(overview\.market\)/);
  assert.match(overview, /count\(matches, "total"\)/);
  assert.match(overview, /count\(matches, "changedInPeriod"\)/);
  assert.match(overview, /count\(challenges, "createdInPeriod"\)/);
  assert.match(overview, /count\(market, "players"\)/);
  assert.doesNotMatch(overview, /count\(matches, "created"\)/);
  assert.doesNotMatch(overview, /count\(players, "market"\)/);
  assert.match(repair, /restrictions\.effective_until/);
  assert.doesNotMatch(repair, /restrictions\.ends_at/);
});

test("client telemetry accepts only a bounded non-PII contract", () => {
  const valid = {
    appVersion: "2.0.0+abc123",
    browserFamily: "Chrome",
    category: "render",
    fingerprint: "a".repeat(64),
    operationId: "aa100000-0000-4000-8000-000000000001",
    platform: "Android",
    route: "/partido",
  };
  assert.deepEqual(sanitizeClientErrorTelemetry(valid), valid);
  assert.equal(sanitizeClientErrorTelemetry({ ...valid, email: "persona@example.test" }), null);
  assert.equal(sanitizeClientErrorTelemetry({ ...valid, message: "contenido escrito por una persona" }), null);
  assert.equal(sanitizeClientErrorTelemetry({ ...valid, route: "/partido?token=secret" }), null);
  assert.equal(sanitizeClientErrorTelemetry({ ...valid, fingerprint: "raw stack trace" }), null);
  assert.equal(sanitizeClientErrorRoute("/invitacion/grupo/sensitive-invitation-token"), "/invitacion/grupo/:token");
  assert.equal(sanitizeClientErrorRoute("/partido/A4A5E5B5/private-match-id"), "/partido/:teamCode/:matchId");
  assert.equal(sanitizeClientErrorRoute("/admin/users/173da3e5-3dbc-4045-a194-91833823a587"), "/admin/users/:userId");
  assert.equal(sanitizeClientErrorRoute("/support/person@example.test"), "/support/:segment");
  assert.equal(
    sanitizeClientErrorTelemetry({ ...valid, route: "/invitacion/partido/sensitive-invitation-token" })?.route,
    "/invitacion/partido/:token",
  );
});

test("administrative secrets remain server-only", async () => {
  const appFiles = (await filesBelow("app")).filter((path) => /\.(ts|tsx)$/.test(path));
  const forbidden = /SUPABASE_SERVICE_ROLE_KEY|STRIPE_ADMIN_RESTRICTED_KEY|STRIPE_SECRET_KEY|VERCEL_ADMIN_TOKEN|SUPABASE_MANAGEMENT_ACCESS_TOKEN/;
  for (const path of appFiles) {
    const content = await source(path);
    if (!/^\s*["']use client["'];/m.test(content)) continue;
    assert.doesNotMatch(content, forbidden, path);
    assert.doesNotMatch(content, /platformServiceClient|platform-external|platform-auth/, path);
  }
  const environment = await source(".env.example");
  assert.doesNotMatch(environment, /NEXT_PUBLIC_(SUPABASE_SERVICE_ROLE_KEY|STRIPE|VERCEL_ADMIN|SUPABASE_MANAGEMENT)/);
});

test("detail APIs redact billing identifiers and PII in the server data layer", async () => {
  const data = await source("app/admin/_lib/platform-data.ts");
  assert.match(data, /const canReadBilling = session\.access\.capabilities\.includes\("billing\.read"\)/);
  assert.match(data, /birth_date: canReadPii \? profile\.birth_date \?\? null : null/);
  assert.match(data, /stripe_customer_id: canReadBilling \? team\.stripe_customer_id : null/);
  assert.match(data, /stripe_subscription_id: canReadBilling \? groupResult\.data\.stripe_subscription_id : null/);
});

test("unknown database errors are not reflected to the browser", async () => {
  const auth = await source("app/admin/_lib/platform-auth.ts");
  assert.match(auth, /La operacion administrativa no pudo completarse\./);
  assert.doesNotMatch(auth, /message\.slice\(0, 240\)/);
});

test("owner bootstrap requires an explicit production release contract before reading credentials", async () => {
  const script = fileURLToPath(new URL("scripts/platform-admin/bootstrap-owner.mjs", root));
  const result = spawnSync(process.execPath, [script], {
    encoding: "utf8",
    env: { ...process.env, PACHANGAS_ENVIRONMENT: "production", VERCEL_ENV: "production" },
  });
  assert.notEqual(result.status, 0);
  assert.match(`${result.stdout}\n${result.stderr}`, /requires explicit confirmation/);

  const incomplete = spawnSync(process.execPath, [
    script,
    "--confirm-production-bootstrap", "I_UNDERSTAND_PRODUCTION",
  ], {
    encoding: "utf8",
    env: { ...process.env, PACHANGAS_ENVIRONMENT: "production", VERCEL_ENV: "production" },
  });
  assert.notEqual(incomplete.status, 0);
  assert.match(`${incomplete.stdout}\n${incomplete.stderr}`, /valid --email/);

  const sourceText = await source("scripts/platform-admin/bootstrap-owner.mjs");
  assert.match(sourceText, /--expected-project-ref/);
  assert.match(sourceText, /Production bootstrap requires an explicit --operation-id UUID/);
  assert.match(sourceText, /auth\.admin\.listUsers/);
  assert.match(sourceText, /user\.email === email/);
  assert.match(sourceText, /identity\.provider\?\.toLowerCase\(\) === provider/);
  assert.match(sourceText, /email_confirmed_at/);
  assert.match(sourceText, /Bootstrap replay did not converge/);
  assert.match(sourceText, /get_pachanga_platform_access_service_v1/);
  assert.doesNotMatch(sourceText, /puntoracingrc@gmail\.com/);
});

test("admin responses and routes are private and noindex", async () => {
  const [auth, config, layout, data, policy] = await Promise.all([
    source("app/admin/_lib/platform-auth.ts"),
    source("next.config.ts"),
    source("app/admin/layout.tsx"),
    source("app/admin/_lib/platform-data.ts"),
    source("app/api/client-policy/_contract.ts"),
  ]);
  assert.match(auth, /Object\.entries\(noStoreHeaders\)/);
  assert.match(policy, /private, no-store/);
  assert.match(auth, /X-Robots-Tag/);
  assert.match(config, /source: "\/admin\/:path\*"/);
  assert.match(config, /source: "\/api\/platform-admin\/:path\*"/);
  assert.match(layout, /robots: \{ follow: false, index: false \}/);
  assert.match(data, /sanitizeChallengeSnapshot/);
  assert.match(data, /group: \{ id: groupResult\.data\.id, name: groupResult\.data\.name/);
  assert.doesNotMatch(data, /return \{[\s\S]{0,100}payload: groupResult\.data\.payload/);
});

test("missing infrastructure integrations degrade to UNKNOWN with short server caches", async () => {
  const external = await source("app/admin/_lib/platform-external.ts");
  assert.match(external, /state: "UNKNOWN"/);
  assert.match(external, /cached\("supabase-management", 90_000/);
  assert.match(external, /cached\("vercel-health", 60_000/);
  assert.match(external, /cached\("stripe-health", 60_000/);
  assert.match(external, /connectorFailureReason\(error\)/);
  assert.doesNotMatch(external, /unknown\("(?:Stripe API|Vercel REST API|Supabase Management API)", error instanceof Error \? error\.message/);
  assert.match(external, /limitsAvailable: false/);
  assert.match(external, /stripe: stripeSummary/);
  assert.doesNotMatch(external, /stripe: stripe,[\s\S]{0,80}supabase/);
  assert.doesNotMatch(external, /state: "OK"[^\n]*Integración no configurada/);
});

test("the shell is responsive without turning platform tools into team admin", async () => {
  const [styles, shell, conduct] = await Promise.all([
    source("app/admin/platform-admin.module.css"),
    source("app/admin/_components/platform-shell.tsx"),
    source("app/admin/conduct/page.tsx"),
  ]);
  assert.match(styles, /@media \(max-width: 760px\)/);
  assert.match(styles, /@media \(orientation: landscape\) and \(max-height:/);
  assert.match(styles, /overflow-x: hidden/);
  assert.match(styles, /\.adminRoot :is\(button, a, input, select, textarea\):focus-visible/);
  assert.match(shell, /environmentBadge/);
  assert.match(shell, /platformNavigation\.filter/);
  assert.match(conduct, /requirePlatformPage\("moderation\.read"\)/);
  assert.doesNotMatch(conduct, /app_metadata|pachangas_security_role/);
});
