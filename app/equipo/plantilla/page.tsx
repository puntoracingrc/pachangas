import type { Metadata } from "next";
import { SocialTeamProduct } from "../social-team-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Plantilla | Pachangas IQ",
};

export default function TeamRosterPage() {
  return <SocialTeamProduct surface="roster" />;
}
