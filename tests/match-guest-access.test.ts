import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";

const migrationsDirectory = new URL("../supabase/migrations/", import.meta.url);

async function readMigration(name: string) {
  const migration = (await readdir(migrationsDirectory)).find((entry) => entry.endsWith(`_${name}.sql`));
  assert.ok(migration, `Missing migration ${name}`);
  return readFile(new URL(migration, migrationsDirectory), "utf8");
}

const files = Promise.all([
  readMigration("match_guest_invitations_notifications"),
  readMigration("match_guest_market_read_closure"),
  readMigration("match_link_invitation_role_hardening"),
  readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/invitacion-partido/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/mercado/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/notification-center.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/partido-invitado/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
]);

test("guest invitations use central RPCs, revisions and idempotent operation ids", async () => {
  const [migration, , , , , market, notifications, guestPage] = await files;
  for (const rpc of [
    "create_pachanga_match_invitation_v1",
    "respond_pachanga_match_invitation_v1",
    "cancel_pachanga_match_invitation_v1",
    "leave_pachanga_guest_match_v1",
    "review_pachanga_guest_withdrawal_v1",
    "cancel_my_pachanga_open_match_request_v1",
  ]) {
    assert.match(migration, new RegExp(`create or replace function public\\.${rpc}`));
    assert.equal(
      classifySupabaseWrite(`https://demo.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }),
      `rpc:${rpc}`,
    );
  }
  assert.match(market, /operation_id: crypto\.randomUUID\(\)/);
  assert.match(market, /expected_match_revision/);
  assert.match(notifications, /expected_invitation_revision/);
  assert.match(notifications, /review_pachanga_open_match_request_authoritative_v2/);
  assert.match(notifications, /requestGroupRevision/);
  assert.match(guestPage, /expected_snapshot_revision/);
  assert.doesNotMatch(guestPage, /localStorage|sessionStorage/);
});

test("public market and guest reads expose canonical safe models only", async () => {
  const [migration, closure, , , , market, , guestPage] = await files;
  assert.match(migration, /create or replace function public\.search_pachanga_open_matches_v1/);
  assert.match(migration, /create or replace function public\.get_pachanga_guest_match_snapshot_v1/);
  assert.match(market, /search_pachanga_open_matches_v1/);
  assert.doesNotMatch(market, /\.from\("pachanga_open_matches"\)/);
  assert.match(closure, /revoke select on table public\.pachanga_open_matches from anon, authenticated/);
  assert.doesNotMatch(guestPage, /phone|telefono|birthDate|ownerUserId|ratingVotes|teamCode|paid|payer/i);
  assert.match(guestPage, /No tienes acceso al grupo, pagos, teléfonos ni controles de administración/);
  assert.match(migration, /round\(open_matches\.lat::numeric, 2\)/);
  assert.doesNotMatch(migration.match(/create or replace function public\.search_pachanga_open_matches_v1[\s\S]*?revoke all/)?.[0] ?? "", /match_url|place_id|source_match_id/);
});

test("Realtime invalidates only the affected guest entities and revoked access closes the view", async () => {
  const [migration, , , , , market, notifications, guestPage, layout] = await files;
  assert.match(layout, /<NotificationCenter \/>/);
  assert.match(notifications, /table: "pachanga_user_notifications"/);
  assert.match(market, /table: "pachanga_open_match_requests"/);
  assert.match(guestPage, /table: "pachanga_match_guest_access"/);
  assert.match(guestPage, /table: "pachanga_match_guest_snapshots"/);
  assert.match(guestPage, /filter: `id=eq\.\$\{initialState\.snapshotId\}`/);
  assert.match(guestPage, /state\.access\.status !== "accepted"/);
  assert.match(migration, /alter table public\.pachanga_match_guest_snapshots replica identity full/);
  assert.match(migration, /alter table public\.pachanga_match_guest_access replica identity full/);
});

test("withdrawal evidence is isolated from Rating V2 and has no automatic sanction", async () => {
  const [migration] = await files;
  const reviewFunction = migration.match(/create or replace function public\.review_pachanga_guest_withdrawal_v1[\s\S]*?revoke all/)?.[0] ?? "";
  assert.match(reviewFunction, /affectsSportRating', false/);
  assert.match(reviewFunction, /next_status not in \('confirmed', 'dismissed'\)/);
  assert.doesNotMatch(reviewFunction, /rating_votes|current_facets|calibrated_facets|social_ban|suspension/);
  assert.doesNotMatch(reviewFunction, /'playerId', selected_review\.player_id/);
  assert.match(migration, /guest_display_name \|\| ' ha abandonado'/);
});

test("canonical ordering never relies on a tied timestamp", async () => {
  const [migration] = await files;
  assert.match(migration, /order by notifications\.server_sequence desc, notifications\.id desc/);
  assert.match(migration, /order by requests\.server_sequence desc, requests\.id desc/);
  assert.match(migration, /order by invitations\.server_sequence desc, invitations\.id desc/);
  assert.doesNotMatch(migration, /order by created_at desc/i);
  assert.match(migration, /private\.pachanga_notification_operation_receipts/);
});

test("match sharing is separate from group and admin invitations", async () => {
  const [, , hardening, home, linkPage] = await files;
  const [sharedMatchRoute, groupInviteRoute, adminInviteRoute, matchInviteRoute] = await Promise.all([
    readFile(new URL("../app/partido/[teamCode]/[matchId]/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/invitacion/grupo/[token]/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/invitacion/admin/[token]/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/invitacion/partido/[token]/page.tsx", import.meta.url), "utf8"),
  ]);

  assert.match(home, /create_pachanga_match_link_invitation_v1/);
  assert.match(home, /Compartir partido/);
  assert.match(home, /Invitar al partido/);
  assert.match(home, /<button type="button" onClick=\{\(\) => void copyTeamInvite\(\)\} disabled=\{!remoteGroupId\}>[\s\S]*Copiar invitación[\s\S]*<\/button>/);
  assert.match(home, /Invitar como admin \(no owner\)/);
  assert.match(home, /\.eq\("user_id", memberUserId\)/);
  assert.match(home, /String\(group\.owner_id \?\? ""\) === memberUserId/);
  assert.match(home, /Este enlace antiguo mezclaba una invitación de grupo con un partido/);
  assert.doesNotMatch(
    home.match(/function prettyTeamParams[\s\S]*?return params;/)?.[0] ?? "",
    /params\.set\("i"/,
  );
  assert.match(
    home.match(/function currentTeamInviteUrl[\s\S]*?\n  }/)?.[0] ?? "",
    /\/invitacion\/grupo\/\$\{encodeURIComponent\(compactUuid\(currentTeam\.inviteToken\)\)\}/,
  );
  assert.match(home, /\/partido\/\$\{encodeURIComponent\(currentTeam\.teamCode\)\}/);
  assert.match(home, /No puedes ver este partido porque no perteneces al grupo/);
  assert.match(home, /const matchMemberShareBox = !matchFinalized && hasRealTeam/);
  assert.match(home, /const matchAdminInviteBox = !matchFinalized && hasRealTeam && canManageTeam/);
  assert.match(home, /match-admin-invite-panel[\s\S]*\{matchAdminInviteBox\}/);
  assert.doesNotMatch(
    home.match(/async function copySharedMatchLink[\s\S]*?\n  }/)?.[0] ?? "",
    /create_pachanga_match_link_invitation_v1/,
  );
  assert.match(sharedMatchRoute, /<Home entryRoute=\{\{ matchId, teamCode \}\}/);
  assert.match(groupInviteRoute, /inviteToken: token/);
  assert.match(adminInviteRoute, /adminInviteToken: token/);
  assert.match(matchInviteRoute, /MatchInvitationContent invitationToken=\{token\}/);
  assert.doesNotMatch(linkPage, /join_pachanga_team|accept_pachanga_admin_invite|pachanga_group_members/);
  assert.match(linkPage, /No te hace miembro, admin ni owner del grupo/);

  for (const rpc of [
    "create_pachanga_match_link_invitation_v1",
    "respond_pachanga_match_link_invitation_v1",
  ]) {
    assert.equal(
      classifySupabaseWrite(`https://demo.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }),
      `rpc:${rpc}`,
    );
  }

  assert.match(hardening, /revoke all on table public\.pachanga_match_link_invitations from public, anon, authenticated/);
  assert.match(hardening, /grant execute on function public\.get_pachanga_match_link_invitation_v1\(uuid\)[\s\S]*to anon, authenticated/);
  assert.match(hardening, /if public\.is_pachanga_group_member\(selected_invitation\.group_id\) then/);
  assert.doesNotMatch(
    hardening.match(/create or replace function public\.respond_pachanga_match_link_invitation_v1[\s\S]*?revoke all/)?.[0] ?? "",
    /insert into public\.pachanga_group_members/,
  );
});
