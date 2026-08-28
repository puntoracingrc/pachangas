import type { MetadataRoute } from "next";
import { getPublicCompetitionSitemap } from "./public-product-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const competitions = await getPublicCompetitionSitemap();
  return [
    { changeFrequency: "weekly", lastModified: new Date(), priority: 1, url: "https://pachangasiq.com" },
    { changeFrequency: "daily", lastModified: new Date(), priority: 0.8, url: "https://pachangasiq.com/competiciones" },
    ...competitions
      .filter((item) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(item.slug))
      .map((item) => ({
        changeFrequency: "daily" as const,
        lastModified: Number.isNaN(Date.parse(item.updated_at)) ? new Date() : new Date(item.updated_at),
        priority: 0.7,
        url: `https://pachangasiq.com/competiciones/${encodeURIComponent(item.slug)}`,
      })),
  ];
}
