import type { Metadata } from "next";
import { OfficialUiV21Lab } from "./lab-client";

export const metadata: Metadata = {
  title: "Official UI V2.1 Deep Demo Parity Lab | Pachangas IQ",
  robots: { follow: false, index: false },
};

function queryValue(value: string | string[] | undefined, fallback: string) {
  return Array.isArray(value) ? value[0] ?? fallback : value ?? fallback;
}

export default async function OfficialUiV21LabPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const query = await searchParams;
  return (
    <OfficialUiV21Lab
      capture={queryValue(query.capture, "0") === "1"}
      initialPane={queryValue(query.pane, "proximo")}
      initialRole={queryValue(query.role, "admin")}
      initialState={queryValue(query.state, "upcoming")}
      initialSurface={queryValue(query.surface, "inicio")}
      initialTheme={queryValue(query.theme, "dark")}
    />
  );
}
