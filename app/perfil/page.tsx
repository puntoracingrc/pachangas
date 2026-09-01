import type { Metadata } from "next";
import { CanonicalPlayerProfile } from "./profile-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Mi perfil | Pachangas IQ",
};

export default function ProfilePage() {
  return <CanonicalPlayerProfile />;
}
