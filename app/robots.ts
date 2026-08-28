import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      allow: "/",
      disallow: ["/admin/", "/api/", "/demo", "/laboratorio-"],
      userAgent: "*",
    },
    sitemap: "https://pachangasiq.com/sitemap.xml",
  };
}
