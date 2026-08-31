import type { Metadata } from "next";
import { SeasonVenuePlannerClient } from "../../../_components/season-venue-planner-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Bloque recurrente · Pachangas IQ" };

export default async function RecurringReservationSeriesPage({ params }: { params: Promise<{ series: string }> }) {
  const { series } = await params;
  return <SeasonVenuePlannerClient seriesId={series} surface="recurring-detail" />;
}
