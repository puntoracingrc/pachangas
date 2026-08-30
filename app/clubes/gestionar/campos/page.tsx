import type { Metadata } from "next";
import { ClubVenueOperationsClient } from "../club-venue-operations-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Campos del Club | Pachangas IQ",
};

export default function ClubVenuesPage() {
  return <ClubVenueOperationsClient mode="venues" />;
}
