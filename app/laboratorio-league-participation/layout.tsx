import type { Metadata } from "next";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Laboratorio R4A · Pachangas IQ" };

export default function LeagueParticipationLabLayout({ children }: { children: React.ReactNode }) {
  return children;
}
