import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { LegalFooter } from "./legal-data";
import { ClientErrorReporter } from "./client-error-reporter";
import { PwaRuntime } from "./pwa-runtime";
import { SocialInboxProvider } from "./social-inbox-provider";
import "./globals.css";

const themePreferenceScript = `
(() => {
  try {
    const preference = localStorage.getItem("pachanga-iq-theme");
    if (preference === "light" || preference === "dark") {
      [document.documentElement, document.body].filter(Boolean).forEach((element) => {
        element.dataset.theme = preference;
        element.style.colorScheme = preference;
      });
    }
  } catch {}
})();
`;

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://pachangasiq.com"),
  title: "Pachangas IQ",
  description: "Organiza pachangas, confirma jugadores y equilibra equipos con historial.",
  applicationName: "Pachangas IQ",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Pachangas IQ",
  },
  icons: {
    icon: [
      { url: "/favicon-16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicon-32.png", sizes: "32x32", type: "image/png" },
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
    ],
    shortcut: "/favicon-32.png",
    apple: "/apple-touch-icon.png",
  },
  other: {
    "mobile-web-app-capable": "yes",
    "msapplication-TileColor": "#116149",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#116149" },
    { media: "(prefers-color-scheme: dark)", color: "#0b1210" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es" suppressHydrationWarning>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        <script dangerouslySetInnerHTML={{ __html: themePreferenceScript }} />
        <PwaRuntime />
        <ClientErrorReporter />
        <SocialInboxProvider>{children}</SocialInboxProvider>
        <LegalFooter />
      </body>
    </html>
  );
}
