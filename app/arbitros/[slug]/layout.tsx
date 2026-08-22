import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Perfil de árbitro | Pachangas IQ",
  robots: { follow: false, index: false },
};

export default function RefereePublicLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
