import type { Metadata } from "next";
import type { ReactNode } from "react";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Laboratorio R4D · Pachangas IQ",
};

export default function LeagueOperationalExceptionsLabLayout({ children }: { children: ReactNode }) {
  return children;
}
