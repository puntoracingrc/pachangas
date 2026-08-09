import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(new URL(import.meta.url).pathname), "../../..");
const sources = {
  guest: await readFile(resolve(root, "supabase/migrations/20260803190301_match_guest_invitations_notifications.sql"), "utf8"),
  notifications: await readFile(resolve(root, "supabase/migrations/20260804144819_notification_foundation.sql"), "utf8"),
  notificationTests: await readFile(resolve(root, "tests/notification-foundation-db.sql"), "utf8"),
  guestTests: await readFile(resolve(root, "tests/match-guest-access-db.sql"), "utf8"),
  notificationUi: await readFile(resolve(root, "app/notification-center.tsx"), "utf8"),
};

const has = (source, expression) => expression.test(source);
const rows = [
  {
    capability: "General player reports",
    classification: "not_implemented",
    evidence: "No canonical table/RPC/UI located; guest withdrawal review is deliberately narrower.",
  },
  {
    capability: "Guest voluntary withdrawal",
    classification: has(sources.guest, /function public\.leave_pachanga_guest_match_v1/) ? "implemented" : "not_implemented",
    evidence: "leave_pachanga_guest_match_v1 revokes access, frees the place and creates one review.",
  },
  {
    capability: "Guest withdrawal admin review",
    classification: has(sources.guest, /function public\.review_pachanga_guest_withdrawal_v1/) && has(sources.notificationUi, /review_pachanga_guest_withdrawal_v1/) ? "implemented" : "partially_implemented",
    evidence: "Admin confirms or dismisses; idempotent, revisioned, private identities, affectsSportRating=false.",
  },
  {
    capability: "Canonical no-show distinction",
    classification: "not_implemented",
    evidence: "Product records status changes and guest withdrawal, but no attended/no-show fact distinct from cancellation.",
  },
  {
    capability: "Attendance joined notification",
    classification: has(sources.notifications, /match_attendance_joined/) && has(sources.notificationTests, /Repeated Voy events must not create duplicate/) ? "implemented" : "partially_implemented",
    evidence: "Only transition into voy notifies; retries do not duplicate.",
  },
  {
    capability: "Attendance cancellation notification",
    classification: has(sources.notifications, /match_attendance_cancelled/) && has(sources.notificationTests, /Voy to No voy must create exactly one/) ? "implemented" : "partially_implemented",
    evidence: "Only voy to no notifies; direct no does not imply misconduct or notify.",
  },
  {
    capability: "Injury and recovery notifications",
    classification: has(sources.notifications, /player_availability_unavailable/) && has(sources.notifications, /player_availability_available/) ? "implemented" : "partially_implemented",
    evidence: "Profile injured transition emits unavailable/available without medical detail.",
  },
  {
    capability: "Notification preferences",
    classification: has(sources.notifications, /update_pachanga_notification_preferences_v1/) ? "implemented" : "not_implemented",
    evidence: "Six categories; in-app, push and email preferences are revisioned through RPC.",
  },
  {
    capability: "Mandatory administrative notices",
    classification: has(sources.notifications, /show_in_app := is_mandatory or/) && has(sources.notificationTests, /must remain visible despite the category opt-out/) ? "implemented" : "partially_implemented",
    evidence: "Security/warning/sanction kinds are mandatory in-app even when a category is disabled.",
  },
  {
    capability: "Warnings and sanctions engine",
    classification: "partially_implemented",
    evidence: "Delivery policy reserves security/warning/sanction kinds, but no canonical decision/history/restriction engine was located.",
  },
  {
    capability: "Independent-source weighting and report abuse defense",
    classification: "not_implemented",
    evidence: "No general reports exist, so source-team independence, coordinated false-report detection and appeals are not product capabilities.",
  },
  {
    capability: "Conduct effect isolation from Rating V2",
    classification: has(sources.guest, /'affectsSportRating', false/) && has(sources.guestTests, /must not change any Rating V2/) ? "implemented" : "partially_implemented",
    evidence: "The one existing withdrawal review explicitly cannot alter sport rating.",
  },
];

const inventory = {
  generatedAt: new Date().toISOString(),
  summary: {
    implemented: rows.filter(({ classification }) => classification === "implemented").length,
    notImplemented: rows.filter(({ classification }) => classification === "not_implemented").length,
    partiallyImplemented: rows.filter(({ classification }) => classification === "partially_implemented").length,
  },
  rows,
};
const outputDirectory = resolve(root, "simulation/synthetic-world/generated");
await mkdir(outputDirectory, { recursive: true });
await writeFile(resolve(outputDirectory, "conduct-inventory.json"), `${JSON.stringify(inventory, null, 2)}\n`, "utf8");
const markdownRows = rows.map((row) => `| ${row.capability} | ${row.classification} | ${row.evidence} |`).join("\n");
await writeFile(resolve(outputDirectory, "conduct-inventory.md"), `# Conduct, reports and no-show inventory\n\nGenerated from local product SQL, UI and DB tests. Absence of a general report route is reported as absence, not simulated as product.\n\n| Capability | Classification | Evidence |\n| --- | --- | --- |\n${markdownRows}\n\n## Decision boundary\n\n- A normal cancellation is not misconduct.\n- Guest withdrawal review is not a no-show detector and creates no automatic sanction.\n- General player reporting, independent-source weighting, restrictions and appeals remain product decisions.\n- Notification transport can carry mandatory future warnings/sanctions, but that does not mean a sanction engine exists.\n`, "utf8");
process.stdout.write(`${JSON.stringify(inventory.summary)}\n`);
