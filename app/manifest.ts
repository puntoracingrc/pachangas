import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Pachangas IQ",
    short_name: "Pachangas IQ",
    description: "Organiza pachangas, confirma jugadores y equilibra equipos con historial.",
    id: "/",
    start_url: "/",
    scope: "/",
    display: "fullscreen",
    display_override: ["fullscreen", "standalone", "minimal-ui", "browser"],
    orientation: "any",
    background_color: "#f7f6f0",
    theme_color: "#116149",
    categories: ["sports", "productivity", "social"],
    dir: "ltr",
    lang: "es",
    launch_handler: {
      client_mode: "focus-existing",
    },
    prefer_related_applications: false,
    icons: [
      {
        src: "/icon-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icon-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icon-maskable-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "maskable",
      },
      {
        src: "/icon-maskable-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
      {
        src: "/icon-monochrome.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "monochrome",
      },
    ],
    shortcuts: [
      {
        name: "Partido",
        short_name: "Partido",
        description: "Abrir el partido activo.",
        url: "/?mobile=partido",
        icons: [{ src: "/icon-192.png", sizes: "192x192", type: "image/png" }],
      },
      {
        name: "Mercado",
        short_name: "Mercado",
        description: "Abrir el mercado de fichajes.",
        url: "/mercado",
        icons: [{ src: "/icon-192.png", sizes: "192x192", type: "image/png" }],
      },
      {
        name: "Equipo",
        short_name: "Equipo",
        description: "Abrir el ranking del equipo.",
        url: "/?mobile=equipo",
        icons: [{ src: "/icon-192.png", sizes: "192x192", type: "image/png" }],
      },
    ],
  };
}
