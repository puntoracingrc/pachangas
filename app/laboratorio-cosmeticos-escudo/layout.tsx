import type { Metadata } from "next";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Laboratorio de escudos | Pachangas IQ",
};

export default function TeamShieldLabLayout({ children }: { children: React.ReactNode }) {
  return children;
}
