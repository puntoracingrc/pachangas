import type { Metadata } from "next";
import { SeasonVenuePlannerClient } from "../../_components/season-venue-planner-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Reservas recurrentes · Pachangas IQ" };

export default function RecurringReservationsPage() {
  return <SeasonVenuePlannerClient surface="recurring-list" />;
}
