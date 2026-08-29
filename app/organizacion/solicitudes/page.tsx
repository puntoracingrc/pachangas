import type { Metadata } from "next";
import { OrganizerAccessClient } from "../../_components/organizer-access-client";

export const metadata: Metadata = { title: "Solicitudes de organización · Pachangas IQ" };

export default function OrganizerAccessApplicationsPage() {
  return <OrganizerAccessClient surface="list" />;
}
