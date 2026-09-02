import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";
import {
  normalizeSocialInboxItem,
  normalizeSocialInboxSnapshot,
  safeSocialInboxDeepLink,
  socialInboxGroup,
} from "../app/social-inbox-contract";

const read = (path: string) => readFile(new URL(path, import.meta.url), "utf8");
const [
  migration,
  receiptIndexMigration,
  layout,
  shell,
  inboxPage,
  provider,
  cache,
  settings,
  legacySettings,
  serviceWorker,
  home,
  team,
  market,
  demo,
  demoInbox,
  demoInboxStyles,
  demoContract,
  packageJson,
  concurrencyTest,
] = await Promise.all([
  read("../supabase/migrations/20260902064632_social_inbox_authority_v1.sql"),
  read("../supabase/migrations/20260902102800_social_inbox_receipt_notification_index_v1.sql"),
  read("../app/layout.tsx"),
  read("../app/_components/official-product-shell-v2.tsx"),
  read("../app/avisos/page.tsx"),
  read("../app/social-inbox-provider.tsx"),
  read("../app/social-inbox-cache.ts"),
  read("../app/ajustes/notificaciones/page.tsx"),
  read("../app/perfil/avisos/page.tsx"),
  read("../app/service-worker-source.ts"),
  read("../app/page.tsx"),
  read("../app/equipo/social-team-client.tsx"),
  read("../app/mercado/marketplace-client.tsx"),
  read("../app/demo-world/demo-world-app.tsx"),
  read("../app/demo-world/demo-social-inbox.tsx"),
  read("../app/demo-world/demo-social-inbox.module.css"),
  read("../app/demo-world/demo-world-contract.ts"),
  read("../package.json"),
  read("./social-inbox-v1-concurrency.mjs"),
]);

const item = (patch: Record<string, unknown> = {}) => normalizeSocialInboxItem({
  archiveState: "ACTIVE",
  attentionState: "ACTION_REQUIRED",
  category: "match",
  context: "Partido",
  ctaLabel: "Revisar",
  deepLink: "/?mobile=partido&p=demo",
  id: "00000000-0000-0000-0000-000000000001",
  kind: "match_attendance_joined",
  occurredAt: "2026-09-02T08:00:00.000Z",
  priority: "high",
  readState: "READ",
  revision: 2,
  serverSequence: 41,
  sourceDomain: "MATCH",
  statusLabel: "Necesita respuesta",
  summary: "Confirma asistencia",
  title: "Confirma si juegas",
  updatedAt: "2026-09-02T08:00:00.000Z",
  ...patch,
});

test("V3G reuses the canonical notification table and adds only minimal authority", () => {
  assert.match(migration, /alter table public\.pachanga_user_notifications[\s\S]*archived_at/);
  assert.match(migration, /private\.pachanga_social_inbox_command_receipts_v1/);
  assert.doesNotMatch(migration, /create table if not exists public\.pachanga_social_inbox|create table if not exists .*outbox/i);
  assert.match(migration, /get_my_pachanga_social_inbox_v1/);
  assert.match(migration, /command_pachanga_social_inbox_v1/);
  assert.match(receiptIndexMigration, /create index if not exists pachanga_social_inbox_receipts_notification_idx[\s\S]*notification_id/);
  assert.doesNotMatch(receiptIndexMigration, /alter table|create table|create or replace function/i);
});

test("the social projection is explicit and excludes advanced or raw payload data", () => {
  const classifier = migration.match(/pachanga_social_inbox_domain_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(classifier, /'MATCH'[\s\S]*'CHALLENGE'[\s\S]*'MARKET'[\s\S]*'TEAM'/);
  for (const excluded of ["league_", "tournament_", "club_", "referee_", "billing_", "platform_"]) assert.doesNotMatch(classifier, new RegExp(`like '${excluded}`));
  const descriptor = migration.match(/pachanga_social_inbox_descriptor_v1[\s\S]*?end;\n\$\$;/)?.[0] ?? "";
  assert.doesNotMatch(descriptor.match(/return jsonb_strip_nulls[\s\S]*?\)\);/)?.[0] ?? "", /'payload'|'recipientUserId'|'email'|'phone'|'token'/i);
  assert.match(migration, /revoke all on function public\.get_my_pachanga_social_inbox_v1[\s\S]*from public, anon, authenticated, service_role/);
});

test("read state stays independent from action-required state", () => {
  const normalized = item();
  assert.ok(normalized);
  assert.equal(normalized.readState, "READ");
  assert.equal(normalized.attentionState, "ACTION_REQUIRED");
  const snapshot = normalizeSocialInboxSnapshot({ items: [normalized], pendingCount: 1, unreadCount: 0, view: "pending" });
  assert.equal(snapshot?.pendingCount, 1);
  assert.equal(snapshot?.unreadCount, 0);
  assert.equal(socialInboxGroup(normalized, new Date("2026-09-02T09:00:00.000Z")), "attention");
});

