import type { Metadata } from "next";
import { SocialTeamProduct } from "../social-team-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Invitaciones de equipo | Pachangas IQ",
};

export default function TeamInvitationsPage() {
  return <SocialTeamProduct surface="invitations" />;
}
