import type { Metadata } from "next";

export const metadata: Metadata = { title: "Referee Platform | Pachangas IQ Lab", robots: { follow: false, index: false } };

export default function RefereeLabLayout({ children }: Readonly<{ children: React.ReactNode }>) { return children; }
