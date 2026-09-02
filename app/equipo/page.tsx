import type { Metadata } from "next";
import { SocialTeamProduct } from "./social-team-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Mi equipo | Pachangas IQ",
};

export default function TeamEntryPage() {
  return <SocialTeamProduct surface="home" />;
}
