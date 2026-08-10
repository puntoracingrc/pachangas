import type { Metadata } from "next";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Laboratorio 3D de escudos | Pachangas IQ",
};

export default function TeamShieldPremium3DLabLayout({ children }: { children: React.ReactNode }) {
  return children;
}
