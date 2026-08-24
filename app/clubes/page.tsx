import type { Metadata } from "next";
import { ClubDirectoryClient } from "./club-directory-client";
import { searchPublicClubs } from "../public-product-data";

export async function generateMetadata(): Promise<Metadata> {
  const data = await searchPublicClubs({}, 1, 1) as { enabled?: unknown } | null;
  const enabled = data?.enabled === true;
  return {
    description: "Directorio público de Clubs, asociaciones y organizadores en Pachangas IQ.",
    robots: { follow: enabled, index: enabled },
    title: "Clubs | Pachangas IQ",
  };
}

export default async function ClubsDirectoryPage() {
  const data = await searchPublicClubs({}, 1, 24);
  return <ClubDirectoryClient initialData={data && typeof data === "object" && !Array.isArray(data) ? data as Record<string, unknown> : null} />;
}
