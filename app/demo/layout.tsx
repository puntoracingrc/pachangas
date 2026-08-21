import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Mundo Demo | Pachangas IQ",
  description: "Un mundo ficticio y navegable para conocer Pachangas IQ sin crear una cuenta.",
  robots: {
    follow: false,
    index: false,
  },
};

export default function DemoLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
