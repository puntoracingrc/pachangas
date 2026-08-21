import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Club | Pachangas IQ",
  robots: { follow: false, index: false },
};

export default function PublicClubLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
