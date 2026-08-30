import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import {
  teamOperationalContinuityLabel,
  teamOperationalIsRelevant,
  teamOperationalScopeLabel,
  teamOperationalStatusLabel,
} from "../app/team-operational-contract";
import {
  assertTeamOperationalV31AuthorityProof,
  loadTeamOperationalV31AuthorityProof,
} from "../scripts/demo-world/team-operational-v31-authority";

const root = process.cwd();
const migrationNames = [
  "20260829221256_team_operational_state_revisions_v1.sql",
  "20260829221258_team_operational_restrictions_continuity_v1.sql",
  "20260829221300_team_operational_reviews_appeals_v1.sql",
  "20260829221302_team_operational_command_authority_v1.sql",
  "20260829221304_team_operational_cross_product_guards_v1.sql",
  "20260829221306_team_operational_read_models_control_center_v1.sql",
  "20260829221309_team_operational_rls_realtime_notifications_v1.sql",
  "20260829221312_team_operational_hardening_indexes_flags_v1.sql",
] as const;

async function source(relativePath: string) {
  return readFile(path.join(root, relativePath), "utf8");
}

test("Team operational labels expose the exact canonical scopes and continuity policies", () => {
  assert.equal(teamOperationalStatusLabel("UNDER_REVIEW"), "En revisión");
  assert.equal(teamOperationalScopeLabel("PUBLIC_DISCOVERY"), "Directorios y búsquedas");
  assert.equal(teamOperationalScopeLabel("TEAM_MEMBERSHIP_ADMINISTRATION"), "Gestión de miembros");
  assert.equal(teamOperationalScopeLabel("PUBLIC_PROFILE"), "Perfil público");
  assert.equal(teamOperationalContinuityLabel("FREEZE_FUTURE_SPORTING_WRITES"), "Nuevas operaciones deportivas detenidas");
  assert.equal(teamOperationalContinuityLabel("PLATFORM_MANAGED_EXIT"), "La plataforma resolverá cada participación afectada");
  assert.equal(teamOperationalIsRelevant({ effectiveStatus: "ACTIVE" }), false);
  assert.equal(teamOperationalIsRelevant({ effectiveStatus: "LIMITED" }), true);
});

