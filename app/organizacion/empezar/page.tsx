import type { Metadata } from "next";
import { OrganizerAccessClient } from "../../_components/organizer-access-client";

export const metadata: Metadata = { title: "Primera competición · Pachangas IQ" };

export default function FirstCompetitionLauncherPage() {
  return <OrganizerAccessClient surface="launcher" />;
}
