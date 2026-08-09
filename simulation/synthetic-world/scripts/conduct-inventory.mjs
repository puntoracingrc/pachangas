import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(new URL(import.meta.url).pathname), "../../..");
const sources = {
  guest: await readFile(resolve(root, "supabase/migrations/20260803190301_match_guest_invitations_notifications.sql"), "utf8"),
  notifications: await readFile(resolve(root, "supabase/migrations/20260804144819_notification_foundation.sql"), "utf8"),
  notificationTests: await readFile(resolve(root, "tests/notification-foundation-db.sql"), "utf8"),
  guestTests: await readFile(resolve(root, "tests/match-guest-access-db.sql"), "utf8"),
  notificationUi: await readFile(resolve(root, "app/notification-center.tsx"), "utf8"),
  conduct: await readFile(resolve(root, "supabase/migrations/20260809162859_conduct_reports_no_show_v1.sql"), "utf8"),
  conductAdminUi: await readFile(resolve(root, "app/admin/conduct/conduct-admin-client.tsx"), "utf8"),
  conductPlayerUi: await readFile(resolve(root, "app/conduct-player-center.tsx"), "utf8"),
  conductReportUi: await readFile(resolve(root, "app/conduct-report-form.tsx"), "utf8"),
};

const has = (source, expression) => expression.test(source);
const rows = [
  {
    capability: "General player reports",
    classification: has(sources.conduct, /function public\.submit_pachanga_conduct_report_v1/) && has(sources.conductReportUi, /submit_pachanga_conduct_report_v1/) ? "implemented" : "partially_implemented",
    evidence: "Context-bound, idempotent reports create clustered moderation cases without automatic sanctions.",
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
    classification: has(sources.conduct, /function public\.close_pachanga_match_attendance_v1/) && has(sources.conductAdminUi, /close_pachanga_match_attendance_v1/) ? "implemented" : "partially_implemented",
    evidence: "A complete post-match roster closure distinguishes played, excused absence, late cancellation and unexcused no-show.",
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
    classification: has(sources.conduct, /pachanga_conduct_warnings/) && has(sources.conduct, /pachanga_social_restrictions/) && has(sources.conduct, /function public\.appeal_pachanga_conduct_action_v1/) ? "implemented" : "partially_implemented",
    evidence: "Warnings, explicit moderator restrictions, expiry and appeals are canonical; social restrictions remain independently flag-gated.",
  },
  {
    capability: "Independent-source weighting and report abuse defense",
    classification: has(sources.conduct, /pachanga_conduct_report_source_clusters/) && has(sources.conduct, /independent_source_count/) ? "implemented" : "partially_implemented",
    evidence: "Reports share source clusters by team/context while different teams increase independent-source count.",
  },
  {
    capability: "Conduct effect isolation from Rating V2",
    classification: has(sources.guest, /'affectsSportRating', false/) && has(sources.guestTests, /must not change any Rating V2/) ? "implemented" : "partially_implemented",
    evidence: "Guest withdrawal and Conduct V1 responses explicitly return affectsSportRating=false; no conduct path writes sport tables.",
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
await writeFile(resolve(outputDirectory, "conduct-inventory.md"), `# Conduct, reports and no-show inventory\n\nGenerated from local product SQL, UI and DB tests. Feature availability is classified from canonical routes, not inferred from Synthetic World labels.\n\n| Capability | Classification | Evidence |\n| --- | --- | --- |\n${markdownRows}\n\n## Decision boundary\n\n- A normal cancellation is not misconduct.\n- Guest withdrawal review remains narrower than post-match attendance closure.\n- Reports create reviewable cases; no report imposes a sanction automatically.\n- Warnings and restrictions require an internal moderator, and social restrictions have an independent feature flag.\n- Conduct and attendance never alter Rating V2, Season Score, TOPS, achievements or reward boxes.\n`, "utf8");
process.stdout.write(`${JSON.stringify(inventory.summary)}\n`);
