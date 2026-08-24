import type { Metadata } from "next";
import { getPublicClubBySlug } from "../../public-product-data";
import { PublicClubProfile } from "./public-club-profile";

function text(value: unknown) { return typeof value === "string" ? value : ""; }

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const club = await getPublicClubBySlug(slug);
  return {
    description: club ? text(club.description).slice(0, 160) || `${text(club.name)} en Pachangas IQ.` : "Perfil de Club no disponible.",
    robots: { follow: Boolean(club), index: Boolean(club) },
    title: club ? `${text(club.name)} | Pachangas IQ` : "Club no disponible | Pachangas IQ",
  };
}

export default async function PublicClubPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <PublicClubProfile club={await getPublicClubBySlug(slug)} />;
}
