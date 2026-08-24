import type { Metadata } from "next";
import { getPublicRefereeBySlug } from "../../public-product-data";
import { PublicRefereeProfile } from "./public-referee-profile";

function text(value: unknown) { return typeof value === "string" ? value : ""; }

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const profile = await getPublicRefereeBySlug(slug);
  return {
    description: profile ? text(profile.bio).slice(0, 160) || `${text(profile.displayName)} en el Mercado arbitral de Pachangas IQ.` : "Perfil arbitral no disponible.",
    robots: { follow: Boolean(profile), index: Boolean(profile) },
    title: profile ? `${text(profile.displayName)} | Pachangas IQ` : "Perfil arbitral no disponible | Pachangas IQ",
  };
}

export default async function RefereePublicPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <PublicRefereeProfile initialProfile={await getPublicRefereeBySlug(slug)} slug={slug} />;
}
