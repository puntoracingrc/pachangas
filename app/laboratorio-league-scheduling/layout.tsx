import type { Metadata } from "next";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Laboratorio League Scheduling · Pachangas IQ",
};

export default function LeagueSchedulingLabLayout({ children }: { children: React.ReactNode }) {
  return children;
}