test("owner and platform HTTP mutations are centrally gated and payload allowlisted", async () => {
  const [shared, ownerRoute, platformRoute] = await Promise.all([
    source("app/api/team-operational/_shared.ts"),
    source("app/api/team-operational/state/route.ts"),
    source("app/api/platform-admin/teams/[teamId]/route.ts"),
  ]);
  assert.match(shared, /forbiddenServerFields = new Set\(\[/);
  for (const field of ["actorId", "effectiveStatus", "serverSequence", "confirmedRevision"]) {
    assert.match(shared, new RegExp(`"${field}"`));
  }
  assert.match(shared, /clientWriteGateResponse\(request\)/);
  assert.match(shared, /origin !== new URL\(request\.url\)\.origin/);
  assert.match(ownerRoute, /command_pachanga_team_operational_state_v1/);
  assert.match(ownerRoute, /isTeamOperationalOwnerAction\(action\)/);
  assert.match(platformRoute, /isTeamOperationalPlatformAction\(action\)/);
  assert.match(platformRoute, /requireSameOriginMutation\(request\)/);
  assert.doesNotMatch(`${shared}\n${ownerRoute}\n${platformRoute}`, /service_role|NEXT_PUBLIC_.*SECRET/i);
});

test("the client keeps only a read cache and reconciles from PostgreSQL after Realtime", async () => {
  const [client, worker, classifier] = await Promise.all([
    source("app/_components/team-operational-client.tsx"),
    source("app/service-worker-source.ts"),
    source("app/pwa-write-classifier.ts"),
  ]);
  assert.match(client, /disposable read cache and never authorizes a mutation/);
  assert.match(client, /if \(!online\) \{[\s\S]*no guardar acciones del equipo/);
  assert.match(client, /clientWriteFetch\("api:team-operational-command"/);
  assert.match(client, /table: TEAM_OPERATIONAL_REALTIME_TABLE/);
  assert.match(client, /status === "SUBSCRIBED"\) reconcile\(\)/);
  assert.match(client, /if \(!active\) return;[\s\S]*const reconcile/);
  assert.doesNotMatch(client, /queue.*offline|pending.*localStorage|optimistic/i);
  assert.match(worker, /"\/equipo\/estado"/);
  assert.match(classifier, /api:team-operational-command/);
  assert.match(classifier, /api:platform-admin-team-operational/);
});

test("Wave 8B consists of exactly eight forward-only migrations after ledger 204", async () => {
  const files = (await readdir(path.join(root, "supabase/migrations")))
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .sort();
  assert.equal(files.length, 212);
  assert.deepEqual(files.slice(-8), [...migrationNames]);
  const sql = (await Promise.all(migrationNames.map((name) => source(`supabase/migrations/${name}`)))).join("\n");
  assert.match(sql, /command_pachanga_team_operational_state_v1/);
  assert.match(sql, /current_revision bigint not null/);
  assert.match(sql, /server_sequence bigint not null/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, /revoke all on table private\.pachanga_team_operational_states_v1 from public, anon, authenticated/);
  assert.match(sql, /foundation_enabled boolean not null default false/);
  assert.match(sql, /demo_world_v31_enabled boolean not null default false/);
  assert.doesNotMatch(sql, /grant update on table public\.pachanga_groups to authenticated/i);
});

test("cross-product guards protect every Wave 8B boundary without mutating sporting history", async () => {
  const sql = await source("supabase/migrations/20260829221304_team_operational_cross_product_guards_v1.sql");
  for (const boundary of [
    "pachanga_open_matches",
    "pachanga_team_challenges",
    "pachanga_competition_registration_requests",
    "pachanga_competition_entries",
    "pachanga_organizer_access_applications_v1",
    "pachanga_organizer_access_grants_v1",
    "pachanga_competition_official_result_decisions",
  ]) {
    assert.match(sql, new RegExp(boundary));
  }
  assert.match(sql, /TEAM_OPERATIONALLY_RESTRICTED/);
  assert.doesNotMatch(sql, /delete from public\.pachanga_competition_(?:entries|official_result_decisions)/i);
  assert.doesNotMatch(sql, /update public\.pachanga_player_rating_snapshots/i);
});

test("Control Center and Team management expose one role-aware canonical surface", async () => {
  const [ownerUi, home, adminList, adminDetail, adminActions] = await Promise.all([
    source("app/_components/team-operational-client.tsx"),
    source("app/page.tsx"),
    source("app/admin/teams/page.tsx"),
    source("app/admin/teams/[teamId]/page.tsx"),
    source("app/admin/teams/[teamId]/team-operational-admin-actions.tsx"),
  ]);
  assert.match(ownerUi, /Solo el owner puede archivar, restaurar o solicitar una revisión/);
  assert.match(ownerUi, /El detalle de impacto operativo solo está disponible para el owner/);
  assert.match(home, /TeamOperationalHomeCard/);
  assert.match(adminList, /listPlatformTeamOperationalStates/);
  assert.match(adminDetail, /TeamOperationalAdminActions/);
  assert.match(adminActions, /Una revisión no bloquea por sí sola/);
  assert.match(adminActions, /La nota privada no forma parte de las proyecciones/);
});

test("Demo World V3.1 is a sanitized, read-only projection of the isolated simulation", () => {
  const proof = assertTeamOperationalV31AuthorityProof(loadTeamOperationalV31AuthorityProof());
  assert.equal(proof.scenarios.length, 7);
  assert.equal(proof.remoteWrites, 0);
  assert.equal(proof.preservation.automaticForfeitsCreated, 0);
  assert.equal(proof.preservation.automaticNoShowsCreated, 0);
  assert.equal(proof.preservation.ratingSnapshotsUnchanged, true);
  assert.equal(proof.preservation.rewardGrantsUnchanged, true);
  assert.equal(proof.preservation.teamCosmeticsUnchanged, true);
  assert.equal(proof.preservation.playerCosmeticsUnchanged, true);
  assert.ok(Object.values(proof.privacy).every((value) => value === false));
});
