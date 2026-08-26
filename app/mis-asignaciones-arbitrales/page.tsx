import type { Metadata } from "next";
import { RefereeAssignmentsClient } from "../_components/referee-assignments-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Mis asignaciones arbitrales · Pachangas IQ",
};

export default function MyRefereeAssignmentsPage() {
  return <RefereeAssignmentsClient surface="my" />;
}
