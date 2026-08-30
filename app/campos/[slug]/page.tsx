import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getPublicVenueBySlug } from "../../public-product-data";
import { PublicVenueProfile } from "./public-venue-profile";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const venue = await getPublicVenueBySlug(slug);
  const name = venue && typeof venue.name === "string" ? venue.name : "Campo";
  return {
    description: "Disponibilidad pública y solicitud de reserva en " + name + ".",
    robots: venue ? { follow: true, index: true } : { follow: false, index: false },
    title: name + " | Pachangas IQ",
  };
}

export default async function PublicVenuePage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const venue = await getPublicVenueBySlug(slug);
  if (!venue) notFound();
  return <PublicVenueProfile venue={venue} />;
}
