import type { Metadata } from "next";
import { ClubVenueOperationsClient } from "../club-venue-operations-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Reservas del Club | Pachangas IQ",
};

export default function ClubReservationsPage() {
  return <ClubVenueOperationsClient mode="reservations" />;
}
