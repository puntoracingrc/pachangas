import type { Metadata } from "next";
import { SeasonVenuePlannerClient } from "../../../../_components/season-venue-planner-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Pools de campos · Pachangas IQ" };

export default function ClubVenuePoolsPage() {
  return <SeasonVenuePlannerClient surface="pools" />;
}
