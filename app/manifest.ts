import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Pachangas IQ",
    short_name: "Pachangas IQ",
    description: "Organiza pachangas, confirma jugadores y equilibra equipos con historial.",
    start_url: "/",
    display: "standalone",
    background_color: "#f7f6f0",
    theme_color: "#116149",
    icons: [
      {
        src: "/icon-192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/icon-512.png",
        sizes: "512x512",
        type: "image/png",
      },
    ],
  };
}
