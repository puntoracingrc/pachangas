import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";

const files = Promise.all([
  readFile(new URL("../supabase/migrations/20260803165703_match_guest_invitations_notifications.sql", import.meta.url), "utf8"),
  readFile(new URL("../supabase/migrations/20260803173745_match_guest_market_read_closure.sql", import.meta.url), "utf8"),
  readFile(new URL("../app/mercado/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/notification-center.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/partido-invitado/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
]);

test("guest invitations use central RPCs, revisions and idempotent operation ids", async () => {
  const [migration, , market, notifications, guestPage] = await files;
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
  const [migration, closure, market, , guestPage] = await files;
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
  const [migration, , market, notifications, guestPage, layout] = await files;
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
