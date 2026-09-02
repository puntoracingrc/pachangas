import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [migration, center, preferences, page, settingsPage, legacyProfilePage, css] = await Promise.all([
  readFile(new URL("../supabase/migrations/20260804144819_notification_foundation.sql", import.meta.url), "utf8"),
  readFile(new URL("../app/notification-center.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/notification-preferences.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/ajustes/notificaciones/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/perfil/avisos/page.tsx", import.meta.url), "utf8"),
  readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
]);

test("notification preferences are server-authoritative, revisioned and idempotent", () => {
  assert.match(migration, /create table if not exists public\.pachanga_notification_preferences/);
  assert.match(migration, /primary key \(user_id, category\)/);
  assert.match(migration, /expected_revision bigint/);
  assert.match(migration, /operation_id uuid/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /Notification preferences are newer/);
  assert.match(migration, /pachanga_notification_preference_receipts/);
  assert.match(migration, /grant execute on function public\.update_pachanga_notification_preferences_v1/);
  assert.doesNotMatch(migration, /grant (insert|update|delete|all) on table public\.pachanga_notification_preferences to authenticated/i);
});

test("RLS and private delivery infrastructure do not expose secondary channels", () => {
  assert.match(migration, /alter table public\.pachanga_notification_preferences enable row level security/);
  assert.match(migration, /\(select auth\.uid\(\)\) = user_id/);
  assert.match(migration, /recipient_user_id and visible_in_app/);
  assert.match(migration, /private\.pachanga_notification_delivery_outbox/);
  assert.match(migration, /revoke all on table private\.pachanga_notification_delivery_outbox/);
  assert.match(migration, /insert into private\.pachanga_notification_channels[\s\S]*'push', false[\s\S]*'email', false/);
  assert.doesNotMatch(preferences, /service_role/i);
});

test("critical notifications override category visibility while optional notices respect it", () => {
  assert.match(migration, /show_in_app := is_mandatory or coalesce\(preference\.in_app_enabled, true\)/);
  assert.match(migration, /'mandatoryInApp'/);
  assert.match(migration, /kind like '%security%'/);
  assert.match(migration, /kind like '%challenge%'/);
  assert.match(migration, /kind = 'group_member_removed'/);
  assert.match(center, /notification\.mandatoryInApp/);
  assert.match(preferences, /Incluye avisos críticos que no se pueden ocultar/);
});

test("the first event base fans out membership, attendance, availability and challenge changes", () => {
  for (const trigger of [
    "pachanga_notify_group_membership_v1",
    "pachanga_notify_attendance_event_v1",
    "pachanga_notify_player_availability_v1",
    "pachanga_notify_challenge_event_v1",
  ]) assert.match(migration, new RegExp(`create trigger ${trigger}`));
  assert.match(migration, /next_status = 'no' and previous_status = 'voy'/);
  assert.match(migration, /previous_status is distinct from 'voy'/);
  assert.match(migration, /order by events\.server_sequence desc, events\.id desc/);
  assert.match(migration, /team_challenge_/);
});

test("achievement notifications keep the reward secret until opened", () => {
  assert.match(migration, /safe_title := 'Nuevo logro desbloqueado'/);
  assert.match(migration, /safe_body := 'Toca para descubrirlo\.'/);
  assert.match(migration, /where kind in \('achievement_reward', 'personal_achievement_reward'\)/);
  assert.match(center, /notification\.category === "achievement" \? "Descubrir"/);
});

test("profile preferences use confirmed RPC responses and never queue offline writes", () => {
  assert.match(preferences, /get_pachanga_notification_preferences_v1/);
  assert.match(preferences, /update_pachanga_notification_preferences_v1/);
  assert.match(preferences, /crypto\.randomUUID\(\)/);
  assert.match(preferences, /if \(!navigator\.onLine\)/);
  assert.match(preferences, /No se ha cambiado ninguna preferencia/);
  assert.doesNotMatch(preferences, /localStorage|indexedDB|optimistic/i);
  assert.match(settingsPage, /<NotificationPreferences \/>/);
  assert.match(legacyProfilePage, /redirect\("\/ajustes\/notificaciones"\)/);
  assert.match(page, /href="\/ajustes\/notificaciones"/);
});

test("the notification center exposes unread count, Realtime refresh and category filters", () => {
  assert.match(center, /unreadCount/);
  assert.match(center, /postgres_changes/);
  assert.match(center, /table: "pachanga_user_notifications"/);
  assert.match(center, /notification-filters/);
  assert.match(center, /selectedCategory/);
  assert.match(center, /href="\/perfil\/avisos"/);
  assert.match(center, /pachangas:reward-deep-link/);
  assert.match(center, /target\.searchParams\.get\("rewards"\) === "pending"/);
  assert.match(css, /\.notification-filters/);
  assert.match(css, /\.notification-preferences-page/);
});