test("safe deep links reject open redirects and allow canonical product destinations", () => {
  for (const value of ["javascript:alert(1)", "data:text/html,x", "//evil.example/x", "https://evil.example/x", "/admin", "/avisos/../../admin"]) assert.equal(safeSocialInboxDeepLink(value), undefined);
  assert.equal(safeSocialInboxDeepLink("/?mobile=partido&p=abc"), "/?mobile=partido&p=abc");
  assert.equal(safeSocialInboxDeepLink("/retos?reto=abc"), "/retos?reto=abc");
  assert.equal(safeSocialInboxDeepLink("/mercado?tab=partidos"), "/mercado?tab=partidos");
  assert.equal(safeSocialInboxDeepLink("/equipo/invitaciones?team=abc"), "/equipo/invitaciones?team=abc");
  assert.equal(safeSocialInboxDeepLink("/partido-invitado?acceso=abc"), "/partido-invitado?acceso=abc");
});

test("commands are own-user, versioned, idempotent, bounded and never domain actions", () => {
  for (const action of ["inbox.mark_read", "inbox.mark_unread", "inbox.mark_all_read", "inbox.archive"]) assert.match(migration, new RegExp(action.replace(".", "\\.")));
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /set_config\('lock_timeout', '5s', true\)/);
  assert.match(migration, /pg_advisory_xact_lock[\s\S]*select \* into receipt[\s\S]*return receipt\.response/);
  assert.match(migration, /notifications\.recipient_user_id = actor_id/);
  assert.match(migration, /SOCIAL_INBOX_STALE/);
  assert.match(migration, /notifications\.server_sequence <= expected_server_sequence/);
  assert.match(migration, /limit 500/);
  assert.doesNotMatch(migration, /inbox\.accept_challenge|inbox\.confirm_attendance|inbox\.join_team/);
  assert.equal(
    classifySupabaseWrite("https://demo.supabase.co/rest/v1/rpc/command_pachanga_social_inbox_v1", { method: "POST" }),
    "rpc:command_pachanga_social_inbox_v1",
  );
  assert.match(concurrencyTest, /holdActorLock/);
  assert.match(concurrencyTest, /Promise\.all/);
  assert.match(concurrencyTest, /assert\.deepEqual\(responses\[0\], responses\[1\]/);
  assert.match(concurrencyTest, /revision, 2/);
  assert.match(concurrencyTest, /receiptCount, 1/);
});

test("pagination and concurrent arrivals use server sequence plus stable ID", () => {
  assert.match(migration, /\(sort_rank, server_sequence, id\) </);
  assert.match(migration, /order by sort_rank desc, server_sequence desc, id desc/);
  assert.match(migration, /nextCursor[\s\S]*serverSequence[\s\S]*notificationId/);
  assert.doesNotMatch(migration, /order by created_at desc\s*(limit|\))/i);
});

test("the global bell opens the Inbox and the legacy command popover is not mounted", () => {
  assert.match(layout, /<SocialInboxProvider>\{children\}<\/SocialInboxProvider>/);
  assert.doesNotMatch(layout, /<NotificationCenter \/>/);
  assert.match(shell, /notificationsHref = account\.notificationsHref \?\? "\/avisos"/);
  assert.match(shell, /pendingCount > 9 \? "9\+" : pendingCount/);
  assert.match(shell, /notificationDot/);
});

test("Inbox UI exposes only read/archive commands and delegates social actions by deep link", () => {
  assert.match(inboxPage, /Pendientes/);
  assert.match(inboxPage, /Todos/);
  assert.match(inboxPage, /Filtrar/);
  assert.match(inboxPage, /Marcar todo leído/);
  assert.match(inboxPage, /<Link href=\{item\.deepLink\}>/);
  assert.doesNotMatch(inboxPage, /respond_pachanga|confirm.*attendance|accept.*challenge|join.*team/i);
  assert.match(provider, /command_pachanga_social_inbox_v1/);
  assert.doesNotMatch(provider, /respond_pachanga_match_invitation|review_pachanga_open_match_request|confirm.*attendance/i);
});

test("preferences moved to Ajustes and the legacy route redirects", () => {
  assert.match(settings, /NotificationPreferences/);
  assert.match(settings, /href="\/avisos"/);
  assert.match(legacySettings, /redirect\("\/ajustes\/notificaciones"\)/);
});

test("private cache is IndexedDB, namespaced by user and cleared on sign-out", () => {
  assert.match(cache, /pachangas-iq-private-read-models/);
  assert.match(cache, /\$\{CACHE_VERSION\}:\$\{userId\}/);
  assert.doesNotMatch(cache, /localStorage|sessionStorage/);
  assert.match(provider, /if \(previousUserId\) await clearSocialInboxCache\(\)/);
  assert.match(provider, /requestGeneration\.current/);
  assert.match(provider, /actorId !== userRef\.current/);
});

