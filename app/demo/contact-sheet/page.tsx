import type { Metadata } from "next";
import { DemoWorldContactSheet } from "../../demo-world/demo-world-contact-sheet";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Demo World V1 · Contact sheet",
};

export default async function DemoWorldContactSheetPage({
  searchParams,
}: {
  searchParams: Promise<{ kind?: string }>;
}) {
  const { kind } = await searchParams;
  return <DemoWorldContactSheet kind={kind === "players" ? "players" : "teams"} />;
}
