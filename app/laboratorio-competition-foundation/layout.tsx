import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Competition Foundation | Pachangas IQ Lab",
  robots: { follow: false, index: false },
};

export default function CompetitionFoundationLabLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
