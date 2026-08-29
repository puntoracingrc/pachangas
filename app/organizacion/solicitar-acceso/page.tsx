import type { Metadata } from "next";
import { OrganizerAccessClient } from "../../_components/organizer-access-client";

export const metadata: Metadata = { title: "Solicitar acceso de organizador · Pachangas IQ" };
type SearchParams = Promise<Record<string, string | string[] | undefined>>;

export default async function OrganizerAccessApplyPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  const plan = Array.isArray(params.plan) ? params.plan[0] ?? "" : params.plan ?? "";
  return <OrganizerAccessClient initialPlanCode={plan} surface="apply" />;
}
