import type { Metadata } from "next";
import { VenueReservationDetailClient } from "./venue-reservation-detail-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Detalle de reserva | Pachangas IQ",
};

export default async function VenueReservationDetailPage({ params }: { params: Promise<{ reservation: string }> }) {
  const { reservation } = await params;
  return <VenueReservationDetailClient reservationId={reservation} />;
}
