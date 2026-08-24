import type { Metadata } from "next";
import type { ReactNode } from "react";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Laboratorio R4C · Pachangas IQ",
};

export default function LeagueMatchOperationsLabLayout({ children }: { children: ReactNode }) {
  return children;
}