test("in-flight Inbox commands cannot update a different signed-in session", () => {
  assert.match(provider, /const actorId = userRef\.current/);
  assert.match(provider, /commandInFlightActor\.current = actorId/);
  assert.match(provider, /if \(actorId !== userRef\.current\) return false/);
  assert.match(provider, /finally \{[\s\S]*commandInFlightActor\.current === actorId[\s\S]*actorId === userRef\.current[\s\S]*setBusyId\(null\)/);
  assert.match(provider, /userRef\.current = nextUserId;[\s\S]*commandInFlightActor\.current = null;[\s\S]*setBusyId\(null\)/);
});

test("Realtime only invalidates and refetches the canonical read model", () => {
  assert.match(provider, /table: "pachanga_user_notifications"/);
  assert.match(provider, /scheduleRefresh/);
  assert.match(provider, /nextStatus === "SUBSCRIBED"/);
  assert.doesNotMatch(provider, /payload\.new|setSnapshot\([^\n]*payload/);
});

test("offline is read-only and the Service Worker caches shells but not private RPC responses", () => {
  assert.match(provider, /if \(!navigator\.onLine\)[\s\S]*Necesitas conexión para confirmar esta acción/);
  assert.match(serviceWorker, /"\/avisos"/);
  assert.match(serviceWorker, /"\/ajustes\/notificaciones"/);
  assert.doesNotMatch(serviceWorker, /get_my_pachanga_social_inbox_v1|command_pachanga_social_inbox_v1/);
});

test("Home uses the canonical pending projection and Team keeps its V3F authority", () => {
  assert.match(home, /pendingSnapshot/);
  assert.match(home, /socialPrimaryAction/);
  assert.match(home, /homeNextAction/);
  assert.match(team, /Invitar jugadores/);
  assert.match(team, /teamCode/);
  assert.doesNotMatch(team, /Estado confirmado/);
  assert.match(team, /operationalStatus !== "ACTIVE"/);
});

test("match invitation response lives in Mercado rather than the Inbox", () => {
  assert.match(market, /get_my_pachanga_match_invitation_action_v1/);
  assert.match(market, /respond_pachanga_match_invitation_v1/);
  assert.match(market, /expected_invitation_revision/);
  assert.match(market, /expected_match_revision/);
  assert.match(market, /operation_id: crypto\.randomUUID\(\)/);
});

test("Demo Social Inbox is local, user-namespaced and documents the 26-step journey", () => {
  assert.match(demoContract, /"avisos"/);
  assert.match(demoContract, /socialInboxByPerspective/);
  assert.match(demo, /socialInboxByPerspective: \{ \.\.\.current\.socialInboxByPerspective, \[perspective\.id\]: next \}/);
  assert.match(demo, /<DemoSocialInbox/);
  assert.match(demo, /!socialFirstTimeOpen && !socialQuickReviewOpen && activeTab !== "avisos"/);
  assert.match(demo, /DEMO_SOCIAL_ATTENDANCE_ID/);
  assert.match(demo, /DEMO_SOCIAL_CHALLENGE_ID/);
  assert.match(demo, /DEMO_SOCIAL_TEAM_INVITATION_ID/);
  assert.match(demoInbox, /Recorrido Social Inbox · 26 pasos/);
  assert.match(demoInbox, /key=\{`\$\{index\}-\$\{step\}`\}/);
  assert.match(demoInboxStyles, /\.toolbar>div:first-child,\.settings,\.item,\.detail,\.proof\{background:var\(--demo-panel-soft\)\}/);
  assert.match(demoInboxStyles, /\.item\[data-selected=true\],\.menu>div\{background:var\(--demo-panel\)\}/);
  assert.match(demoInboxStyles, /orientation:landscape[\s\S]*\.detail h2\{font-size:1rem\}[\s\S]*\.detail button\{min-height:40px/);
  for (const proof of ["remoteWrites = 0", "externalNotifications = 0", "pushSent = 0", "emailsSent = 0", "realEntities = 0", "StripeCalls = 0"]) assert.match(demoInbox, new RegExp(proof));
  assert.doesNotMatch(demoInbox, /supabase|\.rpc\(|fetch\(/i);
  const profileView = demo.match(/function ProfileView[\s\S]*?function PlayerModal/)?.[0] ?? "";
  assert.doesNotMatch(profileView, /pane === "avisos"|Centro de avisos/);
});

test("V3G remains part of the complete suite and does not activate Wave 9C", () => {
  const scripts = JSON.parse(packageJson).scripts as Record<string, string>;
  assert.match(scripts.test, /tests\/social-inbox-v1\.test\.ts/);
  assert.doesNotMatch(migration, /wave_9c|joint_planning|stripe/i);
});
