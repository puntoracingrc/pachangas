import type { Metadata } from "next";
import { TeamOperationalClient } from "../../_components/team-operational-client";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";

export const metadata: Metadata = {
  description: "Estado operativo, restricciones, continuidad y apelaciones del equipo.",
  title: "Estado del equipo | Pachangas IQ",
};

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

export default async function TeamOperationalPage({ searchParams }: { searchParams: SearchParams }) {
  const raw = await searchParams;
  const group = Array.isArray(raw.grupo) ? raw.grupo[0] ?? "" : raw.grupo ?? "";
  return <OfficialProductShellV2 active="equipo" context={{ detail: "Revisión, límites y continuidad", eyebrow: "Equipo", status: "Servidor", title: "Estado operativo" }}>
    <TeamOperationalClient initialGroupId={group} />
  </OfficialProductShellV2>;
}
