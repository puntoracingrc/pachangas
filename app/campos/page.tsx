import type { Metadata } from "next";
import { getVenueFlags, searchPublicVenues } from "../public-product-data";
import { VenueDirectoryClient } from "./venue-directory-client";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export const metadata: Metadata = {
  description: "Campos y disponibilidad pública en Pachangas IQ.",
  title: "Campos | Pachangas IQ",
};

export default async function VenueDirectoryPage() {
  const [initialData, flags] = await Promise.all([
    searchPublicVenues({}, 1, 24),
    getVenueFlags(),
  ]);
  return <VenueDirectoryClient
    directoryEnabled={Boolean(flags && typeof flags === "object" && !Array.isArray(flags) && (flags as Record<string, unknown>).venuePublicDirectoryEnabled)}
    initialData={initialData && typeof initialData === "object" && !Array.isArray(initialData) ? initialData as Record<string, unknown> : null}
  />;
}
