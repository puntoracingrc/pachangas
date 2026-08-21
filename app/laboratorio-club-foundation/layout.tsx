import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Club Foundation | Pachangas IQ Lab",
  robots: { follow: false, index: false },
};

export default function ClubFoundationLabLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
