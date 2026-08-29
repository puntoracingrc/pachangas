import type { Metadata } from "next";
import { OrganizerAccessClient } from "../../../_components/organizer-access-client";

export const metadata: Metadata = { title: "Estado de solicitud · Pachangas IQ" };
type Params = Promise<{ applicationId: string }>;

export default async function OrganizerAccessApplicationPage({ params }: { params: Params }) {
  const { applicationId } = await params;
  return <OrganizerAccessClient initialApplicationId={applicationId} surface="detail" />;
}
