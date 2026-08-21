import type { Metadata } from "next";

export const metadata: Metadata = { title: "Mi ficha de árbitro | Pachangas IQ", robots: { follow: false, index: false } };

export default function RefereeProfileLayout({ children }: Readonly<{ children: React.ReactNode }>) { return children; }
