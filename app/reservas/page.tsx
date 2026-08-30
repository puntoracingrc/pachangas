import type { Metadata } from "next";
import { VenueReservationsClient } from "./venue-reservations-client";

export const metadata: Metadata = {
  description: "Solicitudes y reservas de Campos en Pachangas IQ.",
  robots: { follow: false, index: false },
  title: "Reservas | Pachangas IQ",
};

export default function VenueReservationsPage() {
  return <VenueReservationsClient />;
}
