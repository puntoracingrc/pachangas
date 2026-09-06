import type { Metadata } from "next";
import { SocialTeamProduct } from "../social-team-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Logros del equipo | Pachangas IQ",
};

export default function TeamAchievementsPage() {
  return <SocialTeamProduct surface="achievements" />;
}
