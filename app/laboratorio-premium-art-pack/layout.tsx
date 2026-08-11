import type { Metadata } from "next";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Premium Art Pack V1 | Laboratorio Pachangas IQ",
};

export default function PremiumArtPackLayout({ children }: { children: React.ReactNode }) {
  return children;
}
