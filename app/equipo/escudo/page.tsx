import type { Metadata } from "next";
import { SocialTeamProduct } from "../social-team-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Escudo del equipo | Pachangas IQ",
};

export default function TeamShieldPage() {
  return <SocialTeamProduct surface="shield" />;
}
