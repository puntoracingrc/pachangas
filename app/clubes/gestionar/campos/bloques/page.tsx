import type { Metadata } from "next";
import { SeasonVenuePlannerClient } from "../../../../_components/season-venue-planner-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Bloques recurrentes del Club · Pachangas IQ" };

export default function ClubRecurringBlocksPage() {
  return <SeasonVenuePlannerClient surface="recurring-list" />;
}
