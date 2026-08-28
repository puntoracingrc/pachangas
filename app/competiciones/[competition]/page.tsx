import type { Metadata } from "next";
import { getPublicCompetitionBySlug } from "../../public-product-data";
import { publicCompetitionRecord, publicCompetitionText } from "../../public-competition-contract";
import { PublicCompetitionHub } from "./public-competition-hub";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function generateMetadata({ params }: { params: Promise<{ competition: string }> }): Promise<Metadata> {
  const { competition: slug } = await params;
  const snapshot = await getPublicCompetitionBySlug(slug);
  const competition = publicCompetitionRecord(snapshot?.competition);
  const publication = publicCompetitionRecord(snapshot?.publication);
  const isPublic = publicCompetitionText(publication.visibility) === "public" && publicCompetitionText(publication.status) === "published";
  const name = publicCompetitionText(competition.name) || "Competición";
  const description = publicCompetitionText(competition.description).slice(0, 160) || `${name} en Pachangas IQ.`;
  const canonical = `https://pachangasiq.com/competiciones/${encodeURIComponent(slug)}`;
  const image = publicCompetitionText(competition.image);
  return {
    alternates: isPublic ? { canonical } : undefined,
    description,
    openGraph: isPublic ? { description, images: image ? [{ url: image }] : undefined, title: `${name} | Pachangas IQ`, type: "website", url: canonical } : undefined,
    robots: { follow: isPublic, index: isPublic },
    title: snapshot ? `${name} | Pachangas IQ` : "Competición no disponible | Pachangas IQ",
  };
}

export default async function PublicCompetitionPage({ params }: { params: Promise<{ competition: string }> }) {
  const { competition: slug } = await params;
  const snapshot = await getPublicCompetitionBySlug(slug);
  const competition = publicCompetitionRecord(snapshot?.competition);
  const publication = publicCompetitionRecord(snapshot?.publication);
  const isPublic = publicCompetitionText(publication.visibility) === "public"
    && publicCompetitionText(publication.status) === "published";
  const structuredData = snapshot && isPublic ? {
    "@context": "https://schema.org",
    "@type": "SportsEvent",
    description: publicCompetitionText(competition.description),
    endDate: publicCompetitionText(competition.endsAt) || undefined,
    eventStatus: "https://schema.org/EventScheduled",
    location: publicCompetitionText(competition.municipality) ? { "@type": "Place", name: publicCompetitionText(competition.municipality) } : undefined,
    name: publicCompetitionText(competition.name),
    startDate: publicCompetitionText(competition.startsAt) || undefined,
    url: `https://pachangasiq.com/competiciones/${encodeURIComponent(slug)}`,
  } : null;
  return <>
    {structuredData ? <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replaceAll("<", "\\u003c") }} /> : null}
    <PublicCompetitionHub initialSnapshot={snapshot} slug={slug} />
  </>;
}
