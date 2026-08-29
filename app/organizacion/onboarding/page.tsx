import type { Metadata } from "next";
import { OrganizerAccessClient } from "../../_components/organizer-access-client";

export const metadata: Metadata = { title: "Onboarding de organización · Pachangas IQ" };

export default function OrganizerOnboardingPage() {
  return <OrganizerAccessClient surface="onboarding" />;
}
