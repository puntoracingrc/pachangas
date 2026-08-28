import type { Metadata } from "next";
import { OrganizerPlansClient } from "../_components/organizer-plans-client";

export const metadata: Metadata = {
  description: "Planes de organizacion para Clubs y equipos de Pachangas IQ.",
  title: "Planes de organizacion | Pachangas IQ",
};

export default function OrganizerPlansPage() {
  return <OrganizerPlansClient />;
}
